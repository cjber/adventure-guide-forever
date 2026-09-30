---@type string, AGFNamespace
local _, ns = ...

-- Settings > AddOns > Adventure Guide Forever: a short index page, then a subpage per group (Route, Map,
-- Objective tracker, Interface) so no page grows tall, like tweaks-forever. Every row goes in through
-- Settings.RegisterInitializer, which inserts it from Blizzard's secure delegate: Settings.CreateCheckbox inserts
-- from our code instead, and the settings search reads every layout, so a restricted button in its results
-- (Social's Discord Sign In) was blocked and blamed on us. Child rows use an indent and value predicate, without a
-- link into the shared search layout. Index buttons pass addSearchTags false, so search lists the settings, not
-- the buttons that open them.
function ns.RegisterSettings()
	local category = Settings.RegisterVerticalLayoutCategory(ns.TITLE)

	---@param subcategory AGFSettingsCategory
	---@param key string
	---@param name string
	---@param tooltip string
	---@return AGFSettingsInitializer
	local function Checkbox(subcategory, key, name, tooltip)
		local setting = Settings.RegisterAddOnSetting(
			subcategory,
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

	-- Each group is an index label key and a builder that registers its rows into the group's subcategory, in order.
	local groups = {
		{
			"SETTINGS_GROUP_ROUTE",
			function(subcategory)
				for _, initializer in ipairs({
					Checkbox(subcategory, "wanderer", ns.L.SETTING_WANDERER, ns.L.SETTING_WANDERER_TOOLTIP),
					Checkbox(subcategory, "followQuest", ns.L.SETTING_FOLLOW_QUEST, ns.L.SETTING_FOLLOW_QUEST_TOOLTIP),
					Checkbox(subcategory, "optimisedRoute", ns.L.SETTING_ROUTE_ORDER, ns.L.SETTING_ROUTE_ORDER_TOOLTIP),
					Checkbox(
						subcategory,
						"includeDungeonsDefault",
						ns.L.SETTING_DUNGEONS_DEFAULT,
						ns.L.SETTING_DUNGEONS_DEFAULT_TOOLTIP
					),
					Checkbox(
						subcategory,
						"titleStartsRoute",
						ns.L.SETTING_TITLE_ROUTE,
						ns.L.SETTING_TITLE_ROUTE_TOOLTIP
					),
					Checkbox(subcategory, "autoStart", ns.L.SETTING_AUTO_START, ns.L.SETTING_AUTO_START_TOOLTIP),
					Checkbox(subcategory, "stepSound", ns.L.SETTING_STEP_SOUND, ns.L.SETTING_STEP_SOUND_TOOLTIP),
				}) do
					Settings.RegisterInitializer(subcategory, initializer)
				end
			end,
		},
		{
			"SETTINGS_GROUP_MAP",
			function(subcategory)
				for _, initializer in ipairs({
					Checkbox(subcategory, "showMapPins", ns.L.SETTING_MAP_PINS, ns.L.SETTING_MAP_PINS_TOOLTIP),
					Checkbox(subcategory, "showQuestGivers", ns.L.SETTING_GIVERS, ns.L.SETTING_GIVERS_TOOLTIP),
				}) do
					Settings.RegisterInitializer(subcategory, initializer)
				end
			end,
		},
		{
			"SETTINGS_GROUP_TRACKER",
			function(subcategory)
				local show = Checkbox(subcategory, "showTracker", ns.L.SETTING_TRACKER, ns.L.SETTING_TRACKER_TOOLTIP)
				local track = Checkbox(
					subcategory,
					"trackRouteQuests",
					ns.L.SETTING_TRACK_ROUTE,
					ns.L.SETTING_TRACK_ROUTE_TOOLTIP
				)
				local untrack = Checkbox(
					subcategory,
					"untrackOthers",
					ns.L.SETTING_UNTRACK_OTHERS,
					ns.L.SETTING_UNTRACK_OTHERS_TOOLTIP
				)
				untrack:Indent()
				untrack:AddEvaluateStateCVar("AdventureGuideForever_trackRouteQuests")
				untrack:AddModifyPredicate(function()
					return ns.Setting("trackRouteQuests")
				end)
				Settings.RegisterInitializer(subcategory, show)
				Settings.RegisterInitializer(subcategory, track)
				Settings.RegisterInitializer(subcategory, untrack)
			end,
		},
		{
			"SETTINGS_GROUP_INTERFACE",
			function(subcategory)
				for _, initializer in ipairs({
					Checkbox(subcategory, "floatWindow", ns.L.SETTING_FLOAT_WINDOW, ns.L.SETTING_FLOAT_WINDOW_TOOLTIP),
					Checkbox(
						subcategory,
						"suggestCompanions",
						ns.L.SETTING_COMPANIONS,
						ns.L.SETTING_COMPANIONS_TOOLTIP
					),
					Checkbox(subcategory, "whatsNew", ns.L.SETTING_WHATS_NEW, ns.L.SETTING_WHATS_NEW_TOOLTIP),
				}) do
					Settings.RegisterInitializer(subcategory, initializer)
				end
			end,
		},
	}

	for _, group in ipairs(groups) do
		local subcategory = Settings.RegisterVerticalLayoutSubcategory(category, ns.L[group[1]])
		group[2](subcategory)
		-- The index is buttons that open each subpage; search finds the settings themselves instead.
		Settings.RegisterInitializer(
			category,
			CreateSettingsButtonInitializer(ns.L[group[1]], ns.L.SETTINGS_OPEN, function()
				Settings.OpenToCategory(subcategory:GetID())
			end, nil, false)
		)
	end

	Settings.RegisterAddOnCategory(category)
	function ns.OpenSettings()
		Settings.OpenToCategory(category:GetID())
	end
end
