---@meta

-- The client passes this same table to each TOC file; no runtime import is available.

-- One bundled quest (Data/Quests.lua). Coordinates are uiMapID plus normalized 0-1 x/y.
---@class AGFPlace
---@field map integer uiMapID
---@field x number
---@field y number
---@field name string NPC or object name

---@class AGFQuest
---@field title string English title from the source data; the client's own title wins when cached
---@field level integer quest level (-1 scales to the player)
---@field min integer minimum level to accept
---@field side integer 1 Alliance, 2 Horde, 3 both
---@field races? integer race bitmask (nil = any)
---@field classes? integer class bitmask (nil = any)
---@field zone? integer uiMapID the quest is filed under
---@field start? AGFPlace where it is picked up (nil = item-started or unknown)
---@field finish? AGFPlace where it is handed in
---@field pre? integer[] all must be completed first
---@field preAny? integer[] one of these must be completed first
---@field group? integer exclusive group: completing one member closes the others
---@field next? integer the chain's follow-up
---@field repeatable? boolean
---@field dungeon? integer uiMapID of the instance when the objectives are inside one
---@field elite? boolean group quest

---@class AGFData
---@field build string client build the data was generated for
---@field source string where the data came from, for /agf audit
---@field quests table<integer, AGFQuest>
---@field zones table<integer, {name: string, min: integer, max: integer}> uiMapID -> zone name and level range
---@field maps table<integer, AGFMapCentre> uiMapID -> where the map sits in the world, for every map a place uses

-- Ranks steps on different maps without travel maths (Model.lua Cost). World coordinates are yards.
---@class AGFMapCentre
---@field continent integer the world map (instance) ID: 0 Eastern Kingdoms, 1 Kalimdor
---@field cx number world x of the map rectangle's centre
---@field cy number world y of the map rectangle's centre

-- What the live state tells the planner. Built by State.lua, consumed by Model.lua.
---@class AGFPlayer
---@field level integer
---@field side integer 1 Alliance, 2 Horde
---@field raceBit integer
---@field classBit integer
---@field map? integer current uiMapID
---@field x? number
---@field y? number

---@class AGFLogQuest
---@field id integer
---@field title string
---@field complete boolean ready to hand in
---@field level integer
---@field map? integer where to go next (objective area or turn-in), from C_QuestLog waypoints
---@field x? number
---@field y? number

---@class AGFPrefs
---@field quests boolean
---@field dungeons boolean
---@field legacy boolean
---@field professions boolean
---@field zone? integer uiMapID the player picked in "Where next?"; nil = best fit
---@field skipped table<string, boolean> step keys skipped this session
---@field pinned string[] step keys pinned, in order

---@alias AGFStepKind "turnin"|"pickup"|"objective"|"dungeon"

---@class AGFStep
---@field key string stable identity for pin/skip, e.g. "pickup:1519:0.46:0.52" or "turnin:4581"
---@field kind AGFStepKind
---@field title string e.g. "Turn in: Bathran's Hair" or "The Ruins of Stardust"
---@field detail string grey second line, e.g. "2 quests here"
---@field reason string short why, e.g. "continues chain"
---@field quests integer[] quest IDs this step covers
---@field map integer
---@field x number
---@field y number
---@field place? string NPC/object or area name
---@field optional? boolean elite/group or outside the player's level band
---@field pinned? boolean

-- A quest giver drawn as a "!" on the world map.
---@class AGFGiver
---@field map integer
---@field x number
---@field y number
---@field title string NPC or object name
---@field quests integer[] quest IDs it offers the player now, ascending

---@class AGFZoneChoice
---@field map integer
---@field name string
---@field min integer
---@field max integer
---@field quests integer eligible quests there
---@field best boolean

---@class AGFRoute
---@field steps AGFStep[] 3-5 steps, never more than MAX_STEPS
---@field zones AGFZoneChoice[] up to 3, best first
---@field zone? integer the zone the route was built for

---@class AGFModel
---@field MAX_STEPS integer
---@field IsGray fun(questLevel: integer, playerLevel: integer): boolean
---@field Eligible fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>, questID: integer): boolean
---@field Givers fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>, mapID: integer): AGFGiver[]
---@field Zones fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>): AGFZoneChoice[]
---@field Plan fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>, prefs: AGFPrefs): AGFRoute

---@class AGFState
---@field Player fun(): AGFPlayer
---@field Completed fun(): table<integer, boolean>
---@field Log fun(): table<integer, AGFLogQuest>
---@field OnChange fun(callback: fun())
---@field Ready fun(): boolean completion data has loaded

-- Shortest Path Forever's public API, mirrored field for field from its types/API.lua (SPFAPIStop, SPFPublicAPI) at
-- the sha tests/contract_spec.lua pins; that spec fails on any drift. Integrations.lua's REQUIRED lists exactly
-- the non-optional functions. Descriptions go after `--` so the type is the whole first token.
---@class AGFSPFStop
---@field map integer -- uiMapID
---@field x number -- normalized 0-1
---@field y number -- normalized 0-1
---@field title? string

---@class AGFSPFAPI
---@field version integer -- AGF accepts exactly 1
---@field Estimate fun(fromMap: integer, fromX: number, fromY: number, toMap: integer, toX: number, toY: number): number? -- seconds, nil when unknown or in combat
---@field Navigate fun(owner: string, map: integer, x: number, y: number, title?: string): boolean -- starts or replaces guidance
---@field NavigateRoute fun(owner: string, stops: AGFSPFStop[]): boolean -- 1-64 stops in order
---@field CurrentStop fun(owner: string): integer? -- nil unless owner owns the active journey
---@field Cancel fun(owner: string): boolean -- true only when this owner's journey was cancelled

---@class AGFIntegrations
---@field TravelLine fun(step: AGFStep): string? asks Shortest Path now: one estimate, nil without it
---@field RefreshTravel fun() refetches step 1's line; Core runs it in the frame after each rebuild
---@field Travel fun(step: AGFStep): string? the last line fetched for this step, without asking again
---@field OnTravelChange fun(callback: fun())
---@field Navigate fun(step: AGFStep|AGFGiver) route there with Shortest Path, else the native waypoint
---@field Cancel fun()
---@field Guiding fun(): boolean Shortest Path is walking our multi-stop route and draws its own numbered stops
---@field Provider fun(): string? name of the addon navigating, for copy ("Shortest Path")

-- One region in a layout dump (Dump.lua): plain data, so it survives SavedVariables and JSON.
---@class AGFDumpAnchor
---@field point string
---@field relativeTo? string path of the region it is anchored to
---@field relativePoint string
---@field x number
---@field y number

---@class AGFDumpEntry
---@field path string global name, or the parent's path and the key or type[index] under it
---@field type string object type
---@field anchors AGFDumpAnchor[]
---@field size? number[] width and height set explicitly (GetSize(true)); absent when neither was set
---@field atlas? string
---@field font? string font object name
---@field text? string
---@field onUpdate? boolean frames only: an OnUpdate script is set
---@field stockTemplate? string headless only: the stock template the harness frame stands in for

---@class AGFNamespace
---@field TITLE string
---@field Data AGFData
---@field Model AGFModel
---@field State AGFState
---@field Integrations AGFIntegrations
---@field Print fun(msg: string)
---@field Setting fun(key: string): any
---@field SetSetting fun(key: string, value: any)
---@field Prefs fun(): AGFPrefs
---@field Route fun(): AGFRoute the current route, rebuilt lazily when state or prefs change
---@field Invalidate fun() mark the route stale and notify views
---@field OnRouteChange fun(callback: fun())
---@field Skip fun(key: string)
---@field TogglePin fun(key: string)
---@field DumpLayout fun(root: Frame, describe?: fun(region: Region, entry: AGFDumpEntry)): AGFDumpEntry[]
---@field Dump fun() /agf dump: save the layout, route and frames in AdventureGuideForeverDB.dump
