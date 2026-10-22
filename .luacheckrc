std = "lua51"
max_line_length = 120
exclude_files = {
	"tools/.cache/**",
	-- The test corpus tools/gen_corpus.py builds (gitignored).
	"tests/.corpus/**",
	".types/**",
	"types/**",
	".release/**",
	-- Agent worktrees: whole copies of the repo, untracked.
	".claude/**",
	-- Shortest Path's own types, vendored byte for byte for tests/contract_spec.lua.
	"tests/fixtures/spf_types_API.lua",
}
ignore = { "212/_.*", "212/self" } -- unused args prefixed with _, and self on mixin handlers

globals = {
	"RXPCData",
	"ForeverFamily",
	"ForeverTrackerHost",
	"AdventureGuideForever",
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
	"time",
	"LibStub",
	"LibDBIcon10_RXPGuides",
	"RXP",
	"MinimalSliderWithSteppersMixin",
	"ShowUIPanel",
	"HideUIPanel",
	"CreateFramePoolCollection",
	"C_XMLUtil",
	"CreateScrollBoxListLinearView",
	"CreateDataProvider",
	"ScrollUtil",
	"NORMAL_FONT_COLOR",
	"GRAY_FONT_COLOR",
	"ITEM_QUALITY_COLORS",
	"AtlasLoot",
	"GetInstanceInfo",
	"geterrorhandler",
	"AdventureGuideForeverWindow",
	-- Core.lua
	"DEFAULT_CHAT_FRAME",
	"C_Timer",
	"GetBuildInfo",
	"strtrim",
	"strlenutf8",
	"WorldMapFrame",
	"GetQuestUiMapID",
	"EventUtil",
	"MAP_PIN_INVALID_MAP",
	"ITEM_CLASSES_ALLOWED",
	"ITEM_RACES_ALLOWED",
	"InCombatLockdown",
	"UnitOnTaxi",
	-- Party.lua
	"C_ChatInfo",
	"IsInGroup",
	"IsInRaid",
	"GetNormalizedRealmName",
	"LE_PARTY_CATEGORY_HOME",
	"UNKNOWNOBJECT",
	"UnitExists",
	"UnitName",
	-- Secret.lua
	"canaccessvalue",
	-- SafeCall.lua
	"debugstack",
	-- Offers.lua
	"C_GossipInfo",
	"GetNumAvailableQuests",
	"GetAvailableTitle",
	"GetAvailableQuestInfo",
	-- Closes.lua
	"GetQuestID",
	"QuestGetAutoAccept",
	-- State.lua
	"GetUnitSpeed",
	"bit",
	"UnitRace",
	"UnitClass",
	"UnitClassBase",
	"UnitFactionGroup",
	"UnitLevel",
	"GetMaxPlayerLevel",
	"GetXPExhaustion",
	"IsResting",
	"UnitXPMax",
	"GetRealZoneText",
	"C_Map",
	"C_Minimap",
	"Minimap",
	"C_Texture",
	"C_QuestLog",
	"C_CreatureInfo",
	"C_SkillInfo",
	"C_Reputation",
	"CreateFrame",
	-- Integrations.lua
	"ShortestPathForever",
	"TweaksForever",
	"Polestar",
	"LegacyForever",
	"GetBindLocation",
	"GetLocale",
	"GetTime",
	"GetMoney",
	"UiMapPoint",
	"C_SuperTrack",
	"UIErrorsFrame",
	-- QuestieSource.lua
	"LibQuestieDB",
	"Questie",
	"QuestieLoader",
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
	"GetQuestLogQuestText",
	"BreakUpLargeNumbers",
	"GetLFGDungeonInfo",
	"CreateColor",
	"UIFrameFlash",
	"UIFrameFlashStop",
	"EventRegistry",
	"QuestMapFrame",
	"QuestMapFrameOverrides",
	"QUESTS_LABEL",
	"GameTooltip_Hide",
	"IsShiftKeyDown",
	"SetCursor",
	"ResetCursor",
	-- Tooltip.lua
	"TooltipDataProcessor",
	"Enum",
	"UnitGUID",
	-- Tracker.lua
	"Mixin",
	"ObjectiveTrackerFrame",
	"hooksecurefunc",
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
	"CreateSettingsButtonInitializer",
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
files["Data/Geometry.lua"] = { max_line_length = false }
-- The translations: one phrase per line, however long (enUS.lua, written by hand, keeps the limit).
for _, locale in ipairs({ "deDE", "esES", "esMX", "frFR", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }) do
	files["Locales/" .. locale .. ".lua"] = { max_line_length = false }
end
read_globals[#read_globals + 1] = "EditModeManagerFrame"
