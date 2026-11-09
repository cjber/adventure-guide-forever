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
---@field DEFAULTS table<string, boolean|number|string> account-wide setting defaults (Core.lua)
---@field MinimapButton ForeverMinimapButtonAPI the shared minimap button module (Core/MinimapButton.lua)
---@field minimapButton? ForeverMinimapButton the shared module sets it when it creates the button (host)

---@class AGFPinsModule
---@field Ping fun(key: string) flash the numbered pin for a step, if it's on the shown map.

-- Gethe/wow-ui-source FrameXML: the party category that means an instance group.
---@type number
LE_PARTY_CATEGORY_INSTANCE = nil

---@type {AddMessage: fun(self: table, text: string)}
DEFAULT_CHAT_FRAME = nil

---@type {ContinueOnAddOnLoaded: fun(name: string, callback: fun()), ContinueAfterAllEvents: fun(callback: fun(), ...: string)}
EventUtil = {}

---@type {RegisterCallback: fun(self: any, event: string, callback: fun(...), owner: any), TriggerEvent: fun(self: any, event: string, ...: any)}
EventRegistry = {}

-- UI/Leaderboards.lua publishes the window every Forever addon registers into.
---@type ForeverLeaderboardsAPI?
ForeverLeaderboards = nil

---@class AGFClassColor
---@field GetRGB fun(self: AGFClassColor): number, number, number
---@type table<string, AGFClassColor>?
RAID_CLASS_COLORS = nil

---@class AGFScrollBoxConstants
---@field RetainScrollPosition integer
---@type AGFScrollBoxConstants
ScrollBoxConstants = nil

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

-- Blizzard_FrameXML Mainline/AlertFrames.lua:354: the alert container; a queued subsystem shows up to `maxAlerts` frames
-- of `template` at once, each filled by `setUp` with what AddAlert was given, and holds up to `maxQueue` more.
---@class AGFAlertSubSystem
---@field AddAlert fun(self: AGFAlertSubSystem, ...: any): boolean

---@class AGFAlertContainer : Frame
---@field AddQueuedAlertFrameSubSystem fun(self: AGFAlertContainer, template: string, setUp: fun(frame: any, ...: any), maxAlerts?: integer, maxQueue?: integer): AGFAlertSubSystem
---@type AGFAlertContainer?
AlertFrame = nil

-- Mainline/AlertFrameSystems.lua:429: the achievement toasts' subsystem, present once AchievementAlertFrameTemplate is.
---@type AGFAlertSubSystem?
AchievementAlertSystem = nil

-- Blizzard_AchievementUI/Blizzard_AchievementUI_Bootstrap.lua:1 loads the achievement UI on demand; the client's
-- alert frame calls it before queueing a toast (Mainline/AlertFrames.lua:544), since the template's Shield child
-- needs AchievementShield_OnLoad from that UI. Read with a nil check.
---@type (fun(): boolean)?
AchievementFrame_LoadUI = nil

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

-- Blizzard_WorldMap.lua:1329 (1.60.1.69913): the world map's own opener. It is plain Lua, so addons may call it,
-- unlike the restricted C_Map.OpenWorldMap (#411); the pinned annotations leave it out.
---@param mapID? integer
function OpenWorldMap(mapID) end

-- Blizzard_ObjectiveTracker/Blizzard_ObjectiveTrackerShared.lua:23: an objective line with no dash and no indent.
---@type integer
OBJECTIVE_DASH_STYLE_HIDE_AND_COLLAPSE = 3

-- GlobalStrings.lua: the red or grey marker a ranged item's button shows when it is out of range.
---@type string
RANGE_INDICATOR = nil

-- Blizzard_ObjectiveTracker/Blizzard_ObjectiveTrackerShared.lua: the tracker's line colours (an open line, the line
-- it points at, a done line).
---@type {Normal: ColorMixin, NormalHighlight: ColorMixin, Complete: ColorMixin}
OBJECTIVE_TRACKER_COLOR = nil

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

---@type {InitScrollBoxListWithScrollBar: fun(scrollBox: Frame, scrollBar: any, view: AGFScrollBoxLinearView)}
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

-- The generated FrameXML annotations are absent from this checker's pinned API checkout.
---@class WorldMapFrame : Frame
---@field ScrollContainer Frame
---@field GetMapID fun(self: WorldMapFrame): integer?
---@field GetCanvas fun(self: WorldMapFrame): Frame
---@field GetCanvasScale fun(self: WorldMapFrame): number?
---@field GetCanvasZoomPercent fun(self: WorldMapFrame): number?
---@field GetGlobalPinScale fun(self: WorldMapFrame): number?
---@field GetPinFrameLevelsManager? fun(self: WorldMapFrame): AGFMapFrameLevels
---@class AGFMapFrameLevels
---@field GetValidFrameLevel fun(self: AGFMapFrameLevels, levelType: string): number?
---@type WorldMapFrame
WorldMapFrame = nil

-- Blizzard's ping animation is reused with the shared private pin placement.
---@type {OnLoad: fun(self: ForeverCanvasPin)}
MapPinPingMixin = nil
---@type {GetCurrentStyle: fun(): number}?
C_InputInterfaceStyle = nil
---@type Frame
SoftCursor = nil
---@type table<string, fun(map: ForeverCanvasMap): {x: number, y: number, kind: string}[]>
ForeverMapMarkers = nil
---@param value number
---@return number
function Saturate(value) end
---@param a number
---@param b number
---@param t number
---@return number
function Lerp(a, b, t) end

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

-- The few calls Polestar.lua makes, each checked for before it is called (Polestar's docs/ARCHITECTURE.md, "Engine" and
-- "Message bus").
---@class AGFPolestarEngine
---@field GetGuide? fun(): {id?: string}? the active tab's guide, kept loaded after it is finished
---@field GetStepIndex? fun(): integer? the step shown; nil once the guide is finished

---@class AGFPolestarGlobal
---@field Engine? AGFPolestarEngine
---@field On? fun(message: string, fn: fun(...)): table
---@field Get? fun(path: string): any one of Polestar's settings by its dotted path (Closes.lua reads behavior.warnClosing)

---@type AGFPolestarGlobal?
Polestar = nil

-- Naowh's Journeys (NaowhForever_Utilities, Journeys/Pins.lua): it turns a new native waypoint that is not its own
-- into a journey. Integrations.lua reads these members at the point of use, each checked before it is called.
---@class AGFNaowhJourneySettings
---@field Get fun(key: string): any? one of the module's options by name; "mapPins" is true while map pins become journeys

---@class AGFNaowhJourneyGuide
---@field Destination fun(): integer?, number?, number? the running journey's last stop: map, x and y in percent (0-100); nothing when no journey runs

---@class AGFNaowhJourneys
---@field On fun(): boolean? true while the module is enabled
---@field Settings AGFNaowhJourneySettings
---@field Guide AGFNaowhJourneyGuide

---@class AGFNaowhGlobal
---@field Journeys? AGFNaowhJourneys

---@type AGFNaowhGlobal?
NaowhForever = nil

-- Party.lua: the client's home group category (Enum-era clients define it as 1) and its "Unknown" name for a unit not
-- loaded yet; both read only, and checked against nil.
---@type integer?
LE_PARTY_CATEGORY_HOME = nil
---@type string?
UNKNOWNOBJECT = nil

---@class AGFSettingsSetting
---@field SetValueChangedCallback fun(self: AGFSettingsSetting, callback: fun(setting: AGFSettingsSetting, value: boolean|number))
-- A checkbox's row (Blizzard_Settings_Shared SettingsListElementInitializer); a child is greyed while predicate is false.
---@class AGFControlTextContainer
---@field Add fun(self: AGFControlTextContainer, value: string, text: string)
---@field GetData fun(self: AGFControlTextContainer): table[]
---@class AGFSettingsInitializer
---@field Indent fun(self: AGFSettingsInitializer)
---@field AddEvaluateStateCVar fun(self: AGFSettingsInitializer, variable: string)
---@field AddModifyPredicate fun(self: AGFSettingsInitializer, predicate: fun(): boolean)
---@class AGFSettingsCategory
---@field GetID fun(self: AGFSettingsCategory): integer
---@class AGFSliderOptions
---@field SetLabelFormatter fun(self: AGFSliderOptions, label: integer, formatter: fun(value: number): string)
---@type {Label: {Right: integer}}
MinimalSliderWithSteppersMixin = nil

---@class AGFSettingsModule
---@field VarType {Boolean: string, Number: string, String: string}
---@field RegisterVerticalLayoutCategory fun(name: string): AGFSettingsCategory
---@field RegisterVerticalLayoutSubcategory fun(category: table, name: string): AGFSettingsCategory
---@field RegisterCanvasLayoutSubcategory fun(category: table, frame: Frame, name: string): AGFSettingsCategory
---@field RegisterAddOnSetting fun(category: AGFSettingsCategory, variable: string, key: string, storage: table, variableType: string, name: string, default: boolean|number|string): AGFSettingsSetting
---@field RegisterProxySetting fun(category: AGFSettingsCategory, variable: string, variableType: string, name: string, default: boolean, getter: (fun(): boolean), setter: (fun(value: boolean))): AGFSettingsSetting
---@field NotifyUpdate fun(variable: string)
---@field CreateSliderOptions fun(minimum: number, maximum: number, step: number): AGFSliderOptions
---@field CreateSliderInitializer fun(setting: AGFSettingsSetting, options: AGFSliderOptions, tooltip?: string): AGFSettingsInitializer
---@field CreateCheckboxInitializer fun(setting: AGFSettingsSetting, options?: table, tooltip?: string): AGFSettingsInitializer
---@field CreateCheckbox fun(category: table, setting: AGFSettingsSetting, tooltip?: string)
---@field CreateControlTextContainer fun(): AGFControlTextContainer
---@field CreateDropdownInitializer fun(setting: AGFSettingsSetting, getData: fun(): table[]): AGFSettingsInitializer
---@field CreateElementInitializer fun(template: string, data?: table): AGFSettingsInitializer
---@field RegisterInitializer fun(category: AGFSettingsCategory, initializer: AGFSettingsInitializer) inserts the row from Blizzard's secure delegate
---@field RegisterAddOnCategory fun(category: AGFSettingsCategory)
---@field RegisterCanvasLayoutCategory fun(frame: Frame, name: string): AGFSettingsCategory
---@field OpenToCategory fun(categoryID: integer)
---@type AGFSettingsModule
Settings = nil

-- Blizzard_Settings_Shared.lua: the index page's button; addSearchTags false keeps it out of the settings search.
---@type fun(name: string, buttonText: string, buttonClick: fun(), tooltip?: string, addSearchTags?: boolean): AGFSettingsInitializer
CreateSettingsButtonInitializer = nil

-- The client's input-device switch (Blizzard_SharedXMLGame InputUtil.lua), read by UI/ForeverFamily.lua.
---@class AGFInputUtil
---@field IsGamepadUIEnabled fun(): boolean
---@type AGFInputUtil?
InputUtil = nil

---@class AGFTabButton : Button
---@field SetCustomOnMouseUpHandler fun(self: AGFTabButton, handler: fun(self: AGFTabButton, mouseButton: string, upInside: boolean))
---@field SetChecked fun(self: AGFTabButton, checked: boolean)
---@field Icon Texture
---@field activeAtlas? string
---@field inactiveAtlas? string
---@field tooltipText string

---@class AGFTrackerBlock : Frame
---@field HeaderButton? Button
---@field id string
-- Blizzard_ObjectiveTrackerBlock.lua: the height the block's header and lines take once laid out.
---@field height number
---@field SetHeader fun(self: AGFTrackerBlock, text: string)
---@field AddObjective fun(self: AGFTrackerBlock, index: integer|string, text: string, ...: any)
-- The stock ObjectiveTrackerProgressBarTemplate under the line added last.
---@field AddProgressBar fun(self: AGFTrackerBlock, id: string): {SetPercent: fun(self: table, percent: number)}?

---@class ObjectiveTrackerModuleTemplate : Frame
---@field uiOrder number
---@field SetHeader fun(self: ObjectiveTrackerModuleTemplate, text: string)
---@field GetBlock fun(self: ObjectiveTrackerModuleTemplate, id: string): AGFTrackerBlock
---@field GetContextMenuParent fun(self: ObjectiveTrackerModuleTemplate): Frame
---@field LayoutBlock fun(self: ObjectiveTrackerModuleTemplate, block: AGFTrackerBlock): boolean
---@field MarkDirty fun(self: ObjectiveTrackerModuleTemplate)
---@field LayoutContents fun(self: ObjectiveTrackerModuleTemplate)
---@field UpdateHeight fun(self: ObjectiveTrackerModuleTemplate)
---@field OnBlockHeaderClick fun(self: ObjectiveTrackerModuleTemplate, block: AGFTrackerBlock, mouseButton: string)
---@field blockTemplate string
-- Blizzard_ObjectiveTrackerModule.lua: set by SetCollapsed, which hides the module's contents under its header.
---@field isCollapsed? boolean
-- Blizzard_ObjectiveTrackerModule.lua: the room the tracker gave the module, what its blocks take so far, and the
-- offset the next block hangs at (CanFitBlock compares them).
---@field availableHeight number
---@field contentsHeight number
---@field GetNextBlockAnchoring fun(self: ObjectiveTrackerModuleTemplate): (Region?, number)
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

---@class AGFTopTab : Button
---@field Text FontString
---@field HandleRotation fun(self: AGFTopTab)
---@field SetTabSelected fun(self: AGFTopTab, selected: boolean)

---@class AGFCollapseButton : Button
---@field Icon Texture
---@field UpdateCollapsedState fun(self: AGFCollapseButton, collapsed: boolean)

---@type table<integer, {r: number, g: number, b: number, color: ColorMixin}>
ITEM_QUALITY_COLORS = nil

-- The saved table a consumer hands the shared minimap button: the angle and the hide flag live in it.
---@class ForeverMinimapButtonSpec
---@field name string the frame name, unique in the addon
---@field icon string|number the addon's own content icon
---@field title string the tooltip title
---@field binding? string shown under the title, e.g. "Shift-F"
---@field subtext? string the tooltip's one line about what a click does
---@field onClick? fun(button: Frame, mouseButton: string) what a left click runs
---@field settings? table the saved table holding the angle and hide flag
---@field angleKey? string the settings key holding the angle, default "minimapButtonAngle"
---@field hiddenKey? string the settings key whose true value hides the button, default "minimapButtonHidden"
---@field getShown? fun(): boolean an addon-owned visibility rule, which wins over the hide flag
---@field host? table receives the frame as its minimapButton

-- The registry every vendored copy of Core/MinimapButton.lua shares, published by the first to load.
---@class ForeverMinimapButtonRegistry
---@field buttons ForeverMinimapButton[] every addon button, in creation order
---@type ForeverMinimapButtonRegistry?
ForeverMinimapButtons = nil

-- The frame Core/MinimapButton.lua builds: the client's minimap plate, the addon's icon and the angle on the rim.
---@class ForeverMinimapButton : Button
---@field minimapButtonSpec ForeverMinimapButtonSpec the spec the consumer passed to Create
---@field icon Texture the addon's icon drawn on the plate
---@field angle number the angle around the Minimap, in degrees
---@field dragging boolean? true while the player drags the button around the rim

---@class ForeverMinimapButtonAPI
---@field Create fun(spec: ForeverMinimapButtonSpec): ForeverMinimapButton?
---@field Destroy fun(button: ForeverMinimapButton?)
---@field Refresh fun()
---@field SetShown fun(button: ForeverMinimapButton?, shown: boolean)

-- The client nameplate's child UnitFrame (Blizzard_NamePlateUnitFrame.lua): a CompactUnitFrame whose healthBar is
-- the name-and-health area UI/NpcHighlight.lua centres the quest giver's arrows on.
---@class AGFNamePlateUnitFrame : Button
---@field healthBar Frame? the nameplate's health bar

-- The quest giver window's reward display (Blizzard_UIPanels_Game QuestInfo.xml), read by UI/Upgrades.lua.
---@class AGFQuestRewardButton : Button
---@field type string? "choice" or "reward"
---@field Icon Texture

---@class AGFQuestInfoRewardsFrame : Frame
---@field RewardButtons AGFQuestRewardButton[]
---@type AGFQuestInfoRewardsFrame
QuestInfoRewardsFrame = nil

---@class AGFQuestInfoFrame : Frame
---@field questLog boolean? true while the quest log, not a giver, shows the quest
---@type AGFQuestInfoFrame
QuestInfoFrame = nil

-- QuestInfo.lua's templates for a giver's detail and reward panels.
---@type table
QUEST_TEMPLATE_DETAIL = nil
---@type table
QUEST_TEMPLATE_REWARD = nil

---@param template table
---@param parentFrame Frame
---@param acceptButton Button?
---@param material string?
---@param mapView boolean?
function QuestInfo_Display(template, parentFrame, acceptButton, material, mapView) end
