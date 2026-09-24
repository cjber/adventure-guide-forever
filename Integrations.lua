---@type string, AGFNamespace
local _, ns = ...

---@class AGFIntegrationsModule : AGFIntegrations
local Integrations = {}
ns.Integrations = Integrations

-- Passed to Shortest Path so it can tell our journeys apart from the player's own.
local OWNER = "AdventureGuideForever"

-- The v1 members; types/Namespace.lua AGFSPFAPI is the contract, and tests/contract_spec.lua holds this list to
-- exactly its non-optional functions. A Shortest Path missing any of them is treated as absent.
local REQUIRED = { "Estimate", "Navigate", "NavigateRoute", "CurrentStop", "Cancel" }

---@return AGFSPFAPI?
local function SPF()
	local api = ShortestPathForever and ShortestPathForever.API
	if type(api) ~= "table" or api.version ~= 1 then
		return nil
	end
	for _, name in ipairs(REQUIRED) do
		if type(api[name]) ~= "function" then
			return nil
		end
	end
	---@cast api AGFSPFAPI
	return api
end

-- Step 1's travel line, fetched in its own frame after each rebuild (Core.lua), so the rebuild itself never asks
-- Shortest Path anything. No cache here: Shortest Path keeps its own for 5 s.
---@type {key: string, line: string?}?
local travel
---@type fun()[]
local travelListeners = {}

local L = ns.L
---@type table<AGFSPFMode, string>
local VERBS = {
	walk = L.TRAVEL_WALK,
	flight = L.TRAVEL_FLIGHT,
	boat = L.TRAVEL_BOAT,
	zeppelin = L.TRAVEL_ZEPPELIN,
	lift = L.TRAVEL_LIFT,
	tram = L.TRAVEL_TRAM,
	portal = L.TRAVEL_PORTAL,
	passage = L.TRAVEL_PASSAGE,
}

---@param seconds number
---@return integer
local function Minutes(seconds)
	return math.max(1, math.ceil(seconds / 60))
end

-- The first leg that isn't a walk, and the minutes until it arrives; a trip on foot names where it ends. A new
-- flight path on the way, and a wait of a minute or more for the chosen leg, are added (docs/plan.md F10).
---@param detail AGFSPFDetail
---@return string?
local function DetailLine(detail)
	local chosen, elapsed, newFlightPath = nil, 0, false
	for _, leg in ipairs(detail.legs) do
		newFlightPath = newFlightPath or (leg.mode == "walk" and leg.newFlightPath == true)
		if not chosen then
			elapsed = elapsed + leg.seconds
			chosen = leg.mode ~= "walk" and leg or nil
		end
	end
	chosen = chosen or detail.legs[#detail.legs]
	local verb = chosen and VERBS[chosen.mode]
	if not verb then
		return nil
	end
	return L.TRAVEL:format(verb:format(chosen.to), Minutes(elapsed))
		.. (newFlightPath and L.TRAVEL_NEW_FLIGHT_PATH or "")
		.. (chosen.wait and L.TRAVEL_WAIT:format(Minutes(chosen.wait)) or "")
end

---@param step AGFStep
---@return string?
function Integrations.TravelLine(step)
	local api = SPF()
	local player = ns.State.Player()
	if not (api and player.map and player.x and player.y) or InCombatLockdown() then
		return nil
	end
	if type(api.EstimateDetail) == "function" then
		local detail = api.EstimateDetail(player.map, player.x, player.y, step.map, step.x, step.y)
		return detail and DetailLine(detail)
	end
	local seconds = api.Estimate(player.map, player.x, player.y, step.map, step.x, step.y)
	if seconds then
		return L.TRAVEL_ABOUT:format(Minutes(seconds))
	end
end

-- In combat Shortest Path has no answer to give, so the last line stands and nothing is asked (docs/design.md §2.5).
function Integrations.RefreshTravel()
	if InCombatLockdown() then
		return
	end
	local step = ns.Route().steps[1]
	local line = step and Integrations.TravelLine(step)
	local changed = (travel and travel.key) ~= (step and step.key) or (travel and travel.line) ~= line
	travel = step and { key = step.key, line = line } or nil
	if changed then
		for _, fn in ipairs(travelListeners) do
			fn()
		end
	end
end

-- The last fetched line, only for the step it was fetched for; never an SPF call.
---@param step AGFStep
---@return string?
function Integrations.Travel(step)
	return travel and travel.key == step.key and travel.line or nil
end

---@param fn fun()
function Integrations.OnTravelChange(fn)
	travelListeners[#travelListeners + 1] = fn
end

-- Go and Stop run from the footer, the step menu and the tracker; each tells these so the footer's Stop follows.
---@type fun()[]
local guidanceListeners = {}

---@param fn fun()
function Integrations.OnGuidanceChange(fn)
	guidanceListeners[#guidanceListeners + 1] = fn
end

local function NotifyGuidance()
	for _, fn in ipairs(guidanceListeners) do
		fn()
	end
end

-- True while Shortest Path is walking one of our multi-stop routes; it draws the numbered stops itself then.
---@return boolean
function Integrations.Guiding()
	local api = SPF()
	return api ~= nil and api.CurrentStop(OWNER) ~= nil
end

-- What the last Go handed Shortest Path, which may no longer be the chosen journey's steps.
---@type (AGFStep|AGFGiver)[]
local guided = {}

---@return (AGFStep|AGFGiver)[]
function Integrations.Guided()
	return Integrations.Guiding() and guided or {}
end

-- With Shortest Path, the step and every step after it become one numbered journey. When it declines (it returns
-- false when it cannot plan the route) or is absent, the native waypoint takes the step instead, so Go always
-- leaves a destination on any map the client allows one on. True when something now guides the player.
---@param step AGFStep|AGFGiver
---@return boolean
function Integrations.Navigate(step)
	local api = SPF()
	if api then
		local stops, steps, found = {}, {}, false
		for _, each in ipairs(ns.Route().steps) do
			found = found or each == step
			if found then
				stops[#stops + 1] = { map = each.map, x = each.x, y = each.y, title = each.title }
				steps[#steps + 1] = each
			end
		end
		if not found then
			stops[1] = { map = step.map, x = step.x, y = step.y, title = step.title }
			steps[1] = step
		end
		if api.NavigateRoute(OWNER, stops) then
			guided = steps
			ns.Pins.Refresh()
			NotifyGuidance()
			return true
		end
	end
	if not C_Map.CanSetUserWaypointOnMap(step.map) then
		-- The red line the world map shows when a pin can't go on a map, so Go never fails silently. Any journey an
		-- earlier Go started keeps guiding: a failed Go changes nothing.
		UIErrorsFrame:AddExternalErrorMessage(ns.L.NO_WAYPOINT)
		return false
	end
	-- A refusal leaves the journey an earlier Go started drawn; the waypoint below replaces it.
	if api and api.Cancel(OWNER) then
		ns.Pins.Refresh()
	end
	C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(step.map, step.x, step.y))
	C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	-- Saved per character, so Stop still knows the waypoint as ours after a /reload.
	ns.Prefs().waypoint = { map = step.map, x = step.x, y = step.y }
	NotifyGuidance()
	return true
end

-- The native waypoint is ours while it is still where Go put it (x and y within 1e-4); once the player moves or clears
-- it, it is theirs, and the saved one is forgotten.
---@return boolean
local function OwnsWaypoint()
	local prefs = ns.Prefs()
	local saved, point = prefs.waypoint, C_Map.GetUserWaypoint()
	local same = saved ~= nil
		and point ~= nil
		and point.uiMapID == saved.map
		and math.abs(point.position.x - saved.x) < 1e-4
		and math.abs(point.position.y - saved.y) < 1e-4
	if not same then
		prefs.waypoint = nil
	end
	return same
end

---@return boolean
function Integrations.Owns()
	local owns = OwnsWaypoint()
	return owns or Integrations.Guiding()
end

-- Stop: ends only what Go started. Shortest Path's journey by our name, and the native waypoint only while it is ours.
function Integrations.Cancel()
	local api = SPF()
	if api and api.Cancel(OWNER) then
		ns.Pins.Refresh()
	end
	if OwnsWaypoint() then
		C_Map.ClearUserWaypoint()
		C_SuperTrack.SetSuperTrackedUserWaypoint(false)
		ns.Prefs().waypoint = nil
	end
	NotifyGuidance()
end

---@return string?
function Integrations.Provider()
	if SPF() then
		return "Shortest Path"
	end
end
