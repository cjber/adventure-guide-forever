---@type string, AGFNamespace
local _, ns = ...
local Model = ns.Model
local State = ns.Planner.State
local NONE = {}
local CLOSE = ns.Planner.Travel.CLOSE
local Cost = ns.Planner.Travel.Cost
local Describe = ns.Planner.Steps.Describe
local Distance = ns.Planner.Travel.Distance
local Docks = ns.Planner.Travel.Docks
local Enter = ns.Planner.Steps.Enter
local Gap = ns.Planner.Travel.Gap
local Gather = ns.Planner.Steps.Gather
local Hub = ns.Planner.Steps.Hub
local Ident = ns.Planner.Routing.Ident
local Idents = ns.Planner.Routing.Idents
local Inside = ns.Planner.Steps.Inside
local Locate = ns.Planner.Steps.Locate
local Opens = ns.Planner.Steps.Opens
local Optional = ns.Planner.Steps.Optional
local NearAction = ns.Planner.Routing.NearAction
local Planned = ns.Planner.Steps.Planned
local Position = ns.Planner.Travel.Position
local QuestLevel = ns.Planner.Steps.QuestLevel
local Recommit = ns.Planner.Routing.Recommit
local Stabilise = ns.Planner.Routing.Stabilise
local Tell = ns.Planner.Steps.Tell
local TownPoint = ns.Planner.Steps.TownPoint
local Trim = ns.Planner.Steps.Trim
local UNKNOWN = ns.Planner.Travel.UNKNOWN
local ValidPlace = ns.Model.ValidPlace
local Visit = ns.Planner.Steps.Visit
local Yards = ns.Planner.Travel.Yards

--[[ Laps (docs/design.md §4.2): the route of card 1 and of the chosen card as a player running a guide goes: pick up
     in town, clear the objective areas out one side of it, come back and hand in. Every other card keeps Build's route,
     so a rebuild stays inside its frame budget. ]]

---@param standsIn AGFStep
---@return AGFStep
local function LeadingArea(standsIn)
	local lead = {}
	---@cast lead AGFStep
	for key, value in pairs(standsIn) do
		lead[key] = value
	end
	lead.objectives, lead.quests = {}, {}
	for _, objective in ipairs(standsIn.objectives or NONE) do
		lead.objectives[#lead.objectives + 1] = not standsIn.planned[objective.id] and objective or nil
	end
	for _, objective in ipairs(lead.objectives) do
		lead.quests[#lead.quests + 1] = lead.quests[#lead.quests] ~= objective.id and objective.id or nil
	end
	Tell(lead)
	return lead
end

local RUN = 7 -- yards a second at a run
local LAP_YARDS = 15 * 60 * RUN -- a lap's travel and work: about a quarter of an hour out of town and back
local WORK_YARDS = 4 * RUN -- one count of an objective (a kill, an item): about four seconds' work
local TALK_YARDS = 10 * RUN -- a quest's pickup and its hand-in
-- A conservative work estimate, not measured kill times: above-level objectives take longer and need more recovery.
local function WorkFactor(level, player)
	local above = math.max(0, level - player.level)
	return 1 + above * above * 0.5
end

local KEEP = 0.5 -- a new quest worth less than this share of its town's mean XP per yard waits for a later lap

-- The XP `quest` gives at `level`: CMaNGOS Quest::XPValue, whole up to 5 levels above the quest, then 0.8, 0.6, 0.4 and
-- 0.2 of it, and 0.1 from 10 levels on. Nil where the data has none (a scaling quest's).
---@param quest AGFQuest
function Model.QuestXP(quest, level)
	if not quest.xp or quest.level < 1 then
		return nil
	end
	local over = level - quest.level
	return quest.xp * (over <= 5 and 1 or over >= 10 and 0.1 or 1 - (over - 5) * 0.2)
end

-- Whether a lap may take up a new quest for the player (docs/design.md §4.2): not one a script completes or a
-- timer ends, and each of its objectives in an area the data has. A quest with none (a talk or delivery quest) needs
-- only its pickup and hand-in.
---@param quest AGFQuest
local function Pickable(quest)
	local flags = quest.flags
	if quest.objectivesUnknown or (flags and (flags.event or flags.timed)) then
		return false
	end
	for slot in pairs(quest.need or NONE) do
		local placed = false
		for _, area in ipairs(quest.obj or NONE) do
			placed = placed or area[1] == slot
		end
		if not placed then
			return false
		end
	end
	return true
end

local function Skip(key)
	if State.skippedSeen then
		State.skippedSeen[key] = true
	end
end

---@param lap AGFLapState
---@param place table
---@return AGFPosition?
local function LapPosition(lap, place)
	local position = lap.where[place]
	if position == nil then
		position = Position(lap.data, place, lap.docks) or false
		lap.where[place] = position
	end
	return position or nil
end

---@param lap AGFLapState
local function PickLapQuests(lap)
	local data, player, log, towns, areas, plan, planned, leadID, pinned, skipped, origin =
		lap.data,
		lap.player,
		lap.log,
		lap.towns,
		lap.areas,
		lap.plan,
		lap.planned,
		lap.leadID,
		lap.pinned,
		lap.skipped,
		lap.origin
	local at = lap.at
	-- The new quests each town hands out, and their objective nodes.
	local picks, ids, nodes, offered = lap.picks, lap.ids, lap.nodes, lap.offered
	for _, town in ipairs(towns) do
		local pickups = {}
		for _, id in ipairs(town.pickups) do
			-- One the player added (shift-click) goes whatever its kind, as the lead does.
			if id == leadID or pinned[id] or Pickable(data.quests[id]) then
				pickups[#pickups + 1], picks[id], ids[#ids + 1] = id, town, id
				-- An outdoor elite is picked up, optional and with the group badge, but its work waits for a group.
				nodes[id] = data.quests[id].elite and {} or Planned(data.quests[id], id)
			end
		end
		Trim(town, town.handins, pickups)
	end
	table.sort(ids)

	-- Each new quest's worth against its detour: out to each of its nodes from the nearest of its town, the log's areas
	-- and the other new nodes, and back, with the work there and the talk.
	local ratio, sums, counts, all, owner = lap.ratio, {}, {}, {}, {}
	for _, id in ipairs(ids) do
		for _, node in ipairs(nodes[id]) do
			all[#all + 1], owner[node] = node, id
		end
	end
	for _, id in ipairs(ids) do
		local quest, town = data.quests[id], picks[id]
		local worth = Model.QuestXP(quest, player.level)
		if worth then
			local yards = TALK_YARDS
			for _, node in ipairs(nodes[id]) do
				local p = at(node)
				local nearest = Gap(at(town) or origin, 0, p, node.r)
				for _, area in ipairs(areas) do
					nearest = math.min(nearest, Gap(at(area), area.r, p, node.r))
				end
				-- Nothing is nearer than touching, so the search stops there.
				for _, near in ipairs(all) do
					if nearest == 0 then
						break
					end
					nearest = owner[near] ~= id and math.min(nearest, Gap(at(near), near.r, p, node.r)) or nearest
				end
				yards = yards
					+ 2 * nearest
					+ math.max(1, node.objectives[1].need or 0) * WORK_YARDS * WorkFactor(quest.level, player)
			end
			ratio[id] = worth / yards
			sums[town], counts[town] = (sums[town] or 0) + ratio[id], (counts[town] or 0) + 1
		end
	end
	local function Touches(a, b)
		local here, there = at(a), at(b)
		if here and there and here.known and there.known and here.continent == there.continent then
			return Inside(Yards(here, there), a, b)
		end
		return Distance(a, b) <= CLOSE
	end
	local fresh = {}
	for _, town in ipairs(towns) do
		local pickups = {}
		for _, id in ipairs(town.pickups) do
			-- The planned mode drops a pickup worth less than KEEP of its town's mean XP per yard; nearest keeps it.
			if
				not planned
				or id == leadID
				or pinned[id]
				or not ratio[id]
				or ratio[id] >= KEEP * sums[town] / counts[town]
			then
				pickups[#pickups + 1] = id
				local quest = data.quests[id]
				local optional = Optional(quest, QuestLevel(data, log, player, id), player)
				for _, node in ipairs(nodes[id]) do
					Gather(data, areas, plan.anchors, fresh, node, id, quest.title, "area", optional, Touches, true)
				end
			else
				picks[id] = nil
			end
		end
		Trim(town, town.handins, pickups)
		offered[town.key] = pickups
	end
	for index = #areas, 1, -1 do
		if skipped[areas[index].key] then
			Skip(areas[index].key)
			table.remove(areas, index)
		end
	end
end

---@param lap AGFLapState
local function NameLapAreas(lap)
	local areas, rank = lap.areas, lap.rank
	-- An area keeps the key the committed order knows it by when a quest taken up since, or the lap's pickup, joins
	-- it and would key it anew: the key of its objective the order places first.
	local named = {}
	for _, area in ipairs(areas) do
		named[area.key] = true
	end
	for _, area in ipairs(areas) do
		Tell(area)
		local best = rank[area.key] and area.key or nil
		for _, objective in ipairs(best and NONE or area.objectives) do
			local key = ("area:%d:%d"):format(objective.id, objective.slot)
			if rank[key] and not named[key] and (not best or rank[key] < rank[best]) then
				best = key
			end
		end
		if best and best ~= area.key then
			named[area.key], named[best], area.key = nil, true, best
		end
	end
end

---@param lap AGFLapState
local function Anchor(lap, key, place)
	local anchors, list, at = lap.anchors, lap.list, lap.at
	local anchor = anchors[key]
	if not anchor then
		anchor = { key = key, place = place, pos = at(place), stops = {}, hands = {} }
		anchors[key], list[#list + 1] = anchor, anchor
	end
	return anchor
end

-- A stop no quest's town takes goes to the nearest town within half a lap, else to the laps around the player.
---@param lap AGFLapState
local function Closest(lap, step)
	local list, at = lap.list, lap.at
	local best, bestCost
	for _, anchor in ipairs(list) do
		local cost = anchor.key ~= "" and anchor.pos and Cost(anchor.pos, at(step)) or UNKNOWN
		if cost <= LAP_YARDS / 2 and (not best or cost < bestCost) then
			best, bestCost = anchor, cost
		end
	end
	return best or Anchor(lap, "", lap.player)
end

---@param lap AGFLapState
local function BuildLapAnchors(lap)
	local data, towns, areas, picks, ids, skipped, others, anchors, list =
		lap.data, lap.towns, lap.areas, lap.picks, lap.ids, lap.skipped, lap.others, lap.anchors, lap.list
	local at = lap.at
	for _, town in ipairs(towns) do
		if #town.quests > 0 then
			Anchor(lap, town.key, town).open = town
		end
	end
	local pending, carried, homes = lap.pending, {}, {}
	for _, area in ipairs(areas) do
		for _, objective in ipairs(area.objectives) do
			local id = objective.id
			pending[id] = (pending[id] or 0) + 1
			if not picks[id] and homes[id] == nil then
				carried[#carried + 1], homes[id] = id, false
				local finish = data.quests[id] and data.quests[id].finish
				local key = ValidPlace(finish) and "town:" .. Hub(finish --[[@as AGFPlace]])
				if
					key
					and not skipped[key]
					and Cost(at(area), at(finish --[[@as AGFPlace]])) <= LAP_YARDS / 2
				then
					---@cast finish AGFPlace
					homes[id] = Anchor(lap, key, finish)
				end
			end
		end
	end
	table.sort(carried)
	for _, id in ipairs(carried) do
		-- A carried quest is handed in only once the route can place and work every objective it needs: one whose data
		-- misses an objective is left to the log, where the full build makes it a ready hand-in once it is done.
		local quest, slots = data.quests[id], 0
		for _ in pairs((quest and quest.need) or NONE) do
			slots = slots + 1
		end
		if pending[id] == slots then
			table.insert(homes[id] and homes[id].hands or {}, id)
		end
	end
	for _, id in ipairs(ids) do
		local town, finish = picks[id], data.quests[id].finish
		homes[id] = town and anchors[town.key] or false
		-- A lap hands in only what it does: not an outdoor elite, whose work waits for a group, nor a lead or pinned
		-- quest whose work the data places nowhere. A quest the route cannot finish stays with the log; finishing it
		-- makes it a ready hand-in on the next full build.
		local quest = data.quests[id]
		local handin = not quest.elite and Pickable(quest)
		if
			town
			and handin
			and ValidPlace(finish)
			and "town:" .. Hub(finish --[[@as AGFPlace]]) == town.key
		then
			table.insert(anchors[town.key].hands, id)
		end
	end
	-- A town with only hand-ins ready, which no lap comes back to, is a stop on the way like a turn-in.
	for index = #list, 1, -1 do
		local anchor = list[index]
		if #list > 1 and anchor.open and #anchor.open.pickups == 0 and #anchor.hands == 0 then
			others[#others + 1], anchors[anchor.key] = anchor.open, nil
			table.remove(list, index)
		end
	end
	-- An area goes with the town most of its objectives go back to, the first of them on a tie.
	for _, area in ipairs(areas) do
		local anchor, votes = nil, {}
		for _, objective in ipairs(area.objectives) do
			local home = homes[objective.id]
			if home then
				votes[home] = (votes[home] or 0) + 1
				anchor = (not anchor or votes[home] > votes[anchor]) and home or anchor
			end
		end
		anchor = anchor or Closest(lap, area)
		anchor.stops[#anchor.stops + 1] = area
	end
	local trained = false
	for _, step in ipairs(others) do
		-- A trainer only in a town a lap visits anyway (its hub), and once.
		local anchor
		if step.kind == "trainer" then
			anchor = not trained and step.hub and anchors["town:" .. step.hub] or nil
			trained = trained or anchor ~= nil
		else
			anchor = Closest(lap, step)
		end
		table.insert(anchor and anchor.stops or {}, step)
	end
end

-- All of a town's hand-ins ready to hand in at once, none handed in yet.
---@param lap AGFLapState
---@param walk AGFLapWalk
---@param anchor AGFAnchor
local function Handable(lap, walk, anchor)
	local done, handed, reached = walk.done, walk.handed, walk.reached
	local pending, log = lap.pending, lap.log
	for _, id in ipairs(anchor.hands) do
		if
			(done[id] or 0) ~= (pending[id] or 0)
			or handed[id]
			or not (log[id] or reached[anchor] or anchor.open == nil)
		then
			return false
		end
	end
	return #anchor.hands > 0
end

-- The committed order holds every stop it has, in order (docs/design.md §4.3), so a rebuild or a move never
-- shuffles the route; a pinned quest (and the story's chapter) first among the rest; then the nearest action,
-- with a stop in the town the route is already in preferred while it is within half a lap on its map.
-- The planned mode ranks the committed order, a pinned quest and the story's chapter above plain distance, and
-- finishes a town the route is already in (the look-ahead). The nearest mode ranks by distance alone.
---@param lap AGFLapState
---@param walk AGFLapWalk
---@param choice AGFLapChoice
---@param step AGFStep|AGFAnchor
---@param anchor AGFAnchor
---@param cost number
---@param kind "open"|"stop"|"close"
local function Consider(lap, walk, choice, step, anchor, cost, kind)
	local planned, pinned, leadID, rank, at = lap.planned, lap.pinned, lap.leadID, lap.rank, lap.at
	local lastAnchor = walk.lastAnchor
	local pick, pickRank, pickValue, pickKey = choice.step, choice.rank, choice.value, choice.key
	local pref = 0
	if planned then
		local pin, lead = false, false
		for _, id in ipairs(step.quests or NONE) do
			pin = pin or pinned[id] or false
			lead = lead or id == leadID
		end
		local held = rank[Ident(step)]
		local place = anchor.place
		local same = anchor == lastAnchor
			and anchor.pos ~= nil
			and step.map == place.map
			and Cost(anchor.pos, at(step)) <= LAP_YARDS / 2
		pref = held and held - 6000000 or (pin and -5000000 or (lead and -4000000 or (same and -3000000 or 0)))
	end
	if
		not pick
		or pref < pickRank
		or (pref == pickRank and (cost < pickValue - 1e-6 or (cost <= pickValue + 1e-6 and step.key < pickKey)))
	then
		choice.step, choice.anchor, choice.kind, choice.rank, choice.value, choice.key =
			step, anchor, kind, pref, cost, step.key
	end
end

---@param lap AGFLapState
local function WalkLap(lap)
	local data, log, origin, planned, list, groups = lap.data, lap.log, lap.origin, lap.planned, lap.list, lap.groups
	local at = lap.at
	-- The route is the player's nearest action at every step (docs/design.md §4.1): from where they are, the nearest
	-- town pickup (its open), the nearest area of a quest the town handed out or the player carries, or the nearest
	-- ready hand-in. A stop in the town the route is already in comes before the route leaves it, and a stop already
	-- placed is never revisited. A quest's objectives follow its pickup and its hand-in all of them (Holds and Verify
	-- check the route in order).
	local route, from = {}, origin
	local walk = { done = {}, handed = {}, reached = {} }
	local done, handed, reached = walk.done, walk.handed, walk.reached
	local placed, closed, schooled = {}, {}, false
	-- The planned mode puts the town the player stands in first, whatever leads: its trainer, hand-ins and pickups are
	-- a word away. The nearest mode lets the greedy loop take the nearest stop, which is that town when they stand in it.
	if planned then
		for _, anchor in ipairs(list) do
			for index = #anchor.stops, 1, -1 do
				local stop = anchor.stops[index]
				local town = (stop.kind == "town" or stop.kind == "trainer") and stop.hub
				if town and town == lap.hub then
					placed[stop], walk.lastAnchor = true, anchor
					route[#route + 1] = table.remove(anchor.stops, index)
				end
			end
			local open = not reached[anchor] and anchor.open or nil
			if open and open.hub and open.hub == lap.hub then
				reached[anchor], walk.lastAnchor = true, anchor
				route[#route + 1] = open
			end
		end
		from = route[#route] and at(route[#route]) or from
	end
	-- Leave room for merged visits and log-capacity filtering without planning every eligible stop.
	while #route < Model.MAX_STEPS * 3 do
		local choice = {}
		for _, anchor in ipairs(list) do
			if not reached[anchor] and anchor.open then
				Consider(lap, walk, choice, anchor.open, anchor, Cost(from, at(anchor.open)), "open")
			end
			for _, stop in ipairs(anchor.stops) do
				-- A stop the town's own pickup opens is not a place the route can go yet.
				if not placed[stop] and not (stop.planned and not reached[anchor]) then
					if stop.kind ~= "trainer" or not schooled then
						Consider(lap, walk, choice, stop, anchor, Gap(from, 0, at(stop), stop.r or 0), "stop")
					end
				end
			end
			if not closed[anchor] and Handable(lap, walk, anchor) then
				local cost = anchor.pos and Cost(from, anchor.pos) or UNKNOWN
				Consider(lap, walk, choice, anchor.open or anchor, anchor, cost, "close")
			end
		end
		local pick, pickAnchor, pickKind = choice.step, choice.anchor, choice.kind
		if not pick then
			break
		end
		if pickKind == "close" then
			local closes, close = {}, nil
			for _, id in ipairs(pickAnchor.hands) do
				if not handed[id] then
					close = Visit(closes, {}, data.quests[id].finish, "handins", id)
					close.returns = close.returns or {}
					close.returns[id] = true
					if not log[id] then
						close.planned = close.planned or {}
						close.planned[id] = true
					end
					handed[id] = true
				end
			end
			closed[pickAnchor] = true
			if close then
				route[#route + 1], from, walk.lastAnchor = close, at(close) or from, pickAnchor
			end
		elseif pickKind == "open" then
			reached[pickAnchor] = true
			route[#route + 1], from, walk.lastAnchor = pick, at(pick) or from, pickAnchor
		else
			placed[pick] = true
			schooled = schooled or pick.kind == "trainer"
			for _, objective in ipairs(pick.objectives or NONE) do
				done[objective.id] = (done[objective.id] or 0) + 1
			end
			route[#route + 1], from, walk.lastAnchor = pick, at(pick) or from, pickAnchor
		end
	end
	for _, step in ipairs(groups) do
		route[#route + 1] = step
	end
	lap.route = route
end

---@param lap AGFLapState
---@param steps AGFStep[]
---@return AGFStep[]
local function Verify(lap, steps)
	local log, pending, cap, count, picked, ratio, leadID =
		lap.log, lap.pending, lap.cap, lap.count, lap.picked, lap.ratio, lap.leadID
	local have, did, checked, left, owed = {}, {}, {}, count, 0
	for _, step in ipairs(steps) do
		for _, id in ipairs(step.kind == "town" and step.pickups or NONE) do
			owed = owed + (picked[id] and 1 or 0)
		end
	end
	for _, step in ipairs(steps) do
		if step.kind == "town" then
			local handins, pickups = {}, {}
			for _, id in ipairs(step.handins) do
				local entry, back = log[id], step.returns and step.returns[id]
				if
					(entry and entry.complete and not back)
					or (back and (entry or have[id]) and (did[id] or 0) >= (pending[id] or 0))
				then
					handins[#handins + 1], left = id, left - 1
				end
			end
			local order = {}
			for _, id in ipairs(step.pickups) do
				order[#order + 1] = id
			end
			table.sort(order, function(a, b)
				if (a == leadID) ~= (b == leadID) then
					return a == leadID
				elseif (ratio[a] or math.huge) ~= (ratio[b] or math.huge) then
					return (ratio[a] or math.huge) > (ratio[b] or math.huge)
				end
				return a < b
			end)
			for _, id in ipairs(order) do
				owed = owed - (picked[id] and 1 or 0)
				if left + (picked[id] and 0 or owed) < cap and not have[id] then
					pickups[#pickups + 1], have[id], left = id, true, left + 1
				end
			end
			table.sort(pickups)
			Trim(step, handins, pickups)
		elseif step.objectives then
			local objectives, quests = {}, {}
			for _, objective in ipairs(step.objectives) do
				local id = objective.id
				-- A planned quest can be worked only after its pickup survived log-capacity checks.
				if (log[id] and not log[id].complete) or have[id] then
					objectives[#objectives + 1], did[id] = objective, (did[id] or 0) + 1
					quests[#quests + 1] = quests[#quests] ~= id and id or nil
				end
			end
			step.objectives, step.quests = objectives, quests
		end
		if #step.quests > 0 or step.kind == "trainer" then
			checked[#checked + 1] = step
		end
	end
	return checked
end

-- Whether `steps` may be walked in order: every objective after its quest's pickup, a hand-in the route comes back
-- for after all its objectives there, and the log never past its limit.
---@param lap AGFLapState
---@param steps AGFStep[]
local function Holds(lap, steps)
	local log, cap, count = lap.log, lap.cap, lap.count
	local have, did, total, left = {}, {}, {}, count
	for _, step in ipairs(steps) do
		for _, objective in ipairs(step.objectives or NONE) do
			total[objective.id] = (total[objective.id] or 0) + 1
		end
	end
	for _, step in ipairs(steps) do
		for _, id in ipairs(Model.Handins(step)) do
			if
				not (log[id] or have[id])
				or (step.returns and step.returns[id] and (did[id] or 0) < (total[id] or 0))
			then
				return false
			end
			left = left - 1
		end
		for _, id in ipairs(step.pickups or NONE) do
			have[id], left = true, left + 1
			if left > cap then
				return false
			end
		end
		for _, objective in ipairs(step.objectives or NONE) do
			local id = objective.id
			if not (log[id] or have[id]) then
				return false
			end
			did[id] = (did[id] or 0) + 1
		end
	end
	return true
end

-- Where the player stands leads, whatever the committed order: the town (its trainer, hand-ins and pickups a word
-- away), else the open area.
---@param lap AGFLapState
---@param route AGFStep[]
---@return AGFStep[]
local function Front(lap, route, leads)
	local moved = {}
	for _, step in ipairs(route) do
		moved[#moved + 1] = leads[step] and step or nil
	end
	for _, step in ipairs(route) do
		moved[#moved + 1] = not leads[step] and step or nil
	end
	return Holds(lap, moved) and moved or route
end

---@param lap AGFLapState
local function CommitLap(lap)
	local data, log, player, planned, route, offered, rank, origin, card =
		lap.data, lap.log, lap.player, lap.planned, lap.route, lap.offered, lap.rank, lap.origin, lap.card
	local at = lap.at
	-- A visit collects the town's eligible offers in one pass. Their work may belong to a later lap;
	-- Verify still enforces the client's live log capacity, and a limited session requires that work to fit.
	local visited = {}
	for _, step in ipairs(route) do
		if step.pickups and #step.pickups > 0 and offered[step.key] and not visited[step.key] then
			step.pickups = offered[step.key]
			visited[step.key] = true
		end
	end
	local order, ordered = nil, lap.ordered
	if planned then
		local verified, survived, plain = Verify(lap, Recommit(route, rank)), {}, {}
		for _, step in ipairs(verified) do
			survived[step] = true
		end
		for _, step in ipairs(route) do
			plain[#plain + 1] = survived[step] and step or nil
		end
		route = Stabilise(verified, plain, rank, function(steps)
			return Holds(lap, steps)
		end, at, origin)
		-- The area the player stands in leads over the committed order; the town the player stands in already leads
		-- through the greedy loop's front, so an unfinished step is never passed for a walk away.
		local here = Model.Here(data, player, route, State.heldHere)
		local standsIn = here and route[here]
		if standsIn and here > 1 then
			-- Lead with the area the player stands in. A merged area can hold both objectives the player can work on and
			-- objectives for quests the route has yet to pick up elsewhere; the latter are not work they can do there
			-- yet, so the leading visit keeps only the workable ones (Verify drops what the fronted order cannot reach).
			if standsIn.planned then
				local lead = LeadingArea(standsIn)
				for index, step in ipairs(route) do
					route[index] = step == standsIn and lead or step
				end
				standsIn = lead
			end
			route = Front(lap, route, { [standsIn] = true })
		end
		-- "You're here": the area they stand in, leading, is theirs to clear; nothing guides to it, only on from it.
		if standsIn and route[1] == standsIn then
			standsIn.here = true
		end
		-- The order is committed before the visits merge, so the next build, which splits them again, keeps to it.
		order = State.committedOrders and card and Idents(route) --[[@as AGFOrder?]]
		-- What each ordered step holds now, to tell after the merge and the last check which of them are still there.
		for index, step in ipairs(order and route or NONE) do
			ordered[index] = { step = step, pickups = step.pickups, handins = step.handins }
		end
	else
		route = Verify(lap, route)
		-- Nearest first already puts the area the player stands in at the head; a merged visit keeps only the work
		-- they can do now, not objectives for quests the route has yet to pick up elsewhere.
		local here = Model.Here(data, player, route, State.heldHere)
		local standsIn = here and route[here]
		if standsIn and here == 1 and standsIn.planned then
			local lead = LeadingArea(standsIn)
			route[1], standsIn = lead, lead
		end
		-- A ready hand-in or a pickup beside the player goes before the step they head for, a broad area they stand in
		-- included. Front keeps the route when the check refuses the move, so the head only changes when it is legal.
		local near = NearAction(origin, log, route, at)
		if near and near ~= route[1] then
			route = Front(lap, route, { [near] = true })
		end
		if standsIn and route[1] == standsIn then
			standsIn.here = true
		end
	end
	lap.route, lap.order = route, order
end

---@param lap AGFLapState
local function MergeLapVisits(lap)
	local route, skipped, order, card, ordered = lap.route, lap.skipped, lap.order, lap.card, lap.ordered
	local into = {}
	-- Two visits to one town in a row are one, unless the second hands in what the first handed out.
	for index = #route, 2, -1 do
		local a, b = route[index - 1], route[index]
		if a.kind == "town" and b.kind == "town" and a.key == b.key then
			local apart = false
			for _, id in ipairs(b.handins) do
				apart = apart or a.spots[id] ~= nil
			end
			if not apart then
				local lists = { handins = {}, pickups = {} }
				for name, merged in pairs(lists) do
					for _, step in ipairs({ a, b }) do
						for _, id in ipairs(step[name]) do
							merged[#merged + 1], a.spots[id] = id, a.spots[id] or step.spots[id]
						end
					end
				end
				for _, name in ipairs({ "planned", "returns" }) do
					for id in pairs(b[name] or NONE) do
						a[name] = a[name] or {}
						a[name][id] = true
					end
				end
				Trim(a, lists.handins, lists.pickups)
				into[b] = a
				table.remove(route, index)
			end
		end
	end
	local visits = {}
	for index = 1, #route do
		local step = route[index]
		if step.kind == "town" then
			visits[step.key] = (visits[step.key] or 0) + 1
			step.key = visits[step.key] > 1 and ("%s:%d"):format(step.key, visits[step.key]) or step.key
		end
	end
	for index = #route, 1, -1 do
		if skipped[route[index].key] then
			Skip(route[index].key)
			table.remove(route, index)
		end
	end
	route = Verify(lap, route)
	-- A step the check dropped (its pickups gave way to the log's limit) leaves the order with it, so the next build
	-- ranks only steps this one holds and a rebuild with nothing changed is the same route. A step past the step limit
	-- stays in the order.
	local held = {}
	for _, step in ipairs(route) do
		held[step] = {}
		for _, id in ipairs(step.kind == "town" and step.pickups or NONE) do
			held[step][id] = true
		end
		for _, id in ipairs(step.kind == "town" and step.handins or NONE) do
			held[step][-id] = true
		end
	end
	for index = #route, Model.MAX_STEPS + 1, -1 do
		route[index] = nil
	end
	-- Temporary skips must not overwrite the order that Show again restores.
	if order and not next(skipped) then
		local kept = {}
		for index, ident in ipairs(order) do
			local was = ordered[index]
			local step = was.step
			while into[step] do
				step = into[step]
			end
			local now = held[step]
			local there = now ~= nil and step.kind ~= "town"
			for _, id in ipairs(now and was.pickups or NONE) do
				there = there or now[id] ~= nil
			end
			for _, id in ipairs(now and was.handins or NONE) do
				there = there or now[-id] ~= nil
			end
			kept[#kept + 1] = there and ident or nil
		end
		order = kept
		order.picked = {}
		for _, step in ipairs(route) do
			for _, id in ipairs(step.kind == "town" and step.pickups or NONE) do
				order.picked[id] = true
			end
		end
		State.committedOrders[card] = order
	end
	lap.route = route
end

---@param lap AGFLapState
local function DescribeLap(lap)
	local data, player, completed, log, route, mapName, origin, docks, join =
		lap.data, lap.player, lap.completed, lap.log, lap.route, lap.mapName, lap.origin, lap.docks, lap.join
	if join then
		join(route)
	end
	local from = origin
	for _, step in ipairs(route) do
		if step.kind == "town" then
			Describe(data, log, player, step)
			Opens(data, player, completed, log, step)
			TownPoint(data, step, from)
		elseif step.objectives then
			Tell(step)
			Enter(data, step, not step.here and from or nil)
		elseif step.kind == "trainer" then
			Describe(data, log, player, step)
		end
		Locate(data, step, mapName)
		from = Position(data, step, docks) or from
	end
end

-- The lap route (docs/design.md §4.2), or nil when the player's place is unknown, where Build's route stands. The
-- card's towns hand out their quests and take the finished ones; each new quest is done in areas of the data's (merged
-- with the log's), and one whose XP per yard falls below KEEP of its town's mean waits. The route is the player's
-- nearest action at every step (docs/design.md §4.1): the nearest town pickup (its open), the nearest area of a quest
-- the town handed out or the player carries, or the nearest ready hand-in. The town the player stands in, a pinned
-- quest and the story's chapter lead where they must, and a stop in the town the route is already in, on its map and
-- within a lap of it, is finished before the route leaves it, so a town's work is not split by a nearer rival while
-- an objective across the zone or the sea is no reason to stay; a stop already placed is never revisited. The
-- preview is cut after ordering and merging visits, so its horizon stays stable across rebuilds. The route is
-- checked in order: a quest's objectives never before its pickup, its hand-in never before all of them, and the log
-- never past the client's limit. The card's committed order (`card`, its journey key) keeps the route steady
-- (Stabilise). The town or open area the player stands in leads (Model.Here). A second visit to a town is keyed
-- "town:<hub>:2".
---@param candidates AGFStep[]
---@param plan AGFPlanAreas
---@param leadID? integer
---@param join? fun(selected: AGFStep[])
---@return AGFStep[]?
local function Laps(data, player, completed, log, candidates, plan, prefs, mapName, leadID, join, card)
	local docks = Docks(data, player.side)
	local origin = Position(data, player, docks)
	if not (origin and origin.known) then
		return nil
	end
	-- `planned` keeps the whole heuristic order (chapter lead, town look-ahead, committed order); the default
	-- nearest mode takes the nearest actionable stop at every step.
	local planned = prefs.optimisedRoute == true
	local rank = {}
	for index, ident in ipairs(State.committedOrders and State.committedOrders[card] or NONE) do
		rank[ident] = index
	end
	local skipped, where, pinned = prefs.skipped, {}, prefs.pinned or {}
	local towns, kept, others, groups = {}, {}, {}, {}
	for _, step in ipairs(candidates) do
		if skipped[step.key] then
			Skip(step.key)
		elseif step.kind == "town" then
			towns[#towns + 1] = step
		elseif step.kind == "area" then
			kept[step] = true
		elseif step.kind == "dungeon" then
			groups[#groups + 1] = step
		else
			others[#others + 1] = step
		end
	end
	local areas = {}
	for _, area in ipairs(plan.areas) do
		areas[#areas + 1] = kept[area] and area or nil
	end

	local count = 0
	for _ in pairs(log) do
		count = count + 1
	end
	---@type AGFLapState
	local lap
	lap = {
		at = function(place)
			return LapPosition(lap, place)
		end,
		data = data,
		player = player,
		completed = completed,
		log = log,
		plan = plan,
		mapName = mapName,
		leadID = leadID,
		join = join,
		card = card,
		docks = docks,
		hub = Model.Hub(data, player),
		origin = origin,
		planned = planned,
		rank = rank,
		skipped = skipped,
		pinned = pinned,
		where = where,
		towns = towns,
		others = others,
		groups = groups,
		areas = areas,
		picks = {},
		ids = {},
		nodes = {},
		offered = {},
		ratio = {},
		anchors = {},
		list = {},
		pending = {},
		cap = player.logMax or math.huge,
		count = count,
		picked = State.committedOrders and State.committedOrders[card] and State.committedOrders[card].picked or {},
		route = {},
		ordered = {},
	}
	PickLapQuests(lap)
	NameLapAreas(lap)
	BuildLapAnchors(lap)
	WalkLap(lap)
	CommitLap(lap)
	MergeLapVisits(lap)
	DescribeLap(lap)
	return lap.route
end

ns.Planner.Laps = {
	Laps = Laps,
}
