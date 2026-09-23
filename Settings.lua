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
	Checkbox(
		"showMapPins",
		"Show route pins on the map",
		"Number the suggested route's steps on the world map while their zone is shown."
	)
	Checkbox(
		"includeDungeonsDefault",
		"Include dungeons by default",
		"Turn the Dungeons chip on for a character the first time you open the guide. "
			.. "Change it any time from the guide tab itself."
	)

	Settings.RegisterAddOnCategory(category)
	function ns.OpenSettings()
		Settings.OpenToCategory(category:GetID())
	end
end
