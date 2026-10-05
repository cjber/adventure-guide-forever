---@meta

-- FrameXML surfaces absent from Ketho's pinned Core annotations, or fields our own code adds
-- to the namespace (Pins.lua, Panel.lua, Settings.lua). Signatures follow Gethe/wow-ui-source
-- forever @ (see tools/typecheck.sh for the pinned revision). These declarations never load in
-- the client.

-- Additive: merges with the fields already declared on AGFNamespace in types/Namespace.lua.
---@class AGFNamespace
---@field OpenPanel? fun() set once the world map tab exists (Panel.lua); opens the guide tab.
---@field RegisterSettings fun() defined by Settings.lua, called once after ADDON_LOADED.
---@field OpenSettings? fun() set by RegisterSettings; opens our page under Settings > AddOns.
---@field Pins AGFPinsModule
---@field DEFAULTS table<string, boolean> account-wide setting defaults (Core.lua)

---@class AGFPinsModule
---@field Ping fun(key: string) flash the numbered pin for a step, if it's on the shown map.

---@type {AddMessage: fun(self: table, text: string)}
DEFAULT_CHAT_FRAME = nil

---@type {ContinueOnAddOnLoaded: fun(name: string, callback: fun()), ContinueAfterAllEvents: fun(callback: fun(), ...: string)}
EventUtil = {}

---@type {RegisterCallback: fun(self: any, event: string, callback: fun(...), owner: any), TriggerEvent: fun(self: any, event: string, ...: any)}
EventRegistry = {}

---@class EditModeManagerFrame : Frame
---@field IsEditModeActive fun(self: EditModeManagerFrame): boolean
---@type EditModeManagerFrame?
EditModeManagerFrame = nil

---@type fun(region: Region, fadeInTime: number, fadeOutTime: number, flashDuration: number, showWhenDone: boolean)
UIFrameFlash = nil
---@type fun(frame: Region)
UIFrameFlashStop = nil

-- Blizzard_Minimap Mainline/AddonCompartment.xml: the minimap's addon compartment button; absent where the flavour
-- doesn't load it, so read with a nil check.
---@type DropdownButton?
AddonCompartmentFrame = nil

-- UIErrorsFrame.lua: the red line at the top of the screen, as the client shows its own errors.
---@type {AddExternalErrorMessage: fun(self: any, message: string)}
UIErrorsFrame = nil

-- GlobalStrings: "You can't place a pin on this map." in enUS; absent from some builds, so read with a fallback.
---@type string?
MAP_PIN_INVALID_MAP = nil

-- GlobalStrings: "Classes: %s" and "Races: %s" in enUS, the item tooltip's restriction lines; read with a fallback.
---@type string?
ITEM_CLASSES_ALLOWED = nil
---@type string?
ITEM_RACES_ALLOWED = nil

---@type table<string, fun(msg: string, editBox: EditBox)>
SlashCmdList = nil

-- The zone a quest's objectives are in, 0 when it has none (Blizzard_UIPanels_Game/Mainline/QuestMapFrame.lua:611).
-- The pinned annotations declare it without its signature.
---@param questID integer
---@param ignoreWaypoints? boolean
---@return integer uiMapID
function GetQuestUiMapID(questID, ignoreWaypoints) end

-- Blizzard_ObjectiveTracker/Blizzard_ObjectiveTrackerShared.lua:23: an objective line with no dash and no indent.
---@type integer
OBJECTIVE_DASH_STYLE_HIDE_AND_COLLAPSE = 3

-- ScrollFrameTemplate: ScrollFrame_OnLoad attaches a MinimalScrollBar as ScrollBar.
---@class AGFScrollFrame : ScrollFrame
---@field ScrollBar Frame

-- Blizzard_SharedXML/Shared/Scroll: the scroll box, its linear view and the data provider the list factory builds
-- on. The client loads them with the shared XML, so they are present wherever the guide's window is.
---@class AGFScrollBoxLinearView
---@field SetElementExtent fun(self: AGFScrollBoxLinearView, extent: number)
---@field SetElementExtentCalculator fun(self: AGFScrollBoxLinearView, calculator: fun(index: integer, elementData: any): number)
---@field SetElementInitializer fun(self: AGFScrollBoxLinearView, template: string, initializer: fun(frame: Frame, elementData: any))
---@field SetPadding fun(self: AGFScrollBoxLinearView, top: number, bottom: number, left: number, right: number, spacing?: number)

---@type fun(top?: number, bottom?: number, left?: number, right?: number, spacing?: number): AGFScrollBoxLinearView
CreateScrollBoxListLinearView = nil

---@type {InitScrollBoxListWithScrollBar: fun(scrollBox: Frame, scrollBar: Frame, view: AGFScrollBoxLinearView)}
ScrollUtil = nil

---@type fun(tbl?: any[]): AGFDataProvider
CreateDataProvider = nil

---@class AGFSearchBox : EditBox
---@field Instructions FontString

---@class AGFQuestContentFrame : Frame
---@field displayMode any

---@class AGFQuestMapFrame : Frame
---@field ContentFrames AGFQuestContentFrame[]
---@field QuestsTab Button
---@field MapLegendTab Button
---@field ContentsAnchor Frame
---@field displayMode any
---@type AGFQuestMapFrame
QuestMapFrame = nil

---@class AGFQuestMapFrameOverrides
---@field questTabHidden? boolean
---@field GetQuestsTabAnchorOffset fun(): number, number
---@type AGFQuestMapFrameOverrides
QuestMapFrameOverrides = nil

---@type string
QUESTS_LABEL = nil

---@class AGFMapProvider
---@field GetMap fun(self: AGFMapProvider): AGFWorldMapFrame
---@field RefreshAllData fun(self: AGFMapProvider, fromOnShow?: boolean)
---@field RemoveAllData fun(self: AGFMapProvider)
---@type AGFMapProvider
MapCanvasDataProviderMixin = nil

---@class AGFMapPinMixin : Frame
---@field GetMap fun(self: AGFMapPinMixin): AGFWorldMapFrame
---@field UseFrameLevelType fun(self: AGFMapPinMixin, frameLevelType: string)
---@field SetPosition fun(self: AGFMapPinMixin, x: number, y: number)
---@field SetScalingLimits fun(self: AGFMapPinMixin, style: number, minScale: number, maxScale: number)
---@field SetIgnoreGlobalPinScale fun(self: AGFMapPinMixin, ignore: boolean)
---@field ApplyCurrentScale fun(self: AGFMapPinMixin)
---@type AGFMapPinMixin
MapCanvasPinMixin = nil

---@class AGFWorldMapFrame : Frame
---@field ScrollContainer Frame
---@field AddDataProvider fun(self: AGFWorldMapFrame, provider: AGFMapProvider)
---@field GetMapID fun(self: AGFWorldMapFrame): integer?
---@field AcquirePin fun(self: AGFWorldMapFrame, template: string, ...: any): AGFPinFrame
---@field RemoveAllPinsByTemplate fun(self: AGFWorldMapFrame, template: string)
---@field EnumeratePinsByTemplate fun(self: AGFWorldMapFrame, template: string): fun(): AGFPinFrame?
---@type AGFWorldMapFrame
WorldMapFrame = nil

---@param tooltip GameTooltip
---@param title string
function GameTooltip_SetTitle(tooltip, title) end
---@param tooltip GameTooltip
---@param text string
function GameTooltip_AddNormalLine(tooltip, text) end

---@param tooltip GameTooltip
---@param text string
function GameTooltip_AddHighlightLine(tooltip, text) end
---@param tooltip GameTooltip
---@param text string
function GameTooltip_AddInstructionLine(tooltip, text) end
---@param tooltip GameTooltip
---@param text string
function GameTooltip_AddErrorLine(tooltip, text) end
---@param tooltip GameTooltip
---@param text string
function GameTooltip_AddDisabledLine(tooltip, text) end
function GameTooltip_Hide() end
---@param tooltip GameTooltip
---@param text string
---@param color ColorMixin
function GameTooltip_AddColoredLine(tooltip, text, color) end

-- UIParent.lua: the quest log's colour for a quest of `level` at the player's level (QuestDifficultyColors).
---@param level integer
---@return {r: number, g: number, b: number}
function GetQuestDifficultyColor(level) end

---@class AGFUiMapPointFactory
---@field CreateFromCoordinates fun(uiMapID: integer, x: number, y: number, z?: number): UiMapPoint
---@type AGFUiMapPointFactory
UiMapPoint = nil

---@type {API: table?}? read only through Integrations.lua SPF(), which checks it against AGFSPFAPI
ShortestPathForever = nil

---@type {API: table?}? read through Tweaks.lua and Providers.lua, each checking it against AGFTFAPI
TweaksForever = nil

---@class AGFSettingsSetting
---@field SetValueChangedCallback fun(self: AGFSettingsSetting, callback: fun(setting: AGFSettingsSetting, value: boolean))
-- A checkbox's row (Blizzard_Settings_Shared SettingsListElementInitializer); a child is greyed while predicate is false.
---@class AGFSettingsInitializer
---@field Indent fun(self: AGFSettingsInitializer)
---@field AddEvaluateStateCVar fun(self: AGFSettingsInitializer, variable: string)
---@field AddModifyPredicate fun(self: AGFSettingsInitializer, predicate: fun(): boolean)
---@class AGFSettingsCategory
---@field GetID fun(self: AGFSettingsCategory): integer
---@class AGFSettingsModule
---@field VarType {Boolean: string}
---@field RegisterVerticalLayoutCategory fun(name: string): AGFSettingsCategory
---@field RegisterVerticalLayoutSubcategory fun(category: AGFSettingsCategory, name: string): AGFSettingsCategory
---@field RegisterAddOnSetting fun(category: AGFSettingsCategory, variable: string, key: string, storage: table, variableType: string, name: string, default: boolean): AGFSettingsSetting
---@field RegisterProxySetting fun(category: AGFSettingsCategory, variable: string, variableType: string, name: string, default: boolean, getter: (fun(): boolean), setter: (fun(value: boolean))): AGFSettingsSetting
---@field NotifyUpdate fun(variable: string)
---@field CreateCheckboxInitializer fun(setting: AGFSettingsSetting, options?: table, tooltip?: string): AGFSettingsInitializer
---@field RegisterInitializer fun(category: AGFSettingsCategory, initializer: AGFSettingsInitializer) inserts the row from Blizzard's secure delegate
---@field RegisterAddOnCategory fun(category: AGFSettingsCategory)
---@field OpenToCategory fun(categoryID: integer)
---@type AGFSettingsModule
Settings = nil

-- Blizzard_Settings_Shared.lua: the index page's button; addSearchTags false keeps it out of the settings search.
---@type fun(name: string, tooltip: string, onClick: fun(), getDisabledTooltip?: fun(), addSearchTags?: boolean): AGFSettingsInitializer
CreateSettingsButtonInitializer = nil

---@class AGFTabButton : Button
---@field SetCustomOnMouseUpHandler fun(self: AGFTabButton, handler: fun(self: AGFTabButton, mouseButton: string, upInside: boolean))
---@field SetChecked fun(self: AGFTabButton, checked: boolean)
---@field Icon Texture
---@field activeAtlas? string
---@field inactiveAtlas? string
---@field tooltipText string

---@class AGFTrackerBlock : Frame
---@field id string
---@field SetHeader fun(self: AGFTrackerBlock, text: string)
---@field AddObjective fun(self: AGFTrackerBlock, index: integer|string, text: string, ...: any)

---@class ObjectiveTrackerModuleTemplate : Frame
---@field uiOrder number
---@field SetHeader fun(self: ObjectiveTrackerModuleTemplate, text: string)
---@field GetBlock fun(self: ObjectiveTrackerModuleTemplate, id: string): AGFTrackerBlock
---@field GetContextMenuParent fun(self: ObjectiveTrackerModuleTemplate): Frame
---@field LayoutBlock fun(self: ObjectiveTrackerModuleTemplate, block: AGFTrackerBlock): boolean
---@field MarkDirty fun(self: ObjectiveTrackerModuleTemplate)
---@field LayoutContents fun(self: ObjectiveTrackerModuleTemplate)
---@field OnBlockHeaderClick fun(self: ObjectiveTrackerModuleTemplate, block: AGFTrackerBlock, mouseButton: string)
---@field blockTemplate string
-- Blizzard_ObjectiveTrackerModule.lua:634: the block with this id plays its fanfare at the next layout.
---@field SetNeedsFanfare fun(self: ObjectiveTrackerModuleTemplate, key: string)

-- Blizzard_SharedXML/Mainline/SoundKitConstants.lua:125 (UI_SCENARIO_STAGE_END = 31757), and the character
-- frame's open, close and tab sounds the Adventure Guide window plays (839, 840, 841).
---@type {UI_SCENARIO_STAGE_END: integer, IG_ABILITY_PAGE_TURN: integer, IG_CHARACTER_INFO_OPEN: integer, IG_CHARACTER_INFO_CLOSE: integer, IG_CHARACTER_INFO_TAB: integer}
SOUNDKIT = nil

-- Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.lua: a frame's PanelTabButtonTemplate tabs, anchored in a row
-- after the first, and the selected one (disabled, as the stock tabs show it).
---@param frame Frame
---@param numTabs integer
function PanelTemplates_SetNumTabs(frame, numTabs) end

---@param frame Frame
---@param id integer
function PanelTemplates_SetTab(frame, id) end

-- Blizzard_UIParent/UIParent.lua: names of the frames Escape closes.
---@type string[]
UISpecialFrames = nil

---@type ForeverNativeTrackerFrame
ObjectiveTrackerFrame = nil

-- AGF's own named frames (CreateFrame names in Panel.lua and Tracker.lua); nil until they are built.
---@type Frame?
AdventureGuideForeverPanel = nil
---@type AGFTabButton?
AdventureGuideForeverTab = nil
---@type AGFTabButton?
AdventureGuideForeverQuestsTab = nil
---@type AGFTrackerModule?
AdventureGuideForeverObjectiveTracker = nil

-- Forever's skill lines (probe R5, 1.60.1): the global GetNumSkillLines and GetSkillLineInfo are missing; these
-- answer for the lines the character has, and GetSkillLineInfoByID is nil for an unlearned one.
---@class AGFSkillLineInfo
---@field skillID integer SkillLine ID
---@field name string
---@field rank integer
---@field maxRank integer
---@field skillLineCategoryID integer
---@field isHeader boolean

C_SkillInfo = {}

---@return integer
function C_SkillInfo.GetNumSkillLines() end

---@param index integer
---@return AGFSkillLineInfo?
function C_SkillInfo.GetSkillLineInfo(index) end

---@param skillLineID integer
---@return AGFSkillLineInfo?
function C_SkillInfo.GetSkillLineInfoByID(skillLineID) end
-- Blizzard_SharedXMLGame/Tooltip/TooltipDataHandler.lua:199 (Forever 1.60.1): a callback after a tooltip of this
-- Enum.TooltipDataType has drawn its lines, before it shows; an insecure one runs insecure.
---@type {AddTooltipPostCall: fun(tooltipType: Enum.TooltipDataType, func: fun(tooltip: GameTooltip, tooltipData: TooltipData))}
TooltipDataProcessor = nil

-- Camelot's PvP rank track (Blizzard_UIPanels_Game/Camelot/PVPRankFrame.lua): major faction 2800's progression, which
-- Ketho's Core annotations lack. Unconfirmed by a probe, so PvP.lua reads it with a nil check.
---@class AGFMajorFactionProgressionInfo
---@field renownLevel integer the rank, 0 unranked
---@field renownReputationEarned integer points toward the next rank
---@field renownLevelThreshold integer
---@field maxLevel integer the season's highest rank

---@param majorFactionID integer
---@return AGFMajorFactionProgressionInfo?
function C_MajorFactions.GetMajorFactionProgressionInfo(majorFactionID) end

---@type AGFWindowFrame?
AdventureGuideForeverWindow = nil

---@class AGFTopTab : Button
---@field Text FontString
---@field HandleRotation fun(self: AGFTopTab)
---@field SetTabSelected fun(self: AGFTopTab, selected: boolean)

---@class AGFCollapseButton : Button
---@field Icon Texture
---@field UpdateCollapsedState fun(self: AGFCollapseButton, collapsed: boolean)

---@class AGFMapPing : AGFMapPinMixin
---@field SetNumLoops fun(self: AGFMapPing, loops: integer)
---@field PlayAt fun(self: AGFMapPing, x: number, y: number)

---@type table<integer, {r: number, g: number, b: number}>
ITEM_QUALITY_COLORS = nil
