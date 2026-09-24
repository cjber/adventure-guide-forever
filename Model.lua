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

-- Stories (docs/design.md §2.3): the chain a quest belongs to, from the data's `next` links, which nothing else reads.
-- `prev[id]` is the one quest whose `next` is id, or false when several lead into it. Memoized like Index.
---@class AGFChains
---@field prev table<integer, integer|false>
---@field stories table<integer, AGFStory|false>
---@type table<AGFData, AGFChains>
local chains = setmetatable({}, { __mode = "k" })

-- Walks back to the chain's head, then forward along `next`. No story when the way back forks (which head's
-- chapter count would it be?) or loops, or when the chain is one quest. The total is shown only when the data proves
-- it: every member has at most one `pre` and no `preAny`, and the walk ends on a quest in the data with no `next`.
---@return AGFStory?
local function Walk(data, prev, questID)
	local head, seen = questID, { [questID] = true }
	while prev[head] ~= nil do
		local before = prev[head]
		if not before or seen[before] then
			return nil
		end
		head, seen[before] = before, true
	end
	local members, proven, chapter, id = {}, true, nil, head
	seen = {}
	while id do
		local quest = data.quests[id]
		if not quest or seen[id] then
			proven = false -- a `next` that dangles or loops: the end is unknown
			break
		end
		seen[id], members[#members + 1] = true, id
		chapter = id == questID and #members or chapter
		proven = proven and not quest.preAny and #(quest.pre or {}) <= 1
		id = quest.next
	end
	if #members < 2 or not chapter then
		return nil
	end
	return { chapter = chapter, total = proven and #members or nil, members = members }
end

---@return AGFStory?
function Model.Story(data, questID)
	local memo = chains[data]
	if not memo then
		memo = { prev = {}, stories = {} }
		for _, id in ipairs(Index(data).ids) do
			local nextID = data.quests[id].next
			if nextID then
				memo.prev[nextID] = memo.prev[nextID] == nil and id or false
			end
		end
		chains[data] = memo
	end
	local story = memo.stories[questID]
	if story == nil then
		story = data.quests[questID] and Walk(data, memo.prev, questID) or false
		memo.stories[questID] = story
	end
	return story or nil
end

-- English race and class names by UnitRace/UnitClass ID, the fallback when the client names none (a headless spec).
local RACES = { "Human", "Orc", "Dwarf", "Night Elf", "Undead", "Tauren", "Gnome", "Troll" }
RACES[10], RACES[11] = "Blood Elf", "Draenei"
local CLASSES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest" }
CLASSES[7], CLASSES[8], CLASSES[9], CLASSES[11] = "Shaman", "Mage", "Warlock", "Druid"
local SIDE_RACES = { 1 + 4 + 8 + 64, 2 + 16 + 32 + 128 } -- each side's four classic races, as bit masks
local ALL_CLASSES = 1 + 2 + 4 + 8 + 16 + 64 + 128 + 256 + 1024

-- Whether `mask` holds every bit of `bits`; an absent or zero mask holds everything, as in HasBit.
local function Covers(mask, bits)
	for id = 0, 15 do
		local bit = 2 ^ id
		if math.floor(bits / bit) % 2 == 1 and not (not mask or mask == 0 or math.floor(mask / bit) % 2 == 1) then
			return false
		end
	end
	return true
end

-- Every name a mask holds, joined: the client's (`lookup`) first, the English above otherwise.
local function MaskNames(mask, lookup, english)
	local names = {}
	for id = 1, 16 do
		if math.floor(mask / 2 ^ (id - 1)) % 2 == 1 then
			names[#names + 1] = (lookup and lookup(id)) or english[id]
		end
	end
	return table.concat(names, ns.L.LIST_SEPARATOR)
end

---@param names? AGFWhyNames
local function Title(data, id, names)
	local quest = data.quests[id]
	return (names and names.title and names.title(id)) or (quest and quest.title) or ns.L.WHY_EARLIER_QUEST
end

-- One requirement's line. Built only when Why asks, so the planner's pass never formats a string.
---@param names? AGFWhyNames
local function WhyText(data, key, arg, names)
	local L = ns.L
	if key == "side" then
		return arg == 1 and L.WHY_ALLIANCE or L.WHY_HORDE
	elseif key == "level" then
		return L.WHY_LEVEL:format(arg)
	elseif key == "races" then
		return L.WHY_RACES:format(MaskNames(arg, names and names.race, RACES))
	elseif key == "classes" then
		return L.WHY_CLASSES:format(MaskNames(arg, names and names.class, CLASSES))
	elseif key == "pre" then
		return L.WHY_COMPLETED:format(Title(data, arg, names))
	elseif key == "preAny" then
		local titles = {}
		for index, id in ipairs(arg) do
			titles[index] = Title(data, id, names)
		end
		return L.WHY_ONE_OF:format(table.concat(titles, L.LIST_SEPARATOR))
	elseif key == "group" then
		return L.WHY_CHOSE:format(Title(data, arg, names))
	end
	return L[key]
end

-- Records one requirement when Why passes `lines`. False tells the planner's pass (no `lines`) to stop there.
local function Line(data, lines, met, key, arg, names)
	if lines then
		lines[#lines + 1] = { text = WhyText(data, key, arg, names), met = met }
	end
	return met or lines ~= nil
end

-- The one eligibility check (docs/design.md §2.4). The planner passes no `lines` and it stops at the first unmet
-- requirement; Why passes `lines` and gets every requirement as a line. So the two never disagree: a quest is
-- eligible exactly when every line is met. A met line that says nothing (level 1, a whole side's races, every
-- class) is left out. `level` stands in for the player's own (the next-zone card asks what opens two levels on).
local function Check(data, player, completed, log, id, groups, level, lines, names)
	local quest = data.quests[id]
	if not quest then
		return false
	elseif not ValidPlace(quest.start) then
		-- The generator suppressed the start: the only line, since nothing else about the quest can be acted on.
		Line(data, lines, false, "WHY_NO_START")
		return false
	end
	if completed[id] and not Line(data, lines, false, "WHY_DONE") then
		return false
	elseif log[id] and not Line(data, lines, false, "WHY_IN_LOG") then
		return false
	elseif quest.repeatable and not Line(data, lines, false, "WHY_REPEATABLE") then
		return false
	end
	-- Each line below is written only when unmet (the planner stops there) or when Why asks and it says something.
	local met = quest.side == 3 or quest.side == player.side
	if not met or (lines and quest.side ~= 3) then
		if not Line(data, lines, met, "side", quest.side, names) then
			return false
		end
	end
	met = (level or player.level) >= quest.min
	if not met or (lines and quest.min > 1) then
		if not Line(data, lines, met, "level", quest.min, names) then
			return false
		end
	end
	met = HasBit(quest.races, player.raceBit)
	if not met or (lines and not Covers(quest.races, SIDE_RACES[player.side] or 0)) then
		if not Line(data, lines, met, "races", quest.races, names) then
			return false
		end
	end
	met = HasBit(quest.classes, player.classBit)
	if not met or (lines and not Covers(quest.classes, ALL_CLASSES)) then
		if not Line(data, lines, met, "classes", quest.classes, names) then
			return false
		end
	end
	for _, pre in ipairs(quest.pre or {}) do
		met = pre > 0 and completed[pre] == true
		if (lines or not met) and not Line(data, lines, met, "pre", pre, names) then
			return false
		end
	end
	if quest.preAny then
		met = false
		for _, pre in ipairs(quest.preAny) do
			met = met or (pre > 0 and completed[pre] == true)
		end
		if not Line(data, lines, met, "preAny", quest.preAny, names) then
			return false
		end
	end
	for _, other in ipairs((quest.group and groups[quest.group]) or {}) do
		if other ~= id and (completed[other] or log[other]) and not Line(data, lines, false, "group", other, names) then
			return false
		end
	end
	return true
end

local function Eligible(data, player, completed, log, id, groups, level)
	return Check(data, player, completed, log, id, groups, level)
end

function Model.Eligible(data, player, completed, log, questID)
	return Eligible(data, player, completed, log, questID, Index(data).groups)
end

-- Why a quest is or isn't open to the player: each requirement the data carries, met or not (docs/design.md §2.4).
---@param names? AGFWhyNames the client's names for quests, races and classes
---@return AGFWhyLine[]
function Model.Why(data, player, completed, log, questID, names)
	local lines = {}
	Check(data, player, completed, log, questID, Index(data).groups, nil, lines, names)
	return lines
end

local SEARCH_MAX = 10

-- The player's side's quests whose title holds `query` (plain, case-insensitive, as the quest log's search), by title
-- then ID, at most 10: the search's rows (docs/design.md §2.4). `title` is the client's, the data's otherwise.
---@param title? fun(questID: integer): string?
---@return integer[]
function Model.Search(data, player, query, title)
	query = query:lower()
	local found, titles = {}, {}
	for id, quest in pairs(data.quests) do
		if quest.side == 3 or quest.side == player.side then
			local name = (title and title(id)) or quest.title
			if name:lower():find(query, 1, true) then
				found[#found + 1], titles[id] = id, name
			end
		end
	end
	table.sort(found, function(a, b)
		if titles[a] ~= titles[b] then
			return titles[a] < titles[b]
		end
		return a < b
	end)
	for index = #found, SEARCH_MAX + 1, -1 do
		found[index] = nil
	end
	return found
end

-- The maps of the three zones that best fit `level` for the quests `ids`, best first.
---@return integer[]
local function Rank(data, ids, level)
	local choices, scores = {}, {}
	for _, id in ipairs(ids) do
		local quest = data.quests[id]
		local map = quest.zone or quest.start.map
		local zone = data.zones[map]
		if zone and not Model.IsGray(quest.level, level) then
			if not choices[map] then
				choices[map] = { map = map, min = zone.min, max = zone.max, quests = 0 }
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
	local maps = {}
	for index = 1, math.min(#zones, 3) do
		maps[index] = zones[index].map
	end
	return maps
end

-- One eligibility pass for two levels: the player's, and `ahead` levels on for the next-zone card. A level reaches
-- eligibility only through a quest's minimum, so what opens at level + ahead holds everything open now.
local function Choices(data, player, completed, log, index, prefs, ahead)
	local eligible, later, target = {}, {}, player.level + (ahead or 0)
	for _, id in ipairs(index.ids) do
		local quest = data.quests[id]
		local group = quest.elite or quest.dungeon
		if
			((group and prefs.dungeons) or (not group and prefs.quests))
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

-- The quest and dungeon prefs choose what to pick up; a quest already carried always shows, whatever its kind.
local function LogSteps(data, player, log)
	local ids, steps, objectives = {}, {}, {}
	for id in pairs(log) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local entry, quest = log[id], data.quests[id]
		local group = quest and (quest.elite or quest.dungeon)
		-- A live completion waypoint is a turn-in; an incomplete waypoint is never replaced with the starter.
		local place = ValidPlace(entry) and entry or (entry.complete and quest and quest.finish)
		if ValidPlace(place) then
			local optional = Optional(quest, entry.level, player)
			if entry.complete then
				steps[#steps + 1] = Step(
					"turnin",
					"turnin:" .. id,
					ns.L.TURN_IN:format(entry.title),
					place,
					id,
					optional,
					ns.L.READY_TO_HAND_IN
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
					existing.reason = ns.L.QUESTS_HERE:format(#existing.quests)
					existing.detail = existing.reason
				else
					local step =
						Step(kind, "objective:" .. id, entry.title, place, id, optional, ns.L.QUESTS_IN_PROGRESS)
					objectives[#objectives + 1] = step
					steps[#steps + 1] = step
				end
			end
		end
	end
	return steps
end

-- One step per giver of the eligible quests `wanted` accepts.
---@param wanted fun(quest: AGFQuest): boolean
local function PickupSteps(data, player, eligible, wanted, hubs, steps)
	local pickups, chosenGroups = {}, {}
	for _, id in ipairs(eligible) do
		local quest = data.quests[id]
		local kind = (quest.elite or quest.dungeon) and "dungeon" or "pickup"
		local key = kind .. ":" .. hubs[id]
		if wanted(quest) and not (quest.group and chosenGroups[quest.group]) then
			if quest.group then
				chosenGroups[quest.group] = true
			end
			local step = pickups[key]
			local chain = quest.pre or quest.preAny
			if step then
				step.quests[#step.quests + 1] = id
				step.reason = ns.L.QUESTS_HERE:format(#step.quests)
				step.detail = step.reason
				step.optional = step.optional or Optional(quest, quest.level, player) or nil
			else
				local place = quest.start
				step = Step(
					kind,
					key,
					ns.L.PICK_UP:format(place.name),
					place,
					id,
					Optional(quest, quest.level, player),
					chain and ns.L.CONTINUES_STORY or ns.L.NEAR_YOUR_LEVEL
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

-- The skipped keys a full build still found among its candidates (Model.Plan); nil outside one.
---@type table<string, boolean>?
local skippedSeen

-- Chooses up to MAX_STEPS of `candidates` and orders them from the player (docs/design.md §4.1). `lead`, the story
-- card's chapter, is chosen first, then ordered by cost like the rest.
local function Build(data, player, candidates, prefs, mapName, cheap, lead)
	local pool, where, docks = {}, {}, Docks(data, player.side)
	for _, step in ipairs(candidates) do
		if not (prefs.skipped and prefs.skipped[step.key]) then
			pool[#pool + 1] = step
			where[step] = Position(data, step, docks)
		elseif skippedSeen then
			skippedSeen[step.key] = true
		end
	end
	local origin = Position(data, player, docks)

	-- Selection grows from the player: each pick is the step cheapest to reach from the player or any step already
	-- picked. There is no phase, so a far turn-in never pushes out a nearby pickup.
	-- Without a known place for the player (no position in an instance, a map the data lacks) most steps cost UNKNOWN
	-- from them. A turn-in among those leads, as turn-ins did before costs, and the route grows from it instead of
	-- dropping it for whichever key sorts first.
	local measured = origin ~= nil and origin.known
	local reach, chosen, selected = {}, {}, {}
	for _, step in ipairs(pool) do
		local cost = Cost(origin, where[step])
		reach[step] = (not measured and cost >= UNKNOWN and step.kind == "turnin") and 0 or cost
	end
	local function Take(step)
		chosen[step] = true
		selected[#selected + 1] = step
		for _, other in ipairs(pool) do
			if not chosen[other] then
				reach[other] = math.min(reach[other], Cost(where[step], where[other]))
			end
		end
	end
	if lead and where[lead] then
		Take(lead)
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
local MAX_JOURNEYS = 3 -- docs/design.md §2.2
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
	local carried = LogSteps(data, player, log)
	local steps = Build(data, player, carried, prefs, mapName, cheap)
	if #steps == 0 then
		return nil
	end
	-- A finished quest whose hand-in is across an ocean is not ready yet: the reason line counts those, so no fact
	-- is told twice on the card.
	local L, ready, underway, away, here = ns.L, 0, 0, 0, Position(data, player)
	for _, step in ipairs(carried) do
		if not prefs.skipped[step.key] then
			local there = Position(data, step)
			if step.kind ~= "turnin" then
				underway = underway + #step.quests
			elseif here and there and here.known and there.known and here.continent ~= there.continent then
				away = away + 1
			else
				ready = ready + 1
			end
		end
	end
	local parts = {}
	parts[#parts + 1] = ready > 0 and L.CARRY_READY:format(ready) or nil
	parts[#parts + 1] = underway > 0 and L.CARRY_IN_PROGRESS:format(underway) or nil
	local farther = away > 0 and L.CARRY_AWAY:format(away) or nil
	return {
		kind = "carry",
		key = "carry",
		title = L.JOURNEY_CARRY,
		subline = #parts > 0 and table.concat(parts, L.LIST_SEPARATOR) or farther,
		reason = #parts > 0 and farther or nil,
		map = steps[1].map,
		steps = steps,
	}
end

-- A zone's pickups as one journey (kind, key and title are the caller's), and how many eligible quests it holds.
-- The step that offers `leadID` is always among them.
local function ZoneJourney(data, player, eligible, zone, index, prefs, mapName, leadID)
	local candidates, quests, lead = {}, 0, nil
	for _, id in ipairs(eligible) do
		local quest = data.quests[id]
		quests = quests + ((quest.zone or quest.start.map) == zone and 1 or 0)
	end
	PickupSteps(data, player, eligible, function(quest)
		return (quest.zone or quest.start.map) == zone
	end, index.hubs, candidates)
	for _, step in ipairs(candidates) do
		for _, id in ipairs(step.quests) do
			lead = id == leadID and step or lead
		end
	end
	local steps = Build(data, player, candidates, prefs, mapName, false, lead)
	if #steps == 0 then
		return nil, quests
	end
	-- The lead only when Build kept it: a skipped chapter leaves the card to the zone's count.
	local kept
	for _, step in ipairs(steps) do
		kept = kept or step == lead
	end
	local subline = Count(ns.L.QUESTS_NEAR_ONE, ns.L.QUESTS_NEAR, quests)
	return { map = steps[1].map, steps = steps, subline = subline, count = subline }, quests, kept and lead or nil
end

-- The dungeon card (F15): with dungeons on, the party instance with the most quests the player can take now (the
-- lowest Map.ID on a tie), its steps the givers of those quests. Raids are never offered. Named by the client, in the
-- player's language, and by the data otherwise; an instance the data doesn't name gets no card.
---@param instanceName? fun(id: integer): string?
local function DungeonJourney(data, player, eligible, index, prefs, mapName, instanceName)
	if not (prefs.dungeons and data.instances) then
		return nil
	end
	local counts, best = {}, nil
	for _, id in ipairs(eligible) do
		local quest = data.quests[id]
		local instance = not quest.raid and quest.dungeon
		if instance and data.instances[instance] then
			counts[instance] = (counts[instance] or 0) + 1
		end
	end
	for instance, count in pairs(counts) do
		if not best or count > counts[best] or (count == counts[best] and instance < best) then
			best = instance
		end
	end
	if not best then
		return nil
	end
	local candidates = {}
	PickupSteps(data, player, eligible, function(quest)
		return quest.dungeon == best and not quest.raid
	end, index.hubs, candidates)
	local steps = Build(data, player, candidates, prefs, mapName)
	if #steps == 0 then
		return nil
	end
	local name = instanceName and instanceName(best) or data.instances[best].name
	local subline = Count(ns.L.DUNGEON_QUESTS_ONE, ns.L.DUNGEON_QUESTS, counts[best])
	return {
		kind = "dungeon",
		key = "dungeon:" .. best,
		title = name,
		subline = subline,
		map = steps[1].map,
		steps = steps,
	}
end

-- The zone's story (docs/design.md §2.3): of the chains the player can take up in `zone` now, one they have already
-- started before one they would begin, then the longest proven one, then the lowest quest ID. A chapter whose chain
-- was begun elsewhere, with the chapter before it not done, has no honest reason to offer, so it is never the story.
---@return AGFStory?, integer?, boolean? the chain, the quest that takes it up, and whether it continues one
local function ZoneStory(data, completed, eligible, zone)
	local best, bestID, bestRank, continues
	for _, id in ipairs(eligible) do
		local quest = data.quests[id]
		local story = (quest.zone or quest.start.map) == zone and Model.Story(data, id)
		local started = story and story.chapter > 1 and completed[story.members[story.chapter - 1]] == true
		if story and (started or story.chapter == 1) then
			local rank = (started and 0 or 1000) - (story.total or 0)
			if not bestRank or rank < bestRank then
				best, bestID, bestRank, continues = story, id, rank, started
			end
		end
	end
	return best, bestID, continues
end

---@param mapName? fun(map: integer): string? the client's (localised) name for a map; the data's English otherwise
---@param instanceName? fun(id: integer): string? the client's name for an instance Map.ID; the data's otherwise
function Model.Journeys(data, player, completed, log, prefs, mapName, instanceName)
	local index, L = Index(data), ns.L
	-- Never past the level cap: a player at it has no next zone to head for.
	local levels = math.min(NEXT_ZONE_AHEAD, player.maxLevel - player.level)
	local zones, eligible, ahead = Choices(data, player, completed, log, index, prefs, levels > 0 and levels or nil)
	local journeys = { Carry(data, player, log, prefs, mapName) }
	-- The zone the player's level fits best, named after it. Model.Story (F4) makes it the chapter of a chain; until
	-- then it holds the zone's pickups, as the route did.
	local zone = zones[1]
	local chain, chainID, continues, story, lead, _
	if zone then
		chain, chainID, continues = ZoneStory(data, completed, eligible, zone)
		story, _, lead = ZoneJourney(data, player, eligible, zone, index, prefs, mapName, chainID)
	end
	if story then
		local name = ZoneName(data, zone, mapName)
		story.kind, story.key = "story", "story:" .. zone
		story.title = L.JOURNEY_STORY:format(name)
		-- With a chain, the card tells its chapter in place of the zone's count, and its step says so on the map.
		if chain and lead then
			story.story = chain
			story.subline = chain.total and L.CHAPTER_OF:format(chain.chapter, chain.total)
				or L.CHAPTER:format(chain.chapter)
			story.reason = continues and L.CONTINUES_STORY or L.BEGINS_STORY
			lead.chapter, lead.reason = story.subline, story.reason
			-- A lone quest's detail is its reason, so the row never says the chain continues under a card that begins it.
			lead.detail = #lead.quests == 1 and story.reason or lead.detail
		end
		journeys[#journeys + 1] = story
	end
	-- A player who turned dungeons on asked for this card, so it comes before the next zone's.
	journeys[#journeys + 1] = DungeonJourney(data, player, eligible, index, prefs, mapName, instanceName)
	-- The zone that fits two levels on, when it is another zone than the story's and the one the player stands in,
	-- and already has enough the player can take now.
	for _, map in ipairs(ahead or {}) do
		if map ~= zone and map ~= player.map then
			local nextZone, quests = ZoneJourney(data, player, eligible, map, index, prefs, mapName)
			if nextZone and quests >= NEXT_ZONE_PICKUPS and #journeys < MAX_JOURNEYS then
				nextZone.kind, nextZone.key = "nextzone", "nextzone:" .. map
				local name = ZoneName(data, map, mapName)
				nextZone.title = L.JOURNEY_NEXT_ZONE:format(name, player.level + levels)
				journeys[#journeys + 1] = nextZone
			end
			break
		end
	end
	return journeys
end

-- The route is the chosen journey's steps; the first journey's when the choice is gone or was never made.
local function Route(journeys, prefs)
	local chosen = journeys[1]
	for _, journey in ipairs(journeys) do
		chosen = journey.key == prefs.journey and journey or chosen
	end
	return {
		journeys = journeys,
		journey = chosen and chosen.key,
		steps = chosen and chosen.steps or {},
	}
end

---@param mapName? fun(map: integer): string? the client's (localised) name for a map; the data's English otherwise
---@param instanceName? fun(id: integer): string? the client's name for an instance Map.ID; the data's otherwise
function Model.Plan(data, player, completed, log, prefs, mapName, instanceName)
	skippedSeen = {}
	local route = Route(Model.Journeys(data, player, completed, log, prefs, mapName, instanceName), prefs)
	route.skipped, skippedSeen = skippedSeen, nil
	return route
end

-- A journey from the last full build without the steps skipped since; the same table when none was.
---@param journey AGFJourney
---@return AGFJourney?
local function Unskipped(journey, skipped)
	local steps = {}
	for _, step in ipairs(journey.steps) do
		if not skipped[step.key] then
			steps[#steps + 1] = step
		end
	end
	if #steps == #journey.steps or #steps == 0 then
		return #steps > 0 and journey or nil
	end
	local copy = {}
	for key, value in pairs(journey) do
		copy[key] = value
	end
	copy.steps, copy.map = steps, steps[1].map
	-- A skipped chapter takes the card's chain with it, as the full build does.
	for _, step in ipairs(journey.steps) do
		if step.chapter and skipped[step.key] then
			copy.story, copy.reason, copy.subline = nil, nil, journey.count
		end
	end
	return copy --[[@as AGFJourney]]
end

-- The in-combat rebuild (Core.lua): the carry journey fresh from the live log, which is what changes in a fight,
-- and every other journey as the last full build left it, less any step skipped since. No eligibility pass over the
-- data and no 2-opt, so it stays cheap; the full build runs once combat ends.
---@param last AGFRoute
function Model.Refresh(data, player, log, prefs, last, mapName)
	local journeys = { Carry(data, player, log, prefs, mapName, true) }
	for _, journey in ipairs(last.journeys) do
		local kept = journey.kind ~= "carry" and Unskipped(journey, prefs.skipped or {})
		if kept then
			journeys[#journeys + 1] = kept
		end
	end
	return Route(journeys, prefs)
end
