-- Run from the repository root: luajit tests/camp_spec.lua
-- Where an objective is done (docs/design.md §4.2): the catalogue groups a slot's spawns into camps, the biggest camp
-- first and a lone spawn behind it, each at its camp's medoid (Integrations/QuestieObjectives.lua Places), and marks a
-- spot whose mobs are all elites; the planner then takes a camp of normal mobs over one of elites, and either over one
-- far above the player (Planning/Steps.lua AreaNode).
local ns = {}
local harness = dofile("tests/harness.lua")
harness.model(ns)
ns.QuestieFields = {
	spawns = { "spawns" },
	drops = { "npcDrops", "objectDrops", "itemDrops" },
	level = { "minLevel" },
	rank = { "rank" },
}
assert(loadfile("Integrations/QuestieObjectives.lua"))("AdventureGuideForever", ns)
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

-- A map 1,000 yards square, so a map unit of 0.1 (in QuestieDB's 0-100) is one yard and a cell is 10 units wide.
local MAP = 1436
local rows = { Npc = {}, Object = {}, Item = {} }
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
local data = { maps = { [MAP] = { sx = 1000, sy = 1000 }, [1429] = { sx = 1000, sy = 1000 } } }
local function Map(area)
	return area
end
local function yield() end
local function Reads()
	return { Npc = {}, Object = {}, Item = {}, levels = {}, elite = {}, names = { Npc = {}, Object = {}, Item = {} } }
end
-- The spots QuestieObjectives gives one kill objective of NPC 1, as "x,y r level elite" in order.
local function Spots(zone, reads)
	local _, areas = ns.QuestieObjectives(lib, { { { 1 } } }, nil, zone or MAP, data, Map, yield, 1, reads or Reads())
	local spots = {}
	for _, area in ipairs(areas or {}) do
		spots[#spots + 1] = ("%d,%d r%d %s %s%s"):format(
			area[2],
			area[3],
			area[4],
			tostring(area[6]),
			tostring(area[7]),
			area[5] ~= MAP and (" @" .. area[5]) or ""
		)
	end
	return table.concat(spots, " | ")
end

-- Camps: a camp of six that a 100-yard square's edge cuts in half beats a tight cluster of four, and a lone spawn comes
-- last.
do
	rows.Npc[1] = {
		minLevel = 10,
		spawns = {
			[MAP] = {
				-- The camp: three spawns either side of the line between two squares (x 19.x and 20.x).
				{ 19.5, 50.0 },
				{ 19.8, 50.4 },
				{ 19.6, 49.6 },
				{ 20.2, 50.2 },
				{ 20.5, 49.8 },
				{ 20.3, 50.6 },
				-- A cluster of four in one square, far off.
				{ 70.1, 70.1 },
				{ 70.2, 70.2 },
				{ 70.3, 70.1 },
				{ 70.2, 70.3 },
				-- A lone spawn.
				{ 40.5, 20.5 },
			},
		},
	}
	equal(
		Spots(),
		"202,502 r9 10 nil | 702,702 r2 10 nil | 405,205 r0 10 nil",
		"the camp across the edge first, on the spawn nearest the rest, then the cluster, then the lone spawn"
	)
	-- A camp is one spot: none of its other spawns is offered as another.
	rows.Npc[1].spawns[MAP][11] = nil
	equal(Spots(), "202,502 r9 10 nil | 702,702 r2 10 nil", "a camp's other spawns are the same camp, not a spot")
	-- The ring holds the camp, the spawns within 100 yards; one farther off is a spot of its own.
	rows.Npc[1].spawns[MAP] = { { 50.0, 50.0 }, { 50.3, 50.0 }, { 50.1, 50.4 }, { 61.5, 50.0 } }
	equal(Spots(), "500,500 r5 10 nil | 615,500 r0 10 nil", "a spawn 115 yards off isn't in the camp or its ring")
	-- Scattered mobs (Lazy Peons): the spawn with the most others within 100 yards.
	rows.Npc[1].spawns[MAP] = { { 10.0, 10.0 }, { 18.0, 10.0 }, { 26.0, 10.0 }, { 34.0, 10.0 }, { 60.0, 60.0 } }
	equal(
		Spots(),
		"180,100 r81 10 nil | 340,100 r81 10 nil | 600,600 r0 10 nil",
		"scattered: a spawn between two others first, then the next not in its camp"
	)
end

-- The quest's zone first, then the biggest camp: a camp on another map never beats a spot in the zone.
do
	rows.Npc[1] = {
		minLevel = 10,
		spawns = { [MAP] = { { 30.0, 30.0 } }, [1429] = { { 50.0, 50.0 }, { 50.1, 50.1 }, { 50.2, 50.0 } } },
	}
	equal(Spots(MAP), "300,300 r0 10 nil | 501,501 r2 10 nil @1429", "a lone spawn in the zone before a camp elsewhere")
end

-- Elites: a spot is elite only when every spawn in it is an elite's (QuestieDB rank 1 to 3).
do
	rows.Npc[1] = { minLevel = 12, rank = 1, spawns = { [MAP] = { { 20.0, 20.0 }, { 20.1, 20.1 } } } }
	rows.Npc[2] = { minLevel = 10, rank = 0, spawns = { [MAP] = { { 20.2, 20.2 }, { 60.0, 60.0 } } } }
	rows.Npc[3] = { minLevel = 11, rank = 4, spawns = { [MAP] = { { 80.0, 80.0 } } } }
	rows.Item[7] = { npcDrops = { 1, 2, 3 } }
	local reads = Reads()
	local _, areas = ns.QuestieObjectives(lib, { nil, nil, { { 7 } } }, nil, MAP, data, Map, yield, 1, reads)
	equal(#areas, 3, "three spots")
	equal(areas[1][7], nil, "elites and a normal mob together: not elite")
	equal(areas[1][6], 10, "and the lowest level among them")
	rows.Npc[2].spawns = { [MAP] = { { 60.0, 60.0 } } }
	reads = Reads()
	_, areas = ns.QuestieObjectives(lib, { nil, nil, { { 7 } } }, nil, MAP, data, Map, yield, 1, reads)
	equal(areas[1][7], true, "only elites: elite")
	equal(areas[2][7], nil, "a normal mob alone: not elite")
	equal(areas[3][7], nil, "a rare that isn't elite (rank 4): not elite")
	equal(reads.elite[1], true, "the rank is read with the spawns and kept for the build")
	equal(reads.elite[3], false, "a rare is remembered as not elite")
	equal(ns.QuestieElite(2), true, "a rare elite is elite")
	equal(ns.QuestieElite(3), true, "a boss is elite")
	equal(ns.QuestieElite(nil), false, "no rank: not elite")
	-- A QuestieDB without the rank field: no rank is asked for, and no spot is elite.
	local asked
	local wrapped = lib.Npc.GetAll
	lib.Npc.GetAll = function(id, keys)
		asked = #keys
		return wrapped(id, keys)
	end
	local plain = Reads()
	plain.elite = nil
	_, areas = ns.QuestieObjectives(lib, { { { 1 } } }, nil, MAP, data, Map, yield, 1, plain)
	equal(areas[1][7], nil, "no rank field: never elite")
	equal(asked, 2, "no rank field: spawns and level alone are read")
	lib.Npc.GetAll = wrapped
end

-- The planner: normal mobs before elites, and elites last even after mobs far above (#152's weighting).
do
	local Steps = ns.Planner.Steps
	local quest = { zone = MAP, need = { [0] = 0 } }
	local function At(level, obj)
		quest.obj = obj
		local node = Steps.Planned(quest, 1, level)[1]
		local alternates = {}
		for _, spot in ipairs(node.alternates or {}) do
			alternates[#alternates + 1] = ("%.3f"):format(spot.x)
		end
		return ("%.3f [%s]"):format(node.x, table.concat(alternates, " "))
	end
	equal(
		At(10, { { 0, 100, 100, 40, MAP, 10, true }, { 0, 200, 200, 40, MAP, 10 }, { 0, 300, 300, 40, MAP, 10 } }),
		"0.200 [0.300]",
		"an elite camp is passed over for the next camp of normal mobs; the elites aren't another spot"
	)
	equal(
		At(10, { { 0, 100, 100, 40, MAP, 10, true }, { 0, 200, 200, 40, MAP, 14 } }),
		"0.200 []",
		"normal mobs 4 above before elites at the player's level"
	)
	equal(
		At(10, { { 0, 100, 100, 40, MAP, 14, true }, { 0, 200, 200, 40, MAP, 10, true } }),
		"0.200 []",
		"among elites, those nearer the player's level"
	)
	equal(
		At(10, { { 0, 100, 100, 40, MAP, 10, true }, { 0, 200, 200, 40, MAP, 10, true } }),
		"0.100 [0.200]",
		"every camp elite: the data's first, the others its spots"
	)
	equal(
		At(10, { { 0, 100, 100, 40, MAP, 10, true }, { 0, 200, 200, 40, 1429, 10 } }),
		"0.100 []",
		"a normal camp on another map isn't taken: never a spot across the world"
	)
	equal(
		At(nil, { { 0, 100, 100, 40, MAP, 10, true }, { 0, 200, 200, 40, MAP } }),
		"0.200 []",
		"no level known: still"
	)
end

print(("camp_spec: %d checks passed"):format(checks))
