---@meta

-- FrameXML surfaces absent from Ketho's pinned Core annotations, or fields our own code adds
-- to the namespace (Pins.lua, Panel.lua, Settings.lua). Signatures follow Gethe/wow-ui-source
-- forever @ (see tools/typecheck.sh for the pinned revision). These declarations never load in
-- the client.

-- Additive: merges with the fields already declared on AGFNamespace in types/Namespace.lua.
---@class AGFNamespace
---@field OpenPanel fun() set once the world map tab exists (Panel.lua); opens the guide tab.
---@field RegisterSettings fun() defined by Settings.lua, called once after ADDON_LOADED.
---@field OpenSettings? fun() set by RegisterSettings; opens our page under Settings > AddOns.
---@field Pins AGFPinsModule
---@field DEFAULTS table<string, boolean> account-wide setting defaults (Core.lua)

---@class AGFPinsModule
---@field Ping fun(key: string) flash the numbered pin for a step, if it's on the shown map.

---@type table<string, Frame>
DEFAULT_CHAT_FRAME = nil

---@type {ContinueOnAddOnLoaded: fun(name: string, callback: fun()), ContinueAfterAllEvents: fun(callback: fun(), ...: string)}
EventUtil = {}

---@type {RegisterCallback: fun(self: any, event: string, callback: fun(...), owner: any), TriggerEvent: fun(self: any, event: string, ...: any)}
EventRegistry = {}

---@type fun(region: Region, fadeInTime: number, fadeOutTime: number, flashDuration: number, showWhenDone: boolean)
UIFrameFlash = nil

---@type table<string, fun(msg: string, editBox: EditBox)>
SlashCmdList = nil

---@param uiMapID? integer
function ToggleWorldMap(uiMapID) end

---@param mapID? integer
function OpenQuestLog(mapID) end

-- Blizzard_Menu's root description, as handed to a DropdownButton's SetupMenu generator.
---@class AGFMenu
---@field CreateCheckbox fun(self: AGFMenu, text: string, isSelected: (fun(): boolean), setSelected: fun())
---@field CreateButton fun(self: AGFMenu, text: string, onClick: fun())

---@class AGFDropdown : Frame
---@field SetupMenu fun(self: AGFDropdown, generator: fun(owner: AGFDropdown, root: AGFMenu))

-- ScrollFrameTemplate: ScrollFrame_OnLoad attaches a MinimalScrollBar as ScrollBar.
---@class AGFScrollFrame : ScrollFrame
---@field ScrollBar Frame

---@class AGFSearchBox : EditBox
---@field Instructions FontString

---@class AGFInset : Frame
---@field Bg Texture

---@class AGFQuestContentFrame : Frame
---@field displayMode any

---@class AGFQuestMapFrame : Frame
---@field TabButtons AGFTabButton[]
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

-- Stock backdrop tables (Blizzard_SharedXML/Backdrop.lua); only the edge fields are read.
---@type {edgeFile: string, edgeSize: number}
BACKDROP_TUTORIAL_16_16 = nil
---@type {edgeFile: string, edgeSize: number}
BACKDROP_TOAST_12_12 = nil

---@class AGFMapProvider
---@field GetMap fun(self: AGFMapProvider): AGFWorldMapFrame
---@field OnAdded fun(self: AGFMapProvider, map: AGFWorldMapFrame)
---@field OnRemoved fun(self: AGFMapProvider, map: AGFWorldMapFrame)
---@field RefreshAllData fun(self: AGFMapProvider, fromOnShow?: boolean)
---@field RemoveAllData fun(self: AGFMapProvider)
---@type AGFMapProvider
MapCanvasDataProviderMixin = nil

---@class AGFMapPinMixin : Frame
---@field GetMap fun(self: AGFMapPinMixin): AGFWorldMapFrame
---@field OnLoad fun(self: AGFMapPinMixin)
---@field OnReleased fun(self: AGFMapPinMixin)
---@field UseFrameLevelType fun(self: AGFMapPinMixin, frameLevelType: string)
---@field SetPosition fun(self: AGFMapPinMixin, x: number, y: number)
---@field SetScalingLimits fun(self: AGFMapPinMixin, style: number, minScale: number, maxScale: number)
---@field ApplyCurrentScale fun(self: AGFMapPinMixin)
---@type AGFMapPinMixin
MapCanvasPinMixin = nil

---@class AGFWorldMapFrame : Frame
---@field SetMapID fun(self: AGFWorldMapFrame, mapID: integer)
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
function GameTooltip_Hide() end

---@class AGFUiMapPointFactory
---@field CreateFromCoordinates fun(uiMapID: integer, x: number, y: number, z?: number): UiMapPoint
---@type AGFUiMapPointFactory
UiMapPoint = nil

---@type {API: table?}? read only through Integrations.lua SPF(), which checks it against AGFSPFAPI
ShortestPathForever = nil

---@class AGFSettingsSetting
---@field SetValueChangedCallback fun(self: AGFSettingsSetting, callback: fun(setting: AGFSettingsSetting, value: boolean))
---@class AGFSettingsCategory
---@field GetID fun(self: AGFSettingsCategory): integer
---@class AGFSettingsModule
---@field VarType {Boolean: string}
---@field RegisterVerticalLayoutCategory fun(name: string): AGFSettingsCategory
---@field RegisterAddOnSetting fun(category: AGFSettingsCategory, variable: string, key: string, storage: table, variableType: string, name: string, default: boolean): AGFSettingsSetting
---@field CreateCheckbox fun(category: AGFSettingsCategory, setting: AGFSettingsSetting, tooltip?: string)
---@field RegisterAddOnCategory fun(category: AGFSettingsCategory)
---@field OpenToCategory fun(categoryID: integer)
---@type AGFSettingsModule
Settings = nil

---@class AGFCheckButton : CheckButton
---@field text FontString

---@class AGFTabButton : Button
---@field SetCustomOnMouseUpHandler fun(self: AGFTabButton, handler: fun(self: AGFTabButton, mouseButton: string, upInside: boolean))
---@field SetChecked fun(self: AGFTabButton, checked: boolean)
---@field Icon Texture
---@field activeAtlas? string
---@field inactiveAtlas? string
---@field tooltipText string

---@class AGFTrackerBlock
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

---@type {SetModuleContainer: fun(self: any, module: ObjectiveTrackerModuleTemplate, container: Frame), GetContainerForModule: fun(self: any, module: ObjectiveTrackerModuleTemplate): Frame?, AddContainer: fun(self: any, container: Frame)}
ObjectiveTrackerManager = nil
---@type Frame
ObjectiveTrackerFrame = nil

---@type {CreateContextMenu: fun(parent: Frame, initializer: fun(owner: any, root: any))}
MenuUtil = nil

-- AGF's own named frames (CreateFrame names in Panel.lua and Tracker.lua); nil until they are built.
---@type Frame?
AdventureGuideForeverPanel = nil
---@type AGFTabButton?
AdventureGuideForeverTab = nil
---@type AGFTabButton?
AdventureGuideForeverQuestsTab = nil
---@type AGFTrackerModule?
AdventureGuideForeverObjectiveTracker = nil
