---@type string, AGFNamespace
local _, ns = ...
---@class AGFProviders
local Providers = {}
ns.Providers = Providers
local listeners = {}
function Providers.OnChange(callback)
	listeners[#listeners + 1] = callback
end

function Providers.DungeonEntrance(instanceID)
	local api = TweaksForever and TweaksForever.API
	if not TweaksForever then
		return nil, "missing"
	end
	if
		type(api) ~= "table"
		or type(api.version) ~= "number"
		or api.version < 1
		or type(api.DungeonEntrance) ~= "function"
	then
		return nil, "outdated"
	end
	local point = api.DungeonEntrance(instanceID)
	if type(point) ~= "table" or not ns.Model.ValidPlace(point) then
		return nil, "unknown"
	end
	return { map = point.map, x = point.x, y = point.y }
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, _, name)
	if name == "TweaksForever" then
		for _, callback in ipairs(listeners) do
			callback()
		end
	end
end)
