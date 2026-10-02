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
-- else the step's key. The saved order, the session's commitment, the giver skips and the step sound all key by it.
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

function Model.StepTitle(data, log, step)
	local L = ns.L
	local function Quest(id)
		return (log[id] and log[id].title)
			or (data.quests[id] and data.quests[id].title)
			or step.questTitle
			or step.title
	end
	if step.kind == "town" then
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
		if text and text ~= "" then
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

-- Town numbering changes after accepting its pickups; a saved session identifies each action independently.
-- Model.NoteVisits writes the `visits` a session commits; CommittedVisit reads them back on the next build.
function Model.NoteVisits(visits, step)
	local visit = Model.Visit(step)
	for _, list in ipairs(step.kind == "town" and { "pickups", "handins" } or NONE) do
		for _, id in ipairs(step[list]) do
			visits[list .. ":" .. id] = visit
		end
	end
end

local function CommittedVisit(step, visits, used)
	local best, score, matches = nil, nil, {}
	for _, list in ipairs(step.kind == "town" and { "pickups", "handins" } or NONE) do
		for _, id in ipairs(step[list]) do
			local key = visits[list .. ":" .. id]
			if key and not used[key] then
				matches[key] = (matches[key] or 0) + 1
				if not score or matches[key] > score then
					best, score = key, matches[key]
				end
			end
		end
	end
	return best
end

---@param inputs? AGFPlanInputs
local function FinishRoute(data, player, completed, log, route, last, prefs, inputs)
	local previous = {}
	local committed = inputs and inputs.committed
	for _, card in ipairs(last and last.journeys or {}) do
		previous[card.key] = card.steps
	end
	for _, card in ipairs(route.journeys) do
		local identities, steps, used = Idents(card.steps), {}, {}
		local visits = committed and committed.journey == card.key and committed.visits
		for index, original in ipairs(card.steps) do
			-- Combat retains some step tables; decoration must not mutate the preceding snapshot.
			local step = {}
			for key, value in pairs(original) do
				step[key] = value
			end
			---@cast step AGFStep
			local old = PreviousVisit(step, previous[card.key], used)
			local saved = visits and CommittedVisit(step, visits, used)
			step.orderKey = old and old.orderKey or saved or identities[index]
			used[step.orderKey] = true
			if step.kind == "town" then
				Model.TownChecklist(data, player, completed, log, step, old, prefs.skipped)
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
