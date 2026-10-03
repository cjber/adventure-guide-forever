---@type string, AGFNamespace
local _, ns = ...
-- The route as shown: one pass from a snapshot of the player to the steps the views draw. The planner's route
-- (Plan.lua and Refresh.lua, which read no client state), then the player's own order (docs/design.md §2.20), then the
-- session's trim (§4.3), all over the same player and log. Core.lua's rebuild is the one caller.
---@class AGFShown
local Shown = {}
ns.Shown = Shown

-- Journeys whose committed order the next full build lets go (Order.Reset).
---@type table<string, true>
local forget = {}

---@param journey string
function Shown.Forget(journey)
	forget[journey] = true
end

-- The player's saved order, merged into each card it names; the head's "you're here" follows the new first step.
---@param route AGFRoute
---@param input AGFShownInput
local function Reorder(route, input)
	local orders = input.prefs.customOrders
	if not orders or not next(orders) then
		return
	end
	local player = input.player
	for _, card in ipairs(route.journeys) do
		local keys = orders[card.key]
		if keys then
			card.steps = ns.Order.Merge(card.steps, keys, player.logMax, input.log)
			local here = ns.Model.Here(input.data, player, card.steps)
			for index, step in ipairs(card.steps) do
				step.here = index == 1 and here == 1 or nil
			end
		end
		if route.journey == card.key then
			route.steps = card.steps
		end
	end
end

-- May yield inside a coroutine (the full build is sliced, Model.Journeys); everything after the plan runs in the slice
-- that finishes it.
---@param input AGFShownInput
---@return AGFRoute shown what the views draw: the chosen journey's steps in the player's order, within the session
---@return AGFRoute full the same route before the session's trim: the next build's `last`
function Shown.Build(input)
	local Model = ns.Model
	---@type AGFPlanInputs
	local inputs = { skippedQuests = ns.Order.SkippedQuests(), committed = ns.Session.Committed() }
	local full
	if input.combat then
		full = Model.Refresh(
			input.data,
			input.player,
			input.completed,
			input.log,
			input.prefs,
			input.last,
			input.mapName,
			inputs
		)
	else
		inputs.forget, forget = forget, {}
		full = Model.Plan(
			input.data,
			input.player,
			input.completed,
			input.log,
			input.prefs,
			input.mapName,
			input.instanceName,
			input.last,
			inputs
		)
	end
	Reorder(full, input)
	if input.observe then
		input.observe(full)
	end
	return ns.Session.Apply(full, input.player), full
end
