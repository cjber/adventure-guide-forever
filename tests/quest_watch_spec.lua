-- Run from the repository root: luajit tests/quest_watch_spec.lua
-- One watch owner for a leading RestedXP guide and an Adventure Guide journey (#682): the journey's quests are
-- tracked, and the player's own are never untracked (#865).
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end
local function check(value, label)
	checks = checks + 1
	if not value then
		error(label, 2)
	end
end

local function Load(options)
	options = options or {}
	local log = {
		{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
		{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
		{ id = 850, title = "Kolkar Leaders", level = 15, complete = false },
		{ id = 855, title = "Centaur Bracers", level = 15, complete = false },
	}
	local db = {}
	for key, value in pairs(options.db or {}) do
		db[key] = value
	end
	db.autoStart = false
	return harness.load({
		planned = true,
		spf = "v1",
		db = db,
		charDB = options.charDB or {},
		completed = { 844 },
		log = log,
	})
end

local function Watched(h, questID)
	for _, each in ipairs(h.watched) do
		if each == questID then
			return true
		end
	end
	return false
end

-- #865: a journey leads. Its quests in the log are tracked, and every quest the player tracked stays tracked.
local h = Load()
h.watched = { 850, 855, 843 }
h.ns.Choose("zone:1413", false)
h.flush()
equal(h.ns.QuestWatch.Source(), "journey", "the chosen journey leads")
equal(h.ns.Route().chosen, true, "the route is chosen")
equal(Watched(h, 845), true, "the journey's hand-in is tracked")
for _, questID in ipairs({ 850, 855, 843 }) do
	equal(Watched(h, questID), true, "the player's tracked quest " .. questID .. " stays tracked")
end
local state = h.ns.Prefs().guideWatch
check(state ~= nil and state.added[845], "the journey's own watch is kept on the character")
equal(#state.saved, 0, "no player list is kept: nothing of theirs is taken away")
equal(h.ns.State.Tracked()[845], nil, "the journey's watch is not counted as the player's")
equal(h.ns.State.Tracked()[850], true, "the player's own are")

-- The tracker header keeps the journey's whole title on one line, at the header's own width.
local journey = h.ns.CurrentJourney()
local title = journey.title
journey.title = string.rep("A very long journey title ", 10)
h.fire("CVAR_UPDATE", "questPOI")
local heading = h.tracker.Header.Text
equal(heading:GetText(), journey.title, "the full journey title is the header's text")
equal(heading.wordWrap, false, "the title stays on one line")
equal(heading.maxLines, 1, "...")
journey.title = title
local menu = h.OpenTrackerMenu(h.tracker)
for _, entry in ipairs(menu.entries) do
	check(entry.text ~= "Show all quests", "the header menu has no Show all quests: nothing is hidden")
end

-- The player untracks one of their own quests and tracks the journey's by hand: both stay as they left them.
for index = #h.watched, 1, -1 do
	if h.watched[index] == 855 then
		table.remove(h.watched, index)
	end
end
h.fire("QUEST_WATCH_LIST_CHANGED", 855, false)
h.flush()
equal(Watched(h, 855), false, "a quest the player untracks by hand stays untracked")

-- The client tracks a quest on accept; one the journey does not name is the addon's, not the player's, and goes in
-- the same event, before the quest tracker's next frame draws it (#860): a block drawn for one frame and taken away
-- in the next grows and shrinks the tracker, and the column under it jumps down and back.
h.watched[#h.watched + 1] = 851
h.fire("QUEST_ACCEPTED", 851)
equal(Watched(h, 851), false, "a quest the client tracked on accept is untracked at once")
h.ns.Invalidate()
h.flush()
equal(Watched(h, 851), false, "and stays untracked after the rebuild")
-- Questie's auto tracking adds the watch a moment after the accept: that one goes at once too.
h.fire("QUEST_ACCEPTED", 852)
h.watched[#h.watched + 1] = 852
h.fire("QUEST_WATCH_LIST_CHANGED", 852, true)
equal(Watched(h, 852), false, "a quest auto tracked after the accept is untracked at once")
h.flush()
-- The client's watch event can come before QUEST_ACCEPTED: its watch is still the client's, never the player's.
h.watched[#h.watched + 1] = 853
h.fire("QUEST_WATCH_LIST_CHANGED", 853, true)
h.fire("QUEST_ACCEPTED", 853)
equal(Watched(h, 853), false, "a quest the client tracked just before the accept event is untracked at once")
h.flush()
-- Progress in a fight longer than the auto window: the client's watch on a quest the player untracked is still the
-- client's after it.
h.SetCombat(true)
h.fire("QUEST_WATCH_UPDATE", 855)
h.watched[#h.watched + 1] = 855
h.fire("QUEST_WATCH_LIST_CHANGED", 855, true)
h.time = h.time + 30
h.SetCombat(false)
h.flush()
equal(Watched(h, 855), false, "a quest the player untracked stays untracked after the client tracks it in a long fight")

-- The setting off takes back only what the journey tracked.
h.ns.SetSetting("journeyWatch", false)
h.flush()
equal(Watched(h, 850), true, "the player's own tracked quests stay")
equal(Watched(h, 843), true, "all of them")
equal(Watched(h, 845), false, "what the journey tracked goes")
equal(h.ns.Prefs().guideWatch, nil, "nothing is kept once the journey stops leading")
check(#h.errors == 0, table.concat(h.errors, "\n"))

-- A journey that names no quest in the log (a Books story, #865): every watch survives, through a switch back to a
-- zone and the journey ending.
h = Load()
h.watched = { 850, 855, 843, 845 }
h.ns.Choose("zone:1413", false)
h.flush()
h.ns.Choose("calling", false)
h.flush()
for _, questID in ipairs({ 850, 855, 843, 845 }) do
	equal(Watched(h, questID), true, "another journey leaves the player's quest " .. questID .. " tracked")
end
h.ns.Stop()
h.flush()
for _, questID in ipairs({ 850, 855, 843, 845 }) do
	equal(Watched(h, questID), true, "ending the journey leaves " .. questID .. " tracked")
end
check(#h.errors == 0, table.concat(h.errors, "\n"))

-- A character saved by an earlier version, whose journey had untracked the player's quests: they come back.
h = Load({
	charDB = {
		journey = "zone:1413",
		guideWatch = { saved = { 850, 855, 999 }, added = {}, named = {}, hidden = { [850] = true, [855] = true } },
	},
})
h.ns.QuestWatch.Sync()
h.flush()
equal(Watched(h, 850), true, "an untracked player quest is tracked again on upgrade")
equal(Watched(h, 855), true, "every one of them")
equal(Watched(h, 999), false, "a quest no longer in the log is not")
equal(#h.ns.Prefs().guideWatch.saved, 0, "the old list is emptied once given back")
equal(next(h.ns.Prefs().guideWatch.hidden), nil, "and so is what it hid")
check(#h.errors == 0, table.concat(h.errors, "\n"))

-- Rolled back to v1.11.0: its reader takes the state this version saves without an error, and with nothing saved it
-- untracks none of the player's quests.
h = Load()
h.watched = { 850, 855, 843 }
h.ns.Choose("zone:1413", false)
h.flush()
local saved = h.ns.Prefs().guideWatch
check(type(saved.saved) == "table" and type(saved.hidden) == "table", "the state keeps the fields v1.11.0 reads")
local v111 = assert(loadfile("tests/fixtures/QuestWatch_v1.11.0.lua"))
setfenv(v111, h.G)
v111("AdventureGuideForever", h.ns)
h.ns.QuestWatch.Sync()
h.flush()
check(#h.errors == 0, table.concat(h.errors, "\n"))
for _, questID in ipairs({ 850, 855, 843 }) do
	equal(Watched(h, questID), true, "v1.11.0 leaves the player's tracked quest " .. questID .. " tracked")
end
equal(h.ns.QuestWatch.Hidden and h.ns.QuestWatch.Hidden() or 0, 0, "and counts none hidden")

-- "Stop tracking other quests" carried over: a saved true turns the new setting on, a saved false leaves its default.
local migrated = Load({ db = { untrackOthers = true } })
equal(migrated.ns.Setting("journeyWatch"), true, "a saved untrackOthers true carries over")
equal(migrated.ns.Setting("untrackOthers"), nil, "and the old key is gone")
local legacyOff = Load({ db = { untrackOthers = false } })
equal(legacyOff.ns.Setting("journeyWatch"), true, "a saved untrackOthers false leaves the new default on")
equal(legacyOff.ns.Setting("untrackOthers"), nil, "and the old key is gone there too")
local chosenOff = Load({ db = { journeyWatch = false } })
equal(chosenOff.ns.Setting("journeyWatch"), false, "a saved new setting keeps its value")

print(("quest_watch_spec: %d checks passed"):format(checks))
