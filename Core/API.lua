---@type string, AGFNamespace
local _, ns = ...

-- Public answers and navigation requests for other addons (docs/api.md). Reads return copies;
-- nil means the route is still settling, so ask again later.
---@class AGFAPI
-- `minor` rises with each addition within version 1 (1: Subscribe, 2: Suggestions and StartSuggestion, 3: Stats,
-- 4: Leaderboard, 5: Status, Pause, Resume and each stop's quest IDs);
-- a caller checks a member before using it.
local API = { version = 1, minor = 5 }

local NEXT_LIMIT = 8
local SUGGESTION_LIMIT = 5

-- Local per-character activity records. Returned values are copies.
---@return AGFActivityRecord[]
function API.Stats()
	return ns.ActivityStats and ns.ActivityStats() or {}
end

-- Cumulative quest turn-ins ranked among this character and the guild and group members who reported theirs. Copies;
-- nil for a limit that is not a whole number of zero or more.
---@param limit? integer how many top rows, ten unless given, 25 at most; this character's row is always included
---@return AGFLeaderboard?
function API.Leaderboard(limit)
	return ns.Stats.Leaderboard(limit)
end

-- What the stop is, in the words docs/api.md lists: a town or lone pickup step reads as that visit, an area as its
-- objective work, and a companion guide's step as "guide".
---@type table<string, AGFAPIStopKind>
local KINDS = {
	area = "objective",
	battlemaster = "battlemaster",
	dungeon = "objective",
	guide = "guide",
	objective = "objective",
	pickup = "pickup",
	town = "town",
	trainer = "trainer",
	turnin = "turnin",
}

---@param step AGFStep
---@return AGFAPIStopKind
local function Kind(step)
	if step.kind == "guide" then
		return "guide"
	end
	if step.verb then
		return step.verb
	end
	local kind = step.kind --[[@as string]]
	return KINDS[kind] or "guide"
end

-- A fresh ascending copy: a stop never shares a table with the route.
---@param ids integer[]
---@return integer[]
local function Sorted(ids)
	local copy = {}
	for index, id in ipairs(ids) do
		copy[index] = id
	end
	table.sort(copy)
	return copy
end

---@param step AGFStep
---@return AGFAPIStop?
local function Stop(step)
	if not ns.Model.ValidPlace(step) then
		return nil
	end
	local pickups, handins = ns.Model.Pickups(step), ns.Model.Handins(step)
	return {
		map = step.map,
		x = step.x,
		y = step.y,
		name = step.place or step.zone or step.title,
		isTown = step.kind == "town",
		kind = Kind(step),
		handins = #handins,
		pickups = #pickups,
		pickupQuests = Sorted(pickups),
		turninQuests = Sorted(handins),
		objectiveQuests = Sorted(ns.Model.Objectives(step)),
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

-- Where the chosen journey's guidance stands: "running" while its route is ours, else Guidance's "queued", "paused" or
-- "arrived"; nil when no journey is chosen (or the route does not guide).
---@return AGFAPIStatus?
function API.Status()
	if not ns.RouteSettled() then
		return nil
	end
	local route = ns.Route()
	if not route.chosen then
		return nil
	end
	local status = ns.Guidance.Status()
	if status then
		return status
	end
	return ns.Guidance.Running(route.journey) and "running" or nil
end

-- Stops the chosen journey's route but keeps the choice, in the same paused state as a route cleared in Shortest Path,
-- so its card and the tracker title resume it. False when the route is working out or nothing is chosen.
---@return boolean
function API.Pause()
	if not ns.RouteSettled() then
		return false
	end
	return ns.Guidance.Pause()
end

-- Starts the chosen journey's route again as its card's Start does. False when nothing is chosen, the route is working
-- out, or it cannot start.
---@return boolean
function API.Resume()
	if not ns.RouteSettled() then
		return false
	end
	local route = ns.Route()
	if not route.chosen then
		return false
	end
	return ns.StartJourney(route.journey) == true
end

---@param limit? integer how many, five (the most) unless given
---@return AGFAPISuggestion[]?
function API.Suggestions(limit)
	if limit == nil then
		limit = SUGGESTION_LIMIT
	elseif type(limit) ~= "number" or limit < 0 or limit % 1 ~= 0 then
		return nil
	end
	if not ns.RouteSettled() then
		return nil
	end
	local suggestions, cap = {}, math.min(limit, SUGGESTION_LIMIT)
	for _, journey in ipairs(ns.Model.Cards(ns.Route())) do
		if #suggestions >= cap then
			break
		end
		local step = journey.steps[1]
		local placed = step and ns.Model.ValidPlace(step)
		suggestions[#suggestions + 1] = {
			id = journey.key,
			title = journey.title,
			level = (ns.Model.LevelRange(ns.Data, journey)),
			kind = journey.kind,
			map = placed and step.map or journey.map,
			x = placed and step.x or nil,
			y = placed and step.y or nil,
		}
	end
	return suggestions
end

-- Starts the card `id` names as the guide's own Start does (ns.StartJourney), and hands a RestedXP guide's card to its
-- engine as the card's click does. False when the route is settling, no card has that id, RestedXP refused its guide
-- (in combat) or the chosen card's route could not start.
---@param id string
---@return boolean
function API.StartSuggestion(id)
	if type(id) ~= "string" or not ns.RouteSettled() then
		return false
	end
	for _, journey in ipairs(ns.Route().journeys) do
		if journey.key == id then
			if journey.rxpGroup and journey.rxpName then
				return ns.RestedXP.Choose(journey.rxpGroup, journey.rxpName, true)
			end
			return ns.StartJourney(id)
		end
	end
	return false
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
-- What the last dispatch saw: CurrentStop's answer as a string (false for none), the journey followed and Status().
---@type string|false, string|false, string|false
local lastStop, lastJourney, lastStatus = false, false, false
local pending = false

---@param stop? AGFAPIStop
---@return string|false
local function StopKey(stop)
	if not stop then
		return false
	end
	return ("%d:%.4f:%.4f:%s:%s:%s:%d:%d:%s:%s:%s"):format(
		stop.map,
		stop.x,
		stop.y,
		tostring(stop.name),
		tostring(stop.isTown),
		tostring(stop.kind),
		stop.handins,
		stop.pickups,
		table.concat(stop.turninQuests, ","),
		table.concat(stop.pickupQuests, ","),
		table.concat(stop.objectiveQuests, ",")
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
	local status = API.Status() or false
	local stopChanged, journeyChanged, statusChanged = stop ~= lastStop, journey ~= lastJourney, status ~= lastStatus
	lastStop, lastJourney, lastStatus = stop, journey, status
	if not (stopChanged or journeyChanged or statusChanged) then
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
				status = statusChanged or nil,
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
		lastStatus = route and (API.Status() or false) or false
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
