-- Run from the repository root: luajit tests/quest_watch_spec.lua
-- One watch owner for a leading RestedXP guide and an Adventure Guide journey (#682): the journey's quests are
-- tracked, the player's own come back when it stops, and the tracker counts what it hides.
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

-- A journey leads: its quests in the log are tracked and the player's other tracked quests leave, kept on the
-- character.
local h = Load()
h.watched = { 850, 855 }
h.ns.Choose("zone:1413", false)
h.flush()
equal(h.ns.QuestWatch.Source(), "journey", "the chosen journey leads")
equal(h.ns.Route().chosen, true, "the route is chosen")
equal(Watched(h, 845), true, "the journey's hand-in is tracked")
equal(Watched(h, 850), false, "another tracked quest is gone from the tracker")
equal(Watched(h, 855), false, "and so is the next")
local state = h.ns.Prefs().guideWatch
check(state ~= nil, "what the journey hid is kept on the character")
equal(#state.saved, 2, "the player's two quests are saved")
equal(h.ns.QuestWatch.Hidden(), 2, "the tracker counts them as hidden")

-- The notice: a small grey count, its tooltip, and the header menu's Show all quests.
local notice = h.tracker.hiddenText
check(notice ~= nil and notice:IsShown(), "the header shows the hidden count")
equal(notice:GetText(), h.ns.L.TRACKER_HIDDEN_COUNT:format(2), "in the guide's words")
h.tooltip = {}
h.tracker.Header.scripts.OnEnter(h.tracker.Header)
equal(h.tooltip[1], "title: " .. h.ns.CurrentJourney().title, "hovering the header names the journey")
check(
	table.concat(h.tooltip, "\n"):find(h.ns.L.TRACKER_HIDDEN_TOOLTIP:format(2), 1, true) ~= nil,
	"the tooltip says how many are hidden"
)
check(table.concat(h.tooltip, "\n"):find(h.ns.L.TRACKER_HIDDEN_SHOW_ALL, 1, true) ~= nil, "and how to show them")

-- The player tracks one of their own quests by hand while the journey leads: it stays, and the count drops. The
-- header keeps the journey's whole title on one line, narrowed so the client ellipsises it before the count.
local journey = h.ns.CurrentJourney()
local title = journey.title
journey.title = string.rep("A very long journey title ", 10)
h.watched[#h.watched + 1] = 850
h.fire("QUEST_WATCH_LIST_CHANGED", 850, true)
h.flush()
equal(Watched(h, 850), true, "a quest the player tracks by hand stays tracked")
equal(h.ns.QuestWatch.Hidden(), 1, "and is no longer counted as hidden")
equal(h.tracker.hiddenText:GetText(), h.ns.L.TRACKER_HIDDEN_COUNT:format(1), "the count follows")
local heading = h.tracker.Header.Text
equal(heading:GetText(), journey.title, "the full journey title is the header's text")
equal(heading.wordWrap, false, "the title stays on one line")
equal(heading.maxLines, 1, "...")
check(heading:GetWidth() < 200, "and is narrowed to leave the count its room")
journey.title = title

-- The client tracks a quest on accept; one the journey does not name is the addon's, not the player's, and goes.
h.watched[#h.watched + 1] = 851
h.fire("QUEST_ACCEPTED", 851)
h.ns.Invalidate()
h.flush()
equal(Watched(h, 851), false, "a quest the client tracked on accept is untracked")

-- The setting off gives the player's own list back and stops counting anything.
h.ns.SetSetting("journeyWatch", false)
h.flush()
equal(Watched(h, 850), true, "the player's own tracked quests come back")
equal(Watched(h, 855), true, "both of them")
equal(Watched(h, 845), false, "what the journey tracked goes")
equal(h.ns.Prefs().guideWatch, nil, "nothing is kept once it is given back")
equal(h.ns.QuestWatch.Hidden(), 0, "nothing is hidden any more")
check(not h.tracker.hiddenText:IsShown(), "and the count is gone")
check(#h.errors == 0, table.concat(h.errors, "\n"))

-- The header's right-click menu turns the setting off and gives the player's quests back.
h = Load()
h.watched = { 850 }
h.ns.Choose("zone:1413", false)
h.flush()
check(h.ns.QuestWatch.Hidden() > 0, "the journey hides the player's quest")
local menu = h.OpenTrackerMenu(h.tracker)
local show
for _, entry in ipairs(menu.entries) do
	if entry.text == h.ns.L.TRACKER_SHOW_ALL then
		show = entry
	end
end
check(show ~= nil, "the header menu offers Show all quests")
show.onClick()
h.flush()
equal(h.ns.Setting("journeyWatch"), false, "Show all quests turns the setting off")
equal(Watched(h, 850), true, "and gives the player's quest back")
equal(h.ns.QuestWatch.Hidden(), 0, "with nothing hidden")
check(#h.errors == 0, table.concat(h.errors, "\n"))

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
