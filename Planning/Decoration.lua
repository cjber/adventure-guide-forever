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
	local nearest, distance, complete = nil, nil, #rows > 0
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
		if not row.done then
			local yards = Model.Yards(data, player, row.place)
			if not nearest or (yards and (not distance or yards < distance)) then
				nearest, distance = row.place, yards
			end
		end
	end
	step.checklist, step.complete = rows, complete
	if nearest then
		step.map, step.x, step.y = nearest.map, nearest.x, nearest.y
	end
end

-- An area step's distinct objective spots, in the data's order: two objectives at one node are one spot.
---@param step AGFStep
---@return AGFNode[]
function Model.Spots(step)
	local spots, seen = {}, {}
	for _, shape in ipairs(step.shapes or NONE) do
		local key = ("%d:%.4f:%.4f"):format(shape.map, shape.x, shape.y)
		if not seen[key] then
			seen[key], spots[#spots + 1] = true, shape
		end
	end
	return spots
end

-- "Next spot" (docs/design.md §2.8): an area step's point moves `presses` spots on from the one the planner chose, in
-- order of distance from the player, nearest first, round again after the last; ties keep the data's order. Not while
-- the player stands in the area (its `here`), nor for a step with one spot.
---@param step AGFStep
---@param presses integer
function Model.Camp(data, player, step, presses)
	local shapes = Model.Spots(step)
	if step.here or #shapes < 2 then
		return
	end
	local order, yards = {}, {}
	for index, shape in ipairs(shapes) do
		order[index], yards[shape] = shape, Model.Yards(data, player, shape) or math.huge
	end
	local position = {}
	for index, shape in ipairs(shapes) do
		position[shape] = index
	end
	table.sort(order, function(a, b)
		if yards[a] ~= yards[b] then
			return yards[a] < yards[b]
		end
		return position[a] < position[b]
	end)
	-- From the spot the planner chose (the step's own point), on by `presses`.
	local start = 1
	for index, shape in ipairs(order) do
		if shape.map == step.map and shape.x == step.x and shape.y == step.y then
			start = index
		end
	end
	local shape = order[(start - 1 + presses) % #order + 1]
	step.map, step.x, step.y = shape.map, shape.x, shape.y
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
			elseif step.kind == "area" and prefs.camps and prefs.camps[step.key] then
				Model.Camp(data, player, step, prefs.camps[step.key])
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
