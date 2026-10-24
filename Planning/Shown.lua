---@type string, AGFNamespace
local _, ns = ...
-- The route as shown: one pass from a snapshot of the player to the steps the views draw. The planner's route
-- (Plan.lua and Refresh.lua, which read no client state), then the player's own order (docs/design.md §2.20) and
-- giver skips, all over the same player and log. Core.lua's rebuild is the one caller.
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

-- The player's saved order, merged into each card it names; the head's "you're here" and the card's hub line follow
-- the new first step.
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
			-- As the plan reckoned it: the area it held, and the spots "Next spot" passed over.
			local here = ns.Model.Here(input.data, player, card.steps, route.here, input.prefs.camps)
			for index, step in ipairs(card.steps) do
				step.here = index == 1 and here == 1 or nil
			end
			local first, camps = card.steps[1], input.prefs.camps
			if first and first.kind == "area" then
				ns.Model.PlaceCamp(input.data, player, first, camps and camps[first.key])
			end
			ns.Planner.Journeys.Summarise(card)
		end
		if route.journey == card.key then
			route.steps = card.steps
		end
	end
end

-- Planning and presentation use separate frames; only the finished route is committed by Core.
---@param input AGFShownInput
---@return AGFRoute shown what the views draw: the chosen journey's steps in the player's order
---@return AGFRoute full the same route: the next build's `last`
function Shown.Build(input)
	local Model = ns.Model
	---@type AGFPlanInputs
	local inputs = {
		skippedQuests = ns.Order.SkippedQuests(),
		dungeonEntrances = input.dungeonEntrances,
	}
	local full
	if input.repaint then
		full = Model.Repaint(input.data, input.log, input.last)
	elseif input.combat then
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
		-- Synchronous callers never yield; a Lua 5.2-style host names the main thread too, and flags it.
		local co, main = coroutine.running()
		if co and not main then
			coroutine.yield("frame")
		end
	end
	Reorder(full, input)
	if input.observe then
		input.observe(full)
	end
	return full, full
end
