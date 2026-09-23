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

---@param step AGFStep
function Integrations.Navigate(step)
	local api = SPF()
	if api then
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
