std = "lua51"
max_line_length = 120
exclude_files = {
	"tools/.cache/**",
	".types/**",
	"types/**",
	".release/**",
	"tests/golden/**",
	-- Shortest Path's own types, vendored byte for byte for tests/contract_spec.lua.
	"tests/fixtures/spf_types_API.lua",
}
ignore = { "212/_.*", "212/self" } -- unused args prefixed with _, and self on mixin handlers

globals = {
	"AdventureGuideForeverDB",
	"AdventureGuideForeverCharDB",
	"AdventureGuideForeverPinMixin",
	"AdventureGuideForeverGiverPinMixin",
	"AdventureGuideForever_OnAddonCompartmentClick",
	"SLASH_ADVENTUREGUIDEFOREVER1",
	"SLASH_ADVENTUREGUIDEFOREVER2",
	"SlashCmdList",
	-- Window.lua: the key binding (Bindings.xml) and its names on the Key Bindings page
	"AdventureGuideForever_ToggleWindow",
	"BINDING_HEADER_ADVENTUREGUIDEFOREVER",
	"BINDING_NAME_ADVENTUREGUIDEFOREVER_WINDOW",
}

read_globals = {
	-- Core.lua
	"DEFAULT_CHAT_FRAME",
	"C_Timer",
	"GetBuildInfo",
	"strtrim",
	"WorldMapFrame",
	"ToggleWorldMap",
	"OpenQuestLog",
	"QuestMapFrame_ShowQuestDetails",
	"EventUtil",
	"MAP_PIN_INVALID_MAP",
	"ITEM_CLASSES_ALLOWED",
	"ITEM_RACES_ALLOWED",
	"InCombatLockdown",
	"UnitOnTaxi",
	-- State.lua
	"bit",
	"UnitRace",
	"UnitClass",
	"UnitFactionGroup",
	"UnitLevel",
	"GetMaxPlayerLevel",
	"GetXPExhaustion",
	"IsResting",
	"UnitXPMax",
	"GetRealZoneText",
	"C_Map",
	"C_QuestLog",
	"C_CreatureInfo",
	"C_SkillInfo",
	"C_Reputation",
	"CreateFrame",
	-- Integrations.lua
	"ShortestPathForever",
	"TweaksForever",
	"UiMapPoint",
	"C_SuperTrack",
	"UIErrorsFrame",
	-- QuestieSource.lua
	"LibQuestieDB",
	"C_AddOns",
	"debugprofilestop",
	-- Pins.lua
	"CreateFromMixins",
	"MapCanvasDataProviderMixin",
	"MapCanvasPinMixin",
	"GameTooltip",
	"GameTooltip_SetTitle",
	"GameTooltip_AddNormalLine",
	"GameTooltip_AddHighlightLine",
	"GameTooltip_AddInstructionLine",
	"GameTooltip_AddErrorLine",
	"GameTooltip_AddDisabledLine",
	"GameTooltip_AddColoredLine",
	"GetQuestDifficultyColor",
	"CreateColor",
	"UIFrameFlash",
	"EventRegistry",
	"QuestMapFrame",
	"QuestMapFrameOverrides",
	"QUESTS_LABEL",
	"GameTooltip_Hide",
	"IsShiftKeyDown",
	-- Tooltip.lua
	"TooltipDataProcessor",
	"Enum",
	"UnitGUID",
	-- Tracker.lua
	"Mixin",
	"ObjectiveTrackerManager",
	"ObjectiveTrackerFrame",
	"hooksecurefunc",
	"MenuUtil",
	"OBJECTIVE_DASH_STYLE_HIDE_AND_COLLAPSE",
	"PlaySound",
	"SOUNDKIT",
	"tContains",
	"UIParent",
	-- Moments.lua
	"AddonCompartmentFrame",
	-- Asides.lua and PvP.lua (roadmap #12, #25, #28), each read with a nil check
	"GetNumUnspentTalents",
	"C_PvP",
	"C_MajorFactions",
	"IsInInstance",
	-- Hints/Explore.lua
	"C_MapExplorationInfo",
	-- Settings.lua
	"Settings",
	-- Window.lua and its tabs
	"UISpecialFrames",
	"PanelTemplates_SetNumTabs",
	"PanelTemplates_SetTab",
	"GetBindingAction",
	"GetBindingKey",
	"SetBinding",
	"SaveBindings",
	"GetCurrentBindingSet",
	"SkillUpForever",
	"C_Item",
	"C_Spell",
	"C_CurrencyInfo",
	-- Dump.lua: frames Panel.lua and Tracker.lua create by name
	"AdventureGuideForeverPanel",
	"AdventureGuideForeverTab",
	"AdventureGuideForeverQuestsTab",
	"AdventureGuideForeverObjectiveTracker",
}

files["tests/"] = { std = "+luajit" }
files["Data/Quests.lua"] = { max_line_length = false }
