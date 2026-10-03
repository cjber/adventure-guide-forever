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
equal(#list, 10, "catalog lists questless dungeons and every mapped raid")
equal(list[1].id, 47, "questless dungeon sorted by recommended level")
equal(list[2].id, 33, "catalog sorted by known levels, then ID")
equal(list[3].suitable, true, "recommended range includes the player")
equal(list[4].id, 249, "the announced Onyxia's Lair leads the raids")
equal(list[4].raid, true, "mapped raids carry the raid flag")
equal(list[4].current, true, "the announced Forever tier is marked current")
equal(list[4].players, 40, "raid group size comes from the registry")
equal(list[4].name, "Onyxia's Lair", "a raid absent from the generated data keeps its registry name")
equal(list[4].suitable, false, "a level-60 raid is not suggested to a level-20 player")
equal(list[7].id, 409, "client-present raid maps follow the announced tier")
equal(list[7].name, "Raid", "a generated raid keeps its data name")
equal(list[7].current, false, "client-present raids are not the announced tier")
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
nav.ns.Guidance.Navigate = function(step)
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
equal(ids[409], true, "a client-present raid is browsable")
equal(ids[249], true, "Onyxia's Lair is browsable without a generated instance")

-- The raid registry names the announced Forever tiers and the sizes the client maps do not carry.
local barrow, hyjal, onyxia = h.ns.Raids[1], h.ns.Raids[2], h.ns.Raids[3]
equal(barrow.name, "Barrow Deeps", "10-player launch raid registered")
equal(barrow.players, 10, "Barrow Deeps group size")
equal(hyjal.players, 20, "Hyjal Summit group size")
equal(onyxia.players, 40, "Onyxia's Lair group size")
equal(barrow.map, nil, "Barrow Deeps has no client map in this build")
equal(onyxia.map, 249, "Onyxia's Lair maps to the client instance")
equal(h.ns.RaidByMap[409].players, 40, "the registry indexes client-present raids")

-- Synthetic QuestieDB rows exercise contracts; no Questie-derived data is stored in the repository.
local fake = harness.questieMirror(h.ns.Data)
fake.npcs[999901] =
	{ name = "Test boss", rank = 3, spawns = { [100043] = { { 20, 30 } } }, minLevel = 21, maxLevel = 21 }
fake.npcs[999902] = { name = "Test elite", rank = 1, spawns = { [100043] = { { 25, 30 } } } }
fake.npcs[999903] = { name = "Test boss", rank = 3, spawns = { [1413] = { { 20, 30 } } } }
fake.items = {
	[999904] = { name = "Test drop", npcDrops = { 999901, 999902, 999901 }, questRewards = { 1486 } },
	[999905] = { name = "Outside drop", npcDrops = { 999903 } },
	[999900] = { name = "Elite drop", npcDrops = { 999902 } },
}
fake.quests[1486].objectivesText = { "Test objective." }
fake.zones.dungeons = { [100043] = { "Test instance", { 999906 }, 1413, { { 1413, 51, 32 } } } }
fake.quests[999910] = { name = "Alias area quest", questLevel = 20, requiredLevel = 18, zoneOrSort = 999906 }
local q = harness.load({ questiedb = fake })
equal(q.ns.Data.quests[999910].dungeon, 43, "a quest in a dungeon's alias area is filed under the dungeon")
local yields = 0
local source = q.ns.ReadDungeonSource(function()
	yields = yields + 1
end)
equal(source.bosses[43][1].id, 999901, "boss identified by rank and instance area")
equal(#source.bosses[43], 1, "ordinary elites omitted from Bosses")
equal(#source.loot[43], 2, "drops deduplicated across dungeon NPCs")
equal(source.loot[43][2].id, 999904, "local boss drops retained")
equal(source.loot[43][1].id, 999900, "elite drop retained")
equal(#source.loot[43][2].droppers, 2, "droppers deduplicated and restricted to this instance")
equal(source.loot[43][2].droppers[1].name, "Test boss", "dropper name comes from runtime NPC data")
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
local bosses = D.Journal(43, noop)
equal(bosses[1].name, "Client encounter", "client boss preferred")
equal(D.Journal(33, noop), nil, "missing journal stays absent")
local partial = { bosses = {}, npcs = { [43] = { { id = 555, name = "Client encounter", rank = 1 } } } }
equal(D.Bosses({ bosses = {} }, 43, bosses)[1].name, "Client encounter", "partial source preserves journal")
bosses[2] = { id = 555, name = "Unmatched encounter", rank = 3, journal = true }
local displayed = D.Bosses(partial, 43, bosses)
equal(#displayed, 2, "partial name match preserves every journal encounter")
equal(displayed[1].id, 555, "matched journal encounter uses the source NPC")
equal(displayed[2].name, "Unmatched encounter", "unmatched journal encounter stays visible")
local collision = harness.load({ items = { [999904] = { name = "Test drop", quality = 3 } } })
partial.loot = { [43] = { { id = 999904, name = "Test drop", droppers = { { id = 555 } } } } }
local grouped = collision.ns.Dungeons.LootRows(partial, 43, displayed)
equal(grouped[1].title, "Client encounter", "journal ID cannot overwrite an NPC loot group")
equal(
	collision.ns.Dungeons.LootRows(partial, 43, { displayed[2] })[1].title,
	collision.ns.L.DUNGEON_TRASH,
	"journal ID alone never identifies a loot dropper"
)
bosses[2] = nil

local Button = dofile("tests/ui_helpers.lua").Button
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
	items = { [999904] = { name = "Test drop", quality = 3, icon = 134400 } },
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
equal(Texts(rewardUI)["Test boss"], true, "loot grouped under named boss")
rewardUI.Click(Button(rewardUI, rewardUI.ns.L.DUNGEON_BOSSES_TAB))
-- Bosses come from AtlasLoot/EJ now; this scene has a single named row, so no scroll is needed.
local bossRows = rewardUI.Find(function(frame)
	return frame:IsVisible() and frame.value and frame.value.boss and frame.value.title == "Test boss"
end)
equal(#bossRows, 1, "named boss row")
local bossRow = bossRows[1]
equal(bossRow.Info:GetText():find("Level 21|r", 1, true) ~= nil, true, "difficulty-coloured single level")
equal(bossRow.Giver:GetText(), rewardUI.ns.L.DUNGEON_BOSS_LOOT:format(1), "known drop count and action")
rewardUI.Click(bossRow)
equal(Texts(rewardUI)["Test drop"], true, "boss click opens its loot group")
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
-- Permanent restrictions are absent from every browsing surface; unknown requirements stay locked.
local restricted = harness.load({ player = { level = 19, faction = "Alliance", raceID = 4, classID = 11 } })
local RD = restricted.ns.Dungeons
local rp = restricted.ns.State.Player()
local catalog = RD.List(restricted.ns.Data, rp, noop)
local ragefire
for _, dungeon in ipairs(catalog) do
	if dungeon.id == 389 then
		ragefire = dungeon
	end
end
assert(ragefire)
equal(#ragefire.quests, 0, "Alliance never sees Horde Ragefire quests")
equal(ragefire.hostile, true, "Orgrimmar entrance marked hostile")
local inRange = restricted.ns.State.Player()
inRange.level = 15
for _, dungeon in ipairs(RD.List(restricted.ns.Data, inRange, noop)) do
	if dungeon.id == 389 then
		equal(dungeon.suitable, false, "enemy capital is not suggested even in level range")
	end
end
local questPage = RD.Page(restricted.ns.Data, rp, {}, {}, ragefire, noop)
equal(questPage.xp, 0, "inaccessible quests contribute no XP")
for _, entry in ipairs(questPage.prep) do
	equal(entry.quest, nil, "faction quests also absent from prep")
end
restricted.ns.Window.OpenDungeon(389)
restricted.flush()
local text = Texts(restricted)
equal(text[restricted.ns.L.DUNGEON_NO_FACTION_QUESTS], true, "stock empty state explains faction")
equal(text["Testing an Enemy's Strength"], nil, "no inaccessible detail remains selected")
for line in pairs(text) do
	equal(line:find("0 experience remaining", 1, true), nil, "zero XP omitted")
end
local original = data.quests[1]
data.quests[1] = Quest({ races = 1 })
data.quests[2] = Quest({ classes = 1 })
data.quests[3] = Quest({ side = 0 })
local filtered = D.List(data, player, noop)
local visible = {}
for _, id in ipairs(filtered[3].quests) do
	visible[id] = true
end
equal(visible[1], nil, "wrong race omitted")
equal(visible[2], nil, "wrong class omitted")
equal(visible[5], nil, "wrong faction omitted")
equal(visible[3], true, "unknown faction stays visible")
equal(D.Quest(data, player, {}, {}, 3).status, "unknown", "unknown faction never available")
data.quests[4].preAny = { 1, 2 }
local filteredUI = harness.load()
filteredUI.ns.Data = data
filteredUI.player.level = 20
filteredUI.ns.Window.OpenDungeon(43)
filteredUI.flush()
for _, row in
	ipairs(filteredUI.Find(function(frame)
		return frame:IsVisible() and frame.value and frame.value.quest and frame.value.quest.id == 3
	end))
do
	local _, _, _, titleX = row.Title:GetPoint(1)
	-- Font regions have disjoint horizontal bounds, even when both strings use all their space.
	equal(titleX + row.Title.width < row.width - 8 - row.Info.width, true, "title ends before status")
	filteredUI.Hover(row)
	equal(#filteredUI.tooltip > 2, true, "locked row tooltip includes its reason")
end
for _, row in
	ipairs(filteredUI.Find(function(frame)
		return frame:IsVisible() and frame.value and frame.value.quest and frame.value.quest.id == 4
	end))
do
	filteredUI.Click(row.Expand)
end
for _, row in
	ipairs(filteredUI.Find(function(frame)
		return frame:IsVisible() and frame.value and frame.value.quest
	end))
do
	equal(row.value.quest.id ~= 1 and row.value.quest.id ~= 2, true, "wrong race/class prerequisites hidden on expand")
end
filteredUI.Click(Button(filteredUI, filteredUI.ns.L.DUNGEON_PREP_TAB))
for _, frame in
	ipairs(filteredUI.Find(function(frame)
		return frame:IsVisible() and frame.value and frame.value.quest
	end))
do
	equal(
		frame.value.quest.id ~= 1 and frame.value.quest.id ~= 2 and frame.value.quest.id ~= 5,
		true,
		"permanent restrictions also filtered from prep chains"
	)
end
filteredUI.Click(Button(filteredUI, filteredUI.ns.L.DUNGEON_QUESTS_TAB))
for id in pairs(data.quests) do
	data.quests[id].dungeon = nil
end
filteredUI.ns.Window.Refresh()
filteredUI.flush()
equal(Texts(filteredUI)[filteredUI.ns.L.DUNGEON_NO_QUESTS], true, "questless source explains empty page")
equal(Texts(filteredUI)[filteredUI.ns.L.DUNGEON_SHOW_GIVER], nil, "empty page clears the previous detail")
local emptySource = harness.load({ questiedb = fake })
emptySource.ns.Window.OpenDungeon(389)
emptySource.flush()
emptySource.Click(Button(emptySource, emptySource.ns.L.DUNGEON_BOSSES_TAB))
equal(Texts(emptySource)["Jergosh the Invoker"], nil, "empty optional source has no bundled boss baseline")
equal(Texts(emptySource)[emptySource.ns.L.DUNGEON_NEEDS_QUESTIE], nil, "loaded source is never reported missing")
equal(#filteredUI.errors, 0, "restricted prep UI has no errors")
data.quests[1] = original
local planned = Button(h, h.ns.L.DUNGEON_PLAN)
equal(planned.stockTemplate, "UICheckButtonTemplate", "planning uses the stock checkbox")
equal(planned.checked, true, "chosen dungeon is checked")
h.Click(planned)
h.flush()
equal(h.ns.Prefs().journey, nil, "unchecking clears the shared journey")
equal(planned.checked, false, "cleared journey unchecks the control")
equal(#restricted.errors, 0, "Alliance page has no errors")
-- Explicit map actions navigate, reveal the target zone, and pulse even without an AGF pin there.
local reveal = harness.load()
local mapTarget = {
	key = "test-place",
	kind = "town",
	title = "Test",
	quests = {},
	reason = "",
	detail = "",
	map = 1413,
	x = 0.21,
	y = 0.72,
}
equal(reveal.ns.Guidance.ShowOnMap(mapTarget), true, "map action sets native route")
reveal.flush()
equal(reveal.G.WorldMapFrame:IsShown(), true, "map action opens the world map")
equal(reveal.G.WorldMapFrame:GetMapID(), 1413, "map action switches to target uiMap")
local ping = reveal.pins.AdventureGuideForeverPingPinTemplate[1]
equal(ping.x, 0.21, "ping uses fractional x")
equal(ping.y, 0.72, "ping uses fractional y")
equal(ping.loops, 2, "stock ping loops twice")
equal(ping.frameLevelType, "PIN_FRAME_LEVEL_QUEST_PING", "stock quest ping layer")
reveal.G.WorldMapFrame:SetMapID(1439)
reveal.ns.Guidance.ShowOnMap(mapTarget)
reveal.flush()
equal(reveal.G.WorldMapFrame:GetMapID(), 1413, "already-open map switches zone")
local count = reveal.counts.SetMapID
equal(reveal.ns.Guidance.ShowOnMap({ map = 1413, x = 0.2 }), false, "missing coordinate is a no-op")
equal(reveal.counts.SetMapID, count, "invalid place never changes map")
reveal.G.WorldMapFrame:Hide()
reveal.combat = true
equal(reveal.ns.Guidance.ShowOnMap(mapTarget), true, "combat still sets native route")
reveal.flush()
equal(reveal.G.WorldMapFrame:IsShown(), false, "combat never opens map")
equal(reveal.counts.SetMapID, count, "combat never changes displayed map")

-- Every known dropper must live exclusively in this dungeon; rarity waits for the client cache.
fake.items[999906] = { name = "World drop", npcDrops = { 999901, 999903 } }
fake.items[999907] = { name = "Unknown dropper", npcDrops = { 999901, 888888 } }
fake.items[999908] = { name = "Junk", npcDrops = { 999902 } }
fake.items[999909] = { name = "Quest starter", npcDrops = { 999902 }, startQuest = 1486 }
local loot = harness.load({
	questiedb = fake,
	items = {
		[999904] = {
			name = "Test drop",
			quality = 3,
			itemType = "Armor",
			itemSubType = "Cloth",
			equipSlot = "INVTYPE_HEAD",
			requiredLevel = 20,
		},
		[999900] = { name = "Elite drop", quality = 2 },
		[999908] = { name = "Junk", quality = 1 },
		[999909] = { name = "Quest starter", quality = 1, equipSlot = "INVTYPE_NON_EQUIP_IGNORE" },
	},
})
local localSource = loot.ns.Dungeons.Source(noop)
equal(localSource.worldDrops[999906], true, "outside NPC excludes a world drop")
equal(localSource.worldDrops[999907], true, "unknown NPC cannot prove exclusive drop")
local rows = loot.ns.Dungeons.LootRows(localSource, 43, localSource.bosses[43])
equal(rows[1].title, "Test boss", "boss heading comes first")
equal(rows[2].item, 999904, "shared boss/trash item belongs to boss once")
equal(rows[3].title, "Trash", "non-boss-only drops grouped last")
equal(#rows, 5, "junk and world drops omitted; quest starter kept")
equal(rows[5].item, 999909, "white quest-starting item retained")
equal(rows[2].quality, 3, "loot carries native rarity")
equal(rows[2].info, "Armor · Cloth · Head · Requires level 20", "loot carries compact item metadata")
equal(rows[5].info, "", "an item that cannot be equipped names no slot")
-- Synthetic AtlasLoot shape: no addon tables or data are copied into the project.
local atlasModule = {
	GetDifficultyByName = function(_, name)
		return name == "n" and 1
	end,
	Test = {
		InstanceID = 43,
		LevelRange = { 10, 17, 24 },
		items = {
			{
				name = "Curated elite boss",
				npcID = 999902,
				Level = 20,
				[1] = { { 1, 999900 }, { 2, 999900 }, { 3, 999906 } },
			},
			{ name = "Test boss", npcID = 999901, Level = 21, [1] = { { 1, 999904 } } },
			{ name = "Trash", ExtraList = true, [1] = { { 1, 999900 }, { 2, 999909 } } },
		},
	},
	Wing = {
		InstanceID = 43,
		LevelRange = { 10, 20, 24 },
		items = {
			{ name = "Later wing", npcID = { 111111, 222222 }, Level = 24, [1] = {} },
		},
	},
}
loot.G.AtlasLoot = { Locales = { Trash = "Trash" }, ItemDB = {
	Get = function()
		return atlasModule
	end,
} }
local curated = loot.ns.Dungeons.Source(noop)
equal(#curated.bosses[43], 3, "instance wings merge and encounter NPC arrays are supported")
equal(curated.bosses[43][1].name, "Curated elite boss", "AtlasLoot encounter order takes precedence over rank")
equal(curated.bosses[43][3].name, "Later wing", "wings ordered by level")
equal(#curated.loot[43], 3, "AtlasLoot drops deduped; known world drops still excluded")
local standalone = harness.load({ items = { [999904] = { name = "Test drop", quality = 3 } } })
standalone.G.AtlasLoot = loot.G.AtlasLoot
equal(standalone.ns.Dungeons.Source(noop) ~= nil, true, "AtlasLoot works without QuestieDB")

-- Raids read the same curated AtlasLoot pages, and a raid absent from the generated geometry still pages safely.
local raidLoot = harness.load({ items = { [999910] = { name = "Raid drop", quality = 4 } } })
raidLoot.ns.Data.instances[249] = nil
local raidModule = {
	GetDifficultyByName = function(_, name)
		return name == "n" and 1
	end,
	Onyxia = {
		InstanceID = 249,
		items = {
			{ name = "Onyxia", npcID = 10184, Level = 60, [1] = { { 1, 999910 } } },
		},
	},
}
raidLoot.G.AtlasLoot = { Locales = { Trash = "Trash" }, ItemDB = {
	Get = function()
		return raidModule
	end,
} }
local raidSource = raidLoot.ns.Dungeons.Source(noop)
equal(#raidSource.bosses[249], 1, "a raid's curated encounter is read")
equal(raidSource.bosses[249][1].name, "Onyxia", "raid boss name comes from AtlasLoot")
equal(raidSource.loot[249][1].id, 999910, "raid loot comes from AtlasLoot")
equal(
	raidLoot.ns.Dungeons.Bosses(raidSource, 249, nil)[1].name,
	"Onyxia",
	"raid boss list comes from the curated source"
)
local raidRows = raidLoot.ns.Dungeons.LootRows(raidSource, 249, raidSource.bosses[249])
equal(raidRows[1].title, "Onyxia", "raid loot is grouped under the encounter")
equal(raidRows[2].item, 999910, "raid item row")
local raidEntry
for _, entry in ipairs(raidLoot.ns.Dungeons.List(raidLoot.ns.Data, raidLoot.ns.State.Player(), noop)) do
	if entry.id == 249 then
		raidEntry = entry
	end
end
assert(raidEntry, "Onyxia's Lair is in the catalog")
equal(
	raidLoot.ns.Dungeons.Page(raidLoot.ns.Data, raidLoot.ns.State.Player(), {}, {}, raidEntry, noop).dungeon.id,
	249,
	"a raid without generated geometry still pages"
)

-- The catalog splits dungeons from raids and tags the announced tier with its group size.
local raidUI = harness.load()
raidUI.ns.Window.OpenDungeon(249)
raidUI.flush()
local raidTexts = Texts(raidUI)
equal(raidTexts["Onyxia's Lair"], true, "raid page names the instance")
equal(raidTexts[raidUI.ns.L.DUNGEON_LIST_RAIDS], true, "announced raids get their own heading")
equal(raidTexts[raidUI.ns.L.DUNGEON_LIST_DUNGEONS], true, "dungeons keep their heading")
equal(raidTexts[raidUI.ns.L.DUNGEON_RAID_PLAYERS:format(40)], true, "raid group size is shown")
raidUI.Click(Button(raidUI, raidUI.ns.L.DUNGEON_BOSSES_TAB))
equal(#raidUI.errors, 0, "raid page has no errors")

-- Bosses come from the provider only: its order and details are kept, and the display merge leaves its data alone.
local partialAtlas =
	{ curated = { [43] = true }, bosses = { [43] = { { id = 1, name = "Localized encounter", low = 99, high = 99 } } } }
equal(#D.Bosses(partialAtlas, 43), 1, "AtlasLoot order and localized details retained")
equal(#partialAtlas.bosses[43], 1, "display merge does not mutate provider data")
print(("dungeons_spec: %d checks passed"):format(checks))
