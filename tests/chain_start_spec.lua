-- Run from the repository root: luajit tests/chain_start_spec.lua
-- A locked search row's chain (Model.ChainStart, UI/PanelSearch.lua, docs/design.md §2.4): the earliest prerequisite
-- open now and not orange or red; its tooltip says "Starts with <quest>" and a shift-click adds that quest, never the
-- locked one. Only an eligible quest becomes a target.
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

-- Model.ChainStart on a hand-made chain: 1 -> 2 -> 3 (3 needs 2 needs 1), 5 needs one of 4 or 1.
local ns = {}
harness.model(ns)
local Model = ns.Model
local base = harness.data()
local data = { quests = {}, zones = base.zones, maps = base.maps }
local player = { level = 20, side = 2, raceBit = 2, classBit = 1, maxQuestLevelOffset = 2 }
local function Quest(id, level, pre, preAny)
	data.quests[id] = {
		title = "Quest " .. id,
		level = level,
		min = 1,
		side = 3,
		start = { map = 1413, x = 0.5, y = 0.5, npc = 1 },
		pre = pre,
		preAny = preAny,
	}
end
Quest(1, 18)
Quest(2, 19, { 1 })
Quest(3, 20, { 2 })
Quest(4, 30)
Quest(5, 20, nil, { 4, 1 })
Quest(6, 20, nil, nil)
data.quests[6].min = 30
local completed, log = {}, {}
equal(Model.ChainStart(data, player, completed, log, 3), 1, "chain: the deepest open prerequisite")
completed[1] = true
equal(Model.ChainStart(data, player, completed, log, 3), 2, "chain: on once the first is done")
completed[1] = nil
equal(Model.ChainStart(data, player, completed, log, 5), 1, "one-of: the first that is open and not red (4 is red)")
equal(Model.ChainStart(data, player, completed, log, 6), nil, "a level lock: no chain to start")
log[1] = { id = 1 }
equal(Model.ChainStart(data, player, completed, log, 3), nil, "in the log: nothing to start, it is under way")
log[1] = nil
-- A loop in the data ends.
data.quests[1].pre = { 3 }
equal(Model.ChainStart(data, player, completed, log, 3), nil, "a prerequisite loop: nothing, and no hang")
data.quests[1].pre = nil

-- Through the search: a locked quest whose chain starts now.
local h = harness.load({
	planned = true,
	db = { autoStart = false },
	charDB = { journey = "zone:1413" },
	completed = { 844 },
	log = {
		{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
	},
})
h.flush()
h.ns.OpenPanel()
h.flush()
local state, quests = h.ns.State, h.ns.Data.quests
local player2, done, logged = state.Player(), state.Completed(), state.Log()
local locked, start
for id, quest in pairs(quests) do
	if
		(not locked or id < locked)
		and quest.side ~= (player2.side == 1 and 2 or 1)
		and not h.ns.Model.Eligible(h.ns.Data, player2, done, logged, id)
		and #h.ns.Model.Search(h.ns.Data, player2, quest.title) == 1
	then
		local first = h.ns.Model.ChainStart(h.ns.Data, player2, done, logged, id)
		if first then
			locked, start = id, first
		end
	end
end
assert(locked, "a locked quest whose chain starts now")
local search = h.Find(function(frame)
	return frame.stockTemplate == "SearchBoxTemplate"
end)[1]
h.Type(search, quests[locked].title)
local row
for _, candidate in
	ipairs(h.Find(function(frame)
		return frame:IsVisible() and frame.Lines ~= nil and frame.id == locked
	end))
do
	row = candidate
end
assert(row, "the locked row")
equal(row.chain, start, "row: its chain start")
h.Hover(row)
local said = table.concat(h.tooltip, "\n")
equal(
	said:find(h.ns.L.STARTS_WITH:format(state.QuestTitle(start) or quests[start].title), 1, true) ~= nil,
	true,
	"tooltip: Starts with"
)
equal(h.tooltip[#h.tooltip], "instruction: " .. h.ns.L.SHIFT_ADD_START, "tooltip: offers to add that quest")
h.shift = true
h.call(row.scripts.OnMouseUp, row, "LeftButton")
h.shift = false
h.flush()
equal(h.ns.Prefs().pinned[start], true, "shift-click: the chain's first quest is added")
equal(h.ns.Prefs().pinned[locked], nil, "shift-click: never the locked quest")
equal(#h.errors, 0, "errors\n" .. table.concat(h.errors, "\n"))

print(("chain_start_spec: %d checks passed"):format(checks))
