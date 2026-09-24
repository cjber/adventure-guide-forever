---@type string, AGFNamespace
local _, ns = ...

-- Settings > AddOns > Adventure Guide Forever: one flat page, like tweaks-forever's subpages but
-- short enough here that it doesn't need one of its own.
function ns.RegisterSettings()
	local category = Settings.RegisterVerticalLayoutCategory(ns.TITLE)

	---@param key string
	---@param name string
	---@param tooltip string
	---@return AGFSettingsInitializer
	local function Checkbox(key, name, tooltip)
		local setting = Settings.RegisterAddOnSetting(
			category,
			"AdventureGuideForever_" .. key,
			key,
			AdventureGuideForeverDB,
			Settings.VarType.Boolean,
			name,
			ns.DEFAULTS[key]
		)
		setting:SetValueChangedCallback(function(_, value)
			ns.SetSetting(key, value)
		end)
		return Settings.CreateCheckbox(category, setting, tooltip)
	end

	Checkbox("showTracker", ns.L.SETTING_TRACKER, ns.L.SETTING_TRACKER_TOOLTIP)
	Checkbox("showMapPins", ns.L.SETTING_MAP_PINS, ns.L.SETTING_MAP_PINS_TOOLTIP)
	Checkbox("showQuestGivers", ns.L.SETTING_GIVERS, ns.L.SETTING_GIVERS_TOOLTIP)
	Checkbox("includeDungeonsDefault", ns.L.SETTING_DUNGEONS_DEFAULT, ns.L.SETTING_DUNGEONS_DEFAULT_TOOLTIP)
	Checkbox("titleStartsRoute", ns.L.SETTING_TITLE_ROUTE, ns.L.SETTING_TITLE_ROUTE_TOOLTIP)
	local track = Checkbox("trackRouteQuests", ns.L.SETTING_TRACK_ROUTE, ns.L.SETTING_TRACK_ROUTE_TOOLTIP)
	local untrack = Checkbox("untrackOthers", ns.L.SETTING_UNTRACK_OTHERS, ns.L.SETTING_UNTRACK_OTHERS_TOOLTIP)
	untrack:SetParentInitializer(track, function()
		return ns.Setting("trackRouteQuests")
	end)

	Settings.RegisterAddOnCategory(category)
	function ns.OpenSettings()
		Settings.OpenToCategory(category:GetID())
	end
end
