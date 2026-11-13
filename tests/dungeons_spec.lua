local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local h = harness.load()
local ns = h.ns
local player = { level = 21, side = 1, raceBit = 4, classBit = 64 }
local data = {
	quests = {
		[1] = { title = "Earlier errand", side = 1, min = 10, level = 12 },
		[2] = { title = "Preparation", side = 1, min = 10, level = 15, pre = { 1 } },
		[3] = { title = "Dungeon quest", side = 1, min = 10, level = 20, dungeon = 36, pre = { 2 } },
		[4] = { title = "Other faction", side = 2, min = 10, level = 20, dungeon = 36 },
		[5] = { title = "Other class", side = 1, classes = 1, min = 10, level = 20, dungeon = 36 },
	},
}
local journey = { key = "dungeon:36", instance = 36 }
local function outline(done, steps)
	return table.concat(ns.Widgets.GuideOutline(data, player, done or {}, journey, steps or {}), ",")
end
equal(outline(), "1,2,3", "full prerequisite outline precedes dungeon quest")
equal(outline({ [1] = true }), "2,3", "completed prerequisite omitted")
equal(outline({}, { { quests = { 1 } } }), "2,3", "active prerequisite is already in route")
equal(outline({ [3] = true }), "", "completed dungeon quest has no leftover prerequisites")
data.quests[1].pre = { 3 }
equal(outline(), "1,2,3", "cyclic data stays bounded")

local mirror = harness.questieMirror(ns.Data)
mirror.zones.dungeons = { [100043] = { "Test dungeon", { 999906 }, 1413, { { 1413, 51, 32 } } } }
mirror.quests[999910] = { name = "Alias quest", questLevel = 20, requiredLevel = 18, zoneOrSort = 999906 }
local runtime = harness.load({ questiedb = mirror })
equal(runtime.ns.Data.quests[999910].dungeon, 43, "QuestieDB area alias belongs to dungeon")
equal(runtime.ns.Dungeons.Entrance(43).x, 0.51, "live QuestieDB entrance wins")
equal(runtime.ns.Dungeons.GoEntrance(43), true, "entrance navigates through existing guidance")

local bosses, hint = ns.DungeonLoot.Bosses(36)
equal(#bosses, 0, "optional loot source absent")
equal(hint, ns.L.DUNGEON_LOOT_INSTALL, "absence explains companion install")
local source = {
	West = {
		InstanceID = 36,
		LoadDifficulty = 4,
		items = {
			{ name = "Test boss", npcID = 999901 },
			{ name = "Trash" },
		},
	},
	East = { InstanceID = 36, LoadDifficulty = 4, items = { { name = "Test boss", npcID = 999901 } } },
	Other = { InstanceID = 43, items = { { name = "Other boss", npcID = 999902 } } },
}
local calls = 0
h.G.AtlasLoot = {
	ItemDB = {
		Get = function()
			return source
		end,
		GetItemTable = function(_, module, _, _, difficulty)
			equal(module, "AtlasLootClassic_DungeonsAndRaids", "public installed loot source")
			equal(difficulty, 4, "source-selected difficulty respected")
			calls = calls + 1
			return { { 1, 999801 }, { 2, "INV_Box_01" }, { 3, 999801 }, { 4, 999802 }, { 5, 0 } }
		end,
	},
}
bosses, hint = ns.DungeonLoot.Bosses(36)
equal(#bosses, 1, "boss duplicates across wings merge; trash and other dungeon excluded")
equal(bosses[1].name, "Test boss", "installed name preserved")
equal(table.concat(bosses[1].items, ","), "999801,999802", "only unique positive item IDs are drops")
equal(calls, 1, "linked loot resolved once per boss")
equal(hint, nil, "populated list has no missing hint")
source.East.items[1].npcID = { 999901, 999902 }
bosses = ns.DungeonLoot.Bosses(36)
equal(#bosses, 1, "group bosses use first NPC identity")
h.G.AtlasLoot.ItemDB.GetItemTable = function()
	error("missing linked table")
end
bosses, hint = ns.DungeonLoot.Bosses(36)
equal(#bosses, 0, "incompatible loot table does not crash the guide")
equal(hint, ns.L.DUNGEON_LOOT_UNKNOWN, "broken loot table explains unavailable drops")
local loot = h.G.AtlasLoot
loot.ItemDB.GetItemTable = function()
	return {}
end
loot.ItemDB.Get = function()
	return nil
end
local loaded = false
loot.Loader = {
	LoadModule = function(_, module)
		equal(module, "AtlasLootClassic_DungeonsAndRaids", "load only selected dungeon module")
		loaded = true
		loot.ItemDB.Get = function()
			return source
		end
	end,
}
h.combat = true
ns.DungeonLoot.Bosses(36)
equal(loaded, false, "no loading addon in combat")
h.combat = false
ns.DungeonLoot.Bosses(36)
equal(loaded, true, "lazy module loading outside combat")

local attempts = 0
h.G.AtlasLoot = {
	ItemDB = {
		Get = function()
			return nil
		end,
	},
	Loader = {
		LoadModule = function()
			attempts = attempts + 1
		end,
	},
}
ns.DungeonLoot.Bosses(36)
ns.DungeonLoot.Bosses(36)
equal(attempts, 1, "disabled module load is not retried on every refresh")

-- Another addon's surface can be incomplete in an install this file wasn't written against: a missing method
-- degrades to the install line instead of erroring while a dungeon card draws.
h.G.AtlasLoot = true
bosses, hint = ns.DungeonLoot.Bosses(36)
equal(#bosses, 0, "an AtlasLoot that isn't a table has no bosses")
equal(hint, ns.L.DUNGEON_LOOT_INSTALL, "an AtlasLoot that isn't a table says what to install")
h.G.AtlasLoot = { ItemDB = {} }
bosses, hint = ns.DungeonLoot.Bosses(36)
equal(#bosses, 0, "an ItemDB without Get has no bosses")
equal(hint, ns.L.DUNGEON_LOOT_INSTALL, "an ItemDB without Get says what to install")
h.G.AtlasLoot = {
	ItemDB = {
		Get = function()
			return nil
		end,
	},
	Loader = {},
}
bosses, hint = ns.DungeonLoot.Bosses(36)
equal(#bosses, 0, "a Loader without LoadModule has no bosses")
equal(hint, ns.L.DUNGEON_LOOT_INSTALL, "a Loader without LoadModule says what to install")

local ui = harness.load({ charDB = { journey = "dungeon:389", dungeons = true } })
ui.ns.OpenPanel()
ui.flush()
equal(#ui.errors, 0, "dungeon journey opens without Classic guide or AtlasLoot")

-- #504: a Forever dungeon the client lists is offered at its own level. The Hall of Thanes (Map 3065) is a party
-- instance in Map, a Dungeons activity in GroupFinderActivity and an LFGDungeons row; the corpus files its quests
-- there once the generated data names it.
local forever = harness.load({
	player = { level = 17, faction = "Alliance", raceID = 1, classID = 1, map = 1426, x = 0.5, y = 0.5 },
})
forever.flush()
local foreverPrefs = forever.ns.Prefs()
foreverPrefs.dungeons = true
local foreverPlayer = { level = 17, maxLevel = 60, side = 1, raceBit = 1, classBit = 1, map = 1426, x = 0.5, y = 0.5 }
local foreverPlan = forever.ns.Model.Plan(forever.ns.Data, foreverPlayer, {}, {}, foreverPrefs)
local hall
for _, foreverJourney in ipairs(foreverPlan.journeys) do
	if foreverJourney.kind == "dungeon" and foreverJourney.instance == 3065 then
		hall = foreverJourney
	end
end
equal(hall and hall.title, "The Hall of Thanes", "Forever dungeon: The Hall of Thanes is offered at level 17")
equal(hall and #hall.steps > 0, true, "Forever dungeon: its card has a way in")

-- #536: every quest filed under the instance is listed, including one the guide cannot send the player outside for.
-- An Ancient Grudge (96395) has no giver: the data files it under the Hall, so it is picked up inside and the guide
-- lists it there instead of dropping it from the journey.
local future = forever.ns.Widgets.GuideOutline(forever.ns.Data, foreverPlayer, {}, hall, hall.steps)
local listed = {}
for _, id in ipairs(future) do
	listed[id] = true
end
equal(listed[96395], true, "Forever dungeon: a quest with no giver is listed")
local stepped = false
for _, step in ipairs(hall.steps) do
	for _, id in ipairs(step.quests) do
		stepped = stepped or id == 96395
	end
end
equal(stepped, false, "Forever dungeon: a quest picked up inside is no step outside")
equal(hall.subline, "4 quests for this dungeon", "Forever dungeon: the count counts every quest filed under it")

local hallUI = harness.load({
	player = { level = 17, faction = "Alliance", raceID = 1, classID = 1, map = 1426, x = 0.5, y = 0.5 },
	charDB = { journey = "dungeon:3065", dungeons = true },
})
hallUI.ns.OpenPanel()
hallUI.flush()
local labels = {}
for _, row in
	ipairs(hallUI.Find(function(entry)
		return entry:IsVisible() and entry.questID ~= nil
	end))
do
	labels[row.questID] = row.Detail:GetText()
end
equal(labels[96395], "Picked up inside · guide outline", "Forever dungeon: the inside quest says so")
equal(labels[96393], "Later quest · guide outline", "Forever dungeon: a quest with a giver is just later")
equal(labels[96391], "Later quest · guide outline", "Forever dungeon: a prerequisite outside is not inside")
equal(#hallUI.errors, 0, "Forever dungeon: the panel draws it without error")

print(("dungeons_spec: %d checks passed"):format(checks))
