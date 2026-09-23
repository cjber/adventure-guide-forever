std = "lua51"
max_line_length = 120
exclude_files = { "tools/.cache/**", ".types/**", "types/**", ".release/**" }
ignore = { "212/_.*", "212/self" } -- unused args prefixed with _, and self on mixin handlers

globals = {
	"AdventureGuideForeverDB",
	"AdventureGuideForeverCharDB",
	"AdventureGuideForeverPinMixin",
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
	-- State.lua
	"bit",
	"UnitRace",
	"UnitClass",
	"UnitFactionGroup",
	"UnitLevel",
	"C_Map",
	"C_QuestLog",
	"CreateFrame",
	-- Integrations.lua
	"ShortestPathForever",
	"UiMapPoint",
	"C_SuperTrack",
	-- Pins.lua
	"CreateFromMixins",
	"MapCanvasDataProviderMixin",
	"MapCanvasPinMixin",
	"GameTooltip",
	"GameTooltip_SetTitle",
	"GameTooltip_AddNormalLine",
	"GameTooltip_AddInstructionLine",
	"UIFrameFlash",
	"EventRegistry",
	"UnitXP",
	"UnitXPMax",
	"GetXPExhaustion",
	"QuestMapFrame",
	"QuestMapFrameOverrides",
	"QUESTS_LABEL",
	"BACKDROP_TUTORIAL_16_16",
	"BACKDROP_TOAST_12_12",
	"NORMAL_FONT_COLOR",
	"GRAY_FONT_COLOR",
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
}

files["tests/"] = { std = "+luajit" }
files["Data/Quests.lua"] = { max_line_length = false }
