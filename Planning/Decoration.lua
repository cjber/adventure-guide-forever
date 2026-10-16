---@type string, AGFNamespace
local _, ns = ...
local Model = ns.Model
local NONE = {}
local Idents = ns.Planner.Routing.Idents

local function TownCounts(pickups, handins)
	if pickups == 0 then
		return ns.L.TOWN_HANDINS:format(handins)
	elseif handins == 0 then
		return ns.L.TOWN_PICKUPS:format(pickups)
	end
	return ns.L.TOWN_COUNTS:format(pickups, handins)
end

-- A visit's identity (docs/design.md §4.3): the one a build gave it (FinishRoute), which outlives the town's numbering,
-- else the step's key. The saved order, the giver skips and the step sound all key by it.
function Model.Visit(step)
	return step.orderKey or step.key
end

-- The skipped key (prefs.skipped) of one giver on a town visit's checklist.
function Model.GiverSkip(step, giverKey)
	return "giver:" .. Model.Visit(step) .. ":" .. giverKey
end

-- How much nearer another giver of a town visit must be before the arrow leaves the one it points at.
Model.SWITCH_YARDS = 35

-- Which giver of a town visit the arrow points at (docs/design.md §2.10): the nearest with work left, except that the
-- one it points at now (`current`, a point) keeps it while it has work, until another is SWITCH_YARDS nearer, so two
-- near-equal givers don't flip the waypoint as the player walks. Model.TownChecklist and Core's Walked both ask this.
---@param rows AGFTownGiver[]
---@param current? {map: integer, x: number, y: number}
---@return AGFPlace?
function Model.TownArrow(data, player, rows, current)
	local nearest, distance, kept, keptYards
	for _, row in ipairs(rows) do
		if not row.done then
			local place = row.place
			local yards = Model.Yards(data, player, place)
			if not nearest or (yards and (not distance or yards < distance)) then
				nearest, distance = place, yards
			end
			if current and place.map == current.map and place.x == current.x and place.y == current.y then
				kept, keptYards = place, yards
			end
		end
	end
	if kept and keptYards and distance and keptYards < distance + Model.SWITCH_YARDS then
		return kept
	end
	return nearest
end

-- A checklist keeps completed givers until the visit ends, while its arrow follows real remaining locations.
function Model.TownChecklist(data, player, completed, log, step, previous, skipped)
	local rows, byKey = {}, {}
	local function Skipped(row)
		return skipped ~= nil and skipped[Model.GiverSkip(step, row.key)] == true
	end
	local function Add(place, list, id)
		local key = string.format("%d:%.5f:%.5f:%s", place.map, place.x, place.y, place.name)
		local row = byKey[key]
		if not row then
			row = {
				key = key,
				name = place.name,
				place = place,
				pickups = {},
				handins = {},
				done = false,
				skipped = false,
			}
			rows[#rows + 1], byKey[key] = row, row
		end
		for _, old in ipairs(row[list]) do
			if old == id then
				return
			end
		end
		row[list][#row[list] + 1] = id
	end
	for _, row in ipairs(previous and previous.checklist or {}) do
		for _, id in ipairs(row.pickups) do
			if log[id] or completed[id] or Skipped(row) then
				Add(row.place, "pickups", id)
			end
		end
		for _, id in ipairs(row.handins) do
			if completed[id] or Skipped(row) then
				Add(row.place, "handins", id)
			end
		end
	end
	for _, list in ipairs({ "pickups", "handins" }) do
		for _, id in ipairs(step[list] or {}) do
			Add(step.spots[id], list, id)
		end
	end
	local complete = #rows > 0
	for _, row in ipairs(rows) do
		local done = true
		for _, id in ipairs(row.pickups) do
			done = done and (log[id] ~= nil or completed[id] == true)
		end
		for _, id in ipairs(row.handins) do
			done = done and completed[id] == true
		end
		row.skipped = Skipped(row)
		row.done = done or row.skipped
		row.text = ns.L.TOWN_GIVER:format(row.name, TownCounts(#row.pickups, #row.handins))
		complete = complete and row.done
	end
	local nearest = Model.TownArrow(data, player, rows, previous and previous.map and previous or nil)
	step.checklist, step.complete = rows, complete
	if nearest then
		step.map, step.x, step.y = nearest.map, nearest.x, nearest.y
	end
end

-- A spot's identity, as "Next spot" remembers it: its map and point.
---@param spot {map: integer, x: number, y: number}
---@return string
function Model.SpotKey(spot)
	return ("%d:%.4f:%.4f"):format(spot.map, spot.x, spot.y)
end

-- An area step's distinct objective spots, in the data's order; two at one point are one spot. A step of one objective
-- node also has that objective's other camps on the map (its `alternates`, #187); a merged step keeps to its nodes,
-- since one objective's camps don't serve the others.
---@param step AGFStep
---@return AGFCamp[]
function Model.Spots(step)
	local spots, seen = {}, {}
	local function Add(spot)
		local key = Model.SpotKey(spot)
		if not seen[key] then
			seen[key], spots[#spots + 1] = true, spot
		end
	end
	for _, shape in ipairs(step.shapes or NONE) do
		Add(shape)
	end
	local shapes = step.shapes or NONE
	if #shapes == 1 then
		for _, alternate in ipairs(shapes[1].alternates or NONE) do
			Add(alternate)
		end
	end
	return spots
end

-- The spot "Next spot" passes over: the one the step's arrow points at, or, while the player stands in the area (its
-- `here`), the spot whose edge is nearest them (the deepest, inside one), since that is the camp they found cleared.
---@param step AGFStep
---@param player? AGFPlayer|{map?: integer, x?: number, y?: number}
---@return AGFCamp|AGFStep
function Model.CampAt(data, player, step)
	if not step.here then
		return step
	end
	local best, bestEdge = nil, nil
	for _, spot in ipairs(Model.Spots(step)) do
		local yards = player and Model.Yards(data, player, spot)
		if yards and (not best or yards - spot.r < bestEdge) then
			best, bestEdge = spot, yards - spot.r
		end
	end
	return best or step
end

-- "Next spot" (docs/design.md §2.8): while the spot an area step points at is one the player passed over, its point
-- moves to the nearest spot not passed over, by distance from the player. A spot not passed over keeps the arrow, so
-- walking towards it, a combat rebuild or the planner choosing it again never moves it on. Not while the player is
-- "here" (Model.Here, which a spot passed over doesn't count for), nor for a step with one spot; once every spot
-- left is passed over nothing moves (ns.NextCamp starts the round again first, but objectives can finish).
---@param step AGFStep
---@param passed table<string, true> the spots passed over, by Model.SpotKey
function Model.Camp(data, player, step, passed)
	local spots = Model.Spots(step)
	if step.here or #spots < 2 or not passed[Model.SpotKey(step)] then
		return
	end
	local best, bestYards
	for _, spot in ipairs(spots) do
		local yards = not passed[Model.SpotKey(spot)] and (Model.Yards(data, player, spot) or math.huge)
		if yards and (not best or yards < bestYards) then
			best, bestYards = spot, yards
		end
	end
	if best then
		step.map, step.x, step.y = best.map, best.x, best.y
	end
end

-- Where an area step points among its spots (docs/design.md §2.8), after its here is settled: away from it, Model.Camp
-- leads on from a spot passed over; while here at a step of one objective node with other camps (#187), the camp the
-- player is at (the nearest edge among those not passed over), so Shortest Path's stop is that camp and not the node
-- they left. FinishRoute and the player's order (Shown.lua Reorder) both end with it.
---@param step AGFStep
---@param passed? table<string, true> the spots passed over, by Model.SpotKey
function Model.PlaceCamp(data, player, step, passed)
	local shapes = step.shapes or NONE
	if not step.here then
		if passed then
			Model.Camp(data, player, step, passed)
		end
		return
	end
	if not (#shapes == 1 and shapes[1].alternates) then
		return
	end
	local best, bestEdge
	for _, spot in ipairs(Model.Spots(step)) do
		local yards = not (passed and passed[Model.SpotKey(spot)]) and Model.Yards(data, player, spot)
		if yards and (not best or yards - spot.r < bestEdge) then
			best, bestEdge = spot, yards - spot.r
		end
	end
	if best then
		step.map, step.x, step.y = best.map, best.x, best.y
	end
end

---@param objective AGFAreaObjective
---@return string?
function Model.ObjectiveText(objective)
	if objective.text and objective.text ~= "" then
		return objective.text
	end
	if objective.have and objective.need and objective.need > 0 then
		return ns.L.OBJECTIVE_PROGRESS:format(objective.have, objective.need)
	end
end

function Model.StepTitle(data, log, step)
	local L = ns.L
	local function Quest(id)
		return (log[id] and log[id].title)
			or (data.quests[id] and data.quests[id].title)
			or step.questTitle
			or step.title
	end
	if step.entrance then
		step.verb = "objective"
		step.title = L.GO_TO_ENTRANCE
	elseif step.kind == "town" then
		if #step.quests == 1 then
			step.verb = #step.handins > 0 and "turnin" or "pickup"
			step.title = (step.verb == "turnin" and L.TURN_IN or L.STEP_PICKUP):format(Quest(step.quests[1]))
		else
			step.verb = "town"
			step.title = L.STEP_TOWN:format(step.place or step.zone or "", TownCounts(#step.pickups, #step.handins))
		end
	elseif step.kind == "area" or step.kind == "dungeon" then
		step.verb = "objective"
		step.questTitle = Quest(step.quests[1])
		local objective = step.objectives and step.objectives[1]
		local text = objective and objective.text
		if step.objectives and #step.objectives > 1 then
			local place = #step.quests > 1 and step.zone or nil
			step.title = L.STEP_SHARED_OBJECTIVES:format(#step.objectives, place or step.questTitle)
		elseif text and text ~= "" then
			local prefix = (objective and objective.type == "item" and L.STEP_COLLECT)
				or (objective and objective.type == "monster" and L.STEP_DEFEAT)
				or L.STEP_WORK
			step.title = prefix:format(text, step.questTitle)
		else
			step.title = L.STEP_OBJECTIVE:format(step.questTitle)
		end
	elseif step.kind == "battlemaster" then
		step.verb = "battlemaster"
		step.title = L.STEP_BATTLEMASTER:format(Model.TownName(data, step))
	else
		step.verb = step.kind == "turnin" and "turnin" or "trainer"
	end
end

local function PreviousVisit(step, previous, used)
	local best, score
	for _, old in ipairs(previous or NONE) do
		if not used[old] then
			local matches = 0
			if step.kind == "town" and old.kind == "town" and step.hub == old.hub then
				for _, list in ipairs({ "pickups", "handins" }) do
					for _, id in ipairs(step[list] or NONE) do
						for _, oldID in ipairs(old[list] or NONE) do
							if id == oldID then
								matches = matches + 1
							end
						end
					end
				end
			elseif step.kind ~= "town" and step.key == old.key then
				matches = 1
			end
			if matches > 0 and (not score or matches > score) then
				best, score = old, matches
			end
		end
	end
	if best then
		used[best] = true
	end
	return best
end

local function FinishRoute(data, player, completed, log, route, last, prefs)
	local previous = {}
	for _, card in ipairs(last and last.journeys or {}) do
		previous[card.key] = card.steps
	end
	for _, card in ipairs(route.journeys) do
		local identities, steps, used = Idents(card.steps), {}, {}
		for index, original in ipairs(card.steps) do
			-- Combat retains some step tables; decoration must not mutate the preceding snapshot.
			local step = {}
			for key, value in pairs(original) do
				step[key] = value
			end
			---@cast step AGFStep
			local old = PreviousVisit(step, previous[card.key], used)
			step.orderKey = old and old.orderKey or identities[index]
			if step.kind == "town" then
				Model.TownChecklist(data, player, completed, log, step, old, prefs.skipped)
			elseif step.kind == "area" then
				Model.PlaceCamp(data, player, step, prefs.camps and prefs.camps[step.key])
			end
			Model.StepTitle(data, log, step)
			if not step.complete then
				steps[#steps + 1] = step
			end
		end
		card.steps = steps
		if card.key == route.journey then
			route.steps = steps
		end
	end
end

ns.Planner.Decoration = {
	FinishRoute = FinishRoute,
}
