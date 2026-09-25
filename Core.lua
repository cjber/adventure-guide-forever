---@type string, AGFNamespace
local addonName, ns = ...

local L = ns.L
ns.TITLE = L.TITLE

-- Account-wide settings (Settings.lua), one key per row on the AddOns page. A missing key
-- always reads as its default here, so an old save file and a new option agree (WFA-14).
---@type table<string, boolean>
local DEFAULTS = {
	showTracker = true,
	stepSound = true,
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
	-- Roadmap #24: hint strength, Guide (false) or Wanderer (true), which gates every waypoint, route and map mark.
	wanderer = false,
	-- Walking into the quest area the route leads to selects its quest, so the map draws its blue area (Focus.lua).
	followQuest = true,
	-- One chat line after an update (WhatsNew).
	whatsNew = true,
	-- A line where a missing companion addon would fill a tab or a route step (Companions.lua).
	suggestCompanions = true,
}
ns.DEFAULTS = DEFAULTS

-- Per-character prefs (AGFPrefs). `dungeons` seeds from the account-wide default the first
-- time this character is seen; every other key is a plain default merged in on load.
local PREFS_DEFAULTS = {
	quests = true,
	dungeons = false,
	-- Opt-in (roadmap #12): the Battlegrounds card.
	battlegrounds = false,
	notInterested = {},
	-- Quests added to the route with a shift-click: quest ID -> true.
	pinned = {},
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
	-- Journeys marked "Not interested": key -> the title Show again names it by, and whether it ended the choice of it.
	-- A bare title is the older shape, from before `chosen` was kept: a journey that was not chosen.
	for key, entry in pairs(loaded.notInterested) do
		entry = type(entry) == "string" and { title = entry } or entry
		if type(key) ~= "string" or type(entry) ~= "table" or type(entry.title) ~= "string" then
			loaded.notInterested[key] = nil
		else
			loaded.notInterested[key] = { title = entry.title, chosen = entry.chosen == true or nil }
		end
	end
	for id, value in pairs(loaded.pinned) do
		if type(id) ~= "number" or value ~= true then
			loaded.pinned[id] = nil
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
	if loaded.focus ~= nil and type(loaded.focus) ~= "number" then
		loaded.focus = nil
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
	if type(loaded.customOrders) ~= "table" then
		loaded.customOrders = nil
	end
	for key, order in pairs(loaded.customOrders or {}) do
		if type(key) ~= "string" or type(order) ~= "table" then
			loaded.customOrders[key] = nil
		else
			local keys, seen = {}, {}
			for _, value in ipairs(order) do
				if type(value) == "string" and not seen[value] then
					keys[#keys + 1], seen[value] = value, true
				end
			end
			loaded.customOrders[key] = keys
		end
	end
	local session = loaded.sessionCommit
	if
		session ~= nil
		and not (
			type(session) == "table"
			and type(session.journey) == "string"
			and type(session.minutes) == "number"
			and type(session.keys) == "table"
			and (session.members == nil or type(session.members) == "table")
			and (session.visits == nil or type(session.visits) == "table")
			and (session.seconds == nil or type(session.seconds) == "number")
		)
	then
		loaded.sessionCommit = nil
	end
	if loaded.sessionCommit then
		for _, members in pairs(session.members or {}) do
			if type(members) ~= "table" then
				loaded.sessionCommit = nil
			end
		end
		for action, key in pairs(session.visits or {}) do
			if type(action) ~= "string" or type(key) ~= "string" then
				loaded.sessionCommit = nil
			end
		end
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
	-- Wandering from now: what Go started stops, as the player's Stop would.
	if key == "wanderer" and value then
		ns.Integrations.Cancel()
	end
	-- Rebuilds the route (cheap) and wakes listeners (Panel/Pins/Tracker) to redraw with the new setting.
	ns.Invalidate()
end

-- The Adventure Guide window's own account-wide state (Window.lua): where it was left, its tab, and whether the
-- default key was offered. Not a setting: nothing rebuilds when it changes.
---@return AGFWindowDB
function ns.WindowDB()
	if not db then
		return {}
	end
	if type(db.window) ~= "table" then
		db.window = {}
	end
	return db.window
end

---@return AGFPrefs
function ns.Prefs()
	charDB = charDB or { quests = true, dungeons = false, notInterested = {}, pinned = {} }
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
-- ends, as a click on its card would; Show again chooses it again, after a /reload too.
---@param key string
---@param title string
function ns.NotInterested(key, title)
	local prefs = ns.Prefs()
	prefs.notInterested[key] = { title = title, chosen = prefs.journey == key or nil }
	if prefs.journey == key then
		ns.Choose(nil)
	else
		ns.Invalidate()
	end
end

-- "Not this quest" (docs/design.md §2.18): quest `id` leaves every route on this character, and stays in the log; the
-- Skipped menu's Show again brings it back.
---@param id integer
---@param title string
function ns.NotThisQuest(id, title)
	ns.Prefs().pinned[id] = nil
	ns.NotInterested("quest:" .. id, title)
end

-- Whether every quest in `ids` is on the route by the player's shift-click.
---@param ids integer[]
---@return boolean
function ns.Pinned(ids)
	local pinned = ns.Prefs().pinned
	for _, id in ipairs(ids) do
		if not pinned[id] then
			return false
		end
	end
	return #ids > 0
end

-- A shift-click (docs/design.md §2.18): the quests `ids` join the route whatever the planner would leave out, or leave
-- it when they all had joined. Ruled-out quests come back too.
---@param ids integer[]
function ns.TogglePinned(ids)
	local prefs, pin = ns.Prefs(), not ns.Pinned(ids)
	for _, id in ipairs(ids) do
		prefs.pinned[id] = pin or nil
		if pin then
			prefs.notInterested["quest:" .. id] = nil
		end
	end
	ns.Invalidate()
end

---@param key string
function ns.Unskip(key)
	local aside = key:match("^aside:(.+)$")
	if aside then
		ns.Asides.Restore(aside)
		return
	end
	local dismissed = ns.Prefs().notInterested[key]
	local chosen = dismissed ~= nil and dismissed.chosen
	ns.Prefs().notInterested[key] = nil
	sessionSkipped[key] = nil
	for index, skipped in ipairs(skippedOrder) do
		if skipped.key == key then
			table.remove(skippedOrder, index)
			break
		end
	end
	if chosen then
		ns.Choose(key, ns.Setting("titleStartsRoute"))
		return
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
	for key, dismissed in pairs(ns.Prefs().notInterested) do
		journeys[#journeys + 1] = { key = key, title = dismissed.title }
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

-- The step's quests in the log: a town's hand-ins, or every quest of a turn-in or an area (a group quest's is a
-- "dungeon" step); a town's pickups never are.
---@param step AGFStep
---@return integer[]
local function LogQuests(step)
	local quests = (step.kind == "town" and step.handins)
		or ((step.kind == "turnin" or step.kind == "area" or step.kind == "dungeon") and step.quests)
		or {}
	if not step.planned then
		return quests
	end
	-- A quest the route picks up first wasn't in the log when it was planned.
	local carried = {}
	for _, id in ipairs(quests) do
		carried[#carried + 1] = not step.planned[id] and id or nil
	end
	return carried
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
local rawRoute = cachedRoute
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

-- The spells to train the last full build took (roadmap #5), asked of Tweaks Forever only while a journey is chosen,
-- the only route that stops to train; combat's cheap rebuild keeps them, as Tweaks Forever has no answer in a fight.
---@type AGFTraining?
local training
local trained = false
---@type table<integer, AGFLogQuest>
local buildLog = {}

-- In combat only the cheap rebuild runs (the log's steps; the rest as the last full build left them), and the full
-- one waits for PLAYER_REGEN_ENABLED: looting a quest item mid-fight must not cost a frame.
local function BuildRoute()
	local state, prefs, player = ns.State, ns.Prefs(), ns.State.Player()
	buildLog = state.Log()
	if InCombatLockdown() then
		trained = false
		afterCombat:RegisterEvent("PLAYER_REGEN_ENABLED")
		player.train = training
		return ns.Model.Refresh(ns.Data, player, state.Completed(), buildLog, prefs, rawRoute, state.MapName)
	end
	local previous, known = training, false
	if prefs.journey then
		training, known = ns.Integrations.Training()
	else
		training = nil
	end
	trained = previous ~= nil and known and training == nil
	player.train = training
	return ns.Model.Plan(
		ns.Data,
		player,
		state.Completed(),
		buildLog,
		prefs,
		state.MapName,
		state.InstanceName,
		rawRoute
	)
end

-- The "you're here" head (docs/design.md §4.2): the route is rebuilt on events, never as the player moves, save that
-- walking into an open area the route goes to makes it the head and holds guidance there, and walking out of it
-- (past Model.Here's margin) lets guidance go on. Checked every HERE_EVERY seconds only while they move
-- (PLAYER_STARTED_MOVING to PLAYER_STOPPED_MOVING), so nothing runs while they stand still, and once per area entered
-- or left.
local HERE_EVERY = 2
---@type {Cancel: fun(self)}?
local walking
---@type string?
local hereKey
local function Walked()
	if InCombatLockdown() then
		return
	end
	local map, x, y = ns.State.Where()
	local steps = cachedRoute.steps
	local first = steps[1]
	if first and first.checklist and map and x and y then
		local nearest, distance
		for _, giver in ipairs(first.checklist) do
			local yards = not giver.done and ns.Model.Yards(ns.Data, { map = map, x = x, y = y }, giver.place)
			if yards and (not distance or yards < distance) then
				nearest, distance = giver.place, yards
			end
		end
		if nearest and (nearest.map ~= first.map or nearest.x ~= first.x or nearest.y ~= first.y) then
			ns.Invalidate()
		end
	end
	local index = ns.Model.Here(ns.Data, { map = map, x = x, y = y }, steps, cachedRoute.here)
	local key = index and steps[index].key or nil
	if key ~= hereKey and key ~= cachedRoute.here then
		ns.Invalidate()
	end
	hereKey = key
end
local moving = CreateFrame("Frame")
moving:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_STARTED_MOVING" then
		walking = walking or C_Timer.NewTicker(HERE_EVERY, Walked)
	elseif walking then
		walking:Cancel()
		walking = nil
		Walked()
	end
end)
-- By feature detection, as State's optional events: without them the head moves on the next event's rebuild.
for _, event in ipairs({ "PLAYER_STARTED_MOVING", "PLAYER_STOPPED_MOVING" }) do
	pcall(moving.RegisterEvent, moving, event)
end

-- A spell learned (or a new level's) changes what the trainer stop says, or ends it: rebuild when the answer moved.
local spellbook = CreateFrame("Frame")
spellbook:SetScript("OnEvent", function()
	if not ns.Prefs().journey or InCombatLockdown() then
		return
	end
	local now = ns.Integrations.Training()
	if (now and now.count) ~= (training and training.count) or (now and now.level) ~= (training and training.level) then
		ns.Invalidate()
	end
end)

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

-- The chosen journey's key a filter hides (Quests, Dungeons or Battlegrounds off in the cog): the player's own toggle
-- can bring it back, so the choice is kept. With no next zone (roadmap #21) Dungeons hides nothing, so a dungeon that
-- went ended.
---@param key string
---@param prefs AGFPrefs
---@param route AGFRoute
---@return boolean
local function Filtered(key, prefs, route)
	return (key:find("^dungeon:") ~= nil and not prefs.dungeons and not route.stranded)
		or ((key:find("^zone:") ~= nil or key:find("^chain:") ~= nil or key == "calling") and not prefs.quests)
		or (key:find("^battleground:") ~= nil and not prefs.battlegrounds)
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
	if not Filtered(key, prefs, route) then
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
	local previous = cachedRoute
	rawRoute = BuildRoute()
	ns.Order.Apply(rawRoute, ns.Prefs())
	ns.Sound.Observe(previous, rawRoute, ns.State.Completed(), buildLog, trained)
	cachedRoute = ns.Session.Apply(rawRoute)
	dirty = false
	if not InCombatLockdown() then
		Ended(rawRoute)
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
-- pending rebuild queues its own refresh. The asides are asked in this frame too, then Moments compares what is
-- offered. The cards wait for this frame and ask from the next.
local function RefreshTravel()
	travelPending = false
	if not pendingRebuild then
		ns.Integrations.RefreshTravel()
		ns.Asides.Refresh()
		ns.Moments.Observe()
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
	if ns.Prefs().journey ~= key then
		ns.Prefs().sessionCommit = nil
	end
	local prefs = ns.Prefs()
	local guided = prefs.guided
	prefs.journey = key
	-- A wanderer's choice starts nothing (StartRoute), so nothing waits for combat's end either.
	pendingStart = key ~= nil and start == true and not ns.Setting("wanderer")
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
	-- A wanderer (roadmap #24) chooses the journey and sets off on foot: nothing to start, now or after combat.
	if ns.Setting("wanderer") then
		pendingStart = false
		return false
	elseif ns.Session.Info().pending then
		pendingStart = true
		return true
	elseif InCombatLockdown() and ns.Integrations.Provider() then
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

-- The player's Stop, from the footer or a step's menu: what the back arrow does while it runs, so no journey is left
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
	local route = ns.Route()
	if route.chosen and #route.steps == 0 and ns.Prefs().guided == route.journey and ns.Integrations.Owns() then
		local waiting = ns.Session.Info().pending
		ns.Integrations.Cancel()
		pendingStart = pendingStart or waiting
	end
	if pendingStart and not InCombatLockdown() and ns.Route().chosen then
		ns.StartRoute()
	end
end)

-- No journey chosen draws nothing (docs/design.md §2.2): however the choice went (a click, Not interested, Stop, the
-- journey ending or leaving the cards), what AGF guides stops with it. Only ours: Cancel ends Shortest Path's journey
-- by our name and the waypoint only while it sits where Go put it. Judged on full builds, as Ended is: combat's cheap
-- one can drop a card it will bring back.
local wasChosen = false
ns.OnRouteChange(function()
	if InCombatLockdown() then
		return
	end
	local chosen = ns.Route().chosen
	if wasChosen and not chosen and ns.Integrations.Owns() then
		ns.Integrations.Cancel()
	end
	wasChosen = chosen
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
	local data, questie = ns.Data, ns.QuestieStatus
	local clientVersion, clientBuild = GetBuildInfo()
	ns.Print(L.AUDIT_BUILD:format(data.build, clientVersion, clientBuild))
	if questie.state == "questie" then
		ns.Print(L.AUDIT_SOURCE_QUESTIE:format(questie.version))
	else
		ns.Print(L.AUDIT_SOURCE_BUNDLED)
		if questie.state == "building" then
			ns.Print(L.AUDIT_QUESTIE_BUILDING)
		elseif questie.reason then
			ns.Print(L.AUDIT_QUESTIE_UNUSED:format(questie.reason))
		end
	end

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
	elseif command == "" or command == "window" then
		ns.OpenWindow()
	else
		ns.Print(L.HELP_OPEN)
		ns.Print(L.HELP_AUDIT)
		ns.Print(L.HELP_DUMP)
	end
end

-- Left-click toggles the window; any other click opens the guide on the world map, as every click once did.
---@param _ string the addon's name
---@param mouseButton? string
function AdventureGuideForever_OnAddonCompartmentClick(_, mouseButton)
	if mouseButton == nil or mouseButton == "LeftButton" then
		ns.ToggleWindow()
		return
	end
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
	spellbook:RegisterEvent("SPELLS_CHANGED")
	ns.State.OnInitialLogin(function()
		resumeLatch = true
	end)
	ns.RegisterSettings()
	EventUtil.ContinueAfterAllEvents(ns.WhatsNew, "PLAYER_LOGIN")
end)

-- After an update, one chat line says what changed. Never on a first install (no version seen yet, which is also
-- every login on a client that doesn't load saved variables), nor in a dev checkout, whose TOC version the packager
-- hasn't filled in. `lastVersion` is a record, not a setting, so it has no default.
function ns.WhatsNew()
	local version = C_AddOns.GetAddOnMetadata(addonName, "Version")
	if not db or type(version) ~= "string" or version == "" or version:sub(1, 1) == "@" then
		return
	end
	local seen = db.lastVersion
	db.lastVersion = version
	if type(seen) == "string" and seen ~= version and ns.Setting("whatsNew") then
		ns.Print(L.UPDATED_TO:format(version, L.WHATS_NEW))
	end
end
