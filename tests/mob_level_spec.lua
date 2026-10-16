-- Run from the repository root: luajit tests/mob_level_spec.lua
-- Spots weighted by their mobs' level (#152): each objective spot carries the lowest level of the mobs there
-- (Integrations/QuestieObjectives.lua, QuestieDB's NPC minLevel), and the planner passes over a spot whose mobs are
-- OVER_LEVEL (3) or more above the player for the objective's next spot that isn't (Planning/Steps.lua AreaNode).
local ns = {}
local harness = dofile("tests/harness.lua")
harness.model(ns)
ns.QuestieFields = { spawns = { "spawns" }, drops = { "npcDrops", "objectDrops", "itemDrops" } }
assert(loadfile("Integrations/QuestieObjectives.lua"))("AdventureGuideForever", ns)
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

-- The catalogue: a spot's level is the lowest of its mobs', and none when any spawn in it has no level (an object, or
-- an NPC QuestieDB gives none).
do
	local MAP = 1436
	local reads = { Npc = {}, Object = {}, Item = {}, levels = {}, names = { Npc = {}, Object = {}, Item = {} } }
	local rows = {
		Npc = {
			[1] = { spawns = { [MAP] = { { 28.4, 70.3 }, { 28.5, 70.4 }, { 28.3, 70.2 } } }, minLevel = 16 },
			[2] = { spawns = { [MAP] = { { 34.2, 15.9 } } }, minLevel = 12 },
			[3] = { spawns = { [MAP] = { { 50.0, 50.0 } } }, minLevel = 10 },
			[4] = { spawns = { [MAP] = { { 50.1, 50.1 } } }, minLevel = 14 },
			[5] = { spawns = { [MAP] = { { 70.0, 20.0 } } } },
		},
		Object = { [9] = { spawns = { [MAP] = { { 50.05, 50.05 } } } } },
		Item = {
			[7] = { npcDrops = { 3, 4 } },
			[8] = { npcDrops = { 3 }, objectDrops = { 9 } },
		},
	}
	local function Entity(kind)
		return {
			GetAll = function(id, keys)
				local row = rows[kind][id]
				if not row then
					return nil
				end
				local values = {}
				for index, key in ipairs(keys) do
					values[index] = row[key]
				end
				return values
			end,
		}
	end
	local lib = { Npc = Entity("Npc"), Object = Entity("Object"), Item = Entity("Item") }
	local data = { maps = { [MAP] = { sx = 1000, sy = 700 } } }
	local function Map(area)
		return area
	end
	local function yield() end
	local function Levels(objectives)
		local _, areas = ns.QuestieObjectives(lib, objectives, nil, MAP, data, Map, yield, 1, reads)
		local levels = {}
		for _, area in ipairs(areas or {}) do
			levels[#levels + 1] = ("%d@%d,%d=%s"):format(area[1], area[2], area[3], tostring(area[6]))
		end
		return table.concat(levels, " ")
	end
	equal(Levels({ { { 1 }, { 2 } } }), "0@284,703=16 1@342,159=12", "kills: each spot its mobs' level")
	equal(Levels({ nil, nil, { { 7 } } }), "4@500,500=10", "a drop from two mobs at one spot: the lower level")
	equal(Levels({ nil, nil, { { 8 } } }), "4@500,500=nil", "an object's spawn in the spot: no level")
	equal(Levels({ { { 5 } } }), "0@700,200=nil", "an NPC with no level: none")
	equal(reads.levels[1], 16, "the level is read with the spawns and kept for the build")
	equal(reads.levels[5], false, "no level is remembered as none")
	equal(ns.QuestieLevel("7.0"), 7, "a level from QuestieDB: a number")
	equal(ns.QuestieLevel(0), false, "a zero level is none")
end

-- The planner: Murloc Gills-style, the first spot's mobs are level 16, the second's 12.
do
	local Steps = ns.Planner.Steps
	local MAP = 1436
	local quest = {
		zone = MAP,
		need = { [4] = 0 },
		obj = { { 4, 284, 703, 97, MAP, 16 }, { 4, 342, 159, 39, MAP, 12 }, { 4, 269, 732, 71, MAP, 16 } },
	}
	local function At(level)
		local node = Steps.Planned(quest, 1, level)[1]
		return node and ("%.3f,%.3f"):format(node.x, node.y)
	end
	equal(At(12), "0.342,0.159", "level 12: the level-16 spot is passed over for the level-12 one")
	equal(At(13), "0.342,0.159", "level 13: 16 is still 3 above")
	equal(At(14), "0.284,0.703", "level 14: 16 is only 2 above, the data's first spot")
	equal(At(nil), "0.284,0.703", "no level known: the data's first spot")
	quest.obj = { { 4, 284, 703, 97, MAP, 20 }, { 4, 342, 159, 39, MAP, 18 } }
	equal(At(12), "0.284,0.703", "every spot over: the data's first, the quest stays placed")
	quest.obj = { { 4, 284, 703, 97, MAP }, { 4, 342, 159, 39, MAP, 12 } }
	equal(At(1), "0.284,0.703", "a spot with no level is never over")
	-- A quest under way picks the same way, slot by slot.
	quest.obj = { { 4, 284, 703, 97, MAP, 16 }, { 4, 342, 159, 39, MAP, 12 } }
	local data = harness.data()
	data.quests[999001] = quest
	local nodes = Steps.Nodes(data, { id = 999001, title = "Gills", level = 12, complete = false }, 12)
	equal(nodes[1] and ("%.3f,%.3f"):format(nodes[1].x, nodes[1].y), "0.342,0.159", "under way: the same choice")
	data.quests[999001] = nil
end

print(("mob_level_spec: %d checks passed"):format(checks))
