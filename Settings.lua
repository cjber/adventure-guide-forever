---@type string, AGFNamespace
local _, ns = ...

-- Settings > AddOns > Adventure Guide Forever: one flat page, like tweaks-forever's subpages but
-- short enough here that it doesn't need one of its own. Every row goes in through Settings.RegisterInitializer, which
-- inserts it from Blizzard's secure delegate: Settings.CreateCheckbox inserts from our code instead, and the settings
-- search reads every layout, so a restricted button in its results (Social's Discord Sign In) was blocked and blamed
-- on us. The parent link and its predicate are only read when a row is drawn, so they are set before registering.
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
		return Settings.CreateCheckboxInitializer(setting, nil, tooltip)
	end

	local track = Checkbox("trackRouteQuests", ns.L.SETTING_TRACK_ROUTE, ns.L.SETTING_TRACK_ROUTE_TOOLTIP)
	local untrack = Checkbox("untrackOthers", ns.L.SETTING_UNTRACK_OTHERS, ns.L.SETTING_UNTRACK_OTHERS_TOOLTIP)
	untrack:SetParentInitializer(track, function()
		return ns.Setting("trackRouteQuests")
	end)
	for _, initializer in ipairs({
		Checkbox("showTracker", ns.L.SETTING_TRACKER, ns.L.SETTING_TRACKER_TOOLTIP),
		Checkbox("wanderer", ns.L.SETTING_WANDERER, ns.L.SETTING_WANDERER_TOOLTIP),
		Checkbox("followQuest", ns.L.SETTING_FOLLOW_QUEST, ns.L.SETTING_FOLLOW_QUEST_TOOLTIP),
		Checkbox("showMapPins", ns.L.SETTING_MAP_PINS, ns.L.SETTING_MAP_PINS_TOOLTIP),
		Checkbox("showQuestGivers", ns.L.SETTING_GIVERS, ns.L.SETTING_GIVERS_TOOLTIP),
		Checkbox("includeDungeonsDefault", ns.L.SETTING_DUNGEONS_DEFAULT, ns.L.SETTING_DUNGEONS_DEFAULT_TOOLTIP),
		Checkbox("titleStartsRoute", ns.L.SETTING_TITLE_ROUTE, ns.L.SETTING_TITLE_ROUTE_TOOLTIP),
		track,
		untrack,
		Checkbox("stepSound", ns.L.SETTING_STEP_SOUND, ns.L.SETTING_STEP_SOUND_TOOLTIP),
		Checkbox("suggestCompanions", ns.L.SETTING_COMPANIONS, ns.L.SETTING_COMPANIONS_TOOLTIP),
		Checkbox("whatsNew", ns.L.SETTING_WHATS_NEW, ns.L.SETTING_WHATS_NEW_TOOLTIP),
	}) do
		Settings.RegisterInitializer(category, initializer)
	end

	Settings.RegisterAddOnCategory(category)
	function ns.OpenSettings()
		Settings.OpenToCategory(category:GetID())
	end
end
