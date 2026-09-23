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

---@param step AGFStep
---@return string?
function Integrations.TravelLine(step)
	local api = SPF()
	local player = ns.State.Player()
	if not (api and player.map and player.x and player.y) then
		return nil
	end
	local seconds = api.Estimate(player.map, player.x, player.y, step.map, step.x, step.y)
	if type(seconds) == "number" and seconds >= 0 and seconds < math.huge then
		return ("About %d min away"):format(math.max(1, math.ceil(seconds / 60)))
	end
end

function Integrations.RefreshTravel()
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

-- True while Shortest Path is walking one of our multi-stop routes; it draws the numbered stops itself then.
---@return boolean
function Integrations.Guiding()
	local api = SPF()
	return api ~= nil and api.CurrentStop(OWNER) ~= nil
end

-- With Shortest Path, the step and every step after it become one numbered journey. When it declines (it returns
-- false when it cannot plan the route) or is absent, the native waypoint takes the step instead, so Go always
-- leaves a destination on any map the client allows one on. True when something now guides the player.
---@param step AGFStep|AGFGiver
---@return boolean
function Integrations.Navigate(step)
	local api = SPF()
	if api then
		local stops, found = {}, false
		for _, each in ipairs(ns.Route().steps) do
			found = found or each == step
			if found then
				stops[#stops + 1] = { map = each.map, x = each.x, y = each.y, title = each.title }
			end
		end
		if not found then
			stops[1] = { map = step.map, x = step.x, y = step.y, title = step.title }
		end
		local started = api.NavigateRoute(OWNER, stops)
		if not started then
			-- A refusal leaves the journey an earlier Go started drawn; the waypoint below replaces it.
			api.Cancel(OWNER)
		end
		ns.Pins.Refresh()
		if started then
			return true
		end
	end
	if not C_Map.CanSetUserWaypointOnMap(step.map) then
		-- The red line the world map shows when a pin can't go on a map, so Go never fails silently.
		UIErrorsFrame:AddExternalErrorMessage(ns.L.NO_WAYPOINT)
		return false
	end
	C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(step.map, step.x, step.y))
	C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	return true
end

function Integrations.Cancel()
	local api = SPF()
	if api then
		api.Cancel(OWNER)
		ns.Pins.Refresh()
		return
	end
	C_Map.ClearUserWaypoint()
	C_SuperTrack.SetSuperTrackedUserWaypoint(false)
end

---@return string?
function Integrations.Provider()
	if SPF() then
		return "Shortest Path"
	end
end
