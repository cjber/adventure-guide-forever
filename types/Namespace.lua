---@meta

-- The client passes this same table to each TOC file; no runtime import is available.

-- One bundled quest (Data/Quests.lua). Coordinates are uiMapID plus normalized 0-1 x/y.
---@class AGFPlace
---@field map integer uiMapID
---@field x number
---@field y number
---@field name string NPC or object name
---@field hub? integer the town it stands in (tools/gen_quests.py town_hubs); nil when its map has no world rectangle

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
---@field dungeon? integer instance Map.ID (not a uiMapID) when the quest is filed under a dungeon or raid
---@field raid? boolean the instance is a raid
---@field elite? boolean group quest

---@class AGFData
---@field build string client build the data was generated for
---@field source string where the data came from, for /agf audit
---@field quests table<integer, AGFQuest>
---@field zones table<integer, {name: string, min: integer, max: integer}> uiMapID -> zone name and level range
---@field instances table<integer, {name: string}> instance Map.ID -> its English name, for every quest's `dungeon`
---@field maps table<integer, AGFMapCentre> uiMapID -> where the map sits in the world, for every map a place uses
---@field continents table<integer, AGFContinentShift> continent -> its place on the Azeroth world map
---@field crossings AGFCrossing[] every boat and zeppelin between two continents
---@field hubs table<integer, {name: string}> hub -> its flight master's name, verbatim; only for hubs with one

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
---@field journey? string key of the journey card the player chose; nil (or gone) = none chosen, every card whole
---@field skipped table<string, boolean> step keys skipped this session
---@field last? {key: string, reason: string} step 1 at the last rebuild, for the next login's resume line
---@field waypoint? {map: integer, x: number, y: number} the native waypoint the last Go set, while it may still be ours
---@field guided? string the key of the chosen journey whose route AGF started, while that guidance should run

-- "hub" is a town's stop (its pickups and agreeing hand-ins), "turnin" a hand-in at the client's waypoint, and
-- "objective" or "dungeon" (a group quest) the log's quests under way.
---@alias AGFStepKind "hub"|"turnin"|"objective"|"dungeon"|"trainer"

---@class AGFStep
---@field key string stable identity for skips and the resume line, e.g. "hub:61" or "turnin:4581"
---@field kind AGFStepKind
---@field title string e.g. "Turn in: Bathran's Hair", "Pick up quests: Guard Parker" or "Lakeshire, Redridge"
---@field detail string grey second line, e.g. "2 to hand in, 4 to pick up"
---@field reason string short why, e.g. "continues chain"
---@field quests integer[] quest IDs this step covers; a town's hand-ins first, then by ID
---@field hub? integer a town's hub (AGFPlace.hub); nil for a town the generator could not place
---@field pickups? integer[] a town's eligible quests this card wants there, ascending
---@field handins? integer[] a town's finished log quests handed in there, ascending
---@field givers? string[] a town's distinct NPC and object names, in `quests` order
---@field group? integer how many of a town's quests are elite, dungeon or raid
---@field spots? table<integer, AGFPlace> a town's quest ID -> its start or finish there; the point is one of them
---@field map integer
---@field x number
---@field y number
---@field place? string the town's name, else its busiest giver; a turn-in's NPC only where its waypoint agrees; a trainer's NPC
---@field zone? string the client's name for `map`, else the data's
---@field optional? boolean elite/group or outside the player's level band
---@field chapter? string the story card's chapter line, on the step that takes the chain up

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

---@alias AGFJourneyKind "carry"|"story"|"nextzone"|"dungeon"|"calling"

-- A quest's place in its chain (Model.Story): the data's `next` links from the chain's head. Later members are IDs
-- only, so no later chapter's title is ever drawn.
---@class AGFStory
---@field chapter integer this quest's place in the chain, from 1
---@field total? integer the chain's length, only when the data proves where it ends
---@field members integer[] the chain's quest IDs in order, the head first

-- One card in the guide (docs/design.md §2.2): only steps the player can take now.
---@class AGFJourney
---@field kind AGFJourneyKind
---@field key string stable identity for prefs.journey: "carry", "zone:<uiMapID>" (a zone's story or next-zone card alike), "dungeon:<Map.ID>" or "calling"
---@field title string e.g. "Finish what you carry" or "Westfall story"
---@field subline string e.g. "3 ready to hand in, 1 in progress"
---@field reason? string why this journey, when there is an honest answer
---@field map integer where its first step is: choosing the card turns the world map there
---@field steps AGFStep[] never more than MAX_STEPS, in route order
---@field story? AGFStory the story card's chain, when the zone has one the player can take up now
---@field count? string a zone card's count of quests, the story card's subline once its chapter is skipped
---@field hub? string its first stop's place, else that stop's title: the card's line 3 when it has no reason
---@field more? integer how many stops follow the first (Model.Journeys sets it and `group` once the card is built)
---@field group? integer how many of its quests are elite, dungeon or raid (the sum of its steps' `group`)

---@class AGFRoute
---@field journeys AGFJourney[] at most 3: carry, the zone's story, then the diversions (calling, dungeon, next zone) newest first
---@field journey? string the key of the journey whose steps these are: the chosen one, else the first
---@field chosen boolean the player chose `journey`; false while the route falls back to the first card
---@field steps AGFStep[] that journey's steps, never more than MAX_STEPS
---@field skipped? table<string, boolean> the skipped keys a full build still had a step for; nil after the combat one

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
---@field MAX_JOURNEYS integer the cards a route holds and the panel draws
---@field IsGray fun(questLevel: integer, playerLevel: integer): boolean
---@field Eligible fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>, questID: integer): boolean
---@field Why fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>, questID: integer, names?: AGFWhyNames): AGFWhyLine[] every requirement, met or not; eligible exactly when all are met
---@field Search fun(data: AGFData, player: AGFPlayer, query: string, title?: fun(questID: integer): string?): integer[] up to 10 quest IDs whose title holds `query`, by title
---@field Givers fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>, mapID: integer): AGFGiver[]
---@field Story fun(data: AGFData, questID: integer): AGFStory? the chain the quest belongs to; nil when it is in none, or the way back forks
---@field Journeys fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>, prefs: AGFPrefs, mapName?: (fun(map: integer): string?), instanceName?: (fun(id: integer): string?)): AGFJourney[]
---@field Plan fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>, prefs: AGFPrefs, mapName?: (fun(map: integer): string?), instanceName?: (fun(id: integer): string?)): AGFRoute
---@field Yards fun(data: AGFData, a: {map: integer, x: number, y: number}, b: {map: integer, x: number, y: number}): number? yards between two places on one continent the data places; nil otherwise
---@field Refresh fun(data: AGFData, player: AGFPlayer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>, prefs: AGFPrefs, last: AGFRoute, mapName?: fun(map: integer): string?): AGFRoute the cheap in-combat rebuild: the log's steps fresh, the rest from `last`

---@class AGFState
---@field Player fun(): AGFPlayer
---@field Completed fun(): table<integer, boolean>
---@field Log fun(): table<integer, AGFLogQuest>
---@field OnChange fun(callback: fun())
---@field OnInitialLogin fun(callback: fun()) called on a login's PLAYER_ENTERING_WORLD, never on a /reload
---@field Ready fun(): boolean completion data has loaded
---@field MapName fun(map: integer): string? the client's localised map name, nil when it has none
---@field InstanceName fun(id: integer): string? the client's localised name for an instance Map.ID, nil when it has none
---@field QuestTitle fun(questID: integer): string? the client's cached title, nil until it has one
---@field RaceName fun(raceID: integer): string?
---@field ClassName fun(classID: integer): string?

-- Shortest Path Forever's public API, mirrored field for field from its types/API.lua (SPFAPIStop, SPFPublicAPI) at
-- the sha tests/contract_spec.lua pins; that spec fails on any drift. Integrations.lua's REQUIRED lists exactly
-- the non-optional functions. Descriptions go after `--` so the type is the whole first token. The members a
-- Shortest Path before 1.2 lacks are optional here, and checked where they are used.
---@alias AGFSPFMode "walk"|"flight"|"boat"|"zeppelin"|"lift"|"tram"|"portal"|"passage"
---@alias AGFSPFNoRoute "combat"|"invalid"|"unreachable" -- why an estimate has no answer
---@alias AGFSPFEnded "arrived"|"cleared"|"replaced"|"cancelled" -- reached the last stop; the player cleared it; another journey took over; the owner's own Cancel

---@class AGFSPFStop
---@field map integer -- uiMapID
---@field x number -- normalized 0-1
---@field y number -- normalized 0-1
---@field title? string

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
---@field Navigate fun(owner: string, map: integer, x: number, y: number, title?: string): boolean -- starts or replaces guidance
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
---@field version integer 1
---@field TrainableSpells fun(): AGFTFSpell[]? the spells the player's level allows and they haven't learned; nil before login and in combat

---@class AGFIntegrations
---@field TravelLine fun(step: AGFStep): string? asks Shortest Path now, at most one call: "Fly to X · N min" from EstimateDetail, "About N min away" from Estimate, nil without either or an answer
---@field RefreshTravel fun() refetches step 1's line; Core runs it in the frame after each rebuild
---@field Travel fun(step: AGFStep): string? the last line fetched for this step, without asking again
---@field TravelMinutes fun(step: AGFStep): integer? the whole trip's minutes, fetched with that line
---@field OnTravelChange fun(callback: fun())
---@field Navigate fun(step: AGFStep|AGFGiver): boolean route there with Shortest Path, else (declined or absent) the native waypoint where the map allows one; true when something now guides
---@field OnGuidanceChange fun(callback: fun()) called after every Go that guides and every Stop
---@field ReplacesJourney fun(): boolean Go would replace a Shortest Path journey someone else started (needs Active)
---@field Cancel fun() Stop: cancels our Shortest Path journey, and clears the native waypoint only while it is ours
---@field Owns fun(): boolean Go's guidance is still running: our Shortest Path journey (guided or held), or the waypoint Go set
---@field Guiding fun(): boolean Shortest Path is walking our multi-stop route and draws its own numbered stops; held (its "Guide me" off) is not guiding
---@field Guided fun(): (AGFStep|AGFGiver)[] the stops it walks, while it guides; empty otherwise
---@field Stopped fun(): string? the chosen journey whose route the player cleared or another journey replaced, until something is handed again
---@field Arrived fun(): boolean our journey reached its last stop, and nothing was handed since
---@field Restore fun(steps: AGFStep[]): boolean hands Shortest Path the chosen journey's steps again after a /reload; never the waypoint
---@field Stale fun(handed: AGFStep[], index: integer, steps: AGFStep[], far?: fun(a: AGFStep, b: AGFStep): boolean): boolean the guidance handed to Shortest Path no longer matches the journey's steps
---@field Provider fun(): string? name of the addon navigating, for copy ("Shortest Path")
---@field RefreshCards fun(journeys: AGFJourney[]) the cards shown: drops other answers, asks for up to 3 stale, one a frame
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
---@field AUDIT_BUILD string format: data build, client version, client build
---@field AUDIT_COUNTS string format: bundled, eligible and completed counts
---@field AUDIT_NOT_READY string
---@field HELP_OPEN string
---@field HELP_AUDIT string
---@field HELP_DUMP string
---@field HAND_IN_WHEN string format: zone name; the reason on a turn-in the route leaves for another continent
---@field NO_WAYPOINT string the error Go shows when nothing can guide the player on the step's map
---@field GO string the step menu's entry that starts guidance
---@field REPLACES_JOURNEY string Go's tooltip line while someone else's Shortest Path journey runs
---@field STOP string ends the guidance Go started
---@field SHOW_QUEST string opens a log quest in Blizzard's details
---@field SKIP string hides the step for this session
---@field SKIPPED string format: how many steps are skipped this session
---@field SHOW_AGAIN string format: a skipped step's title
---@field CHOOSE_JOURNEY string opens the guide
---@field CHOOSE_TO_SEE_STEPS string under the cards while none is chosen
---@field SHOW_EVERY_JOURNEY string the chosen card's tooltip: clicking it again chooses none
---@field STOP_AND_SHOW_EVERY_JOURNEY string the same while the route it started runs, which the click stops
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
---@field TRAVEL_WALK string format: the place a leg ends; one per AGFSPFMode
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
---@field TRAINER string
---@field TRAINER_SPELLS string format: spell count
---@field TRAINER_SPELL string
---@field TRAINER_LINE string format: TRAINER, then the spell count
---@field TRACKER_HEADER string
---@field TRACKER_UNATTACHED string
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
---@field STEP_NUMBERED string format: route index, step title
---@field QUEST_LEVEL string format: quest level, quest title
---@field MENU_QUESTS string
---@field MENU_DUNGEONS string
---@field MENU_MAP_PINS string
---@field MENU_GIVERS string
---@field MENU_TRACKER string
---@field MENU_MORE_SETTINGS string
---@field SETTING_TRACKER string
---@field SETTING_TRACKER_TOOLTIP string
---@field SETTING_MAP_PINS string
---@field SETTING_GIVERS string
---@field SETTING_DUNGEONS_DEFAULT string
---@field SETTING_MAP_PINS_TOOLTIP string
---@field SETTING_GIVERS_TOOLTIP string
---@field SETTING_DUNGEONS_DEFAULT_TOOLTIP string
---@field SETTING_TITLE_ROUTE string
---@field SETTING_TITLE_ROUTE_TOOLTIP string
---@field SETTING_TRACK_ROUTE string
---@field SETTING_TRACK_ROUTE_TOOLTIP string
---@field SETTING_UNTRACK_OTHERS string
---@field SETTING_UNTRACK_OTHERS_TOOLTIP string
---@field JOURNEY_CARRY string
---@field JOURNEY_STORY string format: zone name
---@field JOURNEY_NEXT_ZONE string format: zone name
---@field NEXT_ZONE_LEVEL string format: the level the next zone fits
---@field DUNGEON_QUESTS string format: quest count
---@field DUNGEON_QUESTS_ONE string
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
---@field SEARCH_QUESTS string the search box's instructions
---@field SEARCH_NONE string a search that finds no quest

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
---@field Choose fun(key?: string, start?: boolean) choose a journey, or none; `start` sets off on the rebuild with its steps
---@field StartRoute fun(step?: AGFStep): boolean guidance along the chosen journey (choosing the route's own when none is); waits out combat with Shortest Path
---@field Stop fun() the player's Stop: our route stops and the choice clears
---@field Paused fun(): boolean the chosen journey has steps but its route stopped: its card and the tracker title resume it
---@field StartPending fun(): boolean a start waits for combat's end
---@field Settling fun(): boolean a rebuild or step 1's travel line is due, whose frames take no card estimate
---@field PanelShown? fun(): boolean whether the guide is open, set once Blizzard_WorldMap has loaded
---@field Skip fun(key: string, title: string) hide a step for this session; the menu offers it back by its title
---@field Unskip fun(key: string) Show again: a skipped step or a journey not wanted
---@field Skipped fun(): AGFSkipped[] this session's skipped steps in skip order, then the journeys not wanted, by title
---@field Resume fun(step: AGFStep): string? the reason saved last session, while the resume line stands for this step
---@field InLog fun(step: AGFStep): boolean the step is a quest in the player's log (a turn-in or its objectives)
---@field Menu AGFMenuModule
---@field ShowQuest fun(step: AGFStep): boolean open a log step's quest in Blizzard's details; false for other steps or in combat
---@field TurnedIn fun(questID: integer) QUEST_TURNED_IN: latched so a chosen journey that ends there is complete, then OnTurnIn
---@field OnJourneyComplete? fun() a turn-in ended the chosen journey; set by Tracker.lua
---@field OnTurnIn? fun(questID: integer) QUEST_TURNED_IN: the chapter-end fanfare when the quest ends a proven chain; set by Tracker.lua
---@field TrackRouteQuests fun() track the route's log quests; with untrackOthers, stop tracking the rest
---@field DumpLayout fun(root: Frame, describe?: fun(region: Region, entry: AGFDumpEntry)): AGFDumpEntry[]
---@field Dump fun() /agf dump: save the layout, route and frames in AdventureGuideForeverDB.dump

-- NPC roles (tools/gen_quests.py `roles`): where trainers, battlemasters and innkeepers stand.

---@class AGFData
---@field npcs table<integer, AGFNpc> creature entry -> its roles, side and place; only NPCs the data places and sides

---@class AGFNpc
---@field side integer the sides it is not hostile to (FactionTemplate.EnemyGroup): 1 Alliance, 2 Horde, 3 both
---@field place AGFPlace a non-seasonal spawn; within 100 yards of a quest place, its `hub` and that town's usual map
---@field class? integer class trainer: the class ID it trains (1 Warrior ... 11 Druid)
---@field upto? integer class trainer: the highest level among the spells it teaches (6 for a starting-area trainer)
---@field from? integer class trainer: the lowest level among them, when above 1 (a mage's portal trainer's 20)
---@field pet? boolean hunter pet trainer
---@field riding? boolean riding trainer
---@field race? integer riding trainer: the race ID it teaches (CMaNGOS TrainerRace), when it names one
---@field skill? integer profession trainer: its skill line ID
---@field rank? integer profession trainer: the highest rank it teaches, 1 Apprentice to 4 Artisan (SpellEffect SKILL_STEP)
---@field bg? integer battlemaster: its battleground (CMaNGOS battlemaster_entry.bg_template: 1 AV, 2 WSG, 3 AB)
---@field inn? boolean innkeeper

--[[ Stream 1e: what Forever added (tools/diff_forever.py, Data/Forever.lua) and honest coverage ]]

-- The IDs Forever's DB2 tables have and Classic Era's lack, at the pinned builds.
---@class AGFForever
---@field quests table<integer, integer[]> uiMapID -> the added quests whose QuestPOIBlob sits on it; the rest have no zone
---@field areas table<integer, true> the added AreaTable IDs

---@class AGFData
---@field forever? AGFForever nil where only Data/Quests.lua is loaded (the planner specs and bench)

---@class AGFModel
---@field Unlisted fun(data: AGFData, map?: integer, completed: table<integer, boolean>, log: table<integer, AGFLogQuest>): boolean the log holds a quest the data lacks, or Forever added quests on `map` the data lacks and the player hasn't finished

---@class AGFStrings
---@field UNLISTED string the panel's honest-coverage line

-- Stream 1a "Tone" (roadmap #3, #17).

---@class AGFStrings
---@field REASON_GREY string format: how many of a zone card's pickups turn grey at the next level
---@field REASON_CHAIN_GIVER string format: the giver who begins the card's chain
---@field REASON_HANDS string format: the first stop's town, by its flight master's name
---@field NOT_INTERESTED string a journey card's menu: hide it on this character
---@field RIGHT_CLICK_NOT_INTERESTED string a journey card's tooltip: its right-click

---@class AGFPrefs
---@field notInterested table<string, string> journey keys this character is not interested in -> the title Show again names

---@class AGFNamespace
---@field NotInterested fun(key: string, title: string) hide a journey on this character until Show again; a choice of it ends

-- Asides (Asides.lua, docs/design.md §2.11): one-line hints beside the journeys, never a route.
---@class AGFAside
---@field key string stable identity for Skip and Not interested, e.g. "trainer"
---@field text string the whole line, in the game's voice
---@field icon string an atlas the Forever client has (a row of the atlas CSV)
---@field place? AGFPlace where Go takes the player: only a place from the data

---@class AGFAsides
---@field Register fun(provider: fun(): AGFAside?) a domain's provider, asked in step 1's travel frame and never in combat; earlier ones win
---@field Refresh fun() asks every provider again, out of combat; listeners hear only when the shown aside changes
---@field Current fun(): AGFAside? the first answer neither skipped this session nor turned down for this character
---@field OnChange fun(callback: fun())
---@field Skip fun(key: string) hide it until the next session
---@field Decline fun(aside: AGFAside) Not interested: hide it for this character, remembering its text
---@field Declined fun(): {key: string, text: string}[] the turned-down asides, by text, for Show again: its provider's answer now, else the saved text
---@field Restore fun(key: string) Show again: undo a Decline
---@field Go fun(aside: AGFAside): boolean to its place, as Integrations.Navigate; false without one
---@field Open fun(owner: Region, tag: string, aside: AGFAside) its menu: Go with a place, Skip, Not interested

---@class AGFNamespace
---@field Asides AGFAsides

---@class AGFPrefs
---@field asides? table<string, string> the asides this character turned down (Not interested): key -> the text it had

---@class AGFStrings
---@field STORY_HOOK string format: the tracker's one line with no journey chosen: a story's title, its reason or subline

-- Stream 2c: skill- and reputation-gated quests (roadmap #8, docs/design.md §2.4).

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
---@field Skills fun(): table<integer, integer> learned skill line -> rank (C_SkillInfo), read again on SKILL_LINES_CHANGED
---@field Reputation fun(factionID: integer): integer? C_Reputation's currentStanding; nil for a faction it gives none for
---@field SkillName fun(skillLineID: integer): string? the client's name for a learned skill line
---@field FactionName fun(factionID: integer): string?
---@field StandingName fun(reaction: integer): string? FACTION_STANDING_LABEL1-8

---@class AGFStrings
---@field WHY_SKILL string format: a skill line's name and the rank a quest needs
---@field WHY_REP_MIN string format: the standing and the faction a quest needs
---@field WHY_REP_BELOW string format: the standing a quest closes at, and the faction
---@field WHY_REPUTATION string format: a faction whose required value falls between standings

-- Stream 2b "Trainers" (roadmap R3, #5): a step with no quests, and the class trainer's place.

-- Tweaks Forever's spells to train, as the planner and the trainer aside take them.
---@class AGFTraining
---@field count integer how many spells wait
---@field level integer the highest level among them, which the trainer must teach up to

---@class AGFPlayer
---@field train? AGFTraining set by Core while a journey is chosen: its route may stop at a trainer

---@class AGFModel
---@field Trainer fun(data: AGFData, player: AGFPlayer, level: integer): AGFNpc? the nearest class trainer of the player's class and side who teaches from level 1 up to `level`; nil when the data has none or the player has no place
---@field TownName fun(data: AGFData, place: {map: integer, hub?: integer}, mapName?: fun(map: integer): string?): string the hub's flight-master town, else the map's name

---@class AGFIntegrations
---@field Training fun(): AGFTraining? Tweaks Forever's spells to train, counted; nil without a v1 Tweaks Forever, its answer, or a spell to train

---@class AGFStrings
---@field TRAINER_IN string format: the trainer aside's lead with the nearest trainer's town
---@field TRAIN_IN string format: a trainer step's title, its town
--[[ Stream 2a: the diversion slot and your calling (roadmap R4, #7) ]]

---@class AGFPlace
---@field trainer? integer a class quest's start only: the class its giver trains (1 Warrior ... 11 Druid)

---@class AGFStrings
---@field JOURNEY_CALLING string the calling card's title
---@field CALLING_QUESTS string format: how many class quests the player can take now
---@field CALLING_QUESTS_ONE string the same for one
---@field CALLING_TRAINER string format: the lead class quest's title, when the data proves its giver trains the player's class
---@field CALLING_TASK string format: the lead class quest's title, from any other giver
-- Stream 2e "NPC tooltip line" (roadmap #19, Tooltip.lua, docs/design.md §2.9).

---@class AGFPlace
---@field npc? integer the creature entry of an NPC giver, the ID in its UnitGUID; nil for an object

---@class AGFStrings
---@field NPC_JOURNEY string format: the chosen journey's title, on a unit tooltip of an NPC its steps visit
