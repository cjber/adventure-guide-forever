-- Dungeon pages through the real model, optional source adapter, UI and navigation boundary.
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, ("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)))
end
local function noop() end
local h = harness.load()
local D, M = h.ns.Dungeons, h.ns.Model
local at = { map = 1413, x = 0.5, y = 0.3, name = "Test giver" }
local function Quest(extra)
	local q = { title = "Test quest", level = 20, min = 10, side = 3, start = at, xp = 100, dungeon = 43 }
	for key, value in pairs(extra or {}) do
		q[key] = value
	end
	return q
end
local data = {
	quests = {
		[1] = Quest(),
		[2] = Quest({ pre = { 1 }, xp = 200 }),
		[3] = Quest({ preAny = { 2, 9 }, xp = 300 }),
		[4] = Quest({ min = 40 }),
		[5] = Quest({ side = 1 }),
		[6] = Quest({ group = 1 }),
		[7] = Quest({ group = 1, xp = 150 }),
		[8] = Quest({ pre = { 88 } }),
		[9] = Quest({ dungeon = 33 }),
		[10] = Quest({ pre = { 11 } }),
		[11] = Quest({ pre = { 10 } }),
		[12] = Quest({ classes = 1 }),
		[13] = Quest({ side = 2 }),
		[14] = Quest({ preAny = { 999, 1 } }),
	},
	instances = {
		[43] = {
			name = "Second",
			low = 20,
			high = 25,
			entrances = { { trigger = 1, level = 10, items = { 7, 8 }, quest = 1, conditional = true } },
		},
		[33] = { name = "First", low = 15, high = 20 },
		[47] = { name = "No quests", low = 10, high = 15, entrances = { { trigger = 2, level = 5 } } },
		[409] = { name = "Raid", raid = true },
	},
	maps = { [1413] = { continent = 1, cx = 0, cy = 0, sx = 1, sy = 1 } },
	hubs = {},
	zones = {},
}
data.quests[13].start = nil
local player = { level = 20, side = 2, raceBit = 2, classBit = 64 }
local completed, log = {}, {}
local list = D.List(data, player, noop)
equal(#list, 3, "catalog omits raids, retains questless dungeons")
equal(list[1].id, 47, "questless dungeon sorted by recommended level")
equal(list[2].id, 33, "catalog sorted by known levels, then ID")
equal(list[3].suitable, true, "recommended range includes the player")
local cases = {
	[1] = "available",
	[2] = "pre",
	[3] = "pre",
	[4] = "level",
	[5] = "unknown",
	[8] = "pre",
	[12] = "unknown",
	[13] = "unknown",
}
for id, status in pairs(cases) do
	local row = D.Quest(data, player, completed, log, id)
	equal(row.status, status, "status " .. id)
	equal(row.status == "available", M.Eligible(data, player, completed, log, id), "same eligibility " .. id)
	equal(row.place, data.quests[id].start, "known giver independent of eligibility " .. id)
end
equal(D.Quest(data, player, { [1] = true }, {}, 1).status, "done", "completed")
equal(D.Quest(data, player, {}, { [1] = {} }, 1).status, "log", "accepted")
equal(D.Quest(data, player, { [1] = true }, {}, 2).status, "available", "pre-quest completed")
equal(D.Quest(data, player, { [9] = true }, {}, 3).status, "available", "one-of prerequisite")
equal(D.Quest(data, player, { [6] = true }, {}, 7).status, "unknown", "exclusive sibling")
equal(D.Quest(data, player, {}, {}, 999).status, "unknown", "missing data")
equal(table.concat(D.Chain(data, 3, noop), ","), "1,2,9,3", "chain orders prerequisites first")
equal(#D.Chain(data, 10, noop), 2, "cyclic chain terminates")
local page = D.Page(data, player, {}, {}, list[3], noop)
equal(page.xp, 850, "remaining XP proves chains and counts exclusive rewards once")
local done = D.Page(data, player, { [1] = true }, { [2] = {} }, list[3], noop)
equal(done.xp, 750, "completed XP removed, accepted reward retained")
local prep = {}
for _, entry in ipairs(done.prep) do
	if entry.quest then
		prep[entry.quest.id] = true
	end
end
equal(prep[1], nil, "completed pre-quest omitted from prep")
equal(prep[2], nil, "accepted quest omitted from pickups")
equal(prep[9], true, "chain from another dungeon included")
equal(done.prep[#done.prep].gate.items[2], 8, "alternative entrance item retained")
equal(done.prep[#done.prep].gate.conditional, true, "unknown entrance condition retained")
equal(M.QuestXP(data.quests[1], 27), 60, "same level-adjusted XP as planner")

local nav = harness.load()
nav.ns.Data, nav.player.level = data, 20
local destination
nav.ns.Integrations.Navigate = function(step)
	destination = step
	return true
end
equal(nav.ns.Dungeons.Go(1), true, "eligible giver navigates through existing integration")
equal(destination.x, at.x, "exact known giver coordinate")
data.quests[1].pre = { 88 }
destination = nil
equal(nav.ns.Dungeons.Go(1), true, "explicit browsing permits a locked giver")
equal(destination.x, at.x, "locked quest still uses proven coordinates")
equal(nav.ns.Dungeons.Quest(data, player, {}, {}, 1).status, "pre", "navigation does not change eligibility")
data.quests[1].start = nil
destination = nil
equal(nav.ns.Dungeons.Go(1), false, "click revalidates removed coordinates")
equal(destination, nil, "missing coordinates never navigate")
data.quests[1].start = at
data.quests[1].pre = nil
local broken = Quest({ start = { map = 1413, x = -0.1, y = 0.3 } })
data.quests[99] = broken
equal(D.Quest(data, player, {}, { [99] = {} }, 99).place, nil, "accepted quest with invalid coordinates has no Map")
data.quests[99] = nil

-- Generated catalog includes every classic dungeon with a supported entrance, even without filed quests.
local ids = {}
for _, entry in ipairs(D.List(h.ns.Data, h.ns.State.Player(), noop)) do
	ids[entry.id] = true
end
for _, id in ipairs({ 33, 34, 36, 43, 47, 48, 70, 90, 109, 129, 189, 209, 229, 230, 289, 329, 349, 389, 429 }) do
	equal(ids[id], true, "generated dungeon " .. id)
end
equal(ids[409], nil, "generated raid excluded")

-- Synthetic QuestieDB rows exercise contracts; no Questie-derived data is stored in the repository.
local fake = harness.questieMirror(h.ns.Data)
fake.npcs[999901] =
	{ name = "Test boss", rank = 3, spawns = { [100043] = { { 20, 30 } } }, minLevel = 21, maxLevel = 21 }
fake.npcs[999902] = { name = "Test elite", rank = 1, spawns = { [100043] = { { 25, 30 } } } }
fake.npcs[999903] = { name = "Test boss", rank = 3, spawns = { [1413] = { { 20, 30 } } } }
fake.items = {
	[999904] = { name = "Test drop", npcDrops = { 999901, 999902, 999901, 999903 }, questRewards = { 1486 } },
	[999905] = { name = "Outside drop", npcDrops = { 999903 } },
	[999900] = { name = "Elite drop", npcDrops = { 999902 } },
}
fake.quests[1486].objectivesText = { "Test objective." }
fake.zones.dungeons = { [100043] = { "Test instance", { 999906 }, 1413, { { 1413, 51, 32 } } } }
local q = harness.load({ questiedb = fake })
local yields = 0
local source = q.ns.ReadDungeonSource(function()
	yields = yields + 1
end)
equal(source.bosses[43][1].id, 999901, "boss identified by rank and instance area")
equal(source.bosses[43][2].rank, 1, "elite is not relabelled as a boss")
equal(#source.loot[43], 2, "drops deduplicated across dungeon NPCs")
equal(source.loot[43][1].id, 999904, "boss drops precede lower-ID elite drops")
equal(source.loot[43][2].id, 999900, "elite drop retained")
equal(#source.loot[43][1].droppers, 2, "droppers deduplicated and restricted to this instance")
equal(source.loot[43][1].droppers[1].name, "Test boss", "dropper name comes from runtime NPC data")
equal(source.rewards[1486][1].id, 999904, "inverse item questRewards supplies rewards")
equal(source.objectives[1486], "Test objective.", "runtime objective text")
equal(source.entrances[43].x, 0.51, "runtime entrance retains Forever coordinates")
equal(q.ns.Dungeons.Entrance(43, source).y, 0.32, "runtime entrance needs no Tweaks install")
equal(yields > 1000, true, "large reads yield between entities")
equal(h.ns.ReadDungeonSource(noop), nil, "standalone source missing")
q.G.LibQuestieDB.Item.GetAllIds = nil
equal(q.ns.ReadDungeonSource(noop), nil, "optional item contract rejected")

-- Journal IDs are mapped by the client, never inferred from dungeon names, and reads pass the instance ID.
h.G.C_EncounterJournal = {
	GetInstanceForGameMap = function(id)
		return id == 43 and 99 or 0
	end,
}
h.G.EJ_GetEncounterInfoByIndex = function(index, instance)
	equal(instance, 99, "explicit journal instance, no global selection")
	if index == 1 then
		return "Client encounter", "", 123
	end
end
local bosses, journal = D.Journal(43, noop)
equal(bosses[1].name, "Client encounter", "client boss preferred")
equal(journal, 99, "journal ID")
equal(D.Journal(33, noop), nil, "missing journal stays absent")

local function Button(each, text)
	for _, frame in
		ipairs(each.Find(function(f)
			return f:IsVisible() and f:GetText() == text
		end))
	do
		if frame:IsObjectType("Button") then
			return frame
		end
	end
	error("missing button " .. text)
end
local function Texts(each)
	local texts = {}
	for _, entry in ipairs(each.ns.DumpLayout(each.G.AdventureGuideForeverWindow, each.Describe)) do
		if entry.text then
			texts[entry.text] = true
		end
	end
	return texts
end
h.ns.Window.OpenDungeon(43)
h.flush()
equal(#h.errors, 0, "open dungeon UI")
equal(h.ns.WindowDB().dungeon, 43, "selection saved")
h.Click(Button(h, h.ns.L.DUNGEON_LOOT_TAB))
equal(Texts(h)[h.ns.L.DUNGEON_NEEDS_QUESTIE], true, "missing optional source explained")
h.Click(Button(h, h.ns.L.DUNGEON_BOSSES_TAB))
equal(Texts(h)["Client encounter"], true, "journal shown without QuestieDB")
h.Click(Button(h, h.ns.L.DUNGEON_PLAN))
h.flush()
equal(h.ns.Prefs().dungeons, true, "planning shares include-dungeons preference")
equal(h.ns.Dungeons.Planned(43), true, "planning persists independently of eligible quests")
h.ns.Dump()
equal(h.G.AdventureGuideForeverDB.dump.windowTab, "dungeons", "dump names active tab")
equal(#h.G.AdventureGuideForeverDB.dump.window > 0, true, "dump captures window layout")

-- Selecting and hiding while a source job is sliced must stop all reads; a later show restarts safely.
local sliced = harness.load()
local reads = 0
sliced.ns.ReadDungeonSource = function(yield)
	for _ = 1, 100 do
		reads = reads + 1
		yield()
	end
	return { bosses = {}, loot = {}, rewards = {}, objectives = {} }
end
sliced.clockStep = 1
sliced.ns.Window.OpenDungeon(43)
for _ = 1, 10 do
	sliced.tick()
end
sliced.G.AdventureGuideForeverWindow:Hide()
local before = reads
sliced.flush()
equal(reads, before, "hiding cancels source work")
sliced.clockStep = 0
sliced.ns.OpenWindow()
sliced.flush()
equal(reads > before, true, "show resumes source work")
equal(#sliced.errors, 0, "slice lifecycle")
-- Display ranges are independent of quest/entrance levels; a usable explicit LFG range wins.
data.instances[43].lfg = 1
h.G.GetLFGDungeonInfo = function(id)
	equal(id, 1, "explicit client LFG ID")
	return "Client dungeon", 0, 0, 10, 60, 20, 17, 24
end
local ranged = D.List(data, player, noop)
equal(ranged[3].low, 17, "client recommended minimum")
equal(ranged[3].high, 24, "client recommended maximum")
h.G.GetLFGDungeonInfo = function()
	return "Client dungeon", 0, 0, 0, 0, 17, 17, 17
end
ranged = D.List(data, player, noop)
equal(ranged[3].low, 20, "degenerate client tuning uses published range")
equal(ranged[3].high, 25, "entry minimum never becomes a recommended range")
h.G.GetLFGDungeonInfo = nil

local objective = harness.load({
	log = { { id = 1486, title = "Deviate Hides", level = 17, objectiveText = "Client objective." } },
})
equal(objective.ns.Dungeons.Objective(1486), "Client objective.", "accepted objective comes from the log")
equal(
	objective.ns.Dungeons.Objective(1486, { objectives = { [1486] = "Runtime objective." } }),
	"Runtime objective.",
	"runtime objective takes precedence"
)
equal(objective.ns.Dungeons.Objective(1487), nil, "absent objective stays absent")
local part, total = D.ChainPosition(data, 2, 1)
equal(part, 1, "chain position")
equal(total, 2, "chain total")
equal(D.ChainPosition(data, 3, 1), nil, "alternatives do not claim a linear chain position")
equal(D.ChainPosition(data, 10, 10), nil, "cycles do not claim a position")

local copy = harness.load()
copy.G.C_Map.GetMapInfo = function()
	return nil
end
copy.ns.Window.OpenDungeon(43)
copy.flush()
local drawn = Texts(copy)
equal(drawn["Arch Druid Hamuul Runetotem · Thunder Bluff"], true, "giver uses bundled map name")
equal(drawn["Objective text unavailable"], nil, "no placeholder objective")
local formatted = false
for text in pairs(drawn) do
	equal(text:match("Map %d+") == nil and text:match("Item %d+") == nil, true, "no internal IDs in dungeon text")
	if text:find("10,310", 1, true) then
		formatted = true
	end
end
equal(formatted, true, "remaining experience uses client number formatting")
copy.ns.Data.maps[1456].name = nil
copy.ns.Data.zones[1456] = nil
copy.ns.Window.Refresh()
copy.flush()
equal(Texts(copy)["Arch Druid Hamuul Runetotem"], true, "unknown place leaves giver alone")

-- Exercise reward rendering and item tooltips through the same runtime adapter as the source-present scenes.
local rewardUI = harness.load({
	questiedb = fake,
	items = { [999904] = { name = "Test drop", icon = 134400 } },
})
rewardUI.ns.Window.OpenDungeon(43)
rewardUI.flush()
for _, row in
	ipairs(rewardUI.Find(function(frame)
		return frame:IsVisible() and frame.value and frame.value.quest and frame.value.quest.id == 1486
	end))
do
	rewardUI.Click(row)
end
equal(Texts(rewardUI)["Test objective."], true, "runtime objective reaches detail pane")
equal(Texts(rewardUI)[rewardUI.ns.L.DUNGEON_REWARDS], true, "known rewards have a heading")
local icons = rewardUI.Find(function(frame)
	return frame:IsVisible() and frame.NormalTexture and frame.NormalTexture.file == 134400
end)
equal(#icons, 1, "known reward icon renders")
rewardUI.Hover(icons[1])
equal(rewardUI.tooltip[1], "item: 999904", "reward hover uses the client item tooltip")
rewardUI.Click(Button(rewardUI, rewardUI.ns.L.DUNGEON_LOOT_TAB))
equal(Texts(rewardUI)["Test drop"], true, "runtime loot renders")
equal(Texts(rewardUI)["Dropped by Test boss, Test elite"], true, "loot names known droppers")
rewardUI.Click(Button(rewardUI, rewardUI.ns.L.DUNGEON_ELITES_TAB))
equal(Texts(rewardUI)["Boss · Level 21"], true, "single enemy level is not a repeated range")
equal(#rewardUI.errors, 0, "source-present UI and item tooltip have no errors")
-- Browsing a giver is independent of pickup eligibility; absent coordinates hide the control.
local mapUI = harness.load()
mapUI.ns.Data = data
mapUI.player.level = 20
mapUI.ns.Window.OpenDungeon(43)
mapUI.flush()
local function QuestRow(id)
	local rows = mapUI.Find(function(frame)
		return frame:IsVisible() and frame.value and frame.value.quest and frame.value.quest.id == id
	end)
	assert(rows[1], "missing quest row " .. id)
	return rows[1]
end
mapUI.Click(QuestRow(2))
local mapButton = Button(mapUI, mapUI.ns.L.DUNGEON_SHOW_GIVER)
equal(mapButton:IsEnabled(), true, "locked quest detail permits giver browsing")
mapUI.Click(Button(mapUI, mapUI.ns.L.DUNGEON_PREP_TAB))
local pre = QuestRow(2)
equal(pre.Map:IsVisible(), true, "locked prep row shows known map destination")
equal(pre.Map:IsEnabled(), true, "locked prep row enables map destination")
mapUI.ns.SetSetting("wanderer", true)
mapUI.ns.Window.Refresh()
mapUI.flush()
pre = QuestRow(2)
equal(pre.Map:IsEnabled(), false, "wanderer disables prep navigation")
mapUI.Hover(pre.Map)
equal(mapUI.tooltip[1], "title: " .. mapUI.ns.L.DUNGEON_WANDERER, "disabled map tooltip explains wanderer")
mapUI.Click(Button(mapUI, mapUI.ns.L.DUNGEON_QUESTS_TAB))
mapUI.Click(QuestRow(2))
equal(mapButton:IsEnabled(), false, "wanderer disables detail navigation")
mapUI.Hover(mapButton)
equal(mapUI.tooltip[1], "title: " .. mapUI.ns.L.DUNGEON_WANDERER, "detail tooltip explains wanderer")
mapUI.ns.SetSetting("wanderer", false)
data.quests[2].start = { map = 1413, x = -0.1, y = 0.3, name = "Test giver" }
mapUI.ns.Window.Refresh()
mapUI.flush()
equal(mapButton:IsVisible(), false, "missing giver coordinates hide detail navigation")
mapUI.Click(Button(mapUI, mapUI.ns.L.DUNGEON_PREP_TAB))
equal(QuestRow(2).Map:IsVisible(), false, "missing giver coordinates hide prep navigation")
data.quests[2].start = at
equal(#mapUI.errors, 0, "map control refreshes have no errors")
print(("dungeons_spec: %d checks passed"):format(checks))
