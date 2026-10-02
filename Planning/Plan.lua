---@type string, AGFNamespace
local _, ns = ...
local Model = ns.Model
local State = ns.Planner.State
local NONE = {}
local FinishRoute = ns.Planner.Decoration.FinishRoute

-- The route is the chosen journey's steps. With none chosen (never, cleared, or the choice is gone) it is the first
-- journey's, so the tracker still has a next step, and `chosen` says the player picked nothing: the guide then shows
-- every card whole and no steps (docs/design.md §2.1).
local function Route(journeys, prefs)
	local chosen
	for _, journey in ipairs(journeys) do
		chosen = journey.key == prefs.journey and journey or chosen
	end
	local route = chosen or journeys[1]
	return {
		journeys = journeys,
		journey = route and route.key,
		chosen = chosen ~= nil,
		steps = route and route.steps or {},
	}
end

---@param mapName? fun(map: integer): string? the client's (localised) name for a map; the data's English otherwise
---@param instanceName? fun(id: integer): string? the client's name for an instance Map.ID; the data's otherwise
---@param last? AGFRoute the route before, whose committed orders (`orders`) this one keeps to
---@param inputs? AGFPlanInputs what the player's order, skips and session ask of this build; none of them when nil
function Model.Plan(data, player, completed, log, prefs, mapName, instanceName, last, inputs)
	State.skippedSeen, State.committedOrders, State.planDocks, State.heldHere =
		{}, {}, { data = data }, last and last.here
	local forget = inputs and inputs.forget or NONE
	for key, order in pairs(last and last.orders or NONE) do
		State.committedOrders[key] = not forget[key] and order or nil
	end
	local journeys, stranded =
		Model.Journeys(data, player, completed, log, prefs, mapName, instanceName, inputs and inputs.skippedQuests)
	local route = Route(journeys, prefs)
	route.skipped, State.skippedSeen, route.stranded = State.skippedSeen, nil, stranded or nil
	route.orders, State.committedOrders, State.planDocks, State.heldHere = State.committedOrders, nil, nil, nil
	FinishRoute(data, player, completed, log, route, last, prefs, inputs)
	local head = route.steps[1]
	route.here = head and head.here and head.key or nil
	return route
end

ns.Planner.Plan = {
	Route = Route,
}
