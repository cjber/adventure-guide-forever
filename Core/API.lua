---@type string, AGFNamespace
local _, ns = ...

-- Public answers and navigation requests for other addons (docs/api.md). Reads return copies;
-- nil means the route is still settling, so ask again later.
---@class AGFAPI
-- `minor` rises with each addition within version 1 (1: Subscribe); a caller checks a member before using it.
local API = { version = 1, minor = 1 }

local NEXT_LIMIT = 8

---@param step AGFStep
---@return AGFAPIStop?
local function Stop(step)
	if not ns.Model.ValidPlace(step) then
		return nil
	end
	return {
		map = step.map,
		x = step.x,
		y = step.y,
		name = step.place or step.zone or step.title,
		isTown = step.kind == "town",
		handins = #ns.Model.Handins(step),
		pickups = step.pickups and #step.pickups or 0,
	}
end

-- The tracker's step and its place in the settled route.
---@return AGFStep?, integer?
local function Current()
	if not ns.RouteSettled() then
		return nil
	end
	local step = ns.Guidance.CurrentStep()
	for index, candidate in ipairs(ns.Route().steps) do
		if candidate == step then
			return step, index
		end
	end
end

---@return AGFAPIStop?
function API.CurrentStop()
	local step = Current()
	return step and Stop(step)
end

---@param limit? integer how many stops after the current one, 2 unless given
---@return AGFAPIStop[]?
function API.NextStops(limit)
	if limit == nil then
		limit = 2
	elseif type(limit) ~= "number" or limit < 0 or limit % 1 ~= 0 then
		return nil
	end
	local _, index = Current()
	if not index then
		return nil
	end
	local stops, steps = {}, ns.Route().steps
	for offset = 1, math.min(limit, NEXT_LIMIT) do
		local stop = steps[index + offset] and Stop(steps[index + offset])
		if not stop then
			break
		end
		stops[#stops + 1] = stop
	end
	return stops
end

-- RXP keeps its engine; this frontend owns the guide's navigation, including Stop.
---@return boolean
function API.RestedXPIntegrated()
	return ns.RestedXP.Enabled()
end

---@return boolean
function API.RestedXPNativeUI()
	return not ns.Setting("restedxpChoiceMade") or not ns.Setting("restedxpGuide")
end

-- Explicit player request: return to the active RestedXP guide after another addon took navigation.
---@return boolean
function API.ResumeRestedXP()
	if not ns.RestedXP.Enabled() then
		return false
	end
	local journey = ns.RestedXP.Journey()
	if not journey then
		return false
	end
	ns.Choose(journey.key, true)
	return true
end

--[[ Subscribe: the frame after the current stop or the journey changes ]]

---@class AGFSubscription
---@field callback? fun(changes: AGFAPIChanges) nil once unsubscribed

---@type AGFSubscription[]
local subscriptions = {}
-- What the last dispatch saw: CurrentStop's answer as a string (false for none) and the journey followed.
---@type string|false, string|false
local lastStop, lastJourney = false, false
local pending = false

---@param stop? AGFAPIStop
---@return string|false
local function StopKey(stop)
	if not stop then
		return false
	end
	return ("%d:%.4f:%.4f:%s:%s:%d:%d"):format(
		stop.map,
		stop.x,
		stop.y,
		tostring(stop.name),
		tostring(stop.isTown),
		stop.handins,
		stop.pickups
	)
end

-- One burst's changes, to every subscriber there when the call-back began (one added by a callback waits for the next
-- burst), each with its own table and each under
-- ns.SafeCall, so an error in one reaches the game's error handler and the report without stopping the others. While
-- the route is being worked out nothing is sent: the rebuild's own notification queues the next look.
local function Dispatch()
	pending = false
	if not subscriptions[1] or not ns.RouteSettled() then
		return
	end
	local route = ns.Route()
	local stop = StopKey(API.CurrentStop())
	local journey = route.journey and (route.journey .. (route.chosen and ":chosen" or "")) or false
	local stopChanged, journeyChanged = stop ~= lastStop, journey ~= lastJourney
	lastStop, lastJourney = stop, journey
	if not (stopChanged or journeyChanged) then
		return
	end
	local current = {}
	for index, subscription in ipairs(subscriptions) do
		current[index] = subscription
	end
	for _, subscription in ipairs(current) do
		if subscription.callback then
			ns.SafeCall("API subscriber", subscription.callback, {
				stop = stopChanged or nil,
				journey = journeyChanged or nil,
			})
		end
	end
end

local function Queue()
	-- Nobody listening: no timer, no stop read. API.Subscribe takes its baseline when the first one joins.
	if not pending and subscriptions[1] then
		pending = true
		C_Timer.After(0, function()
			ns.SafeCall("API subscribers", Dispatch)
		end)
	end
end
ns.OnRouteChange(Queue)
ns.Guidance.OnChange(Queue)

-- Calls `callback(changes)` the frame after what CurrentStop answers or the journey followed changes, at most once per
-- burst of changes (docs/api.md). Returns a function that unsubscribes, safe to call twice.
---@param callback fun(changes: AGFAPIChanges)
---@return fun()
function API.Subscribe(callback)
	if type(callback) ~= "function" then
		error("AdventureGuideForever.API.Subscribe: callback must be a function", 2)
	end
	if not subscriptions[1] then
		-- The first subscriber: what CurrentStop answers now is the baseline, so it hears only what changes after.
		local route = ns.RouteSettled() and ns.Route()
		lastStop = route and StopKey(API.CurrentStop()) or false
		lastJourney = route and route.journey and (route.journey .. (route.chosen and ":chosen" or "")) or false
	end
	---@type AGFSubscription
	local subscription = { callback = callback }
	subscriptions[#subscriptions + 1] = subscription
	return function()
		subscription.callback = nil
		for index, other in ipairs(subscriptions) do
			if other == subscription then
				table.remove(subscriptions, index)
				return
			end
		end
	end
end

AdventureGuideForever = { API = API }
