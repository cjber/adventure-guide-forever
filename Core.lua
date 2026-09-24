---@type string, AGFNamespace
local addonName, ns = ...

-- Only WoW: Forever loads this addon, so in game it is simply the Adventure Guide.
ns.TITLE = "Adventure Guide"

-- Every line the player reads, in one table: new copy lands here from the start, so one place holds the
-- game's voice (WFA-6) and a later locale only has to replace values. Format strings keep their specifiers.
---@type AGFStrings
ns.L = {
	AUDIT_BUILD = "data from build %s, client build %s.%s",
	AUDIT_COUNTS = "%d bundled quests, %d eligible now, %d completed known",
	AUDIT_NOT_READY = "completed-quest data hasn't finished loading yet; the counts above may be low.",
	HELP_OPEN = "open the world map and use the Adventure Guide tab.",
	HELP_AUDIT = "/agf audit - check the bundled data against the game",
	HELP_DUMP = "/agf dump - save the guide's layout for a bug report",
	HAND_IN_WHEN = "Hand in when you're in %s",
	-- Journey cards (docs/design.md §2.2 and §3): a title, a subline that counts, and a reason when there is one.
	JOURNEY_CARRY = "Finish what you carry",
	JOURNEY_STORY = "%s story",
	JOURNEY_NEXT_ZONE = "Head to %s",
	-- The next zone's level goes under its name, so a long zone name never cuts it off.
	NEXT_ZONE_LEVEL = "For level %d",
	DUNGEON_QUESTS = "%d quests for this dungeon",
	DUNGEON_QUESTS_ONE = "1 quest for this dungeon",
	-- The carry card's counts, joined when several apply: "3 ready to hand in, 1 in progress".
	CARRY_READY = "%d ready to hand in",
	CARRY_IN_PROGRESS = "%d in progress",
	CARRY_AWAY = "%d to hand in across the sea",
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
	NOTHING_NEARBY = "Nothing nearby fits your level.",
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
	-- With no card chosen every card is whole and no steps show (docs/design.md §2.2); the chosen card toggles back.
	CHOOSE_TO_SEE_STEPS = "Choose a journey to see its steps.",
	SHOW_EVERY_JOURNEY = "Click again to see every journey",
	STOP_AND_SHOW_EVERY_JOURNEY = "Click again to stop the route and see every journey",
	-- The chosen journey's route stopped (cleared, replaced or refused): its card and the tracker title resume it.
	CLICK_TO_RESUME = "Click to resume the route",
	ROUTE_PAUSED = "Route paused. Click the journey to resume.",
	-- A card's third line when it has no reason (docs/plan.md §7.4): its first stop, then how many follow.
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
	-- The trainer aside (docs/plan.md F16): text only.
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
	UNLISTED = 'This land has stories the guide doesn\'t know yet; look for the "!" over quest givers.',
	-- The tracker's one line while no journey is chosen: a story's title, then its reason or chapter.
	STORY_HOOK = "%s · %s",
}
local L = ns.L

-- Account-wide settings (Settings.lua), one key per row on the AddOns page. A missing key
-- always reads as its default here, so an old save file and a new option agree (WFA-14).
---@type table<string, boolean>
local DEFAULTS = {
	showTracker = true,
	-- Opt-in: with the Adventure tab closed the map shows no Adventure Guide mark unless the player asks for them.
	showMapPins = false,
	showQuestGivers = false,
	includeDungeonsDefault = false,
	-- Choosing a journey starts its route too; the key keeps the name it had when only the tracker title did, so a
	-- saved choice carries over.
	titleStartsRoute = true,
	-- Opt-in (roadmap #17): the route never takes over the player's tracked quests unasked. A saved true stays true.
	trackRouteQuests = false,
	-- Opt-in: it throws away the player's own choice of tracked quests.
	untrackOthers = false,
}
ns.DEFAULTS = DEFAULTS

-- Per-character prefs (AGFPrefs). `dungeons` seeds from the account-wide default the first
-- time this character is seen; every other key is a plain default merged in on load.
local PREFS_DEFAULTS = {
	quests = true,
	dungeons = false,
	notInterested = {},
}

---@type table<string, any>?
local db
---@type AGFPrefs?
local charDB
-- Skipped steps never survive a reload: a step hidden this session is worth seeing again
-- next time the route is rebuilt from scratch.
---@type table<string, boolean>
local sessionSkipped = {}
-- The same steps in the order they were skipped, with the titles the menu offers them back by.
---@type AGFSkipped[]
local skippedOrder = {}

---@param msg string
function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99" .. ns.TITLE .. "|r " .. msg)
end

local function LoadDB()
	local loaded = type(AdventureGuideForeverDB) == "table" and AdventureGuideForeverDB or {}
	for key, value in pairs(DEFAULTS) do
		if type(loaded[key]) ~= type(value) then
			loaded[key] = value
		end
	end
	AdventureGuideForeverDB = loaded
	db = loaded
end

local function LoadCharDB()
	local loaded = type(AdventureGuideForeverCharDB) == "table" and AdventureGuideForeverCharDB or {}
	-- First time this character is seen: honour the account-wide default instead of PREFS_DEFAULTS.dungeons.
	if loaded.dungeons == nil then
		loaded.dungeons = db and db.includeDungeonsDefault or false
	end
	for key, value in pairs(PREFS_DEFAULTS) do
		if key ~= "dungeons" and type(loaded[key]) ~= type(value) then
			loaded[key] = type(value) == "table" and {} or value
		end
	end
	-- Journeys marked "Not interested": key -> the title Show again names it by.
	for key, title in pairs(loaded.notInterested) do
		if type(key) ~= "string" or type(title) ~= "string" then
			loaded.notInterested[key] = nil
		end
	end
	-- The zone picked in the old "Where next?" cards: nothing offers that choice any more, so none is kept.
	loaded.zone = nil
	if loaded.journey ~= nil and type(loaded.journey) ~= "string" then
		loaded.journey = nil
	end
	-- One key names a zone's journey, whether it shows as the zone's story or as heading there (docs/design.md §2.10).
	if loaded.journey then
		loaded.journey = loaded.journey:gsub("^story:", "zone:"):gsub("^nextzone:", "zone:")
	end
	local last = loaded.last
	if last ~= nil and not (type(last) == "table" and type(last.key) == "string" and type(last.reason) == "string") then
		loaded.last = nil
	end
	if loaded.guided ~= nil and type(loaded.guided) ~= "string" then
		loaded.guided = nil
	end
	local waypoint = loaded.waypoint
	if
		waypoint ~= nil
		and not (
			type(waypoint) == "table"
			and type(waypoint.map) == "number"
			and type(waypoint.x) == "number"
			and type(waypoint.y) == "number"
		)
	then
		loaded.waypoint = nil
	end
	-- The defaults loop above guarantees every AGFPrefs field except `skipped`, which ns.Prefs()
	-- always sets before returning; nothing else reads charDB directly.
	---@cast loaded AGFPrefs
	AdventureGuideForeverCharDB = loaded
	charDB = loaded
end

---@param key string
---@return any
function ns.Setting(key)
	local value = db and db[key]
	if value == nil then
		return DEFAULTS[key]
	end
	return value
end

---@param key string
---@param value any
function ns.SetSetting(key, value)
	if not db then
		return
	end
	db[key] = value
	-- Cheap: this only wakes listeners (Panel/Pins/Tracker) to redraw with the new setting;
	-- the route itself rarely depends on an account-wide setting.
	ns.Invalidate()
end

---@return AGFPrefs
function ns.Prefs()
	charDB = charDB or { quests = true, dungeons = false, notInterested = {} }
	charDB.skipped = sessionSkipped
	return charDB
end

---@param key string
---@param title string
function ns.Skip(key, title)
	if not sessionSkipped[key] then
		sessionSkipped[key] = true
		skippedOrder[#skippedOrder + 1] = { key = key, title = title }
	end
	ns.Invalidate()
end

-- "Not interested" (roadmap #17): the journey `key` is left out on this character until Show again, and a choice of it
-- ends, as a click on its card would.
---@param key string
---@param title string
function ns.NotInterested(key, title)
	local prefs = ns.Prefs()
	prefs.notInterested[key] = title
	if prefs.journey == key then
		ns.Choose(nil)
	else
		ns.Invalidate()
	end
end

---@param key string
function ns.Unskip(key)
	local aside = key:match("^aside:(.+)$")
	if aside then
		ns.Asides.Restore(aside)
		return
	end
	ns.Prefs().notInterested[key] = nil
	sessionSkipped[key] = nil
	for index, skipped in ipairs(skippedOrder) do
		if skipped.key == key then
			table.remove(skippedOrder, index)
			break
		end
	end
	ns.Invalidate()
end

-- This session's skipped steps in the order they were skipped, then the journeys this character is not interested in,
-- by title, then the asides it turned down (keyed "aside:<key>", named by their text).
---@return AGFSkipped[]
function ns.Skipped()
	local all, journeys = {}, {}
	for index, skipped in ipairs(skippedOrder) do
		all[index] = skipped
	end
	for key, title in pairs(ns.Prefs().notInterested) do
		journeys[#journeys + 1] = { key = key, title = title }
	end
	table.sort(journeys, function(a, b)
		if a.title ~= b.title then
			return a.title < b.title
		end
		return a.key < b.key
	end)
	for _, journey in ipairs(journeys) do
		all[#all + 1] = journey
	end
	for _, aside in ipairs(ns.Asides.Declined()) do
		all[#all + 1] = { key = "aside:" .. aside.key, title = aside.text }
	end
	return all
end

-- The step's quests in the log: a town's hand-ins, or every quest of a turn-in or objectives (a group quest under
-- way is a "dungeon" step); a town's pickups never are.
---@param step AGFStep
---@return integer[]
local function LogQuests(step)
	if step.kind == "hub" then
		return step.handins or {}
	end
	return (step.kind == "turnin" or step.kind == "objective" or step.kind == "dungeon") and step.quests or {}
end

---@param step AGFStep
---@return boolean
function ns.InLog(step)
	return #LogQuests(step) > 0
end

-- A quest in the log opens in Blizzard's own details view (docs/design.md §2.5); anything else is left to the caller.
-- Never in combat, when the quest log's frames are the client's to move. True when the details opened.
---@param step AGFStep
---@return boolean
function ns.ShowQuest(step)
	if not ns.InLog(step) or InCombatLockdown() then
		return false
	end
	OpenQuestLog()
	QuestMapFrame_ShowQuestDetails(LogQuests(step)[1])
	return true
end

-- The route's quests in the log join the objective tracker; the client refuses any past its watch limit, and sorts
-- the watches itself (by distance, on each zone change), so no order is kept. With untrackOthers, every other
-- tracked quest leaves first, which also makes room.
function ns.TrackRouteQuests()
	local onRoute, order = {}, {}
	for _, step in ipairs(ns.Route().steps) do
		for _, questID in ipairs(LogQuests(step)) do
			if not onRoute[questID] then
				onRoute[questID] = true
				order[#order + 1] = questID
			end
		end
	end
	if ns.Setting("untrackOthers") then
		for index = C_QuestLog.GetNumQuestWatches(), 1, -1 do
			local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(index)
			if questID and not onRoute[questID] then
				C_QuestLog.RemoveQuestWatch(questID)
			end
		end
	end
	for _, questID in ipairs(order) do
		C_QuestLog.AddQuestWatch(questID)
	end
end

--[[ Route: rebuilt lazily, with invalidations from events/prefs coalesced onto one
     C_Timer.After(0) so a burst of QUEST_LOG_UPDATE events costs one rebuild. ]]

---@type AGFRoute
local cachedRoute = { journeys = {}, chosen = false, steps = {} }
local dirty = true
local pendingRebuild = false
---@type fun()[]
local routeListeners = {}

-- Combat ends: the full build the fight put off. Registered only while one is owed, so no event runs otherwise.
local afterCombat = CreateFrame("Frame")
afterCombat:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	ns.Invalidate()
end)

-- In combat only the cheap rebuild runs (the log's steps; the rest as the last full build left them), and the full
-- one waits for PLAYER_REGEN_ENABLED: looting a quest item mid-fight must not cost a frame.
local function BuildRoute()
	local state = ns.State
	if InCombatLockdown() then
		afterCombat:RegisterEvent("PLAYER_REGEN_ENABLED")
		return ns.Model.Refresh(
			ns.Data,
			state.Player(),
			state.Completed(),
			state.Log(),
			ns.Prefs(),
			cachedRoute,
			state.MapName
		)
	end
	return ns.Model.Plan(
		ns.Data,
		state.Player(),
		state.Completed(),
		state.Log(),
		ns.Prefs(),
		state.MapName,
		state.InstanceName
	)
end

-- The resume line (docs/design.md §2.5). A login sets the latch; the first rebuild with a step 1 compares it once with
-- the step saved last session, and the line lasts until step 1 changes. A /reload never sets the latch.
local resumeLatch = false
---@type {key: string, reason: string}?
local resume

---@param first? AGFStep
local function Remember(first)
	if not first then
		resume = nil
		return
	end
	local prefs = ns.Prefs()
	local last = prefs.last
	if resumeLatch then
		resumeLatch = false
		resume = last and last.key == first.key and { key = last.key, reason = last.reason } or nil
	elseif resume and resume.key ~= first.key then
		resume = nil
	end
	prefs.last = { key = first.key, reason = first.reason }
end

-- The reason the last session left `step` with, while the resume line stands for it.
---@param step AGFStep
---@return string?
function ns.Resume(step)
	return resume and resume.key == step.key and resume.reason or nil
end

-- A quest was handed in since the last full build: a chosen journey that ends there was completed, not abandoned.
local turnedIn = false

-- QUEST_TURNED_IN, from State.lua: latched for the ending below, then the chapter-end fanfare.
---@param questID integer
function ns.TurnedIn(questID)
	turnedIn = true
	if ns.OnTurnIn then
		ns.OnTurnIn(questID)
	end
end

-- The chosen journey's key a filter hides (Quests or Dungeons off in the cog): the player's own toggle can bring it
-- back, so the choice is kept.
---@param key string
---@param prefs AGFPrefs
---@return boolean
local function Filtered(key, prefs)
	return (key:find("^dungeon:") ~= nil and not prefs.dungeons) or (key:find("^zone:") ~= nil and not prefs.quests)
end

local pendingStart = false

-- A chosen journey the full build no longer has ends (docs/design.md §2.10): its route stops, and the choice is
-- cleared, so the cards are whole again; after a turn-in the tracker says it is complete. A filter keeps the key but
-- stops the route. Judged only on full builds: combat's cheap one keeps the last journeys.
---@param route AGFRoute
local function Ended(route)
	local prefs, completed = ns.Prefs(), turnedIn
	turnedIn = false
	local key = prefs.journey
	if not key or route.chosen then
		return
	end
	if not Filtered(key, prefs) then
		prefs.journey, pendingStart = nil, false
		if completed and ns.OnJourneyComplete then
			ns.OnJourneyComplete()
		end
	end
	if prefs.guided == key then
		ns.Integrations.Cancel()
	end
end

local function Rebuild()
	pendingRebuild = false
	if not ns.State.Ready() then
		-- Completed-quest data hasn't loaded yet; an empty route beats a wrong one.
		cachedRoute = { journeys = {}, chosen = false, steps = {} }
		return
	end
	cachedRoute = BuildRoute()
	dirty = false
	if not InCombatLockdown() then
		Ended(cachedRoute)
	end
	-- A skipped step the full build no longer finds (turned in, abandoned) leaves Skipped (n): Show again would
	-- bring nothing back.
	local seen = cachedRoute.skipped
	if seen then
		for index = #skippedOrder, 1, -1 do
			local key = skippedOrder[index].key
			if not seen[key] then
				sessionSkipped[key] = nil
				table.remove(skippedOrder, index)
			end
		end
	end
	Remember(cachedRoute.steps[1])
end

---@return AGFRoute
function ns.Route()
	if dirty then
		Rebuild()
	end
	return cachedRoute
end

---@param fn fun()
function ns.OnRouteChange(fn)
	routeListeners[#routeListeners + 1] = fn
end

local function NotifyRouteChange()
	for _, fn in ipairs(routeListeners) do
		fn()
	end
end

-- Step 1's travel frame is queued: it and the rebuild's frame belong to their own estimate.
local travelPending = false

-- Skipped when an invalidation landed since the rebuild: ns.Route() would rebuild in this frame too, and the
-- pending rebuild queues its own refresh. The asides are asked in this frame too. The cards wait for this frame and
-- ask from the next.
local function RefreshTravel()
	travelPending = false
	if not pendingRebuild then
		ns.Integrations.RefreshTravel()
		ns.Asides.Refresh()
		ns.Integrations.ResumeCards()
	end
end

function ns.Invalidate()
	dirty = true
	if pendingRebuild then
		return
	end
	pendingRebuild = true
	C_Timer.After(0, function()
		-- A caller in the same frame (the map a card click turns) may have rebuilt through ns.Route() already.
		if dirty then
			Rebuild()
		else
			pendingRebuild = false
		end
		-- Set before the listeners run, so a card estimate they queue waits out step 1's frame too.
		travelPending = true
		NotifyRouteChange()
		-- Step 1's travel line gets a frame of its own: at most one Shortest Path estimate, never in the rebuild's.
		C_Timer.After(0, RefreshTravel)
	end)
end

-- A rebuild or step 1's travel line is due: this frame or the next belongs to them, not to a card's estimate.
---@return boolean
function ns.Settling()
	return pendingRebuild or travelPending
end

--[[ Choosing and starting a journey (docs/design.md §2.10): the cards, the tracker, the menus and the map's rings all
     come through here, so every route AGF starts runs on the chosen journey, and prefs.guided records which. ]]

-- pendingStart (above, for the ending): a start waiting for the rebuild that has the chosen journey's steps, or for
-- combat's end. Shortest Path refuses every route in combat, and the rebuild PLAYER_REGEN_ENABLED brings (afterCombat)
-- runs it.

-- Chooses `key`, or none. With `start` its route starts on the rebuild that has its steps. Leaving the journey whose
-- route AGF started stops that route, unless the new choice's start replaces it; never anyone else's.
---@param key? string
---@param start? boolean
function ns.Choose(key, start)
	local prefs = ns.Prefs()
	local guided = prefs.guided
	prefs.journey = key
	pendingStart = key ~= nil and start == true
	if guided and guided ~= key and not pendingStart then
		ns.Integrations.Cancel()
	end
	ns.Invalidate()
end

-- Guidance along the chosen journey from `step`, its first by default. With none chosen, the route's own journey (the
-- first card) is chosen first. With Shortest Path loaded a start in combat waits for
-- combat's end. True when something now guides the player, or the start waits.
---@param step? AGFStep
---@return boolean
function ns.StartRoute(step)
	local route, prefs = ns.Route(), ns.Prefs()
	if not route.journey then
		return false
	end
	if not route.chosen then
		prefs.journey = route.journey
		ns.Invalidate()
	end
	if InCombatLockdown() and ns.Integrations.Provider() then
		pendingStart = true
		return true
	end
	pendingStart = false
	step = step or route.steps[1]
	if step and ns.Integrations.Navigate(step) then
		prefs.guided = route.journey
		return true
	end
	return false
end

-- The player's Stop, from the footer or a step's menu: what a click on the guided card does, so no journey is left
-- chosen with nothing to resume it.
function ns.Stop()
	ns.Integrations.Cancel()
	ns.Choose(nil)
end

-- A start is waiting for combat to end.
---@return boolean
function ns.StartPending()
	return pendingStart
end

-- The route AGF started for the chosen journey stopped without the player's Stop: cleared in Shortest Path, replaced
-- by another journey, refused after a /reload, or its waypoint moved. It has steps, nothing of ours guides it and no
-- start is on its way, so its card and the tracker title resume it rather than clear the choice. A route that arrived
-- at its last stop is done, not paused.
---@return boolean
function ns.Paused()
	local route, integrations = ns.Route(), ns.Integrations
	local key = route.journey
	return route.chosen
		and (ns.Prefs().guided == key or integrations.Stopped() == key)
		and #route.steps > 0
		and ns.Setting("titleStartsRoute")
		and not pendingStart
		and not integrations.Owns()
		and not integrations.Arrived()
end

-- Registered before any view's listener, so the footer already reads the route as started.
ns.OnRouteChange(function()
	if pendingStart and not InCombatLockdown() and ns.Route().chosen then
		ns.StartRoute()
	end
end)

-- Shortest Path's journeys end with the session, so a /reload or login brings back the route AGF had started for the
-- chosen journey (prefs.guided), once, on the first full build that has its steps. Not over someone else's journey,
-- which then keeps the way; and a Shortest Path that declines is asked again on the next full build. The native
-- waypoint needs nothing: the client keeps it.
local restoring = true
ns.OnRouteChange(function()
	if not restoring or InCombatLockdown() or not ns.State.Ready() then
		return
	end
	local prefs, route, integrations = ns.Prefs(), ns.Route(), ns.Integrations
	if not (prefs.guided and route.chosen and route.journey == prefs.guided) or integrations.Owns() then
		restoring = false
	elseif not integrations.Provider() or integrations.ReplacesJourney() then
		restoring, prefs.guided = false, nil
	elseif integrations.Restore(route.steps) then
		restoring = false
	end
end)

--[[ Slash command and audit ]]

local function Audit()
	local data = ns.Data
	local clientVersion, clientBuild = GetBuildInfo()
	ns.Print(L.AUDIT_BUILD:format(data.build, clientVersion, clientBuild))

	local bundled = 0
	for _ in pairs(data.quests) do
		bundled = bundled + 1
	end

	local player, completed, log = ns.State.Player(), ns.State.Completed(), ns.State.Log()
	local eligible = 0
	for questID in pairs(data.quests) do
		if ns.Model.Eligible(data, player, completed, log, questID) then
			eligible = eligible + 1
		end
	end

	local completedKnown = 0
	for _ in pairs(completed) do
		completedKnown = completedKnown + 1
	end

	ns.Print(L.AUDIT_COUNTS:format(bundled, eligible, completedKnown))
	if not ns.State.Ready() then
		ns.Print(L.AUDIT_NOT_READY)
	end
end

SLASH_ADVENTUREGUIDEFOREVER1 = "/agf"
SLASH_ADVENTUREGUIDEFOREVER2 = "/adventureguide"
SlashCmdList.ADVENTUREGUIDEFOREVER = function(msg)
	local command = strtrim(msg or ""):lower()
	if command == "audit" then
		Audit()
	elseif command == "dump" then
		ns.Dump()
	elseif command == "" then
		if ns.OpenPanel then
			ns.OpenPanel()
		end
	else
		ns.Print(L.HELP_OPEN)
		ns.Print(L.HELP_AUDIT)
		ns.Print(L.HELP_DUMP)
	end
end

function AdventureGuideForever_OnAddonCompartmentClick()
	if not WorldMapFrame:IsShown() then
		ToggleWorldMap()
	end
	if ns.OpenPanel then
		ns.OpenPanel()
	end
end

-- Deferred to ADDON_LOADED: every TOC file (including State.lua and Settings.lua, which load
-- after this one) has run by then, so forward references to ns.State/ns.RegisterSettings resolve.
EventUtil.ContinueOnAddOnLoaded(addonName, function()
	LoadDB()
	LoadCharDB()
	ns.State.OnChange(ns.Invalidate)
	ns.State.OnInitialLogin(function()
		resumeLatch = true
	end)
	if ns.RegisterSettings then
		ns.RegisterSettings()
	end
end)
