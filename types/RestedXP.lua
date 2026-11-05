---@meta

---@class AGFRXPElementFrame : Frame
---@field button? Button RestedXP's skip checkbox for the element

---@class AGFRXPElement
---@field questId? integer
---@field tag? string the RestedXP function that made it: accept, turnin, complete, collect, fly, hs...
---@field id? integer|string a collect element's item
---@field targets? string[] friendly names this element talks to
---@field mobs? string[] enemies this element kills
---@field unitscan? string[] enemies this element scans for
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
---@field frame? AGFRXPElementFrame RestedXP's own element frame, while it has one bound
---@field event? string|string[] the client events RestedXP completes this element on, when not its tag's

---@class AGFRXPStep
---@field index integer
---@field title? string
---@field sticky? boolean
---@field hidewindow? boolean
---@field hidetip? boolean
---@field active? boolean
---@field completed? boolean RXP passes over a completed step when the guide reaches it
---@field elements AGFRXPElement[]
---@field activeItems? table<integer, string|boolean> the items this step uses, by ID

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

-- RXP's navigation arrow: a window like the rest, carrying the element it points at.
---@class AGFRXPArrowFrame : AGFRXPWindow
---@field element? AGFRXPElement
---@field wrongContinent? boolean

---@class AGFRXPCurrentStepFrame : Frame
---@field UpdateText fun()

---@class AGFRXPFrame : AGFRXPWindow
---@field activeSteps AGFRXPStep[]
---@field CurrentStepFrame? AGFRXPCurrentStepFrame

---@class AGFRXPEngine
---@field guideTextColors? table<string, string|table<string, string>> each text role's colour (RXP_ENEMY_ and so on) and `default`
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
---@field ResetArrowPosition? fun()
---@field updateSteps? boolean
---@field RenderFrame? function
---@field RegisterMessage? fun(receiver: table, message: string, callback: function)
---@field functions? table<string, any> RestedXP's element callbacks, and `events`, the client events each tag reads
---@field Call? fun(label: string?, callback: function, ...: any): any RestedXP's error-isolating callback runner
---@field locale? {Get: fun(text: string): string}
---@field ReplaceNpcIds? fun(text: string, element?: AGFRXPElement): string
---@field guideList? table<string, {names_: {name: string, group: string}[]}>
---@field guideImporter? {Open: fun(self: table), importCoroutine?: thread, importBufferSize?: integer}
---@field settings? {profile: {showEnabled?: boolean, hideGuideWindow?: boolean}, OpenSettings: fun()}
---@field v2? {state?: {guideWindow?: {frame: AGFRXPWindow}}, UpdateGuideWindow?: fun(self: table)}
---@field arrowFrame? AGFRXPArrowFrame
---@field activeWaypoints? table[]
---@field hideArrow? boolean

---@type AGFRXPEngine?
RXP = nil
---@type {stepSkip: table<integer, boolean>}
RXPCData = nil

---@class AGFRXPItem
---@field id integer the item a step uses

---@class AGFRXPTarget
---@field name string the creature or NPC to target
---@field kind "target"|"mob"|"unitscan" how RestedXP names it: a talk target, a kill target or a scan

---@class AGFRXPInstruction
---@field questId? integer
---@field tag? string
---@field text string
---@field done boolean
---@field elementIndex? integer

---@class AGFRXPDisplayStep
---@field index integer
---@field title string
---@field titled boolean RestedXP gave the step a title of its own (else `title` is "Step N")
---@field target? string the NPC the step's open lines name first, else any line's
---@field targetOpen? boolean `target` comes from a line not yet done
---@field sticky boolean
---@field preview boolean true for a read-only future guide row
---@field lines AGFRXPInstruction[]
---@field items AGFRXPItem[] the step's usable items, by ID
---@field targets AGFRXPTarget[] the step's talk and kill targets
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
---@field Awaits fun(key?: string): boolean `key` is a guide's, guide mode is on and RestedXP has no guide loaded yet
---@field Snapshot fun(): AGFRXPSnapshot
---@field OnChange fun(callback: fun())
---@field Refresh fun()
---@field Cards fun(current?: AGFJourney): AGFJourney[]
---@field Choose fun(group: string, name: string, start?: boolean): boolean false when the engine refused the guide
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
