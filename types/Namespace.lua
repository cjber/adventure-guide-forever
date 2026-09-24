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
---@field continents table<integer, AGFContinentShift> continent -> its place on the Azeroth world map
---@field crossings AGFCrossing[] every boat and zeppelin between two continents

-- Measures between steps on different maps without travel maths (Model.lua Cost). World coordinates are yards.
---@class AGFMapCentre
---@field name string the map's English name, the fallback when the client has none (C_Map.GetMapInfo)
---@field continent integer the world map (instance) ID: 0 Eastern Kingdoms, 1 Kalimdor
---@field cx number world x of the map rectangle's centre
---@field cy number world y of the map rectangle's centre
---@field sx number yards from the map's left edge to its right (map x 0 to 1)
---@field sy number yards from the map's top edge to its bottom (map y 0 to 1)

-- One continent on the Azeroth world map, in yards: x = shift x - world y, y = shift y - world x, so both continents
-- share one frame, oriented like a zone map.
---@class AGFContinentShift
---@field x number
---@field y number

-- One boat or zeppelin between continents (TaxiPathNode stops), so an ocean crossing is measured dock to dock.
---@class AGFCrossing
---@field transport integer the transport's gameobject entry
---@field side integer bitmask of the sides whose flight masters serve both docks: 1 Alliance, 2 Horde
---@field a AGFDock
---@field b AGFDock

---@class AGFDock
---@field continent integer world map (instance) ID
---@field x number world x, yards
---@field y number world y, yards

-- What the live state tells the planner. Built by State.lua, consumed by Model.lua.
---@class AGFPlayer
---@field level integer
---@field maxLevel integer the level cap
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
---@field journey? string key of the journey card the player chose; nil (or gone) = the first card
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
---@field chapter? string the story card's chapter line, on the step that takes the chain up

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

---@alias AGFJourneyKind "carry"|"story"|"nextzone"|"dungeon"

-- A quest's place in its chain (Model.Story): the data's `next` links from the chain's head. Later members are IDs
-- only, so no later chapter's title is ever drawn.
---@class AGFStory
---@field chapter integer this quest's place in the chain, from 1
---@field total? integer the chain's length, only when the data proves where it ends
---@field members integer[] the chain's quest IDs in order, the head first

-- One card in the guide (docs/design.md §2.2): only steps the player can take now.
---@class AGFJourney
---@field kind AGFJourneyKind
---@field key string stable identity for prefs.journey: "carry", "story:<uiMapID>" or "nextzone:<uiMapID>"
---@field title string e.g. "Finish what you carry" or "A Westfall story"
---@field subline string e.g. "3 ready to hand in, 1 in progress"
---@field reason? string why this journey, when there is an honest answer
---@field map integer where its first step is: choosing the card turns the world map there
---@field steps AGFStep[] never more than MAX_STEPS, in route order
---@field story? AGFStory the story card's chain, when the zone has one the player can take up now

---@class AGFRoute
---@field journeys AGFJourney[] at most 3: carry, the zone's story, the next zone
---@field journey? string the chosen journey's key
---@field steps AGFStep[] the chosen journey's steps, never more than MAX_STEPS
---@field zones AGFZoneChoice[] up to 3, best first
---@field zone? integer the zone the route was built for

-- One requirement in the why-not view (Model.Why).
---@class AGFWhyLine
---@field text string
---@field met boolean

-- The client's names for Model.Why; each returns nil when it has none, and the data's English is used.
---@class AGFWhyNames
---@field title? fun(questID: integer): string?
---@field race? fun(raceID: integer): string?
---@field class? fun(classID: integer): string?

---@class AGFModel
---@field MAX_STEPS integer
---@field IsGray fun(questLevel: integer, playerLevel: integer): boolean
---@field Eligible fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>, questID: integer): boolean
---@field Why fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>, questID: integer, names?: AGFWhyNames): AGFWhyLine[] every requirement, met or not; eligible exactly when all are met
---@field Givers fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>, mapID: integer): AGFGiver[]
---@field Story fun(data: AGFData, questID: integer): AGFStory? the chain the quest belongs to; nil when it is in none, or the way back forks
---@field Zones fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>): AGFZoneChoice[]
---@field Journeys fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>, prefs: AGFPrefs, mapName?: fun(map: integer): string?): AGFJourney[], AGFZoneChoice[], integer?
---@field Plan fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>, prefs: AGFPrefs, mapName?: fun(map: integer): string?): AGFRoute
---@field Refresh fun(data: AGFData, player: AGFPlayer, log: table<integer, AGFLogQuest>, prefs: AGFPrefs, last: AGFRoute, mapName?: fun(map: integer): string?): AGFRoute the cheap in-combat rebuild: the log's steps fresh, the rest from `last`

---@class AGFState
---@field Player fun(): AGFPlayer
---@field Completed fun(): table<integer, boolean>
---@field Log fun(): table<integer, AGFLogQuest>
---@field OnChange fun(callback: fun())
---@field Ready fun(): boolean completion data has loaded
---@field MapName fun(map: integer): string? the client's localised map name, nil when it has none

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
---@field Navigate fun(step: AGFStep|AGFGiver): boolean route there with Shortest Path, else (declined or absent) the native waypoint where the map allows one; true when something now guides
---@field Cancel fun()
---@field Guiding fun(): boolean Shortest Path is walking our multi-stop route and draws its own numbered stops
---@field Guided fun(): (AGFStep|AGFGiver)[] the stops it walks, while it guides; empty otherwise
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

---@class AGFStrings every line the player reads (ns.L); format strings keep their specifiers
---@field AUDIT_BUILD string format: data build, client version, client build
---@field AUDIT_COUNTS string format: bundled, eligible and completed counts
---@field AUDIT_NOT_READY string
---@field HELP_OPEN string
---@field HELP_AUDIT string
---@field HELP_DUMP string
---@field HAND_IN_WHEN string format: zone name; the reason on a turn-in the route leaves for another continent
---@field NO_WAYPOINT string the error Go shows when nothing can guide the player on the step's map
---@field SETTING_MAP_PINS_TOOLTIP string
---@field SETTING_GIVERS_TOOLTIP string
---@field SETTING_DUNGEONS_DEFAULT_TOOLTIP string
---@field JOURNEY_CARRY string
---@field JOURNEY_STORY string format: zone name
---@field JOURNEY_NEXT_ZONE string format: zone name, the level it fits
---@field CARRY_READY string format: count of finished quests whose hand-in is on this continent
---@field CARRY_IN_PROGRESS string format: count
---@field CARRY_AWAY string format: count of finished quests whose hand-in is across an ocean
---@field LIST_SEPARATOR string between the parts of one line
---@field QUESTS_NEAR string format: count
---@field QUESTS_NEAR_ONE string
---@field CHAPTER_OF string format: chapter, total
---@field CHAPTER string format: chapter; the chain's length unproven
---@field CONTINUES_STORY string
---@field BEGINS_STORY string
---@field NOTHING_NEARBY string the guide with no journey
---@field WHY_NO_START string the one line for a quest whose start the generator suppressed
---@field WHY_DONE string
---@field WHY_IN_LOG string
---@field WHY_REPEATABLE string
---@field WHY_ALLIANCE string
---@field WHY_HORDE string
---@field WHY_LEVEL string format: minimum level
---@field WHY_COMPLETED string format: the prerequisite's title
---@field WHY_ONE_OF string format: the titles, joined
---@field WHY_CHOSE string format: the exclusive sibling's title
---@field WHY_EARLIER_QUEST string a prerequisite the data has no title for
---@field WHY_RACES string format: race names, joined (the client's ITEM_RACES_ALLOWED)
---@field WHY_CLASSES string format: class names, joined (the client's ITEM_CLASSES_ALLOWED)
---@field LOADING string the guide before the completed quests arrive

---@class AGFNamespace
---@field TITLE string
---@field L AGFStrings
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
---@field PanelShown? fun(): boolean whether the guide is open, set once Blizzard_WorldMap has loaded
---@field Skip fun(key: string)
---@field TogglePin fun(key: string)
---@field DumpLayout fun(root: Frame, describe?: fun(region: Region, entry: AGFDumpEntry)): AGFDumpEntry[]
---@field Dump fun() /agf dump: save the layout, route and frames in AdventureGuideForeverDB.dump
