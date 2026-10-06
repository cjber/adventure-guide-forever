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
	return table.concat(ns.Window.GuideOutline(data, player, done or {}, journey, steps or {}), ",")
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

local ui = harness.load({ charDB = { journey = "dungeon:389", dungeons = true } })
ui.ns.OpenWindow()
ui.flush()
equal(#ui.errors, 0, "dungeon journey opens without Classic guide or AtlasLoot")
equal(#ui.ns.Window.Tabs(), 3, "three top-level tabs")
equal(ui.ns.Window.Tabs()[1].label, "Journey", "default tab is Journey")
print(("dungeons_spec: %d checks passed"):format(checks))
