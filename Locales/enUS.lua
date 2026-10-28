---@type string, AGFNamespace
local _, ns = ...

-- Every line the player reads, in one table: new copy lands here, so one place holds the game's voice (WFA-6).
-- These are the English lines; a translation (Locales/<locale>.lua, after this file in the TOC) replaces the ones it
-- has, so a line nobody has translated yet stays in English. Format strings keep their specifiers.
---@type AGFStrings
ns.L = {
	MICRO_MENU_UNAVAILABLE = "Micro menu unavailable; skipping custom button.",
	SETTING_MICRO_BUTTON = "Show the Adventure Guide micro menu button",
	SETTING_REPLACE_MICRO_BUTTON = "Replace Blizzard's Adventure Guide button",
	SETTING_MICRO_BUTTON_PLACEMENT = "Position",
	SETTING_MICRO_BUTTON_BEFORE = "Before the Game Menu",
	SETTING_MICRO_BUTTON_AFTER = "After Collections",
	MICRO_BUTTON_BINDING_NOTE = "Both buttons can also be bound in Key Bindings > AddOns.",
	MICRO_BUTTON_TOOLTIP = "Adds an Adventure Guide button to the micro menu bar.",
	MICRO_BUTTON_TITLE = "Adventure Guide",
	MICRO_BUTTON_SUBTEXT = "Click to open the levelling guide",
	SETTING_STATS_SHARE = "Share activity with guild and groups",
	SETTING_STATS_SHARE_TOOLTIP = "On by default. Shares cumulative activity rows with addon users in "
		.. "your guild, party, raid or instance. Turn it off to keep records on this character only. "
		.. "Shared records are player-reported, not verified.",
	STATS_SUMMARY = "Activity: %d quest turn-ins recorded locally; %d other addon users reported activity.",
	HELP_STATS = "/agf stats - show local quest turn-ins and the number of peers reporting activity",
	SETTING_RXP = "Use RestedXP guides",
	SETTING_RXP_TOOLTIP = "Add the current RestedXP guide to your journey cards, map and tracker. "
		.. "RestedXP advances guide steps; Shortest Path Forever handles travel. "
		.. "RestedXP stays installed and controls guide progress.",
	RXP_TITLE = "RestedXP guides",
	RXP_PREVIOUS = "Previous",
	RXP_NEXT = "Next",
	RXP_SKIP = "Skip: %s",
	RXP_SKIP_STEP = "Skip step",
	RXP_IMPORT = "Import",
	RXP_SETTINGS = "Settings",
	RXP_ORIGINAL = "Open original RestedXP window",
	RXP_SELECT = "Choose guide",
	RXP_PROGRESS = "Step %d of %d",
	RXP_STEP = "Step %d",
	RXP_NO_GUIDE = "Choose a guide to begin.",
	RXP_STICKY = "%s (ongoing)",
	RXP_RECOMMENDATIONS = "Adventure Guide recommendations",

	SETTING_QUEST_LEVEL = "Maximum quest level above yours",
	SETTING_QUEST_LEVEL_VALUE = "%s levels",
	SETTING_QUEST_LEVEL_ONE = "%s level",
	SETTING_QUEST_LEVEL_TOOLTIP = "Choose the highest quest level the guide recommends relative to your level. "
		.. "The default, +2, avoids orange and red quests. Quests already in your log remain visible.",
	-- The addon's name wherever the game shows it: the window, the map tab, the objective tracker, its settings page and
	-- chat. Only WoW: Forever loads this addon, so in game it is simply the Adventure Guide.
	TITLE = "Adventure Guide",
	AUDIT_BUILD = "data from build %s, client build %s.%s",
	AUDIT_COUNTS = "%d quests in the data, %d eligible now, %d completed known",
	AUDIT_NOT_READY = "completed-quest data hasn't finished loading yet; the counts above may be low.",
	-- Where the quests come from (QuestieSource.lua): the installed QuestieDB when loaded and fit; unavailable otherwise.
	AUDIT_SOURCE_BUNDLED = "Quest data unavailable. Enable QuestieDB; enable Questie for pickup recommendations.",
	AUDIT_SOURCE_QUESTIE = "quests from QuestieDB %s",
	AUDIT_QUESTIE_BUILDING = "QuestieDB's quests are still loading.",
	AUDIT_QUESTIE_UNUSED = "QuestieDB isn't used: %s.",
	WHY_NOT_OFFERED = "The giver didn't offer it",
	NOT_OFFERED = "Skipped %s: the giver didn't offer it.",
	WHY_PROVIDER = "Questie must be ready and confirm this quest is available.",
	QUESTIE_ENABLE = "Enable QuestieDB to load quest data.",
	QUESTIE_POLICY = "Enable Questie for available quest recommendations.",
	QUESTIE_ABSENT = "it isn't loaded",
	QUESTIE_CONTRACT = "its version isn't one the guide can read",
	QUESTIE_FLAVOUR = "it isn't the WoW: Forever edition",
	QUESTIE_FIELD = "it lacks %s",
	QUESTIE_ZONES = "it lacks its zone tables",
	QUESTIE_FAILED = "reading it failed (%s)",
	NEXT_CAMP = "Next spot",
	HELP_OPEN = "/agf - open the guide on the world map.",
	HELP_WHERE = "/agf where - show the stop the guide is on, to copy into a wrong-stop report",
	HELP_REPORT = "/agf report - show a report to copy into a bug report",
	HELP_ISSUE = "/agf issue - report a bug or request a feature with a ready-made GitHub issue link",
	ISSUE_WINDOW_TITLE = "Report a bug or request a feature",
	ISSUE_LINK_HINT = "The link is selected. Press Ctrl+C (Cmd+C on a Mac), then paste it into your browser: "
		.. "GitHub opens a new issue with this filled in.",
	ISSUE_BUG = "Bug",
	ISSUE_BUG_PREFIX = "Bug: ",
	ISSUE_FEATURE = "Feature request",
	ISSUE_FEATURE_PREFIX = "Feature request: ",
	ISSUE_TITLE_LABEL = "Title",
	ISSUE_DETAILS_LABEL = "What happened, or what you would like",
	ISSUE_COPY_LINK = "Copy issue link",
	ISSUE_COPY_REPORT = "Copy report",
	REPORT_TITLE = "Adventure Guide report",
	REPORT_HINT = "The text is selected. Press Ctrl+C (Cmd+C on a Mac) to copy it, then paste it into your bug report.",
	HELP_AUDIT = "/agf audit - check the quest data against the game",
	HELP_DUMP = "/agf dump - save the guide's layout for a bug report",
	HELP_TRACKER = "/agf tracker - print the tracker stack's anchors (for a combat overlap)",
	HAND_IN_WHEN = "Hand in when you're in %s",
	-- Journey cards (docs/design.md §2.2 and §3): a title, a subline that counts, and a reason when there is one.
	PREVIOUS_PAGE = "Previous",
	NEXT_PAGE = "Next",
	JOURNEY_PAGE = "%d / %d",
	JOURNEY_CARRY = "Quests in your log",
	CARRY_EXPLANATION = "Turn-ins and unfinished objectives from your quest log, "
		.. "plus quests you added to the route.",
	JOURNEY_STORY = "%s story",
	JOURNEY_NEXT_ZONE = "Head to %s",
	-- The overview's quest log headers (docs/design.md §2.2): one per kind of card, in this order. A collapsed one
	-- shows how many cards it holds.
	GROUP_CONTINUE = "Continue",
	QUEST_VISIT_WARNING = "Quest visit: %s. This zone is recommended for levels %d-%d.",
	GROUP_ZONES = "Quest destinations",
	GROUP_DUNGEONS = "Dungeons",
	GROUP_BATTLEGROUNDS = "Battlegrounds",
	DUNGEON_QUESTS = "%d quests for this dungeon",
	DUNGEON_QUESTS_ONE = "1 quest for this dungeon",
	-- The dungeon card's reason: the log's quests filed under its instance, counted.
	DUNGEON_INSIDE = "%d of your quests end inside %s",
	DUNGEON_INSIDE_ONE = "1 of your quests ends inside %s",
	-- A chain that leads into an instance, a story when there is no next zone: the instance's name.
	JOURNEY_INTO = "The way into %s",
	-- The carry card's counts, joined when several apply: "3 ready to hand in, 1 in progress".
	CARRY_READY = "%d ready to hand in",
	CARRY_IN_PROGRESS = "%d in progress",
	CARRY_AWAY = "%d to hand in across the sea",
	-- Quests the player added with a shift-click that no zone card holds.
	CARRY_ADDED = "%d you added",
	-- The log nearly full (docs/design.md §2.18): card 1's line 3 counts what could go, and its tooltip lists them.
	LOG_FULL = "Log nearly full: %d you could drop",
	LOG_FULL_ONE = "Log nearly full: 1 you could drop",
	LOG_FULL_LIST = "To make room in your log, you could drop:",
	LATER_LAPS = "%d of them on later laps",
	LIST_SEPARATOR = ", ",
	QUESTS_NEAR = "%d quests near your level",
	QUESTS_NEAR_ONE = "1 quest near your level",
	-- Stories (docs/design.md §2.3): a total only when the data proves it, never a later chapter's title.
	CHAPTER_OF = "Chapter %d of %d",
	CHAPTER = "Chapter %d",
	CONTINUES_STORY = "Continues a story you started",
	BEGINS_STORY = "Begins a new story",
	-- A zone card's reason in the world's voice: a chain's giver, a town by its flight master's name.
	REASON_GREY = "%d quests will soon turn grey",
	REASON_CHAIN_GIVER = "A chain begins with %s",
	REASON_HANDS = "%s needs hands",
	NO_JOURNEY = 'The guide has no journey for you here; look for the "!" over quest givers.',
	LOADING = "Loading your completed quests...",
	SEARCH_QUESTS = "Search quests",
	SEARCH_NONE = "No quests match your search.",
	SETTING_MAP_PINS_TOOLTIP = "The route's numbered steps on the world map while their zone is shown, and quest "
		.. "givers when those are on too. The open guide previews its route either way.",
	SETTING_DUNGEONS_DEFAULT_TOOLTIP = "Suggest dungeon quests on a character from the first time you log in on it "
		.. "with the guide installed. Change it any time from the guide's settings menu.",
	SETTING_GIVERS_TOOLTIP = 'A "!" on the world map over everyone with a quest you can take now. '
		.. "Needs route pins on the map as well.",
	SETTING_TITLE_ROUTE = "Journeys start the route",
	SETTING_TITLE_ROUTE_TOOLTIP = "Choosing a journey in the guide, or clicking the current step's title in the "
		.. "objective tracker, sets off along the route, with Shortest Path Forever when it's loaded and a map "
		.. "waypoint otherwise. Clicking the chosen journey again stops it.",
	SETTING_AUTO_START = "Start the route automatically",
	SETTING_AUTO_START_TOOLTIP = "The guide sends your chosen journey's route to Shortest Path as soon as it is "
		.. "ready, so the map line is drawn on login and after a reload without pressing Go. Pressing Stop still "
		.. "clears it until you choose a journey again.",
	SETTING_TRACK_ROUTE = "Tracker title tracks quests",
	SETTING_TRACK_ROUTE_TOOLTIP = "Clicking the guide's title in the objective tracker adds every quest on the "
		.. "route that's in your log, up to the tracker's limit.",
	SETTING_UNTRACK_OTHERS = "Stop tracking other quests",
	SETTING_UNTRACK_OTHERS_TOOLTIP = "The same click stops tracking every quest that isn't on the route. Needs the "
		.. "route's quests tracked as well.",
	-- Why-not (docs/design.md §2.4): what the data says a quest needs, one line per requirement.
	WHY_NO_START = "The guide can't tell where this starts",
	WHY_DONE = "You've done this",
	WHY_IN_LOG = "In your quest log",
	WHY_REPEATABLE = "Repeatable quests aren't suggested",
	WHY_ALLIANCE = "Alliance only",
	WHY_HORDE = "Horde only",
	WHY_LEVEL = "Requires level %d",
	WHY_COMPLETED = "Completed: %s",
	WHY_ONE_OF = "Requires one of: %s",
	WHY_CHOSE = "You chose %s instead",
	WHY_BREADCRUMB = "Only until you take %s",
	WHY_EARLIER_QUEST = "an earlier quest",
	-- Skill and reputation gates: a skill line and its rank; a standing (the client's word) and a faction.
	WHY_SKILL = "Requires %s %d",
	WHY_REP_MIN = "Requires %s with %s",
	WHY_REP_BELOW = "Only while below %s with %s",
	WHY_REPUTATION = "Depends on your standing with %s",
	-- The client's own lines, localised, where it has one.
	WHY_RACES = ITEM_RACES_ALLOWED or "Races: %s",
	WHY_CLASSES = ITEM_CLASSES_ALLOWED or "Classes: %s",
	NO_WAYPOINT = MAP_PIN_INVALID_MAP or "You can't place a pin on this map.",
	-- The step menu (docs/design.md §2.8).
	GO = "Go",
	REPLACES_JOURNEY = "Replaces your current journey.",
	STOP = "Stop",
	SHOW_QUEST = "Show quest",
	SKIP = "Skip for now",
	SKIPPED = "Skipped (%d)",
	SHOW_AGAIN = "Show again: %s",
	-- A journey card's right-click: hidden on this character until Show again.
	NOT_INTERESTED = "Not interested",
	RIGHT_CLICK_NOT_INTERESTED = "Right-click if you're not interested",
	CHOOSE_JOURNEY = "Choose another journey",
	-- A step's quest ruled out on this character (docs/design.md §2.18): it stays in the log, off every route.
	NOT_THIS_QUEST = "Not this quest",
	-- A quest the route leaves out joins it with a shift-click, in the search or on the map, and leaves the same way.
	SHIFT_ADD = "Shift-click to add it to your route",
	SHIFT_REMOVE = "Shift-click to take it off your route",
	STARTS_WITH = "Starts with %s",
	SHIFT_ADD_START = "Shift-click to add that quest to your route",
	SHIFT_REMOVE_START = "Shift-click to take that quest off your route",
	-- With no card chosen the guide shows every card whole (docs/design.md §2.1); the header's back arrow goes back to
	-- that overview.
	ALL_SUGGESTIONS = "All suggestions",
	BACK_STOPS_ROUTE = "Also stops the route",
	BACK_TO_ALL = "Click the back arrow to see all suggestions",
	-- The chosen journey's route stopped (cleared, replaced or refused): its card and the tracker title resume it.
	CLICK_TO_RESUME = "Click to resume the route",
	ROUTE_PAUSED = "Route paused. Click the journey to resume.",
	-- A card's third line when it has no reason: its first stop, then how many follow.
	HUB_MORE = "%s and %d more stops",
	HUB_MORE_ONE = "%s and 1 more stop",
	-- A card's minutes from Shortest Path, naming a crossing when the subline leaves room.
	CARD_MINUTES = "%d min",
	CARD_BY_BOAT = "%d min by boat",
	CARD_BY_ZEPPELIN = "%d min by zeppelin",
	-- A card's tooltip: how many of its quests need a group, and what a click on it does.
	GROUP_ONE = "1 needs a group",
	GROUP_MANY = "%d need a group",
	-- Why a step's quest wants a group (Overview.GroupNote): an outdoor elite, its dungeon or raid, or the size the quest
	-- log suggests.
	GROUP_NEED_ELITE = "Elite: group advised",
	GROUP_NEED_DUNGEON = "Dungeon: %s",
	GROUP_NEED_RAID = "Raid: %s",
	GROUP_NEED_RAID_ANY = "Raid: group advised",
	GROUP_NEED_SIZE = "Group of %d",
	CLICK_TO_CHOOSE = "Click to choose this journey",
	-- The travel line (docs/design.md §2.5): Shortest Path's own verbs (its JourneySteps.lua VERB), so both addons
	-- name a leg alike.
	TRAVEL = "%s · %d min",
	TRAVEL_ABOUT = "About %d min away",
	TRAVEL_NEW_FLIGHT_PATH = " · new flight path",
	TRAVEL_WAIT = " · %d min wait",
	TRAVEL_WALK = "Walk to %s",
	TRAVEL_FLIGHT = "Fly to %s",
	TRAVEL_BOAT = "Boat to %s",
	TRAVEL_ZEPPELIN = "Zeppelin to %s",
	TRAVEL_LIFT = "Lift to %s",
	TRAVEL_TRAM = "Tram to %s",
	TRAVEL_PORTAL = "Portal to %s",
	TRAVEL_PASSAGE = "Go through to %s",
	-- The tracker (docs/design.md §2.5).
	NEXT = "Next: %s",
	RESUME = "Where you left off: %s",
	STORY_COMPLETE = "Story complete",
	JOURNEY_COMPLETE = "Journey complete",
	CHOOSE_NEXT = "Choose your next journey",
	-- The tracker's journey line and the wait for QuestieDB's catalogue.
	TRACKER_DRAG_TITLE = "Forever tracker",
	TRACKER_DRAG_TOOLTIP = "Drag to move",
	TRACKER_LOCKED_TOOLTIP = "The tracker is locked. Turn off Lock the tracker to move it.",
	TRACKER_LOADING = "Loading quest data...",
	-- While Polestar runs a guide (Polestar.lua): the tracker's one line, and the setting behind it.
	POLESTAR_GUIDING = "Polestar is guiding you",
	POLESTAR_TAKE_OVER = "Click to take over",
	SETTING_POLESTAR_ASIDE = "Step aside while Polestar is guiding",
	SETTING_POLESTAR_ASIDE_TOOLTIP = "While Polestar has a guide running, the guide starts no route of its own and "
		.. "draws no map marks. The tracker says Polestar is guiding you; click it to take over again.",
	-- The warning before taking a quest that closes another (Closes.lua): the offered quest, then what it closes.
	SETTING_WARN_CLOSING = "Warn before a quest closes another",
	SETTING_WARN_CLOSING_TOOLTIP = "When a quest giver offers a quest that would close another one for good, "
		.. "say in chat which quests you'd lose, before you accept.",
	CLOSES_WARNING = "Taking %s closes %s for good.",
	-- The trainer aside.
	TRAINER = "Visit your class trainer",
	TRAINER_SPELLS = "%d new spells",
	TRAINER_SPELL = "1 new spell",
	TRAINER_LINE = "%s · %s",
	TRACKER_UNATTACHED = "couldn't add a section to the objective tracker; please report with /agf audit.",
	DUMP_SAVED = "layout saved. Type /reload, then send "
		.. "WTF\\Account\\<account>\\SavedVariables\\AdventureGuideForever.lua",
	-- Steps (Model.lua): a title and a reason.
	TURN_IN = "Turn in: %s",
	READY_TO_HAND_IN = "ready to hand in",
	-- A hand-in the route comes back for once the quest's objectives are done, and an area of a quest picked up first.
	HAND_IN_WHEN_DONE = "once it's done",
	-- A step moved up the route because a quest item in the bags (named) vanishes after a while.
	BEFORE_IT_RUNS_OUT = "before %s runs out",
	BEFORE_ITEM_RUNS_OUT = "before a quest item runs out",
	AFTER_PICK_UP = "after you pick it up",
	OPENS_CHAPTER_HERE = "Opens the next chapter here",
	QUESTS_IN_PROGRESS = "quests in progress",
	QUESTS_HERE = "%d quests here",
	PICK_UP = "Pick up quests: %s",
	HUB_HAND_IN = "%d to hand in",
	HUB_PICK_UP = "%d to pick up",
	-- A town's tooltip lists its first quests and counts the rest.
	HUB_MORE_QUESTS = "And %d more",
	-- The tracker's line for a town's NPCs: the first two, then how many more.
	HUB_NPCS_MORE = "%s and %d more",
	PLACE = "%s, %s",
	NEAR_YOUR_LEVEL = "near your level",
	-- A pickup someone in the party already has (Party.lua): they can share it.
	PARTY_HAS = "someone in your party has it",
	-- The guide and the map.
	SKIP_STEP = "Skip this step for now",
	OPTIONAL = "optional",
	-- The travel provider's name, for CLICK_TRAVEL.
	SHORTEST_PATH = "Shortest Path",
	STARTS_AFTER_COMBAT = "The route starts when combat ends",
	CLICK_TRAVEL = "Click to travel with %s",
	CLICK_WAYPOINT = "Click to set a waypoint",
	-- A numbered route pin past the first: how to get back to the story's start.
	PIN_RETURN_STORY = "Right-click to route from the story's start",
	STEP_NUMBERED = "%d. %s",
	QUEST_LEVEL = "[%d] %s",
	-- An area's tooltip: each open objective under its quest, in the client's words, else its count.
	OBJECTIVE_LINE = "- %s",
	-- The overview (docs/design.md §2.2): where the player is under the title, the first card's tag, and the other
	-- cards' footers: how far a journey has come, else how many stops it has.
	OVERVIEW_WHERE = "%s · level %d",
	SUGGESTED = "Suggested",
	RECOMMENDED = "Recommended",
	YOUR_CHOICE = "Your choice",
	START_ADVENTURE = "Start",
	RESUME_ADVENTURE = "Resume",
	DO_THIS_NEXT = "Do this next",
	OTHER_ADVENTURES = "Other adventures",
	READY_OF = "%d of %d ready",
	CHAPTERS_DONE = "%d of %d done",
	STOPS_ONE = "1 stop",
	STOPS = "%d stops",
	-- A card's levels at the right of its title, and a group's page beside its arrows.
	LEVELS = "%d-%d",
	LEVELS_FROM = "%d+",
	OBJECTIVE_PROGRESS = "%d/%d",
	-- The guide's settings menu, then the addon's settings page.
	MENU_QUESTS = "Quests",
	MENU_DUNGEONS = "Dungeons",
	MENU_MAP_PINS = "Show map pins",
	MENU_GIVERS = "Show quest givers",
	MENU_TRACKER = "Show in objective tracker",
	MENU_MORE_SETTINGS = "More settings",
	-- The settings page's index groups, and the index button that opens each one.
	SETTINGS_GROUP_ROUTE = "Route",
	SETTINGS_GROUP_MAP = "Map",
	SETTINGS_GROUP_TRACKER = "Objective tracker",
	SETTINGS_GROUP_INTERFACE = "Interface",
	SETTINGS_OPEN = "Open",
	SETTING_TRACKER = "Show tracker section",
	SETTING_ATTACH_TRACKER = "Attach to quest tracker",
	SETTING_ATTACH_TRACKER_TOOLTIP = "Turn this off to drag the shared Forever tracker anywhere on screen.",
	SETTING_LOCK_TRACKER = "Lock the tracker",
	SETTING_LOCK_TRACKER_TOOLTIP = "Keeps the shared Forever tracker where you put it. The grip at its top no "
		.. "longer drags it.",
	SETTING_TRACKER_TOOLTIP = 'A short "Adventure Guide" section above your quests in the objective tracker, for the '
		.. "current step.",
	SETTING_MAP_PINS = "Show route pins on the map",
	SETTING_GIVERS = "Show quest givers on the map",
	SETTING_DUNGEONS_DEFAULT = "Include dungeons by default",
	SETTING_TRAINING_REMINDERS = "Remind me to train class spells",
	SETTING_TRAINING_REMINDERS_TOOLTIP = "Suggest class trainer visits and add spell training to journeys. "
		.. "You can choose which spells to learn; buying every spell is optional.",
	-- Honest coverage (docs/design.md §2.1): the "!" over a giver marks the quests the guide can't list; Forever
	-- draws no givers on the map.
	UNLISTED = 'This land has stories the guide doesn\'t know yet; look for the "!" over quest givers.',
	-- Trainers: the trainer aside names the nearest trainer's town when the data places one,
	-- and a chosen journey's route may stop there.
	TRAINER_IN = "Visit your class trainer in %s",
	TRAIN_IN = "Train in %s",
	-- Your calling (docs/design.md §2.2): the class quests open now; the trainer only when the data says so.
	JOURNEY_CALLING = "Your calling",
	CALLING_QUESTS = "%d quests for your class",
	CALLING_QUESTS_ONE = "1 quest for your class",
	CALLING_TRAINER = "Your class trainer has a task: %s",
	CALLING_TASK = "A task for your class: %s",
	-- A unit tooltip's line on an NPC the chosen journey visits: its title.
	NPC_JOURNEY = "Adventure Guide: %s",
	-- Something new (docs/design.md §2.13): the tracker's line for a journey card the character hasn't been offered.
	MOMENT = "%s is now for your level",
	-- PvP (docs/design.md §2.15): a battleground open to the player, as an aside and as
	-- the opt-in card, which goes to a battlemaster; the next PvP rank's reward, in its own words.
	BATTLEGROUND_OPEN = "%s is open to you",
	BATTLEGROUND_SUBLINE = "A battleground open to you",
	BATTLEMASTER_IN = "Battlemaster in %s",
	BATTLEMASTER_QUEUE = "Queue for %s",
	MENU_BATTLEGROUNDS = "Battlegrounds",
	PVP_RANK_REWARD = "Rank %d · %s",
	-- Unspent talent points.
	TALENT_POINTS = "You have %d talent points to spend",
	TALENT_POINT = "You have 1 talent point to spend",
	-- Professions (docs/design.md §2.16): the profession aside, its lead then where to train.
	PROFESSION_CAP = "Your %s has reached %d of %d",
	PROFESSION_RANK_IN = "%s training in %s",
	PROFESSION_RANK = "%s training is open to you",
	PROFESSION_SLOT = "A profession slot is free",
	PROFESSION_SLOT_IN = "trainers in %s",
	PROFESSION_LEARN_IN = "You can learn %s in %s",
	PROFESSION_LEARN = "You can learn %s",
	PROFESSION_LINE = "%s · %s",
	PROFESSION_RANK_1 = "Apprentice",
	PROFESSION_RANK_2 = "Journeyman",
	PROFESSION_RANK_3 = "Expert",
	PROFESSION_RANK_4 = "Artisan",
	-- Exploration and new lands: a land Forever added and its levels; an area not yet seen.
	NEW_LAND = "%s · For levels %d-%d",
	UNEXPLORED = "You haven't seen %s yet",
	-- A way into an instance is no place to be the level for.
	MOMENT_OPEN = "%s is open to you",
	-- The route's last stop, when rested XP is low and an innkeeper stands there (docs/design.md §2.17).
	REST_HERE = "Rest at the inn here",
	-- Hint strength (docs/design.md §2.17): a wanderer is told where, never taken there.
	SETTING_WANDERER = "Wanderer: name places only",
	SETTING_WANDERER_TOOLTIP = "The guide names where to go next and leaves the way to you: no waypoint, no route "
		.. "with Shortest Path Forever and no marks on the map.",
	SETTING_FOLLOW_QUEST = "Follow your current quest",
	SETTING_FOLLOW_QUEST_TOOLTIP = "When you walk into the area of the quest the route leads to, the guide selects "
		.. "that quest so the map shows its area. It never changes a quest you selected yourself.",
	SETTING_PARTY_QUESTS = "Favour quests your party has",
	SETTING_PARTY_QUESTS_TOOLTIP = "In a party, steps for quests someone in your party also has count as a little "
		.. "nearer, so you tend to do them together. Party members with Adventure Guide tell each other which quests "
		.. "they have, as hidden addon messages.",
	SETTING_ROUTE_ORDER = "Optimised route (beta)",
	SETTING_ROUTE_ORDER_TOOLTIP = "Off: the route is the nearest thing to do next, step by step, so it is simple "
		.. "and predictable. On: an experimental order that leads with the story's chapter, groups a town's work and "
		.. "keeps its earlier suggestions steady.",
	-- The Adventure Guide window (Window.lua): its tabs, the Today strip, the featured card and the Professions tab.
	TAB_JOURNEYS = "Journey",
	TAB_ACTIVITIES = "Activities",
	TAB_PROGRESS = "Progress",
	NEXT_REASON_JOURNEY = "The next step in %s.",
	NEXT_REASON_ASIDE = "Something useful to consider alongside your adventure.",
	NEXT_REASON_TRAINING = "Your class trainer has spells you can learn.",
	NEXT_REASON_TALENTS = "Spending your talent points makes your character stronger.",
	NEXT_REASON_PROFESSIONS = "You meet the requirements for this profession training.",
	TAB_PROFESSIONS = "Professions",
	SHOW_ON_MAP = "Show on Map",
	NEXT_STEPS = "Next steps",
	OPEN_RECIPES = "Open Recipes",
	NEXT_RECIPES = "Next recipes",
	REAGENTS = "Reagents",
	FROM_SKILLUP = "from SkillUp Forever",
	PROFESSION_RANGE = "%d to %d",
	PROFESSION_RANGE_TITLE = "%d to %d · %s",
	PROFESSION_BAR = "%d/%d",
	SEPARATOR = " · ",
	RECIPE_COUNT = "%s  ×%d",
	RECIPE_TRAIN_AT = "train at %d",
	RECIPE_LEARNED = "learned",
	REAGENT_NEED = "%d %s",
	REAGENT_HAVE = "You have %d",
	REAGENT_VENDOR = "Buy from a vendor",
	REAGENT_CRAFT = "Craft it",
	REAGENT_GATHER = "Gather it",
	REAGENT_AUCTION = "Auction house",
	CLICK_WAYPOINT_STEP = "Click to set a waypoint",
	SKILLUP_OUTDATED = "Your next skill-ups come from SkillUp Forever. Update it and they show here.",
	SKILLUP_NONE = "No crafting professions to level. Learn one at a trainer and it shows here.",
	DUNGEON_PICKUP = "Pick up",

	TAB_PVP = "PvP",
	GO_TO_ENTRANCE = "Go to entrance",
	TWEAKS_MISSING = "Install Tweaks Forever to find dungeon entrances.",
	TWEAKS_OUTDATED = "Update Tweaks Forever to find dungeon entrances.",
	TWEAKS_DISABLED = "Enable Tweaks Forever to find dungeon entrances.",
	ENTRANCE_UNKNOWN = "The entrance location is unknown.",
	-- Legacy Forever's own words for items it can't check yet, with its hint when one category holds them all.
	PVP_RANK = "Rank %d",
	PVP_RANK_POINTS = "%d/%d rank points",
	PVP_UNRANKED = "Unranked",
	PVP_CAPPED = "Highest rank reached",
	PVP_UNAVAILABLE = "Rank progress is unavailable.",
	PVP_NO_BATTLEGROUNDS = "No battlegrounds are available at your level.",
	PVP_NO_BATTLEMASTER = "No known battlemaster location",
	PVP_BATTLEGROUND_LEVEL = "From level %d",
	PVP_GO_BATTLEMASTER = "Go to battlemaster",
	PVP_NEXT_REWARD = "Next reward: rank %d · %s",
	GUIDE_OPEN = "View full guide",
	GUIDE_BACK = "Back to journeys",
	MENU_BACK = "Back",
	MENU_CHECKED = "[x] %s",
	MENU_UNCHECKED = "[ ] %s",
	MENU_SUBMENU = "%s >",
	GUIDE_OUTLINE = "Later quest · guide outline",
	GUIDE_OUTLINE_TOOLTIP = "Quests in this area. Availability is checked before the guide recommends a pickup.",
	GUIDE_PAGE = "%d / %d · %d next steps · %d later quests",
	ORDER_DRAG = "Drag to change the order",
	ORDER_SOONER = "Do this sooner",
	ORDER_LATER = "Do this later",
	ORDER_NEXT = "Do this next",
	ORDER_RESET = "Back to suggested order",
	ORDER_CUSTOM = "Your order",
	TOWN_SKIP_GIVER = "Skip this giver",
	TOWN_GIVER = "%s: %s",
	TOWN_COUNTS = "Pick up %d, turn in %d",
	TOWN_PICKUPS = "Pick up %d",
	TOWN_HANDINS = "Turn in %d",
	TODAY_MORE = "+%d more",
	STOP_VISIT = "Stop %d: %s",
	SET_HEARTH = "Set your hearth in %s",
	SETTING_STEP_SOUND = "Sound when a step is done",
	SETTING_STEP_SOUND_TOOLTIP = "Play a short sound once when you finish a route step.",
	STEP_PICKUP = "Pick up: %s",
	STEP_OBJECTIVE = "Complete objectives · %s",
	STEP_SHARED_OBJECTIVES = "Complete %d objectives · %s",
	STEP_COLLECT = "Collect %s · %s",
	STEP_DEFEAT = "Defeat %s · %s",
	STEP_WORK = "Complete %s · %s",
	STEP_TOWN = "Visit %s: %s",
	STEP_BATTLEMASTER = "Visit the battlemaster in %s",
	-- After an update (WhatsNew): the version, then WHATS_NEW.
	UPDATED_TO = "updated to %s. %s",
	SETTING_WHATS_NEW = "What's new after an update",
	SETTING_WHATS_NEW_TOOLTIP = "One line in chat the first time you log in after the guide updates.",
	-- Companion hints (Companions.lua): what another Forever addon would add here, while it isn't loaded. The
	-- Forever addons page itself and its setting are UI/ForeverFamily.lua's, shared by all five addons.
	FAMILY_PAGE = "Forever addons",
	-- The Forever addons page and its address window (UI/ForeverFamily.lua): the shared module looks each up by its
	-- English, so these keep its words exactly (Companions.lua maps them, tests/companions_spec.lua checks).
	FAMILY_LINE_SPF = "Plans the quickest way anywhere and guides you there, with live boat and zeppelin times.",
	FAMILY_LINE_AGF = "Picks quests for your level and plans them into one journey.",
	FAMILY_LINE_SKILLUP = "Plans the cheapest route to your next profession rank.",
	FAMILY_LINE_LEGACY = "Shows the Legacy challenges you can advance in each zone.",
	FAMILY_LINE_TWEAKS = "Quest automation, rare alerts and merchant handling for the default UI.",
	FAMILY_SUGGEST = "Suggest my other Forever addons",
	FAMILY_SUGGEST_ABOUT = "Show a quiet line where one of my other Forever addons would help. "
		.. "Only for addons you don't have.",
	FAMILY_STATE_ON = "On",
	FAMILY_STATE_OFF = "Installed, turned off",
	FAMILY_STATE_MISSING = "Not installed",
	FAMILY_THIS_ADDON = "This addon",
	FAMILY_COPY_LINK = "Copy link",
	FAMILY_COPY_HINT = "Copy the address, then open it in your browser.",
	FAMILY_CLOSE = "Close",
	FAMILY_DONT_SUGGEST = "Don't suggest this again",
	SPF_FAMILY_MENU = "Walked routes and boat times: Shortest Path Forever",
	SKILLUP_FAMILY = "SkillUp Forever plans the cheapest route to your next profession rank.",
	SKILLUP_FAMILY_MENU = "Cheapest route to your next rank: SkillUp Forever",
	TWEAKS_FAMILY_MENU = "Find dungeon entrances: Tweaks Forever",
	SPF_MISSING = "Install Shortest Path Forever for walked routes and boat times.",
	SPF_DISABLED = "Enable Shortest Path Forever for walked routes and boat times.",
	-- The one chat line after an update to this version (ns.WhatsNew): it opens with the headline of its CHANGELOG
	-- entry, and tests/locales_spec.lua fails a release whose entry it does not match.
	WHATS_NEW = "Quest, geometry, zone-art and Forever data re-pinned to client build 1.60.1.70685.",
	DUNGEON_BOSSES_LOOT = "Bosses and loot",
	DUNGEON_LOOT_INSTALL = "Install AtlasLoot Classic and its Dungeons and Raids module for bosses and loot.",
	DUNGEON_LOOT_COMBAT = "Boss loot will load after combat.",
	ITEM_LOADING = "Loading item...",
	DUNGEON_LOOT_UNKNOWN = "AtlasLoot has no boss drops for this dungeon yet.",
	JOURNEY_QUESTS = "Quests in this journey",
	JOURNEY_CHOICES = "Choose an adventure",
	JOURNEY_CHOOSE = "Choose a journey in Activities to begin.",
	JOURNEY_PROGRESS_EMPTY = "Your completed stories will appear here.",
	LEGACY_PROGRESS_LINK = "Open map for Legacy progress",
	LEGACY_PROGRESS_NOTE = "Collections, exploration and zone completion are tracked by Legacy Forever.",
	RXP_SETUP_TITLE = "Guide display",
	RXP_SETUP_NATIVE_TITLE = "RestedXP",
	RXP_SETUP_PROMPT = "RestedXP is installed. Choose where to show its guides.",
	RXP_SETUP_AGF = "Show RestedXP steps in Adventure Guide.",
	RXP_SETUP_SPF = "Use Shortest Path for routes and compass guidance.",
	RXP_SETUP_HIDDEN_SPF = "Hide RestedXP windows, arrow and map markers.",
	RXP_SETUP_HIDDEN = "Hide RestedXP windows and map markers.",
	RXP_SETUP_NATIVE = "Keep its guide window, arrow, targets and map markers.",
	RXP_SETUP_SKILLUP_SPF = "SkillUp: equipment and shopping routes use Shortest Path.",
	RXP_SETUP_SKILLUP = "SkillUp: equipment and shopping journeys are available.",
	RXP_SETUP_SETTINGS = "Change this later in AddOns settings.",
}

_G.BINDING_HEADER_ADVENTUREGUIDEFOREVER = "Adventure Guide Forever"
_G["BINDING_NAME_CLICK AdventureGuideForeverMicroButton:LeftButton"] = "Open Adventure Guide"

-- The Forever addons page's words in English, kept before a translation replaces them. The shared module
-- (UI/ForeverFamily.lua, loaded next) reads its words from ns.FamilyL by their English phrase, since our ns.L is keyed
-- by name: English here, and Integrations/Companions.lua puts each translated line in once every Locales file has
-- loaded.
---@type table<string, string>
ns.FamilyPhrases = {}
---@type table<string, string>
ns.FamilyL = {}
for key, text in pairs(ns.L) do
	if key:find("^FAMILY_") then
		ns.FamilyPhrases[key] = text
		ns.FamilyL[text] = text
	end
end
