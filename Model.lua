---@type string, AGFNamespace
local _, ns = ...
---@class AGFModel
-- Nine: the stock numerals (services-number-1..9) that label each step stop at 9.
local Model = { MAX_STEPS = 9 }
ns.Model = Model

-- CMaNGOS mangos-classic/src/game/Tools/Formulas.h, GetQuestGreenRange (quest, not creature XP).
local GREEN_RANGE = { 4, 4, 5, 5, 6, 6, 7, 7, 8, 9, 10, 11, 12 }
local CLOSE = 0.03 * 0.03

function Model.IsGray(questLevel, playerLevel)
	local range = GREEN_RANGE[math.min(#GREEN_RANGE, math.floor(playerLevel / 5) + 1)] or 4
	return questLevel > 0 and playerLevel - questLevel > range
end

local function ValidPlace(place)
	return place
		and type(place.map) == "number"
		and place.map > 0
		and type(place.x) == "number"
		and place.x >= 0
		and place.x <= 1
		and type(place.y) == "number"
		and place.y >= 0
		and place.y <= 1
end

local function HasBit(mask, bit)
	return not mask or mask == 0 or (bit > 0 and math.floor(mask / bit) % 2 == 1)
end

local function Distance(a, b)
	if not ValidPlace(a) or a.map ~= b.map then
		return 1000000
	end
	return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2
end

-- Only immutable bundled data is memoized; player/log/completion tables may change in place.
-- Static hub anchors keep pin/skip identities when one of a hub's quests is accepted or completed.
---@class AGFIndex
---@field ids integer[]
---@field groups table<integer, integer[]>
---@field hubs table<integer, string>
---@type table<AGFData, AGFIndex>
local indexes = setmetatable({}, { __mode = "k" })

local function Index(data)
	local index = indexes[data]
	if index then
		return index
	end
	index = { ids = {}, groups = {}, hubs = {} }
	for id in pairs(data.quests) do
		index.ids[#index.ids + 1] = id
	end
	table.sort(index.ids)
	local anchors = {}
	for _, id in ipairs(index.ids) do
		local quest = data.quests[id]
		if quest.group and quest.group > 0 then
			local group = index.groups[quest.group] or {}
			index.groups[quest.group] = group
			group[#group + 1] = id
		end
		local place = quest.start
		if ValidPlace(place) then
			local anchor
			for _, candidate in ipairs(anchors[place.map] or {}) do
				if Distance(place, candidate) <= CLOSE then
					anchor = candidate
					break
				end
			end
			if not anchor then
				anchor = place
				anchors[place.map] = anchors[place.map] or {}
				table.insert(anchors[place.map], anchor)
			end
			index.hubs[id] = string.format("%d:%.4f:%.4f", anchor.map, anchor.x, anchor.y)
		end
	end
	indexes[data] = index
	return index
end

-- `level` stands in for the player's own (the next-zone card asks what opens two levels on).
local function Eligible(data, player, completed, log, id, groups, level)
	local quest = data.quests[id]
	if not quest or completed[id] or log[id] or quest.repeatable or not ValidPlace(quest.start) then
		return false
	end
	if
		(quest.side ~= 3 and quest.side ~= player.side)
		or (level or player.level) < quest.min
		or not HasBit(quest.races, player.raceBit)
		or not HasBit(quest.classes, player.classBit)
	then
		return false
	end
	for _, pre in ipairs(quest.pre or {}) do
		if pre <= 0 or not completed[pre] then
			return false
		end
	end
	if quest.preAny then
		local found = false
		for _, pre in ipairs(quest.preAny) do
			if pre > 0 and completed[pre] then
				found = true
				break
			end
		end
		if not found then
			return false
		end
	end
	for _, other in ipairs((quest.group and groups[quest.group]) or {}) do
		if completed[other] or log[other] then
			return false
		end
	end
	return true
end

function Model.Eligible(data, player, completed, log, questID)
	return Eligible(data, player, completed, log, questID, Index(data).groups)
end

-- The three zones that best fit `level` for the quests `ids`, best first.
local function Rank(data, ids, level)
	local choices, scores = {}, {}
	for _, id in ipairs(ids) do
		local quest = data.quests[id]
		local map = quest.zone or quest.start.map
		local zone = data.zones[map]
		if zone and not Model.IsGray(quest.level, level) then
			if not choices[map] then
				choices[map] = { map = map, name = zone.name, min = zone.min, max = zone.max, quests = 0, best = false }
				scores[map] = 0
			end
			choices[map].quests = choices[map].quests + 1
			local questLevel = quest.level == -1 and level or quest.level
			-- Fit dominates; a bounded density bonus below favors enough quests for a short route.
			scores[map] = scores[map] + math.abs(questLevel - level) + math.max(0, questLevel - level - 2)
		end
	end
	local zones = {}
	for map, choice in pairs(choices) do
		scores[map] = scores[map] / choice.quests
			+ math.max(0, choice.min - level, level - choice.max) * 2
			- math.min(choice.quests, 12) * 0.5
		zones[#zones + 1] = choice
	end
	table.sort(zones, function(a, b)
		if scores[a.map] ~= scores[b.map] then
			return scores[a.map] < scores[b.map]
		end
		if a.quests ~= b.quests then
			return a.quests > b.quests
		end
		return a.map < b.map
	end)
	while #zones > 3 do
		table.remove(zones)
	end
	if zones[1] then
		zones[1].best = true
	end
	return zones
end

-- One eligibility pass for two levels: the player's, and `ahead` levels on for the next-zone card. A level reaches
-- eligibility only through a quest's minimum, so what opens at level + ahead holds everything open now.
local function Choices(data, player, completed, log, index, prefs, ahead)
	local eligible, later, target = {}, {}, player.level + (ahead or 0)
	for _, id in ipairs(index.ids) do
		local quest = data.quests[id]
		local group = quest.elite or quest.dungeon
		if
			(not prefs or (group and prefs.dungeons) or (not group and prefs.quests))
			and Eligible(data, player, completed, log, id, index.groups, target)
		then
			later[#later + 1] = id
			if quest.min <= player.level and not Model.IsGray(quest.level, player.level) then
				eligible[#eligible + 1] = id
			end
		end
	end
	return Rank(data, eligible, player.level), eligible, ahead and Rank(data, later, target)
end

-- Every quest giver on `mapID` with a quest the player can take now, one entry per NPC or object, like the
-- game's own "!". Gray quests stay hidden, as the game hides them unless low-level tracking is on.
---@return AGFGiver[]
function Model.Givers(data, player, completed, log, mapID)
	local index, byPlace, givers = Index(data), {}, {}
	for _, id in ipairs(index.ids) do
		local quest = data.quests[id]
		local start = quest.start
		if
			start
			and start.map == mapID
			and not Model.IsGray(quest.level, player.level)
			and Eligible(data, player, completed, log, id, index.groups)
		then
			local key = string.format("%s:%.4f:%.4f", start.name, start.x, start.y)
			local giver = byPlace[key]
			if not giver then
				giver = { map = mapID, x = start.x, y = start.y, title = start.name, quests = {} }
				byPlace[key] = giver
				givers[#givers + 1] = giver
			end
			giver.quests[#giver.quests + 1] = id
		end
	end
	return givers
end

function Model.Zones(data, player, completed, log)
	local zones = Choices(data, player, completed, log, Index(data))
	return zones
end

local function Optional(quest, level, player)
	return (quest and (quest.elite or quest.dungeon) and true)
		or level > player.level + 2
		or Model.IsGray(level, player.level)
end

local function Step(kind, key, title, place, id, optional, reason)
	return {
		kind = kind,
		key = key,
		title = title,
		detail = reason,
		reason = reason,
		quests = { id },
		map = place.map,
		x = place.x,
		y = place.y,
		place = place.name,
		optional = optional or nil,
	}
end

local function LogSteps(data, player, log, prefs)
	local ids, steps, objectives = {}, {}, {}
	for id in pairs(log) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local entry, quest = log[id], data.quests[id]
		local group = quest and (quest.elite or quest.dungeon)
		if (group and prefs.dungeons) or (not group and prefs.quests) then
			-- A live completion waypoint is a turn-in; an incomplete waypoint is never replaced with the starter.
			local place = ValidPlace(entry) and entry or (entry.complete and quest and quest.finish)
			if ValidPlace(place) then
				local optional = Optional(quest, entry.level, player)
				if entry.complete then
					steps[#steps + 1] = Step(
						"turnin",
						"turnin:" .. id,
						"Turn in: " .. entry.title,
						place,
						id,
						optional,
						"ready to hand in"
					)
				else
					local kind = group and "dungeon" or "objective"
					local existing
					for _, step in ipairs(objectives) do
						if step.kind == kind and Distance(step, place) <= CLOSE then
							existing = step
							break
						end
					end
					if existing then
						existing.quests[#existing.quests + 1] = id
						existing.optional = existing.optional or optional or nil
						existing.reason = #existing.quests .. " quests here"
						existing.detail = existing.reason
					else
						local step =
							Step(kind, "objective:" .. id, entry.title, place, id, optional, "quests in progress")
						objectives[#objectives + 1] = step
						steps[#steps + 1] = step
					end
				end
			end
		end
	end
	return steps
end

local function PickupSteps(data, player, eligible, zone, hubs, steps, pins)
	local pickups, chosenGroups, pinned = {}, {}, {}
	for _, key in ipairs(pins) do
		pinned[key] = true
	end
	for _, id in ipairs(eligible) do
		local quest = data.quests[id]
		local kind = (quest.elite or quest.dungeon) and "dungeon" or "pickup"
		local key = kind .. ":" .. hubs[id]
		if
			((quest.zone or quest.start.map) == zone or pinned[key]) and not (quest.group and chosenGroups[quest.group])
		then
			if quest.group then
				chosenGroups[quest.group] = true
			end
			local step = pickups[key]
			local chain = quest.pre or quest.preAny
			if step then
				step.quests[#step.quests + 1] = id
				step.reason = #step.quests .. " quests here"
				step.detail = step.reason
				step.optional = step.optional or Optional(quest, quest.level, player) or nil
			else
				local place = quest.start
				step = Step(
					kind,
					key,
					"Pick up quests: " .. place.name,
					place,
					id,
					Optional(quest, quest.level, player),
					chain and "continues chain" or "near your level"
				)
				pickups[key] = step
				steps[#steps + 1] = step
			end
		end
	end
end

-- One cost in yards, offline, so a rebuild never waits on travel maths (docs/design.md §4.1). A place goes into one
-- frame: its map's world rectangle, then its continent's place on the Azeroth map, so two steps an ocean apart still
-- get a distance. Across an ocean it runs through the player's side's boat or zeppelin docks, so the far side's step
-- nearest the landing is the one the route enters at.
local CROSSING = 10000 -- the wait and the sail, which the distance to and from the docks cannot see
local UNKNOWN = 1000000 -- no way to measure: dearer than any crossing, so it never ties by accident

-- `continent` is the world map ID when the data places the map on the Azeroth map (`known`). A map it doesn't is an
-- island of its own, measured in map units, so its steps still order among themselves but never against the rest.
-- `docks` are the crossings the player's side can take, shared by every position of one plan.
---@class AGFPosition
---@field x number
---@field y number
---@field continent integer|string
---@field known boolean
---@field docks? AGFFrameCrossing[]

-- One direction of an AGFCrossing, its docks in the shared frame.
---@class AGFFrameCrossing
---@field from integer
---@field to integer
---@field leave {x: number, y: number}
---@field land {x: number, y: number}

---@return AGFPosition?
local function Position(data, place, docks)
	if not ValidPlace(place) then
		return nil
	end
	local map = data.maps and data.maps[place.map]
	local shift = map and data.continents and data.continents[map.continent]
	if not shift then
		return { x = place.x, y = place.y, continent = "map " .. place.map, known = false }
	end
	return {
		x = shift.x - map.cy + (place.x - 0.5) * map.sx,
		y = shift.y - map.cx + (place.y - 0.5) * map.sy,
		continent = map.continent,
		known = true,
		docks = docks,
	}
end

-- Both directions of every crossing `side` may take whose continents the data places on the Azeroth map.
---@return AGFFrameCrossing[]
local function Docks(data, side)
	local docks = {}
	local function Frame(dock)
		local shift = data.continents and data.continents[dock.continent]
		return shift and { x = shift.x - dock.y, y = shift.y - dock.x }
	end
	for _, crossing in ipairs(data.crossings or {}) do
		local a, b = Frame(crossing.a), Frame(crossing.b)
		if a and b and HasBit(crossing.side, side) then
			docks[#docks + 1] = { from = crossing.a.continent, to = crossing.b.continent, leave = a, land = b }
			docks[#docks + 1] = { from = crossing.b.continent, to = crossing.a.continent, leave = b, land = a }
		end
	end
	return docks
end

local function Yards(a, b)
	return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end

---@param a AGFPosition?
---@param b AGFPosition?
local function Cost(a, b)
	if not (a and b) or (a.continent ~= b.continent and not (a.known and b.known)) then
		return UNKNOWN
	end
	if a.continent == b.continent then
		return Yards(a, b)
	end
	local best
	for _, dock in ipairs(a.docks or {}) do
		if dock.from == a.continent and dock.to == b.continent then
			local via = Yards(a, dock.leave) + Yards(dock.land, b)
			best = (best and best < via) and best or via
		end
	end
	-- No boat for this side between them: the straight line across the sea, as before the docks were known.
	return CROSSING + (best or Yards(a, b))
end

-- Nearest neighbour from `from`; TwoOpt then removes crossings with that start fixed and the end open.
local function Path(steps, from, where)
	local path, left = {}, {}
	for _, step in ipairs(steps) do
		left[#left + 1] = step
	end
	while #left > 0 do
		local best
		for index, step in ipairs(left) do
			local cost = Cost(from, where[step])
			if not best or cost < best.cost or (cost == best.cost and step.key < left[best.index].key) then
				best = { index = index, cost = cost }
			end
		end
		local step = table.remove(left, best.index)
		path[#path + 1] = step
		from = where[step]
	end
	return path
end

local function TwoOpt(path, start, where)
	local function At(index)
		return index == 0 and start or where[path[index]]
	end
	local improved = true
	while improved do
		improved = false
		for i = 1, #path - 1 do
			for j = i + 1, #path do
				local before = Cost(At(i - 1), At(i)) + (j < #path and Cost(At(j), At(j + 1)) or 0)
				local after = Cost(At(i - 1), At(j)) + (j < #path and Cost(At(i), At(j + 1)) or 0)
				if after < before - 1e-6 then
					for k = 0, math.floor((j - i - 1) / 2) do
						path[i + k], path[j - k] = path[j - k], path[i + k]
					end
					improved = true
				end
			end
		end
	end
	return path
end

-- Groups the selected steps by continent, the player's first and the rest by how dear they are to reach, so the
-- route crosses each ocean once. In each group the turn-ins in `away` (another continent than the player's) go last.
-- `cheap` (the in-combat rebuild) keeps the nearest-neighbour order and skips 2-opt.
local function Order(selected, origin, where, away, cheap)
	local groups, byContinent = {}, {}
	for _, step in ipairs(selected) do
		local continent = where[step].continent
		local group = byContinent[continent]
		if not group then
			group = { continent = continent, main = {}, last = {}, reach = math.huge }
			byContinent[continent] = group
			groups[#groups + 1] = group
		end
		table.insert(away[step] and group.last or group.main, step)
		group.reach = math.min(group.reach, Cost(origin, where[step]))
	end
	local home = origin and origin.continent
	table.sort(groups, function(a, b)
		if (a.continent == home) ~= (b.continent == home) then
			return a.continent == home
		end
		if a.reach ~= b.reach then
			return a.reach < b.reach
		end
		return tostring(a.continent) < tostring(b.continent)
	end)
	local steps, from = {}, origin
	for _, group in ipairs(groups) do
		for _, part in ipairs({ group.main, group.last }) do
			local start = from
			local path = Path(part, start, where)
			for _, step in ipairs(cheap and path or TwoOpt(path, start, where)) do
				steps[#steps + 1] = step
				from = where[step]
			end
		end
	end
	return steps
end

-- Chooses up to MAX_STEPS of `candidates` and orders them from the player (docs/design.md §4.1).
local function Build(data, player, candidates, prefs, mapName, cheap)
	local byKey, pool, where, docks = {}, {}, {}, Docks(data, player.side)
	for _, step in ipairs(candidates) do
		if not (prefs.skipped and prefs.skipped[step.key]) then
			byKey[step.key] = step
			pool[#pool + 1] = step
			where[step] = Position(data, step, docks)
		end
	end
	local origin = Position(data, player, docks)

	-- Selection grows from the player: each pick is the step cheapest to reach from the player or any step already
	-- picked. Pinned steps come first; there is no phase, so a far turn-in never pushes out a nearby pickup.
	-- Without a known place for the player (no position in an instance, a map the data lacks) most steps cost UNKNOWN
	-- from them. A turn-in among those leads, as turn-ins did before costs, and the route grows from it instead of
	-- dropping it for whichever key sorts first.
	local measured = origin ~= nil and origin.known
	local reach, chosen, selected = {}, {}, {}
	for _, step in ipairs(pool) do
		local cost = Cost(origin, where[step])
		reach[step] = (not measured and cost >= UNKNOWN and step.kind == "turnin") and 0 or cost
	end
	local function Take(step, pinned)
		step.pinned = pinned or nil
		chosen[step] = true
		selected[#selected + 1] = step
		for _, other in ipairs(pool) do
			if not chosen[other] then
				reach[other] = math.min(reach[other], Cost(where[step], where[other]))
			end
		end
	end
	for _, key in ipairs(prefs.pinned or {}) do
		local step = byKey[key]
		if step and not chosen[step] and #selected < Model.MAX_STEPS then
			Take(step, true)
		end
	end
	while #selected < Model.MAX_STEPS do
		local best
		for _, step in ipairs(pool) do
			if
				not chosen[step]
				and (not best or reach[step] < reach[best] or (reach[step] == reach[best] and step.key < best.key))
			then
				best = step
			end
		end
		if not best then
			break
		end
		Take(best)
	end

	-- A turn-in across an ocean waits for the rest of that continent's steps, and says where it is.
	local away = {}
	for _, step in ipairs(selected) do
		local position = where[step]
		if
			step.kind == "turnin"
			and origin
			and origin.known
			and position.known
			and position.continent ~= origin.continent
		then
			away[step] = true
			local name = (mapName and mapName(step.map)) or (data.maps[step.map] and data.maps[step.map].name)
			if name then
				step.reason = ns.L.HAND_IN_WHEN:format(name)
				step.detail = step.reason
			end
		end
	end
	-- The order starts from the player when some step is measurable from them, from the first pick otherwise.
	local start = selected[1] and where[selected[1]]
	for _, step in ipairs(selected) do
		if Cost(origin, where[step]) < UNKNOWN then
			start = origin
			break
		end
	end
	return Order(selected, start, where, away, cheap)
end

-- The journey cards (docs/design.md §2.2): at most three, each holding only steps the player can take now.
local NEXT_ZONE_AHEAD = 2 -- levels: the next zone is the one that fits the player two levels on
local NEXT_ZONE_PICKUPS = 5 -- eligible quests there, or the card is too thin to offer (docs/plan.md §1.5)

local function Count(one, many, count)
	return count == 1 and one or many:format(count)
end

local function ZoneName(data, map, mapName)
	return (mapName and mapName(map)) or data.zones[map].name
end

-- "Finish what you carry": the log's turn-ins and objectives. `carried` is every log step, so the subline counts
-- what the player carries, not only the steps that made the route.
local function Carry(data, player, log, prefs, mapName, cheap)
	local carried = LogSteps(data, player, log, prefs)
	local steps = Build(data, player, carried, prefs, mapName, cheap)
	if #steps == 0 then
		return nil
	end
	local L, ready, underway = ns.L, 0, 0
	for _, step in ipairs(carried) do
		if not prefs.skipped[step.key] then
			if step.kind == "turnin" then
				ready = ready + 1
			else
				underway = underway + #step.quests
			end
		end
	end
	return {
		kind = "carry",
		key = "carry",
		title = L.JOURNEY_CARRY,
		subline = ready > 0 and Count(L.CARRY_READY_ONE, L.CARRY_READY, ready)
			or Count(L.CARRY_IN_PROGRESS_ONE, L.CARRY_IN_PROGRESS, underway),
		reason = steps[1].kind == "turnin" and L.READY_TO_HAND_IN or nil,
		map = steps[1].map,
		steps = steps,
	}
end

-- A zone's pickups as one journey (kind, key and title are the caller's), and how many eligible quests it holds.
local function ZoneJourney(data, player, eligible, zone, index, prefs, mapName, pins)
	local candidates, quests = {}, 0
	for _, id in ipairs(eligible) do
		local quest = data.quests[id]
		quests = quests + ((quest.zone or quest.start.map) == zone and 1 or 0)
	end
	PickupSteps(data, player, eligible, zone, index.hubs, candidates, pins)
	local steps = Build(data, player, candidates, prefs, mapName)
	if #steps == 0 then
		return nil, quests
	end
	local subline = Count(ns.L.QUESTS_NEAR_ONE, ns.L.QUESTS_NEAR, quests)
	return { map = steps[1].map, steps = steps, subline = subline }, quests
end

---@param mapName? fun(map: integer): string? the client's (localised) name for a map; the data's English otherwise
function Model.Journeys(data, player, completed, log, prefs, mapName)
	local index, L = Index(data), ns.L
	local zones, eligible, ahead = Choices(data, player, completed, log, index, prefs, NEXT_ZONE_AHEAD)
	local journeys = { Carry(data, player, log, prefs, mapName) }
	-- The zone the player's level fits best (or the one they picked), named after it. Model.Story (F4) makes it the
	-- chapter of a chain; until then it holds the zone's pickups, as the route did.
	local zone = prefs.zone or (zones[1] and zones[1].map)
	local story = zone and ZoneJourney(data, player, eligible, zone, index, prefs, mapName, prefs.pinned or {})
	if story then
		story.kind, story.key = "story", "story:" .. zone
		story.title = L.JOURNEY_STORY:format(ZoneName(data, zone, mapName))
		journeys[#journeys + 1] = story
	end
	-- The zone that fits two levels on, when it is another zone and already has enough the player can take now.
	for _, choice in ipairs(ahead) do
		if choice.map ~= zone then
			local nextZone, quests = ZoneJourney(data, player, eligible, choice.map, index, prefs, mapName, {})
			if nextZone and quests >= NEXT_ZONE_PICKUPS then
				nextZone.kind, nextZone.key = "nextzone", "nextzone:" .. choice.map
				local name = ZoneName(data, choice.map, mapName)
				nextZone.title = L.JOURNEY_NEXT_ZONE:format(name, player.level + NEXT_ZONE_AHEAD)
				journeys[#journeys + 1] = nextZone
			end
			break
		end
	end
	return journeys, zones, zone
end

-- The route is the chosen journey's steps; the first journey's when the choice is gone or was never made.
local function Route(journeys, prefs, zones, zone)
	local chosen = journeys[1]
	for _, journey in ipairs(journeys) do
		chosen = journey.key == prefs.journey and journey or chosen
	end
	return {
		journeys = journeys,
		journey = chosen and chosen.key,
		steps = chosen and chosen.steps or {},
		zones = zones,
		zone = zone,
	}
end

---@param mapName? fun(map: integer): string? the client's (localised) name for a map; the data's English otherwise
function Model.Plan(data, player, completed, log, prefs, mapName)
	local journeys, zones, zone = Model.Journeys(data, player, completed, log, prefs, mapName)
	return Route(journeys, prefs, zones, zone)
end

-- The in-combat rebuild (Core.lua): the carry journey fresh from the live log, which is what changes in a fight,
-- and every other journey as the last full build left it. No eligibility pass over the data and no 2-opt, so it
-- stays cheap; the full build runs once combat ends.
---@param last AGFRoute
function Model.Refresh(data, player, log, prefs, last, mapName)
	local journeys = { Carry(data, player, log, prefs, mapName, true) }
	for _, journey in ipairs(last.journeys) do
		if journey.kind ~= "carry" then
			journeys[#journeys + 1] = journey
		end
	end
	return Route(journeys, prefs, last.zones, last.zone)
end
