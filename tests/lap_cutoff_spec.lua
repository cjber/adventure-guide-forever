-- Run from the repository root: luajit tests/lap_cutoff_spec.lua
-- The lap's town cut-off (docs/design.md §4.2, Planning/Laps.lua): a town keeps a new pickup worth at least KEEP of
-- its mean XP per yard, and that mean is taken over every quest the town offers this lap, taken or not. Following the
-- plan therefore never moves the cut-off: taking a quest at a town leaves the town's other planned pickups alone
-- instead of dropping one (or adding one) because the quest log changed.
local harness = dofile("tests/harness.lua")
local characters = dofile("tests/fixtures/characters.lua")
local checks = 0
local function eq(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local fixture
for _, candidate in ipairs(characters.list) do
	if candidate.name == "orc18_barrens" then
		fixture = candidate
	end
end
assert(fixture, "Missing fixture: orc18_barrens")
local data = harness.data()
local player, completed, baseLog, wanted = characters.Resolve(data, fixture)
local ns = { Data = data }
local Shown = harness.shown(ns)
ns.Invalidate = function() end
ns.Setting = function(key)
	return key == "optimisedRoute"
end
local prefs = {}
for key, value in pairs(wanted) do
	prefs[key] = value
end
prefs.optimisedRoute, prefs.journey = true, "zone:1413"

---@param log table<integer, AGFLogQuest>
local function Build(log)
	return Shown.Build({ data = data, player = player, completed = completed, log = log, prefs = prefs })
end

---@param steps AGFStep[]
---@param key string
---@return integer[]
local function Pickups(steps, key)
	for _, step in ipairs(steps) do
		if step.kind == "town" and step.key == key then
			local ids = {}
			for _, id in ipairs(step.pickups) do
				ids[#ids + 1] = id
			end
			table.sort(ids)
			return ids
		end
	end
	return {}
end

local function Joined(ids)
	return table.concat(ids, " ")
end

-- The Crossroads, where the route plans Fungal Spores (848) beside Lost in Battle (4921) and three more. Taking
-- Fungal Spores in the log was enough to raise the town's mean past Lost in Battle and drop it from the route.
local CROSSROADS, TAKEN = "town:1413:380", 848
local before = Pickups(Build(baseLog).steps, CROSSROADS)
eq(Joined(before), "848 869 899 4921 6541", "the town offers its planned pickups")
local log = {}
for id, entry in pairs(baseLog) do
	log[id] = entry
end
local quest = data.quests[TAKEN]
log[TAKEN] = { id = TAKEN, title = quest.title, level = quest.level, complete = false }
local after = Pickups(Build(log).steps, CROSSROADS)
local rest = {}
for _, id in ipairs(before) do
	rest[#rest + 1] = id ~= TAKEN and id or nil
end
eq(Joined(after), Joined(rest), "taking a planned pickup leaves the town's other pickups")

print(("lap_cutoff_spec: %d checks passed"):format(checks))
