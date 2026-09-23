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
---@field detail string grey second line, e.g. "2 quests · 3 min walk · continues chain"
---@field reason string short why, e.g. "continues chain"
---@field quests integer[] quest IDs this step covers
---@field map integer
---@field x number
---@field y number
---@field place? string NPC/object or area name
---@field seconds? number travel time from the previous step, when known
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
---@field minutes? integer rough total, when travel times are known

-- Travel time between two points in seconds, or nil when unknown. Supplied by Integrations.
---@alias AGFTravel fun(fromMap: integer, fromX: number, fromY: number, toMap: integer, toX: number, toY: number): number?

---@class AGFModel
---@field MAX_STEPS integer
---@field IsGray fun(questLevel: integer, playerLevel: integer): boolean
---@field Eligible fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>, questID: integer): boolean
---@field Givers fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>, mapID: integer): AGFGiver[]
---@field Zones fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>): AGFZoneChoice[]
---@field Plan fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>, prefs: AGFPrefs, travel?: AGFTravel): AGFRoute

---@class AGFState
---@field Player fun(): AGFPlayer
---@field Completed fun(): table<integer, boolean>
---@field Log fun(): table<integer, AGFLogQuest>
---@field OnChange fun(callback: fun())
---@field Ready fun(): boolean completion data has loaded

---@class AGFIntegrations
---@field Travel fun(): AGFTravel? Shortest Path's estimate when it is loaded
---@field Navigate fun(step: AGFStep|AGFGiver) route there with Shortest Path, else the native waypoint
---@field Cancel fun()
---@field Guiding fun(): boolean Shortest Path is walking our multi-stop route and draws its own numbered stops
---@field Provider fun(): string? name of the addon navigating, for copy ("Shortest Path")

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
