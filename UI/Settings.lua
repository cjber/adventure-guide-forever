---@type string, AGFNamespace
local _, ns = ...

if ns.broken then
	return
end

-- Settings > AddOns > Adventure Guide Forever: one page under four short headings (Route, Map, Objective tracker,
-- Interface), most-used first, so there are no subpages to hunt through. Every row goes in through
-- Settings.RegisterInitializer, which inserts it from Blizzard's secure delegate: Settings.CreateCheckbox inserts
-- from our code instead, and the settings search reads every layout, so a restricted button in its results
-- (Social's Discord Sign In) was blocked and blamed on us. The headings go in through ForeverCore's own
-- SettingsSections (the same delegate). Child rows use an indent and value predicate, without a link into the shared
-- search layout.
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

	---@param initializers AGFSettingsInitializer[]
	local function Rows(initializers)
		for _, initializer in ipairs(initializers) do
			Settings.RegisterInitializer(category, initializer)
		end
	end

	---@param key string a phrase key of the heading
	local function Heading(key)
		ForeverCore.SettingsSections.Register(category, ns.L[key])
	end

	Heading("SETTINGS_GROUP_ROUTE")
	local level = Settings.RegisterAddOnSetting(
		category,
		"AdventureGuideForever_maxQuestLevelOffset",
		"maxQuestLevelOffset",
		AdventureGuideForeverDB,
		"number",
		ns.L.SETTING_QUEST_LEVEL,
		ns.DEFAULTS.maxQuestLevelOffset
	)
	level:SetValueChangedCallback(function(_, value)
		ns.SetSetting("maxQuestLevelOffset", value)
	end)
	local options = Settings.CreateSliderOptions(-4, 10, 1)
	options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
		local label = math.abs(value) == 1 and ns.L.SETTING_QUEST_LEVEL_ONE or ns.L.SETTING_QUEST_LEVEL_VALUE
		return label:format(value >= 0 and ("+" .. value) or tostring(value))
	end)
	Settings.RegisterInitializer(
		category,
		Settings.CreateSliderInitializer(level, options, ns.L.SETTING_QUEST_LEVEL_TOOLTIP)
	)
	Rows({
		Checkbox("restedxpGuide", ns.L.SETTING_RXP, ns.L.SETTING_RXP_TOOLTIP),
		Checkbox("wanderer", ns.L.SETTING_WANDERER, ns.L.SETTING_WANDERER_TOOLTIP),
		Checkbox("informationOnly", ns.L.SETTING_INFORMATION_ONLY, ns.L.SETTING_INFORMATION_ONLY_TOOLTIP),
		Checkbox("titleStartsRoute", ns.L.SETTING_TITLE_ROUTE, ns.L.SETTING_TITLE_ROUTE_TOOLTIP),
		Checkbox("autoStart", ns.L.SETTING_AUTO_START, ns.L.SETTING_AUTO_START_TOOLTIP),
		Checkbox("autoNextZone", ns.L.SETTING_AUTO_NEXT_ZONE, ns.L.SETTING_AUTO_NEXT_ZONE_TOOLTIP),
		Checkbox("followQuest", ns.L.SETTING_FOLLOW_QUEST, ns.L.SETTING_FOLLOW_QUEST_TOOLTIP),
		Checkbox("partyQuests", ns.L.SETTING_PARTY_QUESTS, ns.L.SETTING_PARTY_QUESTS_TOOLTIP),
		Checkbox("optimisedRoute", ns.L.SETTING_ROUTE_ORDER, ns.L.SETTING_ROUTE_ORDER_TOOLTIP),
		Checkbox("showOutgrown", ns.L.SETTING_OUTGROWN, ns.L.SETTING_OUTGROWN_TOOLTIP),
		Checkbox("trainingReminders", ns.L.SETTING_TRAINING_REMINDERS, ns.L.SETTING_TRAINING_REMINDERS_TOOLTIP),
		Checkbox("npcHighlight", ns.L.SETTING_NPC_HIGHLIGHT, ns.L.SETTING_NPC_HIGHLIGHT_TOOLTIP),
		Checkbox("polestarAside", ns.L.SETTING_POLESTAR_ASIDE, ns.L.SETTING_POLESTAR_ASIDE_TOOLTIP),
	})

	Heading("SETTINGS_GROUP_MAP")
	Rows({
		Checkbox("showMapPins", ns.L.SETTING_MAP_PINS, ns.L.SETTING_MAP_PINS_TOOLTIP),
		Checkbox("hideQuestMarkers", ns.L.MENU_HIDE_QUEST_MARKERS, ns.L.SETTING_HIDE_QUEST_MARKERS_TOOLTIP),
		Checkbox("showQuestGivers", ns.L.SETTING_GIVERS, ns.L.SETTING_GIVERS_TOOLTIP),
	})

	Heading("SETTINGS_GROUP_TRACKER")
	Rows({ Checkbox("showTracker", ns.L.SETTING_TRACKER, ns.L.SETTING_TRACKER_TOOLTIP) })
	if ns.QuestieOptions.Available() then
		local questie =
			Checkbox("hideQuestieTracker", ns.L.SETTING_HIDE_QUESTIE_TRACKER, ns.L.SETTING_HIDE_QUESTIE_TRACKER_TOOLTIP)
		questie:Indent()
		questie:AddEvaluateStateCVar("AdventureGuideForever_showTracker")
		questie:AddModifyPredicate(function()
			return ns.Setting("showTracker")
		end)
		Settings.RegisterInitializer(category, questie)
	end
	-- Lock keeps the column where it is: the grip ignores drag while it is on. It only writes the saved switch, so it
	-- is safe to toggle in combat.
	---@type ForeverTrackerHostAPI
	local host = ForeverCore.TrackerHost
	if host and host.GetSettings and host.SetLocked then
		local lock = Settings.RegisterProxySetting(
			category,
			"AdventureGuideForever_lockTracker",
			Settings.VarType.Boolean,
			ns.L.SETTING_LOCK_TRACKER,
			false,
			function()
				return host.GetSettings().locked == true
			end,
			function(value)
				host.SetLocked(value == true)
			end
		)
		Settings.RegisterInitializer(
			category,
			Settings.CreateCheckboxInitializer(lock, nil, ns.L.SETTING_LOCK_TRACKER_TOOLTIP)
		)
	end
	Rows({
		Checkbox("journeyWatch", ns.L.SETTING_JOURNEY_WATCH, ns.L.SETTING_JOURNEY_WATCH_TOOLTIP),
		Checkbox("trackRouteQuests", ns.L.SETTING_TRACK_ROUTE, ns.L.SETTING_TRACK_ROUTE_TOOLTIP),
	})

	Heading("SETTINGS_GROUP_INTERFACE")
	Rows({
		Checkbox("markUpgrades", ns.L.SETTING_UPGRADES, ns.L.SETTING_UPGRADES_TOOLTIP),
		Checkbox("warnClosing", ns.L.SETTING_WARN_CLOSING, ns.L.SETTING_WARN_CLOSING_TOOLTIP),
		Checkbox("stepSound", ns.L.SETTING_STEP_SOUND, ns.L.SETTING_STEP_SOUND_TOOLTIP),
		Checkbox("whatsNew", ns.L.SETTING_WHATS_NEW, ns.L.SETTING_WHATS_NEW_TOOLTIP),
	})
	-- Shown unless hidden: the checkbox reads the shown state, while the saved key holds the hide flag
	-- Core/MinimapButton.lua reads (Core.lua's migration carries an old micro menu choice over).
	local minimap = Settings.RegisterProxySetting(
		category,
		"AdventureGuideForever_minimapButton",
		Settings.VarType.Boolean,
		ns.L.SETTING_MINIMAP_BUTTON,
		true,
		function()
			return ns.Setting("minimapButtonHidden") ~= true
		end,
		function(value)
			ns.SetSetting("minimapButtonHidden", value ~= true)
		end
	)
	Settings.RegisterInitializer(
		category,
		Settings.CreateCheckboxInitializer(minimap, nil, ns.L.MINIMAP_BUTTON_TOOLTIP)
	)

	Settings.RegisterAddOnCategory(category)
	function ns.OpenSettings()
		ForeverCore.OpenSettingsPanel(category:GetID())
	end
end
