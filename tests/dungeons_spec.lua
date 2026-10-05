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
fake.items = {
	[999904] = { name = "Test reward", questRewards = { 1486 } },
	[999900] = { name = "Unknown quest reward", questRewards = { 999999 } },
}
fake.quests[1486].objectivesText = { "Test objective." }
fake.zones.dungeons = { [100043] = { "Test instance", { 999906 }, 1413, { { 1413, 51, 32 } } } }
fake.quests[999910] = { name = "Alias area quest", questLevel = 20, requiredLevel = 18, zoneOrSort = 999906 }
local q = harness.load({ questiedb = fake })
equal(q.ns.Data.quests[999910].dungeon, 43, "a quest in a dungeon's alias area is filed under the dungeon")
local yields = 0
local details = q.ns.ReadDungeonDetails(function()
	yields = yields + 1
end)
equal(details.rewards[1486][1], 999904, "inverse item questRewards supplies a reward")
equal(details.rewards[999999], nil, "a reward for an unknown quest is left out")
equal(details.objectives[1486], "Test objective.", "runtime objective text")
equal(q.ns.DungeonEntrance(43).x, 0.51, "runtime entrance retains Forever coordinates")
equal(q.ns.Dungeons.Entrance(43).y, 0.32, "runtime entrance needs no Tweaks install")
equal(yields > 1000, true, "large reads yield between entities")
equal(h.ns.ReadDungeonDetails(noop), nil, "standalone source missing")
q.G.LibQuestieDB.Item.GetAllIds = nil
equal(q.ns.ReadDungeonDetails(noop), nil, "optional item contract rejected")

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
sliced.ns.ReadDungeonDetails = function(yield)
	for _ = 1, 100 do
		reads = reads + 1
		yield()
	end
	return { rewards = {}, objectives = {} }
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
	if text:find("10,305", 1, true) then
		formatted = true
	end
end
equal(formatted, true, "remaining experience uses client number formatting")
copy.ns.Data.maps[1456].name = nil
copy.ns.Data.zones[1456] = nil
copy.ns.Data.hubs = {}
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

-- The catalog splits dungeons from raids and tags the announced tier with its group size.
local raidUI = harness.load()
raidUI.ns.Window.OpenDungeon(249)
raidUI.flush()
local raidTexts = Texts(raidUI)
equal(raidTexts["Onyxia's Lair"], true, "raid page names the instance")
equal(raidTexts[raidUI.ns.L.DUNGEON_LIST_RAIDS], true, "announced raids get their own heading")
equal(raidTexts[raidUI.ns.L.DUNGEON_LIST_DUNGEONS], true, "dungeons keep their heading")
equal(raidTexts[raidUI.ns.L.DUNGEON_RAID_PLAYERS:format(40)], true, "raid group size is shown")
equal(#raidUI.errors, 0, "raid page has no errors")

-- One way in from the first draw: QuestieDB's point is read before any dungeon details, on the page and on the
-- journey card alike, so the text never changes once details load. Tweaks Forever answers only where QuestieDB
-- has no point.
local function Plain()
	local mirror = harness.questieMirror(h.ns.Data)
	mirror.zones.dungeons = { [100043] = { "Test instance", {}, 1413, { { 1413, 51, 32 } } } }
	return mirror
end
local tweaks = { [43] = { map = 1413, x = 0.477, y = 0.35 }, [48] = { map = 1440, x = 0.14, y = 0.14 } }
local way = harness.load({ questiedb = Plain(), entrances = tweaks })
equal(way.ns.Dungeons.Entrance(43).x, 0.51, "QuestieDB's entrance wins before any details are read")
equal(way.ns.Overview.Entrance({ kind = "dungeon", instance = 43 }) ~= nil, true, "the journey card has a way in")
local _, cardPoint = way.ns.Overview.Entrance({ kind = "dungeon", instance = 43 })
equal(cardPoint.x, 0.51, "the journey card names the same entrance as the dungeon page")
equal(way.ns.Dungeons.Entrance(48).x, 0.14, "Tweaks Forever fills an entrance QuestieDB lacks")
local _, why = harness.load({ questiedb = Plain() }).ns.Dungeons.Entrance(48)
equal(why, "missing", "no entrance says why")
way.ns.Window.OpenDungeon(43)
way.flush()
local shownAt = way.ns.L.DUNGEON_ENTRANCE_AT:format(way.ns.State.ZoneName(1413) or "", 51, 32)
equal(Texts(way)[shownAt], true, "the page shows QuestieDB's entrance once details load")

print(("dungeons_spec: %d checks passed"):format(checks))
