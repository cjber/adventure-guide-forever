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
	"EventUtil",
	"MAP_PIN_INVALID_MAP",
	"ITEM_CLASSES_ALLOWED",
	"ITEM_RACES_ALLOWED",
	"InCombatLockdown",
	-- State.lua
	"bit",
	"UnitRace",
	"UnitClass",
	"UnitFactionGroup",
	"UnitLevel",
	"GetMaxPlayerLevel",
	"C_Map",
	"C_QuestLog",
	"CreateFrame",
	-- Integrations.lua
	"ShortestPathForever",
	"UiMapPoint",
	"C_SuperTrack",
	"UIErrorsFrame",
	-- Pins.lua
	"CreateFromMixins",
	"MapCanvasDataProviderMixin",
	"MapCanvasPinMixin",
	"GameTooltip",
	"GameTooltip_SetTitle",
	"GameTooltip_AddNormalLine",
	"GameTooltip_AddHighlightLine",
	"GameTooltip_AddInstructionLine",
	"UIFrameFlash",
	"EventRegistry",
	"QuestMapFrame",
	"QuestMapFrameOverrides",
	"QUESTS_LABEL",
	"GameTooltip_Hide",
	-- Tracker.lua
	"Mixin",
	"ObjectiveTrackerManager",
	"ObjectiveTrackerFrame",
	"hooksecurefunc",
	"MenuUtil",
	"UIParent",
	-- Settings.lua
	"Settings",
	-- Dump.lua: frames Panel.lua and Tracker.lua create by name
	"AdventureGuideForeverPanel",
	"AdventureGuideForeverTab",
	"AdventureGuideForeverQuestsTab",
	"AdventureGuideForeverObjectiveTracker",
}

files["tests/"] = { std = "+luajit" }
files["Data/Quests.lua"] = { max_line_length = false }
