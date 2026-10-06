---@meta

-- The client passes this same table to each TOC file; no runtime import is available.

-- A quest giver or destination: uiMapID plus normalized 0-1 x/y coordinates.
---@class AGFPlace
---@field map integer uiMapID
---@field x number
---@field y number
---@field name string NPC or object name
---@field hub? string the town it stands in, as "map:area"; nil on a map the data doesn't place

-- One named area of a zone map: a WorldMapOverlay's rectangle on the map, the area the world map reveals as you
-- explore and the town a place inside it stands in (tools/gen_quests.py `town_areas`, Data/Geometry.lua `towns`).
---@class AGFTownArea
---@field area integer its AreaTable ID, keyed in AGFData.areaNames for its English name
---@field x0 number left edge on the map, 0-1
---@field y0 number top edge
---@field x1 number right edge
---@field y1 number bottom edge
---@field cx number the overlay's hit rectangle centre (its texture's when it has none), for which is nearer only
---@field cy number

---@class AGFQuestieTowns
---@field Build fun(data: AGFData, places: AGFPlace[], yield: fun()): table<string, {name: string}>
---@field Hub fun(data: AGFData, place: {map: integer, x: number, y: number}): string?
---@field Name fun(data: AGFData, place: {map: integer, hub: string}): string the town's area name, else the map's name

-- What a trainer or battlemaster does (Data/Geometry.lua `roles`); AGFNpc adds its side and place at runtime.
---@class AGFRole
---@field class? integer class trainer: the class ID it trains (1 Warrior ... 11 Druid)
---@field upto? integer class trainer: the highest level among the spells it teaches (6 for a starting-area trainer)
---@field from? integer class trainer: the lowest level among them, when above 1 (a mage's portal trainer's 20)
---@field pet? boolean hunter pet trainer
---@field riding? boolean riding trainer
---@field race? integer riding trainer: the race ID it teaches (CMaNGOS TrainerRace), when it names one
---@field skill? integer profession trainer: its skill line ID
---@field ranks? integer[] profession trainer: each rank it teaches, ascending, 1 Apprentice to 4 Artisan (SpellEffect SKILL_STEP)
---@field bg? integer battlemaster: its battleground (CMaNGOS battlemaster_entry.bg_template: 1 AV, 2 WSG, 3 AB)

---@class AGFQuest
---@field provider? boolean QuestieDB quest; live Questie policy decides pickup availability
---@field kinds? table<integer, string> objective slot type
---@field title string English title from the source data; the client's own title wins when cached
---@field level integer quest level (-1 scales to the player)
---@field min integer minimum level to accept
---@field max? integer maximum level to accept
---@field side integer 1 Alliance, 2 Horde, 3 both
---@field races? integer race bitmask (nil = any)
---@field classes? integer class bitmask (nil = any)
---@field zone? integer uiMapID the quest is filed under
---@field start? AGFPlace where it is picked up (nil = item-started or unknown)
---@field finish? AGFPlace where it is handed in
---@field pre? integer[] all must be completed first
---@field preAny? integer[] one of these must be completed first
---@field group? integer exclusive group: completing one member closes the others
---@field breadcrumb? integer the quest this breadcrumb leads to: open only while that is neither done nor in the log
---@field next? integer the chain's follow-up
---@field repeatable? boolean
---@field dungeon? integer instance Map.ID (not a uiMapID) when the quest is filed under a dungeon or raid
---@field raid? boolean a raid's quest: its instance is a raid, or it is typed Raid wherever it is filed
---@field elite? boolean group quest
---@field xp? integer the XP it gives a player at most 5 levels above it (Quest::XPValue); only with a start
---@field need? table<integer, integer> objective slot -> required count (0 means unknown until logged): 0-3 kill or use, 4-7 collect, 16 explore;
--- every objective, placed in obj or not; never for a dungeon quest
---@field obj? AGFObjectiveArea[] where the objectives are done, at most 3 each; never for a dungeon quest; with need
---@field objectivesUnknown? boolean provider has objectives that cannot be planned
---@field flags? AGFQuestFlags

--- Where one objective is done: Blizzard's quest POI shape, else a group of its spawns (tools/gen_quests.py).
---@class AGFObjectiveArea
---@field [1] integer the objective's slot, a key of the quest's need
---@field [2] integer map x in thousandths
---@field [3] integer map y in thousandths
---@field [4] integer yards from x, y holding 80% of the shape's points or the group's spawns
---@field [5] integer? the uiMapID x, y are on when it is not the quest's zone

---@class AGFQuestFlags
---@field event? true a script completes it: an escort, a spell cast or a summoned fight
---@field timed? integer the seconds it allows

---@class AGFData
---@field build string client build the data was generated for
---@field source string where the data came from, for /agf audit
---@field quests table<integer, AGFQuest>
---@field zones table<integer, {name: string, min: integer, max: integer}> uiMapID -> zone name and level range
---@field instances table<integer, AGFInstance> instance Map.ID -> its English name and whether it is a raid, for each quest's `dungeon` and each supported dungeon entrance
---@field maps table<integer, AGFMapCentre> uiMapID -> where the map sits in the world, for every map a place uses
---@field continents table<integer, AGFContinentShift> continent -> its place on the Azeroth world map
---@field crossings AGFCrossing[] every boat and zeppelin between two continents
---@field hubs table<string, {name: string}> hub ("map:area") -> its town's name. Composed from QuestieDB's quest places (QuestieTowns.lua)
---@field towns table<integer, AGFTownArea[]> zone uiMapID -> its named areas, the areas the world map reveals as you explore
---@field areaNames table<integer, string> AreaTable ID -> its English name, the fallback when the client has none
---@field roles table<integer, AGFRole> creature entry -> what that trainer or battlemaster does

-- Measures between steps on different maps without travel maths (Travel.lua Cost). World coordinates are yards.
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

-- What the live state tells the planner. Built by State.lua, consumed by the planner.
---@class AGFPlayer
---@field questAvailable? fun(id: integer): boolean
---@field level integer
---@field maxQuestLevelOffset? integer highest recommended quest level relative to the player; defaults to +2
---@field maxLevel integer the level cap
---@field logMax? integer the quests the log may hold (C_QuestLog.GetMaxNumQuestsCanAccept); no limit when nil
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
---@field map? integer where to go next, from C_QuestLog.GetNextWaypoint: the live client gives one only once finished
---@field x? number
---@field y? number
---@field objectives? AGFLogObjective[] the client's objectives, in its order (C_QuestLog.GetQuestObjectives)
---@field poi? {map: integer, x: number, y: number} the client's point for the quest (C_QuestLog.GetQuestsOnMap)

-- One objective of a logged quest as the client counts it.
---@class AGFLogObjective
---@field type string "monster", "object", "item", "event", or another kind the data has no slot for
---@field text string the client's words for it with its count, e.g. "Redridge Gnoll slain: 3/10"; may be empty
---@field done boolean
---@field have integer
---@field need integer

-- The composed QuestieDB catalogue kept in the per-character save between logins (QuestieSource.lua). `key` names
-- the inputs that built it, and the three tables are ns.Data's own, saved under it.
---@class AGFCatalogue
---@field key string
---@field quests table<integer, AGFQuest>
---@field hubs table<string, {name: string}>
---@field npcs table<integer, AGFNpc>

---@class AGFPrefs
---@field plannedDungeons table<integer, boolean>
---@field quests boolean
---@field dungeons boolean
---@field catalogue? AGFCatalogue the composed catalogue the last login built, reused when every input matches
---@field optimisedRoute? boolean the account-wide planned (beta) route order; nil/false is the nearest-action order
---@field journey? string key of the journey card the player chose; nil (or gone) = none chosen, the first card drawn
---@field previewGroups table<string, boolean> the overview headers this character collapsed, by group key; a group with no entry uses its default
---@field skipped table<string, boolean> step keys skipped this session
---@field last? {key: string, reason: string} step 1 at the last rebuild, for the next login's resume line
---@field lead? integer the map of the zone the story led with, which the next build keeps while it still has useful work
---@field left? integer the map of the zone the story left, which waits behind every other zone the next build offers
---@field waypoint? {map: integer, x: number, y: number} the native waypoint the last Go set, while it may still be ours
---@field guided? string the key of the chosen journey whose route AGF started, while that guidance should run
---@field focus? integer the quest AGF selected on walking into its area (Focus.lua), while that selection is still AGF's

-- What Focus.Next keeps between looks: the area step 1 was, and the quest AGF selected.
---@class AGFFocusState
---@field area? string
---@field quest? integer

---@class AGFFocus
---@field Next fun(state: AGFFocusState, here?: {key: string, quests: integer[]}, current?: integer, enabled: boolean): integer?
---@field Sync fun() the selection follows the route as it is now; Guidance runs it on each route change

-- "town" is a visit to a town (its pickups and agreeing hand-ins), "turnin" a hand-in anywhere else, and "area" or
-- "dungeon" (a group quest's) where the log's quests under way are done.
---@alias AGFStepKind "town"|"turnin"|"area"|"dungeon"|"trainer"|"battlemaster"

-- Where a quest under way is done next (Steps.lua Nodes): one open objective's area, or the client's point for the
-- quest with every open objective.
---@class AGFNode
---@field map integer
---@field x number
---@field y number
---@field r number its radius in yards, 0 for a single point
---@field slot integer the data's need slot of its first objective; 0 when none is known
---@field objectives AGFAreaObjective[]

-- One open objective an area step holds. `finish` is the town the quest is handed in at, which a route visits after.
---@class AGFAreaObjective
---@field id integer the quest
---@field slot integer the data's need slot
---@field have? integer the client's count, when its objectives line up with the data's slots
---@field need? integer the count it needs, the client's else the data's
---@field text? string the client's words for it, when they line up and it has any
---@field finish? string the town key ("town:<hub>") of the quest's hand-in, when the data has one

---@class AGFStep
---@field key string stable identity for skips and the resume line; repeated town visits append ":<n>" to the town key
---@field entrance? integer an instance entrance stop for accepted quests whose objective points are unknown
---@field kind AGFStepKind
---@field title string e.g. "Turn in: Bathran's Hair", "Pick up quests: Guard Parker" or "Lakeshire, Redridge"
---@field detail string grey second line, e.g. "2 to hand in, 4 to pick up"
---@field reason string short why, e.g. "continues chain"
---@field quests integer[] quest IDs this step covers; a town's hand-ins first, then by ID
---@field hub? string a town's hub (AGFPlace.hub); nil for a town the data could not place
---@field pickups? integer[] a town's eligible quests this card wants there, ascending
---@field handins? integer[] a town's finished log quests handed in there, ascending
---@field objectives? AGFAreaObjective[] an area's open objectives, by quest and slot
---@field givers? string[] a town's distinct NPC and object names, in `quests` order
---@field group? integer how many of a town's quests are elite, dungeon or raid
---@field spots? table<integer, AGFPlace> a town's quest ID -> its start or finish there; the point is one of them
---@field map integer
---@field x number
---@field y number
---@field place? string the town's name, else its busiest giver; a turn-in's NPC only where its waypoint agrees; a trainer's NPC
---@field zone? string the client's name for `map`, else the data's
---@field optional? boolean elite/group or outside the player's level band
---@field r? number an area's radius in yards, wide enough for all its objectives; 0 for a point
---@field planned? table<integer, true> the quests on it the route picks up first, not in the log yet (Laps.lua)
---@field returns? table<integer, true> a town's hand-ins the route comes back for once their objectives are done
---@field chapter? string the story card's chapter line, on the step that takes the chain up
---@field shapes? AGFNode[] an area's objective nodes, each its own ring, merged into it
---@field here? true step 1 is the area the player stands in, objectives open: nothing guides to it, only on past it

---@class AGFSkipped
---@field key string
---@field title string

-- A quest giver drawn as a "!" on the world map.
---@class AGFGiver
---@field map integer
---@field x number
---@field y number
---@field title string NPC or object name
---@field quests integer[] quest IDs it offers the player now, ascending
---@field adds integer[] those a shift-click puts on the route: none orange or red

---@alias AGFJourneyKind "carry"|"story"|"nextzone"|"dungeon"|"calling"|"battleground"

-- The overview's quest log header a journey shows under (Overview.GROUPS): its kind at build time, so no title is
-- guessed from. "continue" holds the story, Quests in your log and your calling.
---@alias AGFJourneySection "continue"|"zones"|"dungeons"|"battlegrounds"

-- A quest's place in its chain (Model.Story): the data's `next` links from the chain's head. Later members are IDs
-- only, so no later chapter's title is ever drawn.
---@class AGFStory
---@field chapter integer this quest's place in the chain, from 1
---@field total? integer the chain's length, only when the data proves where it ends
---@field members integer[] the chain's quest IDs in order, the head first

-- One card in the guide (docs/design.md §2.2): only steps the player can take now.
---@class AGFJourney
---@field kind AGFJourneyKind
---@field section AGFJourneySection the overview header it shows under
---@field zone? integer uiMapID of a zone story or next-zone journey, independent of its first step
---@field instance? integer Map.ID of a dungeon journey or a story leading into an instance
---@field level? integer a battleground journey: the level it opens at
---@field key string stable identity for prefs.journey: "carry", "zone:<uiMapID>" (a zone's story or next-zone card alike), "dungeon:<Map.ID>", "calling", "chain:<questID>" (a way into an instance, by its chain's first quest) or "battleground:<BattlemasterList ID>"
---@field title string e.g. "Quests in your log" or "Westfall story"
---@field subline string e.g. "3 ready to hand in, 1 in progress"
---@field reason? string why this journey, when there is an honest answer
---@field map integer where its first step is: choosing the card turns the world map there
---@field steps AGFStep[] never more than MAX_STEPS, in route order
---@field story? AGFStory the story card's chain, when the zone has one the player can take up now
---@field count? string a zone card's count of quests, the story card's subline once its chapter is skipped
---@field hub? string its first stop's place, else that stop's title: the card's line 3 when it has no reason
---@field more? integer how many stops follow the first (Model.Journeys sets it and `group` once the card is built)
---@field group? integer how many of its quests are elite, dungeon or raid (the sum of its steps' `group`)
---@field drop? integer[] the first card's log-full note: the log's quests the guide would let go, by ID, when 2 or fewer slots are free
---@field ready? integer the log's quests it holds that are ready to hand in (Quests in your log and a zone story)
---@field underway? integer the log's quests it holds that are still in progress
---@field holds? table<integer, true> a zone story's log quests on its zone, a later lap's too: carry (Quests in your log) holds the rest

---@class AGFRoute
---@field journeys AGFJourney[] all available options: the zone's story, carry, then the diversions (calling, dungeon, a way into an instance, battleground, next zone) newest first
---@field journey? string the key of the journey whose steps these are: the chosen one, else the first
---@field chosen boolean the player chose `journey`; false while the route falls back to the first card
---@field stranded? true no next zone: the dungeon card came whatever the Dungeons toggle says
---@field steps AGFStep[] that journey's steps, never more than MAX_STEPS
---@field skipped? table<string, boolean> the skipped keys a full build still had a step for; nil after the combat one
---@field orders? table<string, AGFOrder> each card's committed order by journey key, which the next build keeps to; the planner's own, read by nothing else
---@field lead? integer the map of the zone the story led with, which the next build keeps while it still has useful work
---@field left? integer the map of the zone the story left, which waits behind every other zone the next build offers
---@field here? string the key of the area the player stood in (step 1's `here`), which the next build lets go only past HERE_MARGIN

-- A card's committed order (docs/design.md §4.3): its steps' identities in order (Routing.lua Idents), and the quests
-- its route picks up, which keep their slots in the log on the next build.
---@class AGFOrder: string[]
---@field picked? table<integer, true>

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
---@field LevelPreference fun(questLevel: integer, playerLevel: integer): integer lower is taken first; at the player's level and one or two below are free, each level above costs twice its distance, and each level further below costs one
---@field EXPLORE_SLOT integer the data's need slot for an explore objective (tools/gen_quests.py)
---@field ValidPlace fun(place?: {map?: integer, x?: number, y?: number}): boolean? true when `place` has a positive map and x, y in 0..1
---@field Hub fun(data: AGFData, place: {map: integer, x: number, y: number}): string? the town `place` stands in, as "map:area"
---@field Hard fun(quest: AGFQuest, player: AGFPlayer): boolean above the chosen quest level ceiling
---@field Eligible fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>, questID: integer): boolean
---@field Why fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>, questID: integer, names?: AGFWhyNames): AGFWhyLine[] every requirement, met or not; eligible exactly when all are met
---@field Search fun(data: AGFData, player: AGFPlayer, query: string, title?: fun(questID: integer): string?): integer[] up to 10 quest IDs whose title holds `query`, by title
---@field Givers fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>, mapID: integer): AGFGiver[]
---@field Story fun(data: AGFData, questID: integer): AGFStory? the chain the quest belongs to; nil when it is in none, or the way back forks
---@field Journeys fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>, prefs: AGFPrefs, mapName?: (AGFMapName), instanceName?: (fun(id: integer): string?), skippedQuests?: table<string, integer[]>, lead?: integer, left?: integer, entrances?: table<integer, AGFLocation>): AGFJourney[], boolean
---@field Plan fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>, prefs: AGFPrefs, mapName?: (AGFMapName), instanceName?: (fun(id: integer): string?), last?: AGFRoute, inputs?: AGFPlanInputs): AGFRoute
---@field Here fun(data: AGFData, where?: {map?: integer, x?: number, y?: number}, steps: AGFStep[], held?: string): integer? the open area step `where` stands in: the head when it is one, else the first; `held`, the key of the one stood in last, lets go past a margin
---@field NearAction fun(from?: AGFPosition, log: table<integer, AGFLogQuest>, steps: AGFStep[], at: (fun(step: AGFStep): AGFPosition?)): AGFStep? the ready hand-in or pickup beside the player that goes before the head, or nil
---@field Yards fun(data: AGFData, a: {map: integer, x: number, y: number}, b: {map: integer, x: number, y: number}): number? yards between two places on one continent the data places; nil otherwise
---@field Refresh fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>, prefs: AGFPrefs, last: AGFRoute, mapName?: (AGFMapName), inputs?: AGFPlanInputs): AGFRoute the cheap in-combat rebuild: the log's steps fresh, the rest from `last`

-- What the player's order and skips ask of a build, as plain values (Shown.Build gathers them); Model.Plan
-- reads no other module.
---@class AGFPlanInputs
---@field dungeonEntrances? table<integer, AGFLocation> known instance entrance points
---@field skippedQuests? table<string, integer[]> the quests of each skipped giver, by skipped key: no route offers them
---@field forget? table<string, true> journeys whose committed order (`AGFRoute.orders`) this build lets go

---@class AGFState
---@field Player fun(): AGFPlayer
---@field Where fun(): integer?, number?, number? the player's map and point on it; nil where the client places them nowhere
---@field Completed fun(): table<integer, boolean>
---@field Log fun(): table<integer, AGFLogQuest>
---@field OnChange fun(callback: fun())
---@field QuestChanged fun() a quest changed outside the client's own events (Questie's live updates), coalesced with them
---@field QuestUpdateChanged fun(id: integer): boolean whether a Questie update moved the quest's live availability since the last plan
---@field OnInitialLogin fun(callback: fun()) called on a login's PLAYER_ENTERING_WORLD, never on a /reload
---@field Ready fun(): boolean completion data has loaded
---@field MapName fun(map: integer): string? the client's localised map name, nil when it has none
---@field ZoneName fun(map: integer, data?: AGFData): string? the client's name for the map, else the bundled data's zone or map name
---@field InstanceName fun(id: integer): string? the client's localised name for an instance Map.ID, nil when it has none
---@field QuestTitle fun(questID: integer): string? the client's cached title, nil until it has one
---@field RaceName fun(raceID: integer): string?
---@field ClassName fun(classID: integer): string?

-- Shortest Path Forever's public API, mirrored field for field from its types/API.lua (SPFAPIStop, SPFPublicAPI) at
-- the sha tests/contract_spec.lua pins; that spec fails on any drift. Integrations.lua's REQUIRED lists exactly
-- the non-optional functions. Descriptions go after `--` so the type is the whole first token. The members a
-- Shortest Path before 1.2 lacks are optional here, and checked where they are used.
---@alias AGFSPFMode "walk"|"flight"|"boat"|"zeppelin"|"lift"|"tram"|"portal"|"passage"|"teleport"
---@alias AGFSPFNoRoute "combat"|"invalid"|"unreachable" -- why an estimate has no answer
---@alias AGFSPFEnded "arrived"|"cleared"|"replaced"|"cancelled" -- reached the last stop; the player cleared it; another journey took over; the owner's own Cancel

-- What stands at a stop; Shortest Path draws the game's own mark for it on the stop's pin.
---@alias AGFSPFStopKind "pickup"|"turnin"|"objective"|"trainer"|"innkeeper"|"flightmaster"|"battlemaster"|"dungeon"|"boat"|"zeppelin"|"lift"|"tram"|"portal"

--- An objective area a held stop stands for: its outline is drawn, and the stop and its line step aside, while the
-- player stands inside.
---@class AGFSPFShape
---@field map integer -- uiMapID
---@field x number -- normalized 0-1
---@field y number -- normalized 0-1
---@field radius number -- yards

---@class AGFSPFStop
---@field map integer -- uiMapID
---@field x number -- normalized 0-1
---@field y number -- normalized 0-1
---@field title? string
---@field kind? AGFSPFStopKind -- a Shortest Path before kinds ignores it
---@field tooltip? string optional quest level/chain detail for the stop tooltip
---@field hold? boolean keep guidance until the owner replaces the route after quest progress
---@field radius? number yards around a held stop where travel cues pause
---@field questID? number the one quest this area stands for, so Shortest Path can use the client's own inside-area state
---@field questIDs? number[] every quest this area covers, for the game's own quest area on the map; a Shortest Path before it ignores it
---@field shapes? AGFSPFShape[] the objective areas a held stop stands for

---@class AGFSPFLeg
---@field mode AGFSPFMode
---@field to string -- where the leg ends, named as Shortest Path's tracker names it
---@field seconds number -- from the previous leg's arrival (the first from the start), waits included
---@field wait? number -- seconds waiting for a boat, zeppelin, lift or tram; present only from 60 up
---@field newFlightPath? boolean -- a walk to a flight master this character has not discovered

---@class AGFSPFDetail
---@field seconds number -- equal to Estimate's answer
---@field legs AGFSPFLeg[] -- fresh copies on every call

---@class AGFSPFAPI
---@field version integer -- AGF accepts exactly 1
---@field Estimate fun(fromMap: integer, fromX: number, fromY: number, toMap: integer, toX: number, toY: number): number?, AGFSPFNoRoute? -- travel seconds; nil comes with the reason
---@field Navigate fun(owner: string, map: integer, x: number, y: number, title?: string, kind?: AGFSPFStopKind): boolean -- starts or replaces guidance
---@field NavigateRoute fun(owner: string, stops: AGFSPFStop[]): boolean -- 1-64 stops in order
---@field CurrentStop fun(owner: string): integer? -- nil unless owner owns the active journey
---@field Cancel fun(owner: string): boolean -- true only when this owner's journey was cancelled
---@field EstimateDetail? fun(fromMap: integer, fromX: number, fromY: number, toMap: integer, toX: number, toY: number): AGFSPFDetail?, AGFSPFNoRoute? -- Estimate leg by leg, sharing its cache
---@field Active? fun(): boolean -- true while any journey is guiding, whoever started it
---@field Ended? fun(owner: string): AGFSPFEnded?, number? -- why owner's last journey ended and its GetTime(); nil while it runs, before any, or after a reload

-- Tweaks Forever's public API (its types/API.lua TFPublicAPI and TFAPITrainableSpell), version 1.
---@class AGFTFSpell
---@field spellID integer
---@field name string
---@field level integer the level the trainer teaches it from
---@field cost? integer the fee in copper, when known
---@field line string the spellbook tab, localised, for display only
---@field lineID integer the tab's SkillLine ID (the spell's own when `general`): compare this, not `line`
---@field general boolean it goes on the General tab

---@class AGFTFAPI
---@field version integer 1 or 2, additive
---@field TrainableSpells fun(): AGFTFSpell[]? the spells the player's level allows and they haven't learned; nil before login and in combat
---@field Trainers? fun(): AGFTFTrainer[]? (version 2) the player's class trainers with their places; {} for a class with none

-- The raw shape Tweaks Forever's API v2 answers with (its types/Namespace.lua TFClassTrainer); place is flat here.
---@class AGFTFTrainer
---@field npc integer
---@field name string
---@field map? integer
---@field x? number
---@field y? number

-- One class trainer Tweaks Forever knows, with the place it projects (version 2).
---@class AGFClassTrainer
---@field npc integer the trainer's creature entry
---@field name string
---@field place? AGFPlace where the trainer stands; nil when the data places none

---@class AGFIntegrations
---@field Kind fun(step: AGFStep|AGFGiver): AGFSPFStopKind? what Shortest Path is told stands at a stop: a town's "?" where a hand-in is its point, else its "!"
---@field TravelLine fun(step: AGFStep): string? asks Shortest Path now, at most one call: "Fly to X · N min" from EstimateDetail, "About N min away" from Estimate, nil without either or an answer
---@field RefreshTravel fun() refetches step 1's line; Core runs it in the frame after each rebuild
---@field Debug fun(guidance: string): string the travel line and guidance state, for /agf travel; `guidance` is Guidance's part
---@field Travel fun(step: AGFStep): string? the last line fetched for this step, without asking again
---@field TravelMinutes fun(step: AGFStep): integer? the whole trip's minutes, fetched with that line
---@field OnTravelChange fun(callback: fun())
---@field ReplacesJourney fun(): boolean Go would replace a Shortest Path journey someone else started (needs Active)
---@field Guiding fun(): boolean Shortest Path is walking our multi-stop route and draws its own numbered stops; held (its "Guide me" off) is not guiding
---@field Provider fun(): string? name of the addon navigating, for copy ("Shortest Path")
---@field Hand fun(steps: (AGFStep|AGFGiver)[], hold?: boolean): boolean hands Shortest Path the steps as one journey of ours; false when it is absent or refuses
---@field Drop fun(): boolean ends Shortest Path's journey by our name; true when it ended one
---@field CurrentStop fun(): integer? the stop of our journey Shortest Path heads for, guiding it or not; nil when it holds none of ours
---@field EndReason fun(last?: AGFStep|AGFGiver): string? why our journey ended: Shortest Path's Ended, else guessed from another journey running or standing in the last stop's town or area
---@field WaypointAt fun(place?: {map: integer, x: number, y: number}): boolean the client's waypoint still sits at the place
---@field CanWaypoint fun(map: integer): boolean the client allows a waypoint on the map
---@field SetWaypoint fun(place: {map: integer, x: number, y: number}, track?: boolean) the client's waypoint goes there; `track` points the arrow at it
---@field ClearWaypoint fun() the client's waypoint and its arrow go
---@field RefreshCards fun(journeys: AGFJourney[]) the cards shown: drops other answers, asks for stale destinations, one a frame
---@field ResumeCards fun() step 1's travel frame is over: the queued cards ask from the next frame
---@field CardTravel fun(journey: AGFJourney): AGFCardTravel? a card's last answer, without asking again
---@field OnCardTravel fun(callback: fun()) called as each card's answer arrives

-- A card's travel from Shortest Path; all nil when it had no answer.
---@class AGFCardTravel
---@field line? string the travel line, as TravelLine gives it
---@field minutes? integer the whole trip
---@field crossing? AGFSPFMode "boat" or "zeppelin" when the way takes one
---@field from? string where the player stood when it was asked ("map:x:y")

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
---@field TITLE string the addon's name in the window title, map tab, settings page and chat
---@field AUDIT_BUILD string format: data build, client version, client build
---@field AUDIT_COUNTS string format: bundled, eligible and completed counts
---@field AUDIT_NOT_READY string
---@field HELP_OPEN string
---@field HELP_AUDIT string
---@field HELP_DUMP string
---@field HELP_TRACKER string
---@field HAND_IN_WHEN string format: zone name; the reason on a turn-in the route leaves for another continent
---@field NO_WAYPOINT string the error Go shows when nothing can guide the player on the step's map
---@field GO string the step menu's entry that starts guidance
---@field REPLACES_JOURNEY string Go's tooltip line while someone else's Shortest Path journey runs
---@field STOP string ends the guidance Go started
---@field SHOW_QUEST string opens the map on a log quest's zone
---@field SKIP string hides the step for this session
---@field SKIPPED string format: how many steps are skipped this session
---@field SHOW_AGAIN string format: a skipped step's title
---@field CHOOSE_JOURNEY string opens the guide
---@field ALL_SUGGESTIONS string the header's back arrow tooltip: it chooses none, so the guide shows the overview again
---@field BACK_STOPS_ROUTE string the back arrow's tooltip while AGF's route runs, which going back stops
---@field BACK_TO_ALL string the chosen card's tooltip: the back arrow goes back to every card
---@field CLICK_TO_RESUME string the chosen card's tooltip while its route is paused: the click resumes it
---@field ROUTE_PAUSED string the footer line while the chosen journey's route is paused
---@field HUB_MORE string format: a card's first stop, how many stops follow it
---@field HUB_MORE_ONE string format: a card's first stop, when one stop follows it
---@field CARD_MINUTES string format: a card's minutes to its first stop
---@field CARD_BY_BOAT string format: the same when the way takes a boat
---@field CARD_BY_ZEPPELIN string format: the same when the way takes a zeppelin
---@field GROUP_ONE string a card's tooltip when one of its quests needs a group
---@field GROUP_MANY string format: how many of a card's quests need a group
---@field CLICK_TO_CHOOSE string an unchosen card's tooltip instruction
---@field TRAVEL string format: a leg ("Fly to X"), minutes until it arrives
---@field TRAVEL_ABOUT string format: minutes; the line from a Shortest Path with Estimate only
---@field TRAVEL_NEW_FLIGHT_PATH string appended when a walk leg reaches an undiscovered flight master
---@field TRAVEL_WAIT string format: minutes waiting for the chosen leg's boat, zeppelin, lift or tram; appended
---@field TRAVEL_WALK string format: the place a leg ends; one per AGFSPFMode but "teleport"
---@field TRAVEL_FLIGHT string
---@field TRAVEL_BOAT string
---@field TRAVEL_ZEPPELIN string
---@field TRAVEL_LIFT string
---@field TRAVEL_TRAM string
---@field TRAVEL_PORTAL string
---@field TRAVEL_PASSAGE string
---@field NEXT string format: the step after the tracker's
---@field RESUME string format: the reason saved with step 1 last session
---@field STORY_COMPLETE string the tracker header that glows when a proven chain's last quest is handed in
---@field JOURNEY_COMPLETE string the tracker header that glows when a turn-in ends the chosen journey
---@field CHOOSE_NEXT string its line: the guide has every journey again
---@field TRACKER_DRAG_TITLE string shared tracker grip title
---@field TRACKER_DRAG_TOOLTIP string shared tracker grip tooltip
---@field TRAINER string
---@field TRAINER_SPELLS string format: spell count
---@field TRAINER_SPELL string
---@field TRAINER_LINE string format: TRAINER, then the spell count
---@field TRACKER_UNATTACHED string
---@field TRACKER_LOADING string the tracker's quiet line while QuestieDB's catalogue builds
---@field DUMP_SAVED string
---@field TURN_IN string format: quest title
---@field READY_TO_HAND_IN string
---@field OPENS_CHAPTER_HERE string
---@field QUESTS_IN_PROGRESS string
---@field QUESTS_HERE string format: quest count
---@field PICK_UP string format: place name
---@field HUB_HAND_IN string format: a town stop's hand-in count
---@field HUB_PICK_UP string format: a town stop's pickup count
---@field HUB_MORE_QUESTS string format: how many more quests a town's tooltip leaves out
---@field HUB_NPCS_MORE string format: a town's first NPCs, how many more
---@field PLACE string format: a step's place (NPC or town), its zone
---@field NEAR_YOUR_LEVEL string
---@field SKIP_STEP string
---@field OPTIONAL string
---@field SHORTEST_PATH string
---@field STARTS_AFTER_COMBAT string the footer while a choice made in combat waits to start its route
---@field CLICK_TRAVEL string format: travel addon name
---@field CLICK_WAYPOINT string
---@field PIN_RETURN_STORY string a numbered pin's instruction to route from the story's start
---@field STEP_NUMBERED string format: route index, step title
---@field QUEST_LEVEL string format: quest level, quest title
---@field OVERVIEW_WHERE string format: the overview's line under the title, the player's zone and level
---@field RECOMMENDED string
---@field YOUR_CHOICE string
---@field START_ADVENTURE string
---@field RESUME_ADVENTURE string
---@field DO_THIS_NEXT string
---@field OTHER_ADVENTURES string
---@field SUGGESTED string the overview's first card's tag
---@field READY_OF string format: a Quests in your log card's footer in the overview, ready of all it holds
---@field CHAPTERS_DONE string format: a story card's footer in the overview, chapters done of the chain's
---@field STOPS_ONE string a card's footer in the overview when it has one stop
---@field STOPS string format: the same for several
---@field OBJECTIVE_LINE string format: the client's words for an open objective, with its count
---@field OBJECTIVE_COUNT string format: an open objective's count so far, the count it needs
---@field MENU_QUESTS string
---@field MENU_DUNGEONS string
---@field MENU_MAP_PINS string
---@field MENU_GIVERS string
---@field MENU_TRACKER string
---@field MENU_MORE_SETTINGS string
---@field SETTINGS_GROUP_ROUTE string
---@field SETTINGS_GROUP_MAP string
---@field SETTINGS_GROUP_TRACKER string
---@field SETTINGS_GROUP_INTERFACE string
---@field SETTINGS_OPEN string
---@field SETTING_TRACKER string
---@field SETTING_TRACKER_TOOLTIP string
---@field SETTING_ATTACH_TRACKER string
---@field SETTING_ATTACH_TRACKER_TOOLTIP string
---@field SETTING_MAP_PINS string
---@field SETTING_GIVERS string
---@field SETTING_DUNGEONS_DEFAULT string
---@field SETTING_QUEST_LEVEL string
---@field SETTING_QUEST_LEVEL_VALUE string
---@field SETTING_QUEST_LEVEL_ONE string
---@field SETTING_QUEST_LEVEL_TOOLTIP string
---@field SETTING_TRAINING_REMINDERS string
---@field SETTING_TRAINING_REMINDERS_TOOLTIP string
---@field SETTING_MAP_PINS_TOOLTIP string
---@field SETTING_GIVERS_TOOLTIP string
---@field SETTING_DUNGEONS_DEFAULT_TOOLTIP string
---@field SETTING_TITLE_ROUTE string
---@field SETTING_TITLE_ROUTE_TOOLTIP string
---@field SETTING_AUTO_START string
---@field SETTING_AUTO_START_TOOLTIP string
---@field SETTING_TRACK_ROUTE string
---@field SETTING_TRACK_ROUTE_TOOLTIP string
---@field SETTING_UNTRACK_OTHERS string
---@field SETTING_UNTRACK_OTHERS_TOOLTIP string
---@field PREVIOUS_PAGE string
---@field NEXT_PAGE string
---@field JOURNEY_PAGE string
---@field JOURNEY_CARRY string
---@field CARRY_EXPLANATION string
---@field JOURNEY_STORY string format: zone name
---@field JOURNEY_NEXT_ZONE string format: zone name
---@field GROUP_CONTINUE string the overview's quest log header over the story, the log and your calling
---@field GROUP_ZONES string the header over the "Head to <zone>" cards
---@field GROUP_DUNGEONS string the header over the dungeon cards
---@field GROUP_BATTLEGROUNDS string the header over the battleground cards
---@field LEVELS string a card's level range, low then high
---@field LEVELS_FROM string a battleground card's first level
---@field DUNGEON_QUESTS string format: quest count
---@field DUNGEON_QUESTS_ONE string
---@field DUNGEON_INSIDE string format: count of the log's quests filed under the instance, its name
---@field DUNGEON_INSIDE_ONE string format: the instance's name
---@field JOURNEY_INTO string format: the instance a chain leads into
---@field CARRY_READY string format: count of finished quests whose hand-in is on this continent
---@field HAND_IN_WHEN_DONE string a lap's return visit's reason for its one hand-in, a quest the lap does first
---@field AFTER_PICK_UP string an area's reason for its one quest, which the lap picks up first
---@field CARRY_IN_PROGRESS string format: count
---@field CARRY_AWAY string format: count of finished quests whose hand-in is across an ocean
---@field LATER_LAPS string format: count of a story's log quests its later laps take
---@field LIST_SEPARATOR string between the parts of one line
---@field QUESTS_NEAR string format: count
---@field QUESTS_NEAR_ONE string
---@field CHAPTER_OF string format: chapter, total
---@field CHAPTER string format: chapter; the chain's length unproven
---@field CONTINUES_STORY string
---@field BEGINS_STORY string
---@field NO_JOURNEY string the guide with no journey
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
---@field WHY_BREADCRUMB string format: the title of the quest a breadcrumb leads to
---@field WHY_EARLIER_QUEST string a prerequisite the data has no title for
---@field WHY_RACES string format: race names, joined (the client's ITEM_RACES_ALLOWED)
---@field WHY_CLASSES string format: class names, joined (the client's ITEM_CLASSES_ALLOWED)
---@field LOADING string the guide before the completed quests arrive
---@field SEARCH_QUESTS string the search box's instructions
---@field SEARCH_NONE string a search that finds no quest

---@class ForeverTrackerHostAPI
---@field GetSettings fun(): ForeverTrackerSettings
---@field SetAttached fun(value: boolean)
---@field IsAttachedToQuestTracker fun(): boolean
---@field OnAttachmentChanged fun(callback: fun(attached: boolean))
---@field SavePosition fun(x: number, y: number)

---@alias AGFGuidanceStatus "queued"|"paused"|"arrived" -- a start waits for combat's end; the route stopped without the player's Stop and can be resumed; it reached its last stop

-- The guidance lifecycle (Guidance.lua): the one writer of AGFPrefs.guided and AGFPrefs.waypoint. Choosing, starting
-- and stopping are ns.Choose, ns.StartRoute and ns.Stop.
---@class AGFGuidance
---@field Status fun(): AGFGuidanceStatus? where the chosen journey's guidance stands, when it is not simply running or absent
---@field Owns fun(): boolean Go's guidance is still running: our Shortest Path journey (guided or held), or the waypoint Go set
---@field Navigate fun(step: AGFStep|AGFGiver, follow?: boolean): boolean route there with Shortest Path, else (declined or absent) the native waypoint where the map allows one; true when something now guides
---@field ShowOnMap fun(step: AGFStep|AGFGiver): boolean route, open its zone and ping the destination
---@field Cancel fun() Stop: cancels our Shortest Path journey, and clears the native waypoint only while it is ours
---@field Reroute fun() the player reordered the chosen journey: the route AGF runs for it starts again a frame on
---@field CurrentStep fun(): AGFStep? the step the handed route heads for while it guides, else the route's head
---@field Guided fun(): (AGFStep|AGFGiver)[] the stops Shortest Path walks, while it guides; empty otherwise
---@field OnChange fun(callback: fun()) called after every Go that guides, every Stop and the super-tracking events
---@field Stale fun(handed: AGFStep[], index: integer, steps: AGFStep[], far: fun(a: AGFStep, b: AGFStep): boolean): boolean the guidance handed to Shortest Path no longer matches the journey's steps
---@field Ended fun(route: AGFRoute) Core's commit of a full build: a chosen journey the build no longer has ends
---@field RouteChanged fun() Core, ahead of every route listener: a waiting start, a choice that went, the restore, Focus.Sync, then following
---@field Debug fun(): string /agf travel's line

---@class AGFNamespace
---@field PanelSearch AGFPanelSearch
---@field QuestieFields {spawns: string[], drops: string[]}
---@field TrackerHost ForeverTrackerHostAPI
---@field TrackerHostSettings fun(): ForeverTrackerSettings
---@field Geometry AGFGeometry the native-geometry adapter (Geometry.lua)
---@field TITLE string
---@field L AGFStrings
---@field Data AGFData
---@field Model AGFModel
---@field State AGFState
---@field Integrations AGFIntegrations
---@field Guidance AGFGuidance
---@field Focus AGFFocus
---@field Print fun(msg: string)
---@field Setting fun(key: string): any
---@field SetSetting fun(key: string, value: any)
---@field Prefs fun(): AGFPrefs
---@field Route fun(): AGFRoute the current route, rebuilt lazily when state or prefs change
---@field Snapshot fun(): AGFSnapshot what the current route was planned from; a fresh read while no build stands behind it
---@field CurrentJourney fun(): AGFJourney? the journey the route shows (the chosen one, else the first card's)
---@field RouteSettled fun(): boolean Route() answers from the committed route, without building one
---@field QuestieBuilding fun(): boolean QuestieDB's catalogue is still building: the route holds and the tracker waits
---@field Invalidate fun() mark the route stale and notify views
---@field OnRouteChange fun(callback: fun())
---@field Choose fun(key?: string, start?: boolean) choose a journey, or none; `start` sets off on the rebuild with its steps
---@field StartRoute fun(step?: AGFStep): boolean guidance along the chosen journey (choosing the route's own when none is); waits out combat with Shortest Path
---@field Stop fun() the player's Stop: our route stops and the choice clears
---@field Settling fun(): boolean a rebuild or step 1's travel line is due, whose frames take no card estimate
---@field Rebuilding fun(): boolean a full build is being sliced across frames (true until its last slice commits)
---@field PanelShown? fun(): boolean whether the guide is open, set once Blizzard_WorldMap has loaded
---@field Skip fun(key: string, title: string) hide a step for this session; the menu offers it back by its title
---@field Unskip fun(key: string) Show again: a skipped step or a journey not wanted
---@field Skipped fun(): AGFSkipped[] this session's skipped steps in skip order, then the journeys not wanted, by title
---@field Resume fun(step: AGFStep): string? the reason saved last session, while the resume line stands for this step
---@field InLog fun(step: AGFStep): boolean the step is a quest in the player's log (a turn-in or its objectives)
---@field Menu AGFMenuModule
---@field ContextMenu fun(owner: Region, generator: fun(owner: Region, root: AGFMenuDescription)): AGFMenuDescription
---@field ShowQuest fun(step: AGFStep): boolean open the map on a log step's quest and select it; false for other steps or in combat
---@field TurnedIn fun(questID: integer) QUEST_TURNED_IN: latched so a chosen journey that ends there is complete, then OnTurnIn
---@field OnJourneyComplete? fun() a turn-in ended the chosen journey; set by Tracker.lua
---@field OnTurnIn? fun(questID: integer) QUEST_TURNED_IN: the chapter-end fanfare when the quest ends a proven chain; set by Tracker.lua
---@field TrackRouteQuests fun() track the route's log quests; with untrackOthers, stop tracking the rest
---@field DumpLayout fun(root: Frame, describe?: fun(region: Region, entry: AGFDumpEntry)): AGFDumpEntry[]
---@field Dump fun() /agf dump: save the layout, route and frames in AdventureGuideForeverDB.dump

-- NPC roles (tools/gen_quests.py `roles`): where trainers, battlemasters and innkeepers stand.

---@class AGFData
---@field npcs? table<integer, AGFNpc> creature entry -> its roles, side and place; absent until QuestieDB publishes its catalogue

---@class AGFNpc : AGFRole
---@field side integer the sides it is friendly to (QuestieDB friendlyToFaction): 1 Alliance, 2 Horde, 3 both
---@field place AGFPlace a QuestieDB spawn on its usual map; its `hub` is the town it stands in
---@field inn? boolean innkeeper (QuestieDB npcFlags)

--[[ What Forever added (tools/diff_forever.py, Data/Forever.lua) and honest coverage ]]

-- The IDs Forever's DB2 tables have and Classic Era's lack, at the pinned builds.
---@class AGFForever
---@field quests table<integer, integer[]> uiMapID -> the added quests whose QuestPOIBlob sits on it; the rest have no zone
---@field areas table<integer, true> the added AreaTable IDs

---@class AGFData
---@field forever? AGFForever nil in specs and benches that load only route geometry and the quest fixture

--[[ The overview's round zone icons (tools/gen_zoneart.py, Data/ZoneArt.lua, docs/design.md §2.2) ]]

---@class AGFData
---@field zoneArt? table<integer, integer[][]> uiMapID -> its world-map overlays, each { offsetX, offsetY, width, height, tile FileDataIDs row-major }; nil when the zone-art data is not loaded

---@class AGFZoneIconModule
---@field Create fun(parent: Frame, size: number, badge: number): AGFZoneIcon a round zone icon, its art `size` across and the kind badge `badge`
---@field Set fun(icon: AGFZoneIcon, atlas: string, map?: integer, x?: number, y?: number, span: number) the zone's art round (x, y), `span` map pixels across; the plain ring with `atlas` centred when there is none
---@field CreateBackdrop fun(parent: Frame): AGFZoneBackdrop a card's rectangular zone art, for the Adventure Guide window
---@field SetBackdrop fun(backdrop: AGFZoneBackdrop, width: number, height: number, map?: integer, x?: number, y?: number, span: number): boolean the zone's art round (x, y) in width x height, `span` map pixels across; false and hidden when there is none

---@class AGFZoneBackdrop : Frame
---@field Clip Frame
---@field Art AGFZoneIconArt
---@field width number
---@field key? string the zone and window drawn

---@class AGFNamespace
---@field ZoneIcon AGFZoneIconModule

---@class AGFModel
---@field Unlisted fun(data: AGFData, map?: integer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>): boolean the log holds a quest the data lacks, or Forever added quests on `map` the data lacks and the player hasn't finished

---@class AGFStrings
---@field UNLISTED string the panel's honest-coverage line

---@class AGFStrings
---@field REASON_GREY string format: how many of a zone card's pickups turn grey at the next level
---@field REASON_CHAIN_GIVER string format: the giver who begins the card's chain
---@field REASON_HANDS string format: the first stop's town, by its area's or map's name
---@field NOT_INTERESTED string a journey card's menu: hide it on this character
---@field RIGHT_CLICK_NOT_INTERESTED string a journey card's tooltip: its right-click

---@class AGFNotInterested
---@field title string the title Show again names the journey by
---@field chosen? boolean it was the chosen journey: Show again chooses it again

---@class AGFPrefs
---@field notInterested table<string, AGFNotInterested> journey keys this character is not interested in, and "quest:<id>" for each quest dropped by "Not this quest"

---@class AGFNamespace
---@field NotInterested fun(key: string, title: string) hide a journey on this character until Show again; a choice of it ends

-- Choice (docs/design.md §2.18): quests the player drops or adds, and the log-full note.

---@class AGFStrings
---@field CARRY_ADDED string format: count of quests the player added that Quests in your log holds
---@field LOG_FULL string format: the log-full note's count of quests the player could drop
---@field LOG_FULL_ONE string the same for one quest
---@field LOG_FULL_LIST string the log-full note's tooltip, over the quests' titles
---@field NOT_THIS_QUEST string a step's menu: drop one of its quests on this character
---@field SHIFT_ADD string a quest giver's or search result's tooltip: its shift-click adds the quests
---@field SHIFT_REMOVE string the same once they are added: its shift-click takes them off

---@class AGFPrefs
---@field pinned table<integer, true> quests the player added by shift-click: in the route past the ratio cut

---@class AGFNamespace
---@field NotThisQuest fun(id: integer, title: string) drop a quest on this character until Show again; it stays in the log
---@field Pinned fun(ids: integer[]): boolean every one is added, and there is at least one
---@field TogglePinned fun(ids: integer[]) add them all, or take them all off when every one is added

-- Asides (Asides.lua, docs/design.md §2.11): one-line hints beside the journeys, never a route.
---@class AGFAside
---@field category? AGFRecommendationCategory the kind of useful hint
---@field reason? string why the provider offers this hint
---@field key string stable identity for Skip and Not interested, e.g. "trainer"
---@field text string the whole line, in the game's voice
---@field icon string an atlas the Forever client has (a row of the atlas CSV)
---@field place? AGFPlace where Go takes the player: only a place from the data

---@class AGFAsides
---@field Register fun(provider: fun(): AGFAside?) a domain's provider, asked in step 1's travel frame and never in combat; earlier ones win
---@field Refresh fun() asks every provider again, out of combat; listeners hear only when the shown aside changes
---@field Current fun(): AGFAside? the first answer neither skipped this session nor turned down for this character
---@field All fun(): AGFAside[] every answer neither skipped this session nor turned down, in registration order: the panel's lines
---@field OnChange fun(callback: fun())
---@field Skip fun(key: string) hide it until the next session
---@field Decline fun(aside: AGFAside) Not interested: hide it for this character, remembering its text
---@field Declined fun(): {key: string, text: string}[] the turned-down asides, by text, for Show again: its provider's answer now, else the saved text
---@field Restore fun(key: string) Show again: undo a Decline
---@field Go fun(aside: AGFAside): boolean to its place, as Guidance.Navigate; false without one
---@field Click fun(owner: Region, mouseButton: string, aside: AGFAside?)
---@field Enter fun(owner: Region, aside: AGFAside?)
---@field Open fun(owner: Region, aside: AGFAside) its menu: Go with a place, Skip, Not interested

---@class AGFNamespace
---@field Asides AGFAsides

---@class AGFRecommendation
---@field key string
---@field title string
---@field reason string
---@field icon? string|integer
---@field journey? string
---@field step? AGFStep
---@field aside? AGFAside

---@alias AGFRecommendationCategory "training"|"professions"

---@class AGFRecommendations
---@field Build fun(route: AGFRoute, asides: AGFAside[], player: AGFPlayer): AGFRecommendation[]
---@field Current fun(): AGFRecommendation[]
---@field ActionLabel fun(item: AGFRecommendation): string
---@field CanAct fun(item: AGFRecommendation): boolean
---@field Act fun(item: AGFRecommendation): boolean

---@class AGFNamespace
---@field Recommendations AGFRecommendations

---@class AGFPrefs
---@field asides? table<string, string> the asides this character turned down (Not interested): key -> the text it had

-- Skill- and reputation-gated quests (docs/design.md §2.4).

-- CMaNGOS RequiredSkill/Value: the skill line's rank must be at least `value`.
---@class AGFSkillGate
---@field id integer SkillLine ID
---@field value integer

-- CMaNGOS RequiredMin/MaxRep: the reputation (0 starts Neutral, 3000 Friendly, 42000 Exalted, the client's
-- FactionData.currentStanding) must be at least `min` and below `max`.
---@class AGFRepGate
---@field faction integer Faction ID
---@field min? integer
---@field max? integer

---@class AGFQuest
---@field skill? AGFSkillGate
---@field rep? AGFRepGate

---@class AGFData
---@field skills? table<integer, {name: string}> SkillLine ID -> its English name, for every quest's `skill`
---@field factions? table<integer, {name: string}> Faction ID -> its English name, for every quest's `rep`

---@class AGFPlayer
---@field skills? table<integer, integer> learned skill line -> rank; an absent line has rank 0
---@field reputation? fun(factionID: integer): integer? the standing on AGFRepGate's scale; nil when the client gives none

---@class AGFWhyNames
---@field skill? fun(skillLineID: integer): string?
---@field faction? fun(factionID: integer): string?
---@field standing? fun(reaction: integer): string? 1 Hated to 8 Exalted

---@class AGFState
---@field Reputation fun(factionID: integer): integer? C_Reputation's currentStanding; nil for a faction it gives none for
---@field SkillName fun(skillLineID: integer): string? the client's name for a learned skill line
---@field FactionName fun(factionID: integer): string?
---@field StandingName fun(reaction: integer): string? FACTION_STANDING_LABEL1-8

---@class AGFStrings
---@field WHY_SKILL string format: a skill line's name and the rank a quest needs
---@field WHY_REP_MIN string format: the standing and the faction a quest needs
---@field WHY_REP_BELOW string format: the standing a quest closes at, and the faction
---@field WHY_REPUTATION string format: a faction whose required value falls between standings

-- "Trainers": a step with no quests, and the class trainer's place.

-- Tweaks Forever's spells to train, as the planner and the trainer aside take them.
---@class AGFTraining
---@field count integer how many spells wait
---@field level integer the highest level among them, which the trainer must teach up to

---@class AGFPlayer
---@field train? AGFTraining set by Core while a journey is chosen: its route may stop at a trainer

---@class AGFModel
---@field Trainer fun(data: AGFData, player: AGFPlayer, level: integer): AGFNpc? the nearest class trainer of the player's class and side who teaches from level 1 up to `level`; nil when the data has none or the player has no place
---@field TownName fun(data: AGFData, place: {map: integer, hub?: string}, mapName?: AGFMapName): string the hub's town, else the map's name

---@class AGFIntegrations
---@field Training fun(): AGFTraining?, boolean Tweaks Forever's affordable spells to train, counted; nil without a v1+ Tweaks Forever, its answer, or an affordable spell to train
---@field Trainers fun(): AGFClassTrainer[]? Tweaks Forever's class trainers with their places (API v2), for a class the bundled trainer data does not place (Forever's extra combos); nil without a v2

---@class AGFStrings
---@field TRAINER_IN string format: the trainer aside's lead with the nearest trainer's town
---@field TRAIN_IN string format: a trainer step's title, its town
--[[ The diversion slot and your calling ]]

---@class AGFPlace
---@field trainer? integer a class quest's start only: the class its giver trains (1 Warrior ... 11 Druid)

---@class AGFStrings
---@field JOURNEY_CALLING string the calling card's title
---@field CALLING_QUESTS string format: how many class quests the player can take now
---@field CALLING_QUESTS_ONE string the same for one
---@field CALLING_TRAINER string format: the lead class quest's title, when the data proves its giver trains the player's class
---@field CALLING_TASK string format: the lead class quest's title, from any other giver
-- "NPC tooltip line" (Tooltip.lua, docs/design.md §2.9).

---@class AGFPlace
---@field npc? integer the creature entry of an NPC giver, the ID in its UnitGUID; nil for an object

---@class AGFStrings
---@field NPC_JOURNEY string format: the chosen journey's title, on a unit tooltip of an NPC its steps visit
-- "Something new" (Moments.lua, docs/design.md §2.13).

---@class AGFMoments
---@field Observe fun() step 1's travel frame, out of combat: what is offered joins the seen set; a look armed by a level or a zone marks what the set lacks
---@field IsNew fun(key: string): boolean the journey's card carries the "new" mark
---@field Unseen fun(): boolean something new since the guide last opened: the tab's and the compartment's pips
---@field Line fun(): string? the tracker's line, while unseen and its journey is still offered
---@field Opened fun() the guide shows: the pips and the tracker's line go
---@field Closed fun() the guide hides: the cards' marks go
---@field OnChange fun(callback: fun())

---@class AGFAsides
---@field Answers fun(): AGFAside[] every provider's last answer, skipped or not, in registration order

---@class AGFNamespace
---@field Moments AGFMoments
---@field OnMoment? fun(journey: boolean, aside: boolean) something new: glow the moment's line and/or the aside's; set by Tracker.lua

---@class AGFPrefs
---@field seen? table<string, boolean> journey keys this character has been offered, and "aside:<key>" while a provider gives it

---@class AGFStrings
---@field MOMENT string format: the tracker's line for a new journey: its zone's or dungeon's name
---@field MOMENT_OPEN string format: the tracker's line for a new way into an instance: the card's title

-- QuestieDB as a quest source (QuestieSource.lua, docs/design.md §2.14).

---@class AGFQuestieStatus
---@field state "unavailable"|"building"|"questie" provider unavailable, building, or ready
---@field settled boolean whether the deferred provider startup has completed
---@field version? string QuestieDB's version, once its quests are in use
---@field reason? string why QuestieDB is not used (an ns.L line); nil while it is, or before login

---@class AGFNamespace
---@field QuestieStatus AGFQuestieStatus

---@class AGFStrings
---@field AUDIT_SOURCE_BUNDLED string
---@field AUDIT_SOURCE_QUESTIE string format: QuestieDB's version
---@field AUDIT_QUESTIE_BUILDING string
---@field AUDIT_QUESTIE_UNUSED string format: one of the QUESTIE_ reasons
---@field QUESTIE_ABSENT string
---@field QUESTIE_CONTRACT string
---@field QUESTIE_FLAVOUR string
---@field QUESTIE_FIELD string format: the entity or field it lacks
---@field QUESTIE_ZONES string
---@field QUESTIE_FAILED string format: the error

-- "PvP" (docs/design.md §2.15) and unspent talent points.

-- A battleground open to the player (State.Battlegrounds, from C_PvP.GetLevelUpBattlegrounds).
---@class AGFBattleground
---@field id integer its BattlemasterList ID, which AGFNpc.bg shares (2 Warsong Gulch, 3 Arathi Basin)
---@field name string the client's name for it
---@field level integer the level it opened at

---@class AGFPlayer
---@field battlegrounds? AGFBattleground[] open to the player, the newest first; the opt-in card's choices

---@class AGFPrefs
---@field battlegrounds? boolean the opt-in Battlegrounds card (the guide's cog), off by default
---@field battled? integer the highest level this character has stood in a battleground at: the aside's acted on

---@class AGFModel
---@field Battlemaster fun(data: AGFData, player: AGFPlayer, bg: integer): AGFNpc?, integer? the nearest battlemaster of the player's side for battleground `bg`, and its creature entry; nil when the data places none or the player has no place

---@class AGFState
---@field Battlegrounds fun(): AGFBattleground[] open to the player, the newest first; empty without C_PvP.GetLevelUpBattlegrounds

---@class AGFAside
---@field renew? integer how often its provider found it news again (a talent point gained): a Skip for now holds while it is unchanged
---@field texture? integer|string a client texture (a reward's icon) drawn in place of `icon`, which stays the fallback

---@class AGFAsides
---@field RefreshOn fun(event: string) ask the providers again on the event, when the client has it

---@class AGFStrings
---@field BATTLEGROUND_OPEN string format: a battleground's name; the aside, and the new card's tracker line
---@field BATTLEGROUND_SUBLINE string the Battlegrounds card's subline
---@field BATTLEMASTER_IN string format: the battlemaster's town; the step's title and the card's reason
---@field BATTLEMASTER_QUEUE string format: the battleground's name; the battlemaster step's reason
---@field MENU_BATTLEGROUNDS string the guide's cog: the opt-in Battlegrounds card
---@field PVP_RANK_REWARD string format: the next rank with a reward, and the reward's description
---@field TALENT_POINTS string format: how many talent points wait to be spent
---@field TALENT_POINT string the same for one

--[[ "Professions" (Hints/Profession.lua, docs/design.md §2.16) ]]

-- A rank a trainer teaches and what its rank spell asks (npc_trainer reqlevel, reqskillvalue; the most any asks).
---@class AGFProfessionRank
---@field rank integer 1 Apprentice to 4 Artisan
---@field level integer
---@field skill integer

---@class AGFProfession
---@field name string SkillLine.DisplayName_lang (English), for a line the character has not learned
---@field secondary? boolean a secondary skill (First Aid, Cooking, Fishing), which takes no profession slot
---@field ranks AGFProfessionRank[] ascending; a rank no trainer teaches (from a book or quest) is absent

---@class AGFData
---@field professions? table<integer, AGFProfession> SkillLine ID -> its trainers' ranks, for each line a trainer here teaches

-- One reason to visit a profession trainer, in Model.Profession's order: "cap" a learned line at its rank's cap whose
-- next rank the player can train now, "slot" a free profession slot, "learn" a secondary skill they lack.
---@alias AGFProfessionNudgeKind "cap"|"slot"|"learn"

---@class AGFProfessionNudge
---@field key string the aside's: "profession:<skill>:<rank>", or "profession:slot"
---@field kind AGFProfessionNudgeKind
---@field rank integer the rank to train: the next for a cap, 1 (Apprentice) otherwise
---@field skill? integer the line, for a cap or a secondary skill
---@field skills? integer[] a free slot: the professions the player lacks and can learn now
---@field npc? AGFNpc the nearest trainer of that rank the data places for the player; nil when none

---@class AGFPlayer
---@field caps? table<integer, integer> learned skill line -> its rank's cap (C_SkillInfo maxRank)
---@field primaries? integer how many professions (SkillLine category 11) the character has; nil when unknown

---@class AGFModel
---@field Profession fun(data: AGFData, player: AGFPlayer, wanted?: fun(key: string): boolean): AGFProfessionNudge? the first nudge `wanted` takes, with its nearest trainer

---@class AGFAsides
---@field Wanted fun(key: string, renew?: integer): boolean neither skipped this session (at this `renew`) nor turned down: a provider offers the first it still wants

---@class AGFStrings
---@field PROFESSION_CAP string format: a line's name, its rank and its cap
---@field PROFESSION_RANK_IN string format: the next rank's name and the nearest trainer's town
---@field PROFESSION_RANK string format: the next rank's name, without a trainer the data places
---@field PROFESSION_SLOT string a free profession slot
---@field PROFESSION_SLOT_IN string format: the nearest profession trainer's town
---@field PROFESSION_LEARN_IN string format: a secondary skill's name and the nearest trainer's town
---@field PROFESSION_LEARN string format: a secondary skill's name, without a trainer the data places
---@field PROFESSION_LINE string format: the lead, then where to train
---@field PROFESSION_RANK_1 string
---@field PROFESSION_RANK_2 string
---@field PROFESSION_RANK_3 string
---@field PROFESSION_RANK_4 string

-- "Exploration and new lands" (Hints/Explore.lua, docs/design.md §2.11).

-- A zone map's explorable area (tools/gen_quests.py `overlays`): a WorldMapOverlay the client draws once explored.
---@class AGFOverlay
---@field area integer its AreaTable ID, for C_Map.GetAreaInfo
---@field name string its English name, the fallback when the client has none
---@field level integer its ExplorationLevel, never 0
---@field ox integer its offset, as GetExploredMapTextures returns it for an explored one
---@field oy integer
---@field x number its hit rectangle's centre on the map, for which is nearer only: never a place
---@field y number

-- A zone map Forever added (tools/diff_forever.py `lands`): its range and its flight masters.
---@class AGFLand
---@field name string its English name, the fallback when the client has none
---@field min integer the least non-zero ExplorationLevel of its areas
---@field max integer the greatest
---@field taxi AGFLandTaxi[] its Forever flight masters that serve a side, by node ID

---@class AGFLandTaxi : AGFPlace
---@field side integer 1 Alliance, 2 Horde

---@class AGFForever
---@field lands table<integer, AGFLand> uiMapID -> the land; only lands with a level range

---@class AGFData
---@field overlays? table<integer, AGFOverlay[]> zone uiMapID -> its explorable areas

---@class AGFExplore
---@field Explored fun(map: integer): table<string, true>? the map's explored overlays by "ox:oy"; nil without C_MapExplorationInfo
---@field Unexplored fun(data: AGFData, player: AGFPlayer, explored: table<string, true>): AGFOverlay? the area to suggest on the player's map
---@field NewLand fun(data: AGFData, player: AGFPlayer, explored: fun(map: integer): table<string, true>?): integer?, AGFLand?, AGFLandTaxi? the land to suggest, and where Go takes the player

---@class AGFNamespace
---@field Explore AGFExplore

---@class AGFStrings
---@field NEW_LAND string format: the land's name, its least and greatest level
---@field UNEXPLORED string format: the area's name

-- "Rest and pacing" (docs/design.md §2.17).

---@class AGFPlayer
---@field rested? integer rested XP (GetXPExhaustion, 0 with none); nil where the player's rest is unknown
---@field xpMax? integer the XP the level needs (UnitXPMax), when the client gives it
---@field resting? boolean in an inn or a city (IsResting): the last stop's rest line is ticked off

-- What Model.RestLow reads of the player: an AGFPlayer, or State's own read of the rest.
---@class AGFRest
---@field level integer
---@field maxLevel integer
---@field rested? integer
---@field xpMax? integer

---@class AGFModel
---@field RestLow fun(player: AGFRest): boolean rested XP under one bubble (a twentieth of the level), below the cap; false when unknown

---@class AGFStrings
---@field REST_HERE string the route's last stop, when rest is low and an innkeeper of the player's side stands there
---@field SETTING_WANDERER string hint strength: Wanderer names places and sets no waypoint, route or map mark
---@field SETTING_WANDERER_TOOLTIP string
---@field SETTING_FOLLOW_QUEST string walking into the route's quest area selects the quest (Focus.lua)
---@field SETTING_FOLLOW_QUEST_TOOLTIP string
---@field SETTING_ROUTE_ORDER string beta: the planned route order (chapter lead, town look-ahead, committed order)
---@field SETTING_ROUTE_ORDER_TOOLTIP string

---@class AGFNamespace
---@field Art AGFArt
---@field Overview AGFOverview
---@field Widgets AGFWidgets shared guide row and popup widgets

---@class AGFStrings
---@field TAB_JOURNEYS string
---@field TAB_ACTIVITIES string
---@field TAB_PROGRESS string
---@field NEXT_REASON_JOURNEY string
---@field NEXT_REASON_ASIDE string
---@field NEXT_REASON_TRAINING string
---@field NEXT_REASON_TALENTS string
---@field NEXT_REASON_PROFESSIONS string
---@field TAB_PROFESSIONS string
---@field SHOW_ON_MAP string
---@field NEXT_STEPS string
---@field OPEN_RECIPES string
---@field NEXT_RECIPES string
---@field REAGENTS string
---@field FROM_SKILLUP string the profession card's source tag
---@field PROFESSION_RANGE string format: from rank, to rank
---@field PROFESSION_RANGE_TITLE string format: rank, cap, the rank's title
---@field PROFESSION_BAR string format: rank, cap
---@field SEPARATOR string between the parts of a detail line
---@field RECIPE_COUNT string format: the recipe, how many crafts
---@field RECIPE_TRAIN_AT string format: the skill a recipe is trained at
---@field RECIPE_LEARNED string
---@field REAGENT_NEED string format: how many, the reagent
---@field REAGENT_HAVE string format: how many the bags and bank hold
---@field REAGENT_VENDOR string
---@field REAGENT_CRAFT string
---@field REAGENT_GATHER string
---@field REAGENT_AUCTION string
---@field CLICK_WAYPOINT_STEP string a profession step's tooltip, when SkillUp can route to it
---@field SKILLUP_MISSING string the Professions view without SkillUp Forever
---@field SKILLUP_OUTDATED string the Professions view with a SkillUp Forever too old for its API
---@field SKILLUP_NONE string the Professions view with no crafting profession to level

---@class AGFTownGiver
---@field key string
---@field name string
---@field text string
---@field pickups integer[]
---@field handins integer[]
---@field done boolean
---@field skipped boolean
---@field place AGFPlace

---@class AGFStep
---@field verb? "pickup"|"turnin"|"objective"|"town"|"trainer"|"battlemaster"
---@field orderKey? string stable identity of this visit, distinguishing repeat visits at a town
---@field questTitle? string undecorated objective quest title
---@field checklist? AGFTownGiver[]
---@field complete? boolean

---@class AGFAreaObjective
---@field type? string

---@class AGFPrefs
---@field customOrders? table<string, string[]>

---@class AGFOrderModule
---@field CanMove fun(from: integer, to: integer): boolean
---@field Move fun(from: integer, to: integer): boolean
---@field Reset fun()
---@field IsCustom fun(): boolean
---@field SkipGiver fun(stepKey: string, giverKey: string): boolean
---@field SkippedQuests fun(): table<string, integer[]>
---@field Dependencies fun(steps: AGFStep[]): table<integer, table<integer, boolean>>
---@field Valid fun(steps: AGFStep[], cap?: integer, log?: table<integer, AGFLogQuest>): boolean
---@field Merge fun(steps: AGFStep[], keys?: string[], cap?: integer, log?: table<integer, AGFLogQuest>): AGFStep[]

-- One rebuild's read of the client (Core.lua's BuildRoute): the route is planned from it, and it is kept beside the
-- cached route for the views that draw that route (ns.Snapshot). Read-only.
---@class AGFSnapshot
---@field player AGFPlayer
---@field completed table<integer, boolean>
---@field log table<integer, AGFLogQuest>

-- One build's snapshot of the player (Shown.Build): Core.lua reads the client once and every stage shares it.
---@class AGFShownInput
---@field dungeonEntrances? table<integer, AGFLocation> known instance entrance points
---@field data AGFData
---@field player AGFPlayer
---@field completed table<integer, boolean>
---@field log table<integer, AGFLogQuest>
---@field prefs AGFPrefs
---@field mapName? AGFMapName
---@field instanceName? fun(id: integer): string?
---@field last? AGFRoute the full route of the build before
---@field combat? boolean the cheap in-combat build (Model.Refresh), which needs `last`
---@field observe? fun(full: AGFRoute) called with the ordered route

---@class AGFShown
---@field Build fun(input: AGFShownInput): AGFRoute, AGFRoute
---@field Forget fun(journey: string)

---@class AGFSound
---@field ClientEvent fun()
---@field Complete fun(key: string, story?: boolean)
---@field Observe fun(previous: AGFRoute, current: AGFRoute, world: AGFSnapshot, trained?: boolean) the build's own snapshot, never a fresh read
---@class AGFHearth
---@field Advice fun(data: AGFData, player: AGFPlayer, steps: AGFStep[], bind?: string, locale?: string): AGFAside?

---@class AGFModel
---@field TownChecklist fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>, step: AGFStep, previous?: AGFStep, skipped?: table<string, boolean>)
---@field Visit fun(step: AGFStep): string the visit's identity: `orderKey`, else `key`
---@field GiverSkip fun(step: AGFStep, giverKey: string): string the skipped key of one giver on a town visit
---@field StepTitle fun(data: AGFData, log: table<integer, AGFLogQuest>, step: AGFStep)
---@class AGFNamespace
---@field Providers AGFProviders
---@field PvP AGFPvP
---@field Order AGFOrderModule
---@field Shown AGFShown
---@field Sound AGFSound
---@field Hearth AGFHearth

---@class AGFStrings
---@field TAB_PVP string
---@field GO_TO_ENTRANCE string
---@field TWEAKS_MISSING string
---@field TWEAKS_OUTDATED string
---@field ENTRANCE_UNKNOWN string
---@field LEGACY_MISSING string
---@field PVP_RANK string
---@field PVP_RANK_POINTS string
---@field PVP_UNRANKED string
---@field PVP_CAPPED string
---@field PVP_UNAVAILABLE string
---@field PVP_NO_BATTLEGROUNDS string
---@field PVP_NO_BATTLEMASTER string
---@field PVP_BATTLEGROUND_LEVEL string
---@field PVP_GO_BATTLEMASTER string
---@field PVP_NEXT_REWARD string
---@field GUIDE_OPEN string
---@field GUIDE_BACK string
---@field MENU_BACK string
---@field MENU_CHECKED string
---@field MENU_UNCHECKED string
---@field MENU_SUBMENU string
---@field GUIDE_OUTLINE string
---@field GUIDE_OUTLINE_TOOLTIP string
---@field GUIDE_PAGE string
---@field ORDER_DRAG string
---@field ORDER_SOONER string
---@field ORDER_LATER string
---@field ORDER_NEXT string
---@field ORDER_RESET string
---@field ORDER_CUSTOM string
---@field TOWN_SKIP_GIVER string
---@field TOWN_GIVER string
---@field TOWN_PICKUPS string
---@field TOWN_HANDINS string
---@field TOWN_COUNTS string
---@field TODAY_MORE string
---@field STOP_VISIT string
---@field SET_HEARTH string
---@field SETTING_STEP_SOUND string
---@field SETTING_STEP_SOUND_TOOLTIP string
---@field STEP_PICKUP string
---@field STEP_OBJECTIVE string
---@field STEP_COLLECT string
---@field STEP_DEFEAT string
---@field STEP_WORK string
---@field STEP_TOWN string
---@field STEP_BATTLEMASTER string
---@field UPDATED_TO string format: the version, then WHATS_NEW
---@field WHATS_NEW string this version's headline, printed once after an update
---@field SETTING_WHATS_NEW string
---@field SETTING_WHATS_NEW_TOOLTIP string
---@field SETTING_COMPANIONS string
---@field SETTING_COMPANIONS_TOOLTIP string
---@field SPF_MISSING string a route step's tooltip without Shortest Path Forever installed
---@field SPF_DISABLED string a route step's tooltip with Shortest Path Forever installed but not enabled
---@field SKILLUP_DISABLED string the Professions view with SkillUp Forever installed but not enabled
---@field SKILLUP_ABSENT string the Professions view without SkillUp Forever, companion hints off
---@field LEGACY_DISABLED string the Progress page with Legacy Forever installed but not enabled

---@alias AGFCompanionState "loaded"|"disabled"|"missing"

---@class AGFCompanions
---@field State fun(addon: string): AGFCompanionState loaded, installed but not loaded, or not installed
---@field Hint fun(addon: string): string? the line naming what the companion adds, while it isn't loaded and hints are on

---@class AGFNamespace
---@field WhatsNew fun() on login: print WHATS_NEW once if the version changed since the last one seen
---@field Companions AGFCompanions

---@class AGFModel
---@field ObjectiveDone fun(data: AGFData, entry?: AGFLogQuest, slot: integer): boolean

---@class AGFEntranceGate
---@field trigger integer
---@field level integer
---@field items? integer[] alternatives; possession of either satisfies the item gate
---@field quest? integer
---@field conditional? boolean server condition the addon cannot establish

---@class AGFInstance
---@field lfg? integer LFGDungeons.ID for client recommended levels
---@field name string
---@field raid? boolean
---@field entrances? AGFEntranceGate[]
---@field low? integer published recommended level
---@field high? integer published recommended level

---@class AGFModel
---@field QuestXP fun(quest: AGFQuest, level: integer): number?

---@class AGFNamespace
---@field Dungeons AGFDungeons
---@field DungeonEntrance fun(instance: integer): AGFPoint?

---@class AGFStrings
---@field DUNGEON_PICKUP string

---@alias AGFMapLookup fun(area: integer): integer?
---@alias AGFYield fun()
---@alias AGFQuestieReads {Npc: table<integer, table|false>, Object: table<integer, table|false>, Item: table<integer, table|false>}

---@class AGFQuestieNpcRow one Npc's place and service fields for a catalogue build
---@field name string
---@field spots AGFPoint[]
---@field home integer? the uiMapID the NPC is most common on
---@field inn boolean QuestieDB's innkeeper flag
---@field trains boolean QuestieDB's trainer flag
---@field side integer? 1 Alliance, 2 Horde, 3 both, nil neither

---@class AGFNamespace
---@field QuestieTowns AGFQuestieTowns
---@field QuestieObjectives fun(lib: AGFQuestieDB, objectives: table?, trigger: table?, zone: integer?, data: AGFData, mapOf: AGFMapLookup, yield: AGFYield, questID: integer, reads: AGFQuestieReads): table?, AGFObjectiveArea[]?, table?, boolean?

---@class AGFStrings
---@field WHY_PROVIDER string

---@class AGFNamespace
---@field SourceHint fun(): string?
---@class AGFQuestieStatus
---@field catalogueCount? integer
---@field questCount? integer
---@class AGFStrings
---@field QUESTIE_ENABLE string
---@field QUESTIE_POLICY string

---@class AGFWidgets
---@field GuideOutline fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, journey: AGFJourney, steps: AGFStep[]): integer[]

---@class AGFStrings
---@field DUNGEON_BOSSES_LOOT string

---@class ForeverTrackerSettings
---@field attached boolean
---@field x? number
---@field y? number

---@class ForeverTrackerNamespace
---@field TrackerHost? ForeverTrackerHostAPI
---@field TrackerHostSettings? fun(): ForeverTrackerSettings
---@field L table<string, string>

---@class AGFIndex
---@field ids integer[]
---@field dungeons integer[] dungeon quest IDs in the same stable order as ids
---@field dungeonsByLevel table<integer, integer[]> dungeon IDs that are open by level
---@field choicesByLevel table<integer, table<string, integer[]>> non-grey quest IDs by side, level, race and class
---@field starts table<integer, integer[]> quest IDs by pickup map
---@field groups table<integer, integer[]>
---@field sides table<integer, integer[]> by side, the IDs a player of it could ever take: its own side's or both
---sides', with a start the data places, not repeatable (Check's first lines)

---@class AGFChains
---@field prev table<integer, integer|false>
---@field stories table<integer, AGFStory|false>

-- `continent` is the world map ID when the data places the map on the Azeroth map (`known`). A map it doesn't is an
-- island of its own, measured in map units, so its steps still order among themselves but never against the rest.
-- `docks` are the crossings the player's side can take, shared by every position of one plan.

---@class AGFPosition
---@field x number
---@field y number
---@field continent integer|string
---@field known boolean
---@field docks? AGFFrameCrossing[]

-- One direction of an AGFCrossing, its docks in the shared frame.

---@class AGFFrameCrossing
---@field from integer
---@field to integer
---@field leave {x: number, y: number}
---@field land {x: number, y: number}

-- The areas a card's quests are done in and the first node of each, which a lap's pickups join.
---@class AGFPlanAreas
---@field areas AGFStep[]
---@field anchors table<AGFStep, AGFNode>

---@class AGFAnchor
---@field key string the town's key ("town:<hub>"), or "" for the stops no town reaches, swept around the player
---@field place {map: integer, x: number, y: number} the town's point
---@field pos? AGFPosition
---@field open? AGFStep the town's visit that hands out its quests and takes its finished ones
---@field stops AGFStep[] the areas and stops its laps go out to
---@field hands integer[] the quests a lap hands in back there, once all their objectives are done

---@class AGFLapState
---@field data AGFData
---@field player AGFPlayer
---@field completed table<integer, boolean>
---@field log table<integer, AGFLogQuest>
---@field plan AGFPlanAreas
---@field mapName? AGFMapName
---@field leadID? integer
---@field join? fun(selected: AGFStep[])
---@field card string
---@field docks AGFFrameCrossing[]
---@field hub string? the town the player stands in, its areas' own
---@field origin AGFPosition
---@field planned boolean
---@field rank table<string, integer>
---@field ranked table<integer, integer> each quest's first place in the committed order among its work's areas
---@field skipped table<string, boolean>
---@field pinned table<integer, boolean>
---@field where table<table, AGFPosition|false>
---@field at fun(place: table): AGFPosition?
---@field towns AGFStep[]
---@field others AGFStep[]
---@field groups AGFStep[]
---@field areas AGFStep[]
---@field picks table<integer, AGFStep>
---@field ids integer[]
---@field nodes table<integer, AGFNode[]>
---@field offered table<string, integer[]>
---@field ratio table<integer, number>
---@field anchors table<string, AGFAnchor>
---@field list AGFAnchor[]
---@field pending table<integer, integer>
---@field cap number
---@field count integer
---@field picked table<integer, true>
---@field route AGFStep[]
---@field order? AGFOrder
---@field ordered {step: AGFStep, pickups?: integer[], handins?: integer[]}[] each step of `order` as it was committed

---@class AGFLapWalk
---@field done table<integer, integer>
---@field handed table<integer, boolean>
---@field reached table<AGFAnchor, boolean>
---@field lastAnchor? AGFAnchor

---@class AGFLapChoice
---@field step? AGFStep|AGFAnchor
---@field anchor? AGFAnchor
---@field kind? "open"|"stop"|"close"
---@field rank? number
---@field value? number
---@field key? string

---@class AGFNamespace
---@field Planner AGFPlanner

-- Internal planner seams. Public callers use Model; these functions are cached by each planner file at load time.
---@class AGFPlanner
---@field State AGFPlannerState
---@field Eligibility AGFPlannerEligibility
---@field Travel AGFPlannerTravel
---@field Zones AGFPlannerZones
---@field Steps AGFPlannerSteps
---@field Services AGFPlannerServices
---@field Routing AGFPlannerRouting
---@field Laps AGFPlannerLaps
---@field Journeys AGFPlannerJourneys
---@field Decoration AGFPlannerDecoration
---@field Plan AGFPlannerPlan

-- Caches for the full build under way, shared by its cards across coroutine yields; absent outside Plan.
---@class AGFPlannerState
---@field skippedSeen? table<string, boolean>
---@field committedOrders? table<string, AGFOrder>
---@field planDocks? {data: AGFData, [integer]: AGFFrameCrossing[]}
---@field heldHere? string

---@alias AGFLocation {map?: integer, x?: number, y?: number}
---@alias AGFMapName fun(map: integer): string?

---@class AGFPlannerEligibility
---@field Dropped fun(id: integer): boolean
---@field Eligible fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>, id: integer, groups: table<integer, integer[]>): boolean
---@field Index fun(data: AGFData): AGFIndex
---@field ORANGE integer
---@field ReadDropped fun(prefs: AGFPrefs, skippedQuests?: table<string, integer[]>)
---@field SimpleOpen fun(quest: AGFQuest, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>, id: integer): boolean

---@class AGFPlannerTravel
---@field CLOSE number
---@field UNKNOWN number
---@field Cost fun(a?: AGFPosition, b?: AGFPosition): number
---@field CostTo fun(a: AGFPosition?, bx: number?, by: number, bContinent: integer|string, bKnown: boolean): number
---@field Distance fun(a: AGFLocation?, b: AGFLocation): number
---@field Docks fun(data: AGFData, side: integer): AGFFrameCrossing[]
---@field Gap fun(a: AGFPosition?, ra: number, b: AGFPosition?, rb: number): number
---@field Oversea fun(data: AGFData, a: AGFLocation, b: AGFLocation): boolean
---@field Point fun(data: AGFData, place: AGFLocation?): number?, number, integer|string, boolean
---@field Position fun(data: AGFData, place: AGFLocation?, docks?: AGFFrameCrossing[]): AGFPosition?
---@field Yards fun(a: {x: number, y: number}, b: {x: number, y: number}): number

---@class AGFPlannerZones
---@field Choices fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>, index: AGFIndex, prefs: AGFPrefs, far: (fun(map: integer): number)): integer[], integer[]
---@field Far fun(data: AGFData, player: AGFPlayer): fun(map: integer): number
---@field InZone fun(zone?: integer): fun(quest: AGFQuest): boolean
---@field OutdoorElite fun(quest: AGFQuest): boolean?

---@class AGFPlannerSteps
---@field Count fun(one: string, many: string, count: integer): string
---@field Describe fun(data: AGFData, log: table<integer, AGFLogQuest>, player: AGFPlayer, step: AGFStep)
---@field Enter fun(data: AGFData, step: AGFStep, from?: AGFPosition)
---@field Gather fun(data: AGFData, areas: AGFStep[], anchors: table<AGFStep, AGFNode>, steps: AGFStep[], node: AGFNode, id: integer, title: string, kind: AGFStepKind, optional: boolean?, near: (fun(a: AGFNode, b: AGFNode): boolean), planned?: boolean): AGFStep
---@field GreyRisk fun(level: integer, player: AGFPlayer): boolean
---@field Hub fun(place: AGFPlace): string
---@field Inside fun(yards: number, a: AGFNode, b: AGFNode): boolean
---@field Locate fun(data: AGFData, step: AGFStep, mapName?: AGFMapName)
---@field LogSteps fun(data: AGFData, player: AGFPlayer, log: table<integer, AGFLogQuest>, ready: table<integer, AGFPlace>, belongs: (fun(id: integer, place?: AGFLocation): boolean), stops: table<string, AGFStep>, steps: AGFStep[], plan: AGFPlanAreas): table<integer, AGFStep|false>
---@field Nodes fun(data: AGFData, entry: AGFLogQuest): AGFNode[]
---@field Opens fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>, step: AGFStep)
---@field Optional fun(quest: AGFQuest?, level: integer, player: AGFPlayer): boolean?
---@field PickupSteps fun(data: AGFData, eligible: integer[], wanted: (fun(quest: AGFQuest): boolean), steps: AGFStep[], stops?: table<string, AGFStep>)
---@field Planned fun(quest: AGFQuest, id: integer): AGFNode[]
---@field QuestLevel fun(data: AGFData, log: table<integer, AGFLogQuest>, player: AGFPlayer, id: integer): integer
---@field Ready fun(data: AGFData, log: table<integer, AGFLogQuest>): table<integer, AGFPlace>
---@field Tell fun(area: AGFStep)
---@field TownPoint fun(data: AGFData, step: AGFStep, from?: AGFPosition)
---@field Trim fun(town: AGFStep, handins: integer[], pickups: integer[])
---@field Visit fun(stops: table<string, AGFStep>, steps: AGFStep[], place: AGFPlace, list: "handins"|"pickups", id: integer): AGFStep

---@class AGFPlannerServices
---@field Rest fun(data: AGFData, player: AGFPlayer, steps: AGFStep[])
---@field TrainerSteps fun(data: AGFData, player: AGFPlayer, prefs: AGFPrefs, key: string): AGFStep[]

---@class AGFPlannerRouting
---@field HandInOnly fun(step: AGFStep): boolean
---@field Build fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>, candidates: AGFStep[], prefs: AGFPrefs, mapName?: AGFMapName, lead?: AGFStep, join?: (fun(selected: AGFStep[]))): AGFStep[]
---@field Ident fun(step: AGFStep|AGFAnchor): string
---@field Idents fun(route: AGFStep[]): string[]
---@field NearAction fun(from?: AGFPosition, log: table<integer, AGFLogQuest>, steps: AGFStep[], at: (fun(step: AGFStep): AGFPosition?)): AGFStep? the ready hand-in or pickup beside the player that goes before the head, or nil
---@field Recommit fun(route: AGFStep[], rank: table<string, integer>): AGFStep[]
---@field Stabilise fun(route: AGFStep[], plain: AGFStep[], rank: table<string, integer>, holds: (fun(steps: AGFStep[]): boolean), at: (fun(step: AGFStep): AGFPosition?), origin: AGFPosition): AGFStep[]

---@class AGFPlannerLaps
---@field Laps fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>, candidates: AGFStep[], plan: AGFPlanAreas, prefs: AGFPrefs, mapName: AGFMapName?, leadID: integer?, join: (fun(selected: AGFStep[]))?, card: string): AGFStep[]?

---@class AGFPlannerJourneys
---@field Added fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>, prefs: AGFPrefs, elsewhere: (fun(quest: AGFQuest): boolean)): integer[]
---@field Carry fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>, ready: table<integer, AGFPlace>, prefs: AGFPrefs, mapName: AGFMapName?, added: integer[]): AGFJourney?
---@field Summarise fun(journey: AGFJourney)

---@class AGFPlannerDecoration
---@field FinishRoute fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>, route: AGFRoute, last: AGFRoute?, prefs: AGFPrefs)

---@class AGFPlannerPlan
---@field Route fun(journeys: AGFJourney[], prefs: AGFPrefs): AGFRoute

---@class AGFModel
---@field Nearest fun(from: AGFPosition?, stops: AGFStep[], at: (fun(step: AGFStep): AGFPosition?), group?: (fun(step: AGFStep): unknown)): AGFStep[]

---@class AGFDungeonRow : Button
---@field Title FontString
---@field Info FontString
---@field Giver FontString
---@field Selected AGFArtSlice
---@field Map Button
---@field Expand AGFCollapseButton
---@field value? table

---@class AGFDataProvider
---@field GetSize fun(self: AGFDataProvider): integer
---@field Find fun(self: AGFDataProvider, index: integer): table?

---@class AGFScrollBoxListMixin
---@field GetDerivedScrollOffset fun(self: AGFScrollBoxListMixin): number
---@field ScrollToOffset fun(self: AGFScrollBoxListMixin, offset: number)
---@field SetDataProvider fun(self: AGFScrollBoxListMixin, provider: AGFDataProvider, retainScrollPosition?: boolean)
---@field GetVerticalScroll fun(self: AGFScrollBoxListMixin): number the ScrollFrameTemplate accessor the list keeps for its callers
---@field SetVerticalScroll fun(self: AGFScrollBoxListMixin, value: number)

---@class AGFScrollBox : Frame, AGFScrollBoxListMixin

---@class AGFDungeonListWidget
---@field frame AGFScrollBox
---@field scrollBox AGFScrollBox
---@field scrollBar Frame
---@field rows AGFDungeonRow[]
---@field values table[]
---@field tops number[]
---@field heights number[]
---@field height number
---@field rowHeight number
---@field headingHeight number
---@field paint fun(row: AGFDungeonRow, value: table)

-- The public surface (Core/API.lua, docs/api.md).
---@class AGFAPIStop
---@field map integer uiMapID
---@field x number normalized 0-1
---@field y number normalized 0-1
---@field name string the town, else the step's busiest giver, zone or title
---@field isTown boolean
---@field handins integer quests the route hands in there
---@field pickups integer quests the route picks up there

---@class AGFAPI
---@field version integer
---@field CurrentStop fun(): AGFAPIStop?
---@field NextStops fun(limit?: integer): AGFAPIStop[]?

---@class AGFGlobal
---@field API AGFAPI

---@type AGFGlobal
AdventureGuideForever = nil

---@class AGFStoryCompletion
---@field Record fun(questID: integer): boolean true only for a new proven final turn-in

---@class AGFNamespace
---@field StoryCompletion AGFStoryCompletion

---@class AGFPrefs
---@field completedStories table<string, {key: string, title: string, quest: integer}> proven story milestones for this character

---@class AGFStrings
---@field QUEST_VISIT_WARNING string

---@class AGFOverview
---@field VisitWarning fun(journey: AGFJourney, player?: AGFPlayer): string?

---@class AGFNamespace
---@field DungeonLoot {Bosses: fun(instance: integer): AGFLootBoss[], string?}

---@class AGFStrings
---@field DUNGEON_LOOT_INSTALL string
---@field DUNGEON_LOOT_COMBAT string
---@field ITEM_LOADING string
---@field DUNGEON_LOOT_UNKNOWN string
---@field JOURNEY_QUESTS string
---@field JOURNEY_CHOICES string
---@field JOURNEY_CHOOSE string
---@field JOURNEY_PROGRESS_EMPTY string
---@field LEGACY_PROGRESS_LINK string
---@field LEGACY_PROGRESS_NOTE string

---@class AGFDungeonRow
---@field Icon Texture
---@field Ring AGFRingIcon

---@class AGFDungeonRow
---@field journey? AGFJourney

---@class AGFJourneyBanner : AGFWindowCard
---@field journey? AGFJourney
