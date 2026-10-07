---@meta

---@class AGFRXPElement
---@field questId? integer
---@field tag? string
---@field text? string
---@field tooltipText? string
---@field rawtext? string
---@field hideTooltip? boolean
---@field hidden? boolean
---@field textOnly? boolean
---@field optional? boolean
---@field completed? boolean
---@field skip? boolean
---@field OnComplete? fun(element: AGFRXPElement)
---@field arrow? boolean this element has a navigation arrow marker
---@field zone? integer uiMapID for the element's waypoint
---@field x? number x coordinate as a percentage (0-100)
---@field y? number y coordinate as a percentage (0-100)
---@field generated? integer non-zero when auto-generated; 0 or nil for a real waypoint
---@field parent? {completed?: boolean, skip?: boolean}
---@field step? AGFRXPStep the step this element belongs to

---@class AGFRXPStep
---@field index integer
---@field title? string
---@field sticky? boolean
---@field hidewindow? boolean
---@field hidetip? boolean
---@field active? boolean
---@field elements AGFRXPElement[]

---@class AGFRXPGuide
---@field lowPrio? string
---@field name string
---@field group string
---@field empty? boolean
---@field chapter? boolean
---@field OnClick? function
---@field steps AGFRXPStep[]

---@class AGFRXPWindow : Frame
---@field savePosition? boolean

---@class AGFRXPCurrentStepFrame : Frame
---@field UpdateText fun()

---@class AGFRXPFrame : AGFRXPWindow
---@field activeSteps AGFRXPStep[]
---@field CurrentStepFrame? AGFRXPCurrentStepFrame

---@class AGFRXPEngine
---@field activeItemFrame? AGFRXPWindow
---@field UpdateItemFrame? function
---@field ResetItemPosition? function
---@field targeting? {activeTargetFrame?: AGFRXPWindow, UpdateTargetFrame?: function}
---@field RXPFrame AGFRXPFrame
---@field currentGuide? AGFRXPGuide
---@field GetGuideProgress fun(): integer, string?
---@field SetStep fun(index: integer)
---@field GetGuideTable fun(group: string, name: string): AGFRXPGuide?
---@field IsGuideActive fun(guide: AGFRXPGuide): boolean
---@field LoadGuideTable fun(self: AGFRXPEngine, group: string, name: string)
---@field DisplayLines? function
---@field UpdateMap fun(resetPins?: boolean)
---@field UpdateGotoSteps? fun()
---@field updateSteps? boolean
---@field RenderFrame? function
---@field RegisterMessage? fun(receiver: table, message: string, callback: function)
---@field locale? {Get: fun(text: string): string}
---@field ReplaceNpcIds? fun(text: string, element?: AGFRXPElement): string
---@field guideList? table<string, {names_: {name: string, group: string}[]}>
---@field guideImporter? {Open: fun(self: table), importCoroutine?: thread, importBufferSize?: integer}
---@field settings? {profile: {showEnabled?: boolean, hideGuideWindow?: boolean}, OpenSettings: fun()}
---@field v2? {state?: {guideWindow?: {frame: AGFRXPWindow}}, UpdateGuideWindow?: fun(self: table)}
---@field arrowFrame? {element?: AGFRXPElement, wrongContinent?: boolean}
---@field activeWaypoints? table[]
---@field hideArrow? boolean

---@type AGFRXPEngine?
RXP = nil
---@type {stepSkip: table<integer, boolean>}
RXPCData = nil

---@class AGFRXPInstruction
---@field questId? integer
---@field tag? string
---@field text string
---@field done boolean
---@field elementIndex? integer

---@class AGFRXPDisplayStep
---@field index integer
---@field title string
---@field sticky boolean
---@field preview boolean true for a read-only future guide row
---@field lines AGFRXPInstruction[]
---@field map integer uiMapID; 0 when no real waypoint is known
---@field x number normalized 0-1; 0 when unknown
---@field y number normalized 0-1; 0 when unknown

---@class AGFRXPSnapshot
---@field name string
---@field group string
---@field index integer
---@field total integer
---@field steps AGFRXPDisplayStep[]

---@class AGFRestedXPAdapter
---@field Enabled fun(): boolean
---@field Active fun(): boolean
---@field Snapshot fun(): AGFRXPSnapshot
---@field OnChange fun(callback: fun())
---@field Refresh fun()
---@field Cards fun(current?: AGFJourney): AGFJourney[]
---@field Choose fun(group: string, name: string, start?: boolean)
---@field Guides fun(): {group: string, name: string}[]
---@field Select fun(group: string, name: string): boolean
---@field Move fun(delta: integer): boolean
---@field Skip fun(index: integer, elementIndex?: integer): boolean
---@field OpenImport fun(): boolean
---@field OpenSettings fun(): boolean
---@field UseOriginal fun()
---@field Journey fun(): AGFJourney?
---@field SkipKey fun(key: string): boolean

---@class AGFNamespace
---@field RestedXP AGFRestedXPAdapter

---@type AGFRXPWindow?
LibDBIcon10_RXPGuides = nil

---@class AGFRXPMapLine : Frame
---@field lineData? {element?: AGFRXPElement}

---@class AGFRXPPinsLibrary
---@field RemoveAllWorldMapIcons fun(self: AGFRXPPinsLibrary, owner: table)
---@field RemoveAllMinimapIcons fun(self: AGFRXPPinsLibrary, owner: table)
---@field AddMinimapIconMap fun(self: AGFRXPPinsLibrary, owner: table, icon: Frame, map: integer, x: number, y: number, showInParentZone?: boolean, floatOnEdge?: boolean)

---@class AGFRXPLibStub
---@field GetLibrary fun(self: AGFRXPLibStub, name: "HereBeDragons-Pins-2.0", silent?: boolean): AGFRXPPinsLibrary?

---@type AGFRXPLibStub?
LibStub = nil
