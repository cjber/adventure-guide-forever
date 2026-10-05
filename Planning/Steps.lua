---@type string, AGFNamespace
local _, ns = ...
local Model = ns.Model
local NONE = {}
local CLOSE = ns.Planner.Travel.CLOSE
local CostTo = ns.Planner.Travel.CostTo
local Distance = ns.Planner.Travel.Distance
local Dropped = ns.Planner.Eligibility.Dropped
local Eligible = ns.Planner.Eligibility.Eligible
local Index = ns.Planner.Eligibility.Index
local ORANGE = ns.Planner.Eligibility.ORANGE
local Point = ns.Planner.Travel.Point
local ValidPlace = ns.Model.ValidPlace

-- The live map POI still places a completed Forever quest when GetNextWaypoint and QuestieDB do not.
local function TurnInPlace(entry, quest)
	return ValidPlace(entry) and entry or ValidPlace(entry.poi) and entry.poi or quest and quest.finish
end

local function Count(one, many, count)
	return count == 1 and one or many:format(count)
end

-- A quest's level for its colour: the log's, the data's otherwise; a scaling quest (-1) is the player's own.
local function QuestLevel(data, log, player, id)
	local entry, quest = log[id], data.quests[id]
	local level = (entry and entry.level) or (quest and quest.level)
	return (level and level > 0) and level or player.level
end

-- Not grey now, grey at the next level: the stock colours' last chance.
local function GreyRisk(level, player)
	return not Model.IsGray(level, player.level) and Model.IsGray(level, player.level + 1)
end

local function Optional(quest, level, player)
	return (quest and (quest.elite or quest.dungeon) and true)
		or level - player.level >= ORANGE
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
		optional = optional or nil,
	}
end

-- The town a place stands in (the data's hub), so a stop keeps its identity when one of the town's quests is taken
-- or done. A place the generator could not put in a town is a town of its own.
---@param place AGFPlace
local function Hub(place)
	return place.hub and tostring(place.hub) or string.format("%d:%.4f:%.4f", place.map, place.x, place.y)
end

-- The visit to `place`'s town among `stops` (by key), made and added to `steps` when the card has none yet, with quest
-- `id` added to its `list` ("handins" or "pickups"), which `place` finishes or starts. Every card keys a town the same
-- way, so a town skipped is skipped wherever it shows. Its point is the first quest's place until Build moves it to
-- the giver nearest the route.
---@param place AGFPlace
---@param list "handins"|"pickups"
---@return AGFStep
local function Visit(stops, steps, place, list, id)
	local key = "town:" .. Hub(place)
	local town = stops[key]
	if not town then
		town = {
			kind = "town",
			key = key,
			hub = place.hub,
			title = "",
			detail = "",
			reason = "",
			quests = {},
			pickups = {},
			handins = {},
			givers = {},
			group = 0,
			spots = {},
			map = place.map,
			x = place.x,
			y = place.y,
		}
		stops[key] = town
		steps[#steps + 1] = town
	end
	town[list][#town[list] + 1] = id
	town.quests[#town.quests + 1] = id
	town.spots[id] = place
	return town
end

-- Describe's sort key per quest ID, reused across calls: hand-in first, then grey at the next level, then the level
-- gap, then the ID, packed into one exact number.
---@type table<integer, number>
local describeOrder = {}
local function DescribeBefore(a, b)
	return describeOrder[a] < describeOrder[b]
end

-- A town's quests, givers, group count, title and detail, from its pickups and hand-ins; it is optional only when
-- every quest there is. The quests go in describeOrder's order, and the givers and the quest ShowQuest opens follow
-- it. One quest keeps the single step's title; several take the town's name, else their busiest giver's.
---@param step AGFStep
---@param log table<integer, AGFLogQuest>
local function Describe(data, log, player, step)
	local L = ns.L
	-- A trainer's stop has no quests: its reason is the spells waiting there.
	if step.kind == "trainer" then
		step.reason = Count(L.TRAINER_SPELL, L.TRAINER_SPELLS, player.train.count)
		step.detail = step.reason
		return
	end
	local optional, handins, pickups = true, step.handins or NONE, step.pickups or NONE
	for pass = 1, 2 do
		for _, id in ipairs(pass == 1 and handins or pickups) do
			local level = QuestLevel(data, log, player, id)
			describeOrder[id] = ((pass - 1) * 2 + (GreyRisk(level, player) and 0 or 1)) * 2 ^ 40
				+ Model.LevelPreference(level, player.level) * 2 ^ 32
				+ id
			optional = optional and Optional(data.quests[id], level, player)
		end
	end
	step.optional = optional or nil
	table.sort(step.handins, DescribeBefore)
	table.sort(step.pickups, DescribeBefore)
	local quests, givers, counts, group = {}, {}, {}, 0
	for pass = 1, 2 do
		for _, id in ipairs(pass == 1 and handins or pickups) do
			quests[#quests + 1] = id
			local name, quest = step.spots[id].name, data.quests[id]
			if not counts[name] then
				counts[name], givers[#givers + 1] = 0, name
			end
			counts[name] = counts[name] + 1
			group = group + ((quest and (quest.elite or quest.dungeon or quest.raid)) and 1 or 0)
		end
	end
	local busiest = givers[1]
	for _, name in ipairs(givers) do
		busiest = counts[name] > counts[busiest] and name or busiest
	end
	local town = step.hub and data.hubs and data.hubs[step.hub]
	step.quests, step.givers, step.group = quests, givers, group
	step.place = town and town.name or busiest
	if #quests == 1 then
		local id, quest = quests[1], data.quests[quests[1]]
		if #step.handins == 1 then
			step.title = L.TURN_IN:format((log[id] and log[id].title) or quest.title)
			step.reason = (step.returns and step.returns[id]) and L.HAND_IN_WHEN_DONE or L.READY_TO_HAND_IN
		else
			step.title = L.PICK_UP:format(step.spots[id].name)
			step.reason = (quest.pre or quest.preAny) and L.CONTINUES_STORY or L.NEAR_YOUR_LEVEL
		end
	else
		step.title = step.place
		local handing = #step.handins > 0 and L.HUB_HAND_IN:format(#step.handins) or nil
		local picking = #step.pickups > 0 and L.HUB_PICK_UP:format(#step.pickups) or nil
		step.reason = handing and picking and handing .. L.LIST_SEPARATOR .. picking or handing or picking or ""
	end
	step.detail = step.reason
end

-- A town says when its hand-ins open the next chapter there: the data proves the chapter starts in the same town and
-- Check proves it shut now and open once the hand-in is done (the data's `next` alone is display-only). A follow-up is
-- never added as a pickup before the turn-in: it comes with the rebuild after QUEST_TURNED_IN. Nothing is said when
-- the data cannot prove it.
---@param step AGFStep
local function Opens(data, player, completed, log, step)
	local groups, opens = Index(data).groups, false
	for _, id in ipairs(step.hub and step.handins or NONE) do
		local nextID = data.quests[id] and data.quests[id].next
		local quest = nextID and data.quests[nextID]
		local after = setmetatable({ [id] = true }, { __index = completed })
		if
			quest
			and quest.start
			and quest.start.hub == step.hub
			and not Eligible(data, player, completed, log, nextID, groups)
			and Eligible(data, player, after, log, nextID, groups)
		then
			opens = true
		end
	end
	if opens then
		step.reason = ns.L.OPENS_CHAPTER_HERE
		step.detail = #step.quests == 1 and step.reason or step.detail
	end
end

-- The data's need slots each client objective type fills, each kind in slot order (tools/gen_quests.py): a kill or
-- use takes 0-3, a collect 4-7, an explore 16.
local EXPLORE_SLOT = 16
local SLOTS = { monster = { 0, 3 }, object = { 0, 3 }, item = { 4, 7 }, event = { EXPLORE_SLOT, EXPLORE_SLOT } }
Model.EXPLORE_SLOT = EXPLORE_SLOT

-- The data's need slots still open for a quest under way, each to the client's objective for it. The client's
-- objectives line up with the slots only when it lists as many as the data needs and each kind fills a slot of its
-- own; otherwise every slot counts as open, to `true`, and the second return is false.
---@param quest AGFQuest
---@param entry AGFLogQuest
---@return table<integer, AGFLogObjective|true>, boolean aligned
local function OpenSlots(quest, entry)
	local slots, open = {}, {}
	for slot in pairs(quest.need or NONE) do
		slots[#slots + 1], open[slot] = slot, true
	end
	local objectives = entry.objectives
	if not objectives or #objectives ~= #slots then
		return open, false
	end
	table.sort(slots)
	local aligned, used = {}, {}
	for _, objective in ipairs(objectives) do
		local range, slot = SLOTS[objective.type], nil
		for _, candidate in ipairs(range and slots or NONE) do
			if
				not slot
				and not used[candidate]
				and candidate >= range[1]
				and candidate <= range[2]
				and (not quest.kinds or quest.kinds[candidate] == objective.type)
			then
				slot = candidate
			end
		end
		if not slot then
			return open, false
		end
		used[slot], aligned[slot] = true, (not objective.done) and objective or nil
	end
	return aligned, true
end

function Model.ObjectiveDone(data, entry, slot)
	local quest = entry and data.quests[entry.id]
	if not quest then
		return false
	end
	local open, aligned = OpenSlots(quest, entry)
	return aligned and quest.need[slot] ~= nil and open[slot] == nil
end

-- One open objective of a quest under way: the client's count and words for it when its objectives line up with the
-- data's slots (`counted`), the data's count otherwise, and the town it is handed in at, which a route visits after.
---@param quest? AGFQuest
---@param entry AGFLogQuest
---@param slot integer
---@param counted AGFLogObjective|true|nil
---@return AGFAreaObjective
local function Objective(quest, entry, slot, counted)
	local client = counted ~= true and counted or nil
	local finish = quest and quest.finish
	return {
		id = entry.id,
		slot = slot,
		have = client and client.have,
		-- A client count of 0 is a kind it does not tally, not a need of none: the data's count stands then.
		need = client and client.need ~= 0 and client.need or (quest and quest.need and quest.need[slot]),
		text = client and client.text ~= "" and client.text or nil,
		type = client and client.type,
		finish = (finish and ValidPlace(finish)) and "town:" .. Hub(finish) or nil,
	}
end

-- Quest `quest`'s node for objective `slot`: its first area for the slot (the generator orders them) with its radius,
-- counting `objective`. Nil when the data has no area for the slot or its place is not a valid one.
---@param quest AGFQuest
---@return AGFNode?
local function AreaNode(quest, slot, objective)
	for _, area in ipairs(quest.obj or NONE) do
		if area[1] == slot then
			local node = {
				map = area[5] or quest.zone or 0, -- 0: no map, which ValidPlace refuses
				x = area[2] / 1000,
				y = area[3] / 1000,
				r = area[4],
				slot = slot,
				objectives = { objective },
			}
			return ValidPlace(node) and node or nil
		end
	end
	return nil
end

-- Where a quest under way is done next, in slot order: each open objective the data places, at its first area (the
-- generator orders them) with its radius. The client's point for the quest stands in for them all when its objectives
-- don't line up with the data's slots or the data places none of the open ones, and the client's waypoint (the live
-- client gives one only once finished) before anything. Empty when nothing places it.
---@param entry AGFLogQuest
---@return AGFNode[]
local function Nodes(data, entry)
	local quest = data.quests[entry.id]
	local open, aligned, slots, nodes = {}, false, {}, {}
	if quest then
		open, aligned = OpenSlots(quest, entry)
	end
	for slot in pairs(open) do
		slots[#slots + 1] = slot
	end
	table.sort(slots)
	for _, slot in ipairs(ValidPlace(entry) and NONE or slots) do
		nodes[#nodes + 1] = AreaNode(quest, slot, Objective(quest, entry, slot, open[slot]))
	end
	if #nodes > 0 and (aligned or not ValidPlace(entry.poi)) then
		return nodes
	end
	local point = ValidPlace(entry) and entry or ValidPlace(entry.poi) and entry.poi or nil
	if not point then
		return nodes
	end
	local objectives = {}
	for _, slot in ipairs(slots) do
		objectives[#objectives + 1] = Objective(quest, entry, slot, open[slot])
	end
	return { { map = point.map, x = point.x, y = point.y, r = 0, slot = slots[1] or 0, objectives = objectives } }
end

-- An area's reason: how many quests are done there; a lone quest the route picks up first says so.
---@param area AGFStep
local function Tell(area)
	local planned = area.planned and area.planned[area.quests[1]]
	area.reason = #area.quests > 1 and ns.L.QUESTS_HERE:format(#area.quests)
		or planned and ns.L.AFTER_PICK_UP
		or ns.L.QUESTS_IN_PROGRESS
	area.detail = area.reason
end

-- Objective nodes share an area when one's point lies in the other's ring (0 for a single point or the client's
-- point) or within AREA_GAP of it: rings that merely overlap stay apart, so a merged ring never runs across a zone.
-- On a map the data places nowhere, CLOSE in map units.
local AREA_GAP = 60

---@param a AGFNode
---@param b AGFNode
local function Inside(yards, a, b)
	return yards <= math.max(a.r, b.r) + AREA_GAP
end

---@param a AGFNode
---@param b AGFNode
local function Near(data, a, b)
	local yards = Model.Yards(data, a, b)
	if yards then
		return Inside(yards, a, b)
	end
	return Distance(a, b) <= CLOSE
end

-- Adds `node` (quest `id`'s) to the first of `areas` of its kind it nearly touches (`near`, against the area's first
-- node in `anchors`), else as a new area keyed by its quest and slot, added to `steps` too; the ring grows to hold it.
-- A quest the route picks up first (`planned`) is marked so on the area.
---@param node AGFNode
---@param near fun(a: AGFNode, b: AGFNode): boolean
---@return AGFStep
local function Gather(data, areas, anchors, steps, node, id, title, kind, optional, near, planned)
	local area
	for _, step in ipairs(areas) do
		area = area or (step.kind == kind and near(anchors[step], node) and step or nil)
	end
	if area then
		area.quests[#area.quests + 1] = area.quests[#area.quests] ~= id and id or nil
		area.optional = area.optional and optional or nil
	else
		area = Step(kind, ("area:%d:%d"):format(id, node.slot), title, node, id, optional, "")
		area.objectives, area.r, area.shapes, anchors[area] = {}, node.r, {}, node
		areas[#areas + 1], steps[#steps + 1] = area, area
	end
	area.shapes[#area.shapes + 1] = node
	if planned then
		area.planned = area.planned or {}
		area.planned[id] = true
	end
	for _, objective in ipairs(node.objectives) do
		area.objectives[#area.objectives + 1] = objective
	end
	area.r = math.max(area.r, (Model.Yards(data, area, node) or 0) + node.r)
	return area
end

-- The log quests a card holds, as steps added to `steps`, and the card's count of them. The quest and dungeon prefs
-- choose what to pick up; a quest already carried always shows, whatever its kind. A finished quest in `ready` (the
-- data and the client agree where it is handed in) joins its town's visit in `stops`, the towns the card's pickups
-- share; any other finished quest is a turn-in at its hand-in. A quest under way is done in areas (Nodes), each merged
-- with the nearby ones of its kind (Near) into one visit keyed by its first quest and slot, its ring wide enough for
-- them all. One nothing places has no step, and still counts: `held` maps every quest the card holds to its first
-- step, or false. `plan` keeps the areas and their first nodes, for a lap's pickups to join (Laps).
---@param ready table<integer, AGFPlace>
---@param belongs fun(id: integer, place?: table): boolean which log quests the card holds, by where they are done next
---@param plan AGFPlanAreas
---@return table<integer, AGFStep|false> held
local function LogSteps(data, player, log, ready, belongs, stops, steps, plan)
	local ids, held = {}, {}
	local function Touches(a, b)
		return Near(data, a, b)
	end
	for id in pairs(log) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local entry, quest = log[id], data.quests[id]
		local nodes = entry.complete and {} or Nodes(data, entry)
		---@type AGFPlace?
		local place = ready[id] or (entry.complete and TurnInPlace(entry, quest)) or nodes[1]
		place = ValidPlace(place) and place or nil
		if belongs(id, place) then
			held[id] = false
			local optional = Optional(quest, entry.level, player)
			if ready[id] then
				held[id] = Visit(stops, steps, ready[id], "handins", id)
			elseif place and entry.complete then
				steps[#steps + 1] = Step(
					"turnin",
					"turnin:" .. id,
					ns.L.TURN_IN:format(entry.title),
					place,
					id,
					optional,
					ns.L.READY_TO_HAND_IN
				)
				held[id] = steps[#steps]
			end
			local kind = (quest and (quest.elite or quest.dungeon)) and "dungeon" or "area"
			for _, node in ipairs(place and nodes or NONE) do
				local area =
					Gather(data, plan.areas, plan.anchors, steps, node, id, entry.title, kind, optional, Touches)
				held[id] = held[id] or area
			end
		end
	end
	for _, area in ipairs(plan.areas) do
		Tell(area)
	end
	return held
end

-- One visit per town of the eligible quests `wanted` accepts; a group quest joins its town's like any other. `stops`
-- holds the towns the card already has (LogSteps' hand-ins), which a pickup there joins.
---@param wanted fun(quest: AGFQuest): boolean
local function PickupSteps(data, eligible, wanted, steps, stops)
	local chosenGroups = {}
	stops = stops or {}
	for _, id in ipairs(eligible) do
		local quest = data.quests[id]
		if wanted(quest) and not (quest.group and chosenGroups[quest.group]) then
			if quest.group then
				chosenGroups[quest.group] = true
			end
			Visit(stops, steps, quest.start, "pickups", id)
		end
	end
end

-- The finished log quests whose hand-in the data and the client agree on: the client's waypoint stands in the same
-- town as the data's finish, which is in a town. Each maps to that finish; none ruled out.
---@return table<integer, AGFPlace>
local function Ready(data, log)
	local ready = {}
	for id, entry in pairs(log) do
		local quest = not Dropped(id) and data.quests[id]
		local finish = entry.complete and quest and quest.finish
		if finish and finish.hub then
			local point = TurnInPlace(entry, nil)
			if point and Model.Hub(data, point) == finish.hub then
				ready[id] = finish
			end
		end
	end
	return ready
end

-- Where a step is, for its "NPC, zone" line: the zone is the client's name for its map, the data's otherwise. A turn-in
-- names the data's finish NPC only while its point stands in that finish's town; a town named itself in Describe; a
-- trainer's stop is titled by its town.
---@param step AGFStep
---@param mapName? AGFMapName
local function Locate(data, step, mapName)
	step.zone = (mapName and mapName(step.map)) or (data.maps and data.maps[step.map] and data.maps[step.map].name)
	if step.kind == "trainer" then
		step.title = ns.L.TRAIN_IN:format(Model.TownName(data, step, mapName))
	elseif step.kind == "turnin" then
		local quest = data.quests[step.quests[1]]
		local finish = quest and quest.finish
		step.place = finish and Model.Hub(data, step) == finish.hub and finish.name or nil
	end
end

-- An area's point is the objective node nearest `from` (the stop before it, or the player): each node is a place the
-- data has (a spawn group's medoid, or the point the generator placed inside a shape), so the route targets the work
-- itself rather than a spot on the shape's ring, where the marker reads as the area's border. The nearest node is the
-- near end of a long area; a node the player already stands in keeps the point on the work, not the far node.
-- Where the data cannot measure the way, or the player is already inside (no `from`), the point stays the middle
-- (the area's first node, the centroid they stand on).
---@param step AGFStep
---@param from? AGFPosition
local function Enter(data, step, from)
	if not (from and from.known) then
		return
	end
	local best, bestGap
	for _, shape in ipairs(step.shapes or NONE) do
		local x, y, continent, known = Point(data, shape)
		if known and continent == from.continent then
			local gap = math.sqrt((from.x - x) ^ 2 + (from.y - y) ^ 2) - shape.r
			if not best or gap < bestGap then
				best, bestGap = shape, gap
			end
		end
	end
	if not best then
		return
	end
	step.map, step.x, step.y = best.map, best.x, best.y
end

-- A town's name for the player: its own, else the client's name for its map, else the data's. Only names the data has.
---@param data AGFData
---@param place {map: integer, hub?: integer}
---@param mapName? AGFMapName
---@return string
function Model.TownName(data, place, mapName)
	local town = data.hubs and place.hub and data.hubs[place.hub] or nil
	if town then
		return (town.name:match("^(.-),") or town.name)
	end
	return (mapName and mapName(place.map)) or data.maps[place.map].name
end

-- A town points at the quest giver nearest the preceding stop.
---@param step AGFStep
---@param from? AGFPosition
local function TownPoint(data, step, from)
	local best, bestCost
	for _, id in ipairs(step.quests) do
		local cost = CostTo(from, Point(data, step.spots[id])) -- multi-value: the spot's point
		if not best or cost < bestCost then
			best, bestCost = step.spots[id], cost
		end
	end
	step.map, step.x, step.y = best.map, best.x, best.y
end

-- A town's lists after some of its quests went: its hand-ins first, as Visit adds them.
---@param town AGFStep
local function Trim(town, handins, pickups)
	town.handins, town.pickups, town.quests = handins, pickups, {}
	for _, list in ipairs({ handins, pickups }) do
		for _, id in ipairs(list) do
			town.quests[#town.quests + 1] = id
		end
	end
end

-- A new quest's objective nodes, one for each slot at its first area (AreaNode, as for a quest under way), each
-- counting the data's need.
---@param quest AGFQuest
---@return AGFNode[]
local function Planned(quest, id)
	local slots, nodes = {}, {}
	for slot in pairs(quest.need or NONE) do
		slots[#slots + 1] = slot
	end
	table.sort(slots)
	local finish = ValidPlace(quest.finish) and "town:" .. Hub(quest.finish) or nil
	for _, slot in ipairs(slots) do
		nodes[#nodes + 1] = AreaNode(quest, slot, { id = id, slot = slot, need = quest.need[slot], finish = finish })
	end
	return nodes
end

ns.Planner.Steps = {
	Count = Count,
	Describe = Describe,
	Enter = Enter,
	Gather = Gather,
	GreyRisk = GreyRisk,
	Hub = Hub,
	Inside = Inside,
	Locate = Locate,
	LogSteps = LogSteps,
	Nodes = Nodes,
	Opens = Opens,
	Optional = Optional,
	PickupSteps = PickupSteps,
	Planned = Planned,
	QuestLevel = QuestLevel,
	Ready = Ready,
	Tell = Tell,
	TownPoint = TownPoint,
	Trim = Trim,
	Visit = Visit,
}
