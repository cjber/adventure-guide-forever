---@type string, AGFNamespace
local _, ns = ...

-- Every line the player reads, in one table: new copy lands here, so one place holds the game's voice (WFA-6).
-- These are the English lines; Locales/Translations.lua replaces the ones CurseForge's translators have done, so
-- a line nobody has translated yet stays in English. Format strings keep their specifiers.
---@type AGFStrings
ns.L = {
	-- The addon's name wherever the game shows it: the window, the map tab, its settings page and chat. Only WoW: Forever
	-- loads this addon, so in game it is simply the Adventure Guide.
	TITLE = "Adventure Guide",
	AUDIT_BUILD = "data from build %s, client build %s.%s",
	AUDIT_COUNTS = "%d quests in the data, %d eligible now, %d completed known",
	AUDIT_NOT_READY = "completed-quest data hasn't finished loading yet; the counts above may be low.",
	-- Where the quests come from (QuestieSource.lua): QuestieDB when it is loaded and fit, the bundled data otherwise.
	AUDIT_SOURCE_BUNDLED = "quests from the bundled data",
	AUDIT_SOURCE_QUESTIE = "quests from QuestieDB %s",
	AUDIT_QUESTIE_BUILDING = "QuestieDB's quests are still loading; the bundled ones serve until then.",
	AUDIT_QUESTIE_UNUSED = "QuestieDB isn't used: %s.",
	QUESTIE_ABSENT = "it isn't loaded",
	QUESTIE_CONTRACT = "its version isn't one the guide can read",
	QUESTIE_FLAVOUR = "it isn't the WoW: Forever edition",
	QUESTIE_FIELD = "it lacks %s",
	QUESTIE_ZONES = "it lacks its zone tables",
	QUESTIE_FAILED = "reading it failed (%s)",
	HELP_OPEN = "/agf - open the Adventure Guide window; it is also a tab on the world map's quest log.",
	HELP_AUDIT = "/agf audit - check the quest data against the game",
	HELP_DUMP = "/agf dump - save the guide's layout for a bug report",
	HAND_IN_WHEN = "Hand in when you're in %s",
	-- Journey cards (docs/design.md §2.2 and §3): a title, a subline that counts, and a reason when there is one.
	JOURNEY_CARRY = "Loose ends",
	JOURNEY_STORY = "%s story",
	JOURNEY_NEXT_ZONE = "Head to %s",
	-- The next zone's level goes under its name, so a long zone name never cuts it off.
	NEXT_ZONE_LEVEL = "For level %d",
	DUNGEON_QUESTS = "%d quests for this dungeon",
	DUNGEON_QUESTS_ONE = "1 quest for this dungeon",
	-- The dungeon card's reason (roadmap #15): the log's quests filed under its instance, counted.
	DUNGEON_INSIDE = "%d of your quests end inside %s",
	DUNGEON_INSIDE_ONE = "1 of your quests ends inside %s",
	-- A chain that leads into an instance, a story when there is no next zone (roadmap #21): the instance's name.
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
	-- A zone card's reason in the world's voice (roadmap #3): a chain's giver, a town by its flight master's name.
	REASON_GREY = "%d quests will soon turn grey",
	REASON_CHAIN_GIVER = "A chain begins with %s",
	REASON_HANDS = "%s needs hands",
	NO_JOURNEY = 'The guide has no journey for you here; look for the "!" over quest givers.',
	LOADING = "Loading your completed quests...",
	SEARCH_QUESTS = "Search quests",
	SEARCH_NONE = "No quests match your search.",
	SETTING_MAP_PINS_TOOLTIP = "The route's numbered steps on the world map while their zone is shown, and quest "
		.. "givers when those are on too. The open guide previews its route either way.",
	SETTING_DUNGEONS_DEFAULT_TOOLTIP = "Suggest dungeon quests for a character the first time you open "
		.. "the guide. Change it any time from the guide's settings menu.",
	SETTING_GIVERS_TOOLTIP = 'A "!" on the world map over everyone with a quest you can take now. '
		.. "Needs route pins on the map as well.",
	SETTING_TITLE_ROUTE = "Choosing a journey starts the route",
	SETTING_TITLE_ROUTE_TOOLTIP = "Choosing a journey in the guide, or clicking the current step's title in the "
		.. "objective tracker, sets off along the route, with Shortest Path Forever when it's loaded and a map "
		.. "waypoint otherwise. Clicking the chosen journey again stops it.",
	SETTING_TRACK_ROUTE = "Clicking the tracker title tracks the route's quests",
	SETTING_TRACK_ROUTE_TOOLTIP = "Every quest on the route that's in your log joins the objective tracker, up to "
		.. "the tracker's limit.",
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
	-- Skill and reputation gates (roadmap #8): a skill line and its rank; a standing (the client's word) and a faction.
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
	-- A journey card's right-click (roadmap #17): hidden on this character until Show again.
	NOT_INTERESTED = "Not interested",
	RIGHT_CLICK_NOT_INTERESTED = "Right-click if you're not interested",
	CHOOSE_JOURNEY = "Choose another journey",
	-- A step's quest ruled out on this character (docs/design.md §2.18): it stays in the log, off every route.
	NOT_THIS_QUEST = "Not this quest",
	-- A quest the route leaves out joins it with a shift-click, in the search or on the map, and leaves the same way.
	SHIFT_ADD = "Shift-click to add it to your route",
	SHIFT_REMOVE = "Shift-click to take it off your route",
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
	-- The trainer aside.
	TRAINER = "Visit your class trainer",
	TRAINER_SPELLS = "%d new spells",
	TRAINER_SPELL = "1 new spell",
	TRAINER_LINE = "%s · %s",
	TRACKER_HEADER = "Adventure Guide",
	TRACKER_UNATTACHED = "couldn't add a section to the objective tracker; please report with /agf audit.",
	DUMP_SAVED = "layout saved. Type /reload, then send "
		.. "WTF\\Account\\<account>\\SavedVariables\\AdventureGuideForever.lua",
	-- Steps (Model.lua): a title and a reason.
	TURN_IN = "Turn in: %s",
	READY_TO_HAND_IN = "ready to hand in",
	-- A hand-in the route comes back for once the quest's objectives are done, and an area of a quest picked up first.
	HAND_IN_WHEN_DONE = "once it's done",
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
	-- The guide and the map.
	SKIP_STEP = "Skip this step for now",
	OPTIONAL = "optional",
	-- The travel provider's name, for CLICK_TRAVEL.
	SHORTEST_PATH = "Shortest Path",
	STARTS_AFTER_COMBAT = "The route starts when combat ends",
	CLICK_TRAVEL = "Click to travel with %s",
	CLICK_WAYPOINT = "Click to set a waypoint",
	STEP_NUMBERED = "%d. %s",
	QUEST_LEVEL = "[%d] %s",
	-- An area's tooltip: each open objective under its quest, in the client's words, else its count.
	OBJECTIVE_LINE = "- %s",
	-- The overview (docs/design.md §2.2): where the player is under the title, the first card's tag, and the other
	-- cards' footers: how far a journey has come, else how many stops it has.
	OVERVIEW_WHERE = "%s · level %d",
	SUGGESTED = "Suggested",
	READY_OF = "%d of %d ready",
	CHAPTERS_DONE = "%d of %d done",
	STOPS_ONE = "1 stop",
	STOPS = "%d stops",
	OBJECTIVE_COUNT = "- %d/%d",
	-- The guide's settings menu, then the addon's settings page.
	MENU_QUESTS = "Quests",
	MENU_DUNGEONS = "Dungeons",
	MENU_MAP_PINS = "Show map pins",
	MENU_GIVERS = "Show quest givers",
	MENU_TRACKER = "Show in objective tracker",
	MENU_MORE_SETTINGS = "More settings",
	SETTING_TRACKER = "Show tracker section",
	SETTING_TRACKER_TOOLTIP = 'A short "Adventure Guide" section above your quests in the objective tracker, for the '
		.. "current step.",
	SETTING_MAP_PINS = "Show route pins on the map",
	SETTING_GIVERS = "Show quest givers on the map",
	SETTING_DUNGEONS_DEFAULT = "Include dungeons by default",
	-- Honest coverage (docs/design.md §2.1): the "!" over a giver marks the quests the guide can't list; Forever
	-- draws no givers on the map (§9 probe `questoffer`).
	MORE_IN_GUIDE = "More in the Adventure Guide",
	MORE_IN_GUIDE_KEY = "More in the Adventure Guide (%s)",
	UNLISTED = 'This land has stories the guide doesn\'t know yet; look for the "!" over quest givers.',
	-- Stream 2b "Trainers" (roadmap #5): the trainer aside names the nearest trainer's town when the data places one,
	-- and a chosen journey's route may stop there.
	TRAINER_IN = "Visit your class trainer in %s",
	TRAIN_IN = "Train in %s",
	-- Your calling (roadmap #7, docs/design.md §2.2): the class quests open now; the trainer only when the data says so.
	JOURNEY_CALLING = "Your calling",
	CALLING_QUESTS = "%d quests for your class",
	CALLING_QUESTS_ONE = "1 quest for your class",
	CALLING_TRAINER = "Your class trainer has a task: %s",
	CALLING_TASK = "A task for your class: %s",
	-- A unit tooltip's line on an NPC the chosen journey visits: its title.
	NPC_JOURNEY = "Adventure guide: %s",
	-- Something new (docs/design.md §2.13): the tracker's line for a journey card the character hasn't been offered.
	MOMENT = "%s is now for your level",
	-- Stream 3a "PvP" (roadmap #12, #28, docs/design.md §2.15): a battleground open to the player, as an aside and as
	-- the opt-in card, which goes to a battlemaster; the next PvP rank's reward, in its own words.
	BATTLEGROUND_OPEN = "%s is open to you",
	BATTLEGROUND_SUBLINE = "A battleground open to you",
	BATTLEMASTER_IN = "Battlemaster in %s",
	BATTLEMASTER_QUEUE = "Queue for %s",
	MENU_BATTLEGROUNDS = "Battlegrounds",
	PVP_RANK_REWARD = "Rank %d · %s",
	-- Unspent talent points (roadmap #25).
	TALENT_POINTS = "You have %d talent points to spend",
	TALENT_POINT = "You have 1 talent point to spend",
	-- Stream 3b "Professions" (roadmap #9, docs/design.md §2.16): the profession aside, its lead then where to train.
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
	-- Exploration and new lands (roadmap #13 and #14): a land Forever added and its levels; an area not yet seen.
	NEW_LAND = "%s · For levels %d-%d",
	UNEXPLORED = "You haven't seen %s yet",
	-- A way into an instance is no place to be the level for (roadmap #21).
	MOMENT_OPEN = "%s is open to you",
	-- Roadmap #11: the route's last stop, when rested XP is low and an innkeeper stands there.
	REST_HERE = "Rest at the inn here",
	-- Roadmap #24: hint strength. A wanderer is told where, never taken there.
	SETTING_WANDERER = "Wanderer: name places only",
	SETTING_WANDERER_TOOLTIP = "The guide names where to go next and leaves the way to you: no waypoint, no route "
		.. "with Shortest Path Forever and no marks on the map.",
	SETTING_FOLLOW_QUEST = "Follow the quest you're working on",
	SETTING_FOLLOW_QUEST_TOOLTIP = "When you walk into the area of the quest the route leads to, the guide selects "
		.. "that quest so the map shows its area. It never changes a quest you selected yourself.",
	-- The Adventure Guide window (Window.lua): its tabs, the Today strip, the featured card and the Professions tab.
	TAB_JOURNEYS = "Journeys",
	TAB_PROFESSIONS = "Professions",
	OPEN_IN_WINDOW = "Open in window",
	BINDING_TOGGLE_WINDOW = "Toggle the Adventure Guide window",
	BINDING_SET = "Shift-J now opens the Adventure Guide window. Change it under Key Bindings.",
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
	SKILLUP_MISSING = "Your next skill-ups come from SkillUp Forever. Install it and they show here.",
	SKILLUP_OUTDATED = "Your next skill-ups come from SkillUp Forever. Update it and they show here.",
	SKILLUP_NONE = "No crafting professions to level. Learn one at a trainer and it shows here.",
	TAB_PVP = "PvP",
	TAB_COMPLETION = "Completion",
	GO_TO_ENTRANCE = "Go to entrance",
	TWEAKS_MISSING = "Install Tweaks Forever to find dungeon entrances.",
	TWEAKS_OUTDATED = "Update Tweaks Forever to find dungeon entrances.",
	ENTRANCE_UNKNOWN = "The entrance location is unknown.",
	LEGACY_MISSING = "Install Legacy Forever to see your completion progress.",
	LEGACY_OUTDATED = "Update Legacy Forever to see your completion progress.",
	COMPLETION_EMPTY = "No completion categories are available here.",
	COMPLETION_LOADING = "Loading completion progress…",
	COMPLETION_UNAVAILABLE = "Completion progress is unavailable here.",
	COMPLETION_COUNTS = "%d/%d",
	COMPLETION_PENDING = "%d pending",
	COMPLETION_ACCOUNT = "Account",
	COMPLETION_GO = "Go to objective",
	COMPLETION_NO_LOCATION = "Location unknown",
	COMPLETION_CATEGORY_AREAS = "Areas",
	COMPLETION_CATEGORY_TAXIS = "Flight paths",
	COMPLETION_CATEGORY_DUNGEONS = "Dungeons",
	COMPLETION_CATEGORY_RAIDS = "Raids",
	COMPLETION_CATEGORY_LEGACY = "Legacy",
	COMPLETION_CATEGORY_REPUTATIONS = "Reputations",
	COMPLETION_CATEGORY_QUESTS = "Quests",
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
	SESSION_LABEL = "Time for this journey",
	SESSION_UNLIMITED = "No limit",
	SESSION_MINUTES = "%d min",
	SESSION_ABOUT = "About %d min",
	SESSION_EMPTY = "No complete task fits this session.",
	SESSION_PENDING = "Estimating this session…",
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
	STOP_MORE = "+%d",
	STOP_VISIT = "Stop %d: %s",
	SET_HEARTH = "Set your hearth in %s",
	SETTING_STEP_SOUND = "Play a sound when a step is done",
	SETTING_STEP_SOUND_TOOLTIP = "Play a short sound once when you finish a route step.",
	STEP_PICKUP = "Pick up: %s",
	STEP_OBJECTIVE = "Complete objectives · %s",
	STEP_COLLECT = "Collect %s · %s",
	STEP_DEFEAT = "Defeat %s · %s",
	STEP_WORK = "Complete %s · %s",
	STEP_TOWN = "Visit %s: %s",
	STEP_BATTLEMASTER = "Visit the battlemaster in %s",
}
