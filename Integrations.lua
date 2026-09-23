---@type string, AGFNamespace
local _, ns = ...

---@class AGFIntegrationsModule : AGFIntegrations
local Integrations = {}
ns.Integrations = Integrations

-- Passed to Shortest Path so it can tell our journeys apart from the player's own.
local OWNER = "AdventureGuideForever"

---@class AGFShortestPathAPI
---@field version integer
---@field Estimate AGFTravel
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

---@return AGFTravel?
function Integrations.Travel()
	local api = SPF()
	return api and api.Estimate
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
