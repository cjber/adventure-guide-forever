---@type string, AGFNamespace
local _, ns = ...

if ns.broken then
	return
end

-- Public answers and navigation requests for other addons (docs/api.md). Reads return copies; a read with nothing to
-- answer returns nil and a reason from ForeverCore.APIKit.NotReady, and Subscribe is the shared hub.
local APIKit = assert(ForeverCore.APIKit)

---@class AGFAPI
-- `minor` rises with each addition within version 1 (1: Subscribe, 2: Suggestions and StartSuggestion, 3: Stats,
-- 4: Status, Pause, Resume and each stop's quest IDs, 5: each read's not-ready reason and the shared
-- subscription hub, 7: the `suggestions` change and `nil, "invalid"` for a bad limit); a caller checks a member before
-- using it.
local API = { version = 1, minor = 7 }

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
	local step = ns.Guidance.CurrentStep()
	for index, candidate in ipairs(ns.Route().steps) do
		if candidate == step then
			return step, index
		end
	end
end

---@return AGFAPIStop?, ForeverCoreAPIReason?
function API.CurrentStop()
	if not ns.RouteSettled() then
		return APIKit.NotReady("loading")
	end
	local step = Current()
	if not step then
		return APIKit.NotReady("none")
	end
	local stop = Stop(step)
	if not stop then
		return APIKit.NotReady("none")
	end
	return stop
end

---@param limit? integer how many stops after the current one, 2 unless given
---@return AGFAPIStop[]?, AGFAPIReadError?
function API.NextStops(limit)
	if limit == nil then
		limit = 2
	elseif type(limit) ~= "number" or limit < 0 or limit % 1 ~= 0 then
		return nil, "invalid"
	end
	if not ns.RouteSettled() then
		return APIKit.NotReady("loading")
	end
	local _, index = Current()
	if not index then
		return APIKit.NotReady("none")
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
-- "arrived"; nil and a reason when no journey is chosen, the wanderer has travel off, or the route does not guide.
---@return AGFAPIStatus?, ForeverCoreAPIReason?
function API.Status()
	if not ns.RouteSettled() then
		return APIKit.NotReady("loading")
	end
	local route = ns.Route()
	if not route.chosen then
		return APIKit.NotReady("none")
	end
	if ns.Setting("wanderer") then
		return APIKit.NotReady("disabled")
	end
	local status = ns.Guidance.Status()
	if status then
		return status
	end
	if ns.Guidance.Running(route.journey) then
		return "running"
	end
	return APIKit.NotReady("none")
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
---@return AGFAPISuggestion[]?, AGFAPIReadError?
function API.Suggestions(limit)
	if limit == nil then
		limit = SUGGESTION_LIMIT
	elseif type(limit) ~= "number" or limit < 0 or limit % 1 ~= 0 then
		return nil, "invalid"
	end
	if not ns.RouteSettled() then
		return APIKit.NotReady("loading")
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

--[[ Subscribe: the frame after the current stop, the cards, the journey or the status changes
     (ForeverCore.APIKit.Hub) ]]

-- What a stop reads as, so a moved, emptied or restaffed stop is a change and a rebuild that leaves it alone is not.
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

-- What the cards read as, so a card that appears, goes, moves, reorders or changes its level, kind, map or place is a
-- change and a rebuild that leaves every card alone is not. Each card's six answered fields, in the panel's order.
---@param suggestions AGFAPISuggestion[]?
---@return string|false
local function SuggestionsKey(suggestions)
	if not suggestions then
		return false
	end
	local cards = {}
	for index, suggestion in ipairs(suggestions) do
		cards[index] = ("%s:%s:%s:%s:%s:%s"):format(
			suggestion.id,
			tostring(suggestion.kind),
			tostring(suggestion.level),
			tostring(suggestion.map),
			suggestion.x and ("%.4f"):format(suggestion.x) or "-",
			suggestion.y and ("%.4f"):format(suggestion.y) or "-"
		)
	end
	return table.concat(cards, "|")
end

-- Every change name docs/api.md lists, read only while the route is settled and only while someone listens: one hub for
-- the whole API, so the frame-after rule, the one-call burst, the fresh `changes` table and the per-subscriber SafeCall
-- are the kit's own.
local hub = APIKit.Hub("AdventureGuideForever", {
	stop = function()
		local stop = API.CurrentStop()
		return StopKey(stop)
	end,
	suggestions = function()
		local suggestions = API.Suggestions()
		return SuggestionsKey(suggestions)
	end,
	journey = function()
		local route = ns.Route()
		return route.journey and (route.journey .. (route.chosen and ":chosen" or "")) or false
	end,
	status = function()
		return API.Status() or false
	end,
}, ns.RouteSettled)

-- Calls `callback(changes)` the frame after what CurrentStop answers, the cards, the journey followed or Status()
-- changes, at most once per burst of changes (docs/api.md). Returns a function that unsubscribes, safe to call twice.
---@type fun(callback: fun(changes: AGFAPIChanges)): fun()
API.Subscribe = hub.Subscribe
ns.OnRouteChange(hub.Queue)
ns.Guidance.OnChange(hub.Queue)

AdventureGuideForever = { API = API }

-- Lists this API in ForeverCore.APIKit.Addons() for other addons (ForeverCore 1.3.2 or later); an older core has no
-- Publish, and the addon loads as before.
if (ForeverCore.APIKit.minor or 1) >= 2 then
	ForeverCore.APIKit.Publish("AdventureGuideForever", API)
end
