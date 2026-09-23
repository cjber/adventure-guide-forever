---@type string, AGFNamespace
local _, ns = ...

-- Settings > AddOns > Adventure Guide Forever: one flat page, like tweaks-forever's subpages but
-- short enough here that it doesn't need one of its own.
function ns.RegisterSettings()
	local category = Settings.RegisterVerticalLayoutCategory(ns.TITLE)

	---@param key string
	---@param name string
	---@param tooltip string
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
		Settings.CreateCheckbox(category, setting, tooltip)
	end

	Checkbox(
		"showTracker",
		"Show tracker section",
		'A short "Adventure Guide" section above your quests in the objective tracker, for the current step.'
	)
	Checkbox("showMapPins", "Show route pins on the map", ns.L.SETTING_MAP_PINS_TOOLTIP)
	Checkbox("showQuestGivers", "Show quest givers on the map", ns.L.SETTING_GIVERS_TOOLTIP)
	Checkbox("includeDungeonsDefault", "Include dungeons by default", ns.L.SETTING_DUNGEONS_DEFAULT_TOOLTIP)

	Settings.RegisterAddOnCategory(category)
	function ns.OpenSettings()
		Settings.OpenToCategory(category:GetID())
	end
end
