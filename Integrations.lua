---@type string, AGFNamespace
local _, ns = ...

---@class AGFIntegrationsModule : AGFIntegrations
local Integrations = {}
ns.Integrations = Integrations

-- Passed to Shortest Path so it can tell our journeys apart from the player's own.
local OWNER = "AdventureGuideForever"

---@class AGFShortestPathAPI
---@field version integer
---@field Estimate fun(map: integer, x: number, y: number, toMap: integer, toX: number, toY: number): number?
---@field Navigate fun(owner: string, map: integer, x: number, y: number, title: string): boolean
---@field NavigateRoute? fun(owner: string, stops: { map: integer, x: number, y: number, title: string }[]): boolean
---@field CurrentStop? fun(owner: string): integer?
---@field Cancel fun(owner: string)

---@return AGFShortestPathAPI?
local function SPF()
	local api = ShortestPathForever and ShortestPathForever.API
	if api and api.version and api.version >= 1 then
		return api
	end
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
	return api ~= nil and api.CurrentStop ~= nil and api.CurrentStop(OWNER) ~= nil
end

-- With a Shortest Path that takes routes, the step and every step after it become one numbered journey.
---@param step AGFStep|AGFGiver
function Integrations.Navigate(step)
	local api = SPF()
	if api and api.NavigateRoute then
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
		api.NavigateRoute(OWNER, stops)
		ns.Pins.Refresh()
		return
	elseif api then
		api.Navigate(OWNER, step.map, step.x, step.y, step.title)
		return
	end
	local point = UiMapPoint.CreateFromCoordinates(step.map, step.x, step.y)
	C_Map.SetUserWaypoint(point)
	C_SuperTrack.SetSuperTrackedUserWaypoint(true)
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
