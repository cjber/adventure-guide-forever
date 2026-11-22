-- Run from the repository root: luajit tests/lap_cutoff_spec.lua
-- The lap's town cut-off (docs/design.md §4.2, Planning/Laps.lua): a town keeps a new pickup worth at least KEEP of
-- its mean XP per yard, and that mean is taken over every quest the town offers this lap, taken or not. Following the
-- plan therefore never moves the cut-off: taking a quest at a town leaves the town's other planned pickups alone
-- instead of dropping one (or adding one) because the quest log changed. A pinned quest a lap cannot plan is one of
-- the town's offers too, whether the log carries it or not.
local harness = dofile("tests/harness.lua")
local characters = dofile("tests/fixtures/characters.lua")
local checks = 0
local function eq(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- One fixture's route on one card: `Build` from a log with the player's prefs, `pinned` added when given, and `Take`
-- as the same log with `id` accepted.
---@param name string
---@param journey string
local function Setup(name, journey)
	local fixture
	for _, candidate in ipairs(characters.list) do
		if candidate.name == name then
			fixture = candidate
		end
	end
	assert(fixture, "Missing fixture: " .. name)
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
	prefs.optimisedRoute, prefs.journey = true, journey
	---@param log table<integer, AGFLogQuest>
	---@param pinned? table<integer, boolean>
	---@return AGFStep[]
	local function Build(log, pinned)
		local buildPrefs = prefs
		if pinned then
			buildPrefs = {}
			for key, value in pairs(prefs) do
				buildPrefs[key] = value
			end
			buildPrefs.pinned = pinned
		end
		return Shown.Build({ data = data, player = player, completed = completed, log = log, prefs = buildPrefs }).steps
	end
	---@param log table<integer, AGFLogQuest>
	---@param id integer
	---@return table<integer, AGFLogQuest>
	local function Take(log, id)
		local taken = {}
		for key, entry in pairs(log) do
			taken[key] = entry
		end
		local quest = data.quests[id]
		taken[id] = { id = id, title = quest.title, level = quest.level, complete = false }
		return taken
	end
	return { baseLog = baseLog, Build = Build, Take = Take }
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

-- `ids` without `id`.
---@param ids integer[]
---@param id integer
---@return integer[]
local function Without(ids, id)
	local rest = {}
	for _, other in ipairs(ids) do
		rest[#rest + 1] = other ~= id and other or nil
	end
	return rest
end

-- The Crossroads, where the route plans Fungal Spores (848) beside Lost in Battle (4921) and four more. Taking
-- Fungal Spores in the log was enough to raise the town's mean past Lost in Battle and drop it from the route.
-- QuestieDB v1.1.4 moves Vrang's Game's objectives, adding Harpy Raiders as a sixth pickup.
local CROSSROADS, TAKEN = "town:1413:380", 848
local barrens = Setup("orc18_barrens", "zone:1413")
local before = Pickups(barrens.Build(barrens.baseLog), CROSSROADS)
eq(Joined(before), "848 867 869 899 4921 6541", "the town offers its planned pickups")
local after = Pickups(barrens.Build(barrens.Take(barrens.baseLog, TAKEN)), CROSSROADS)
eq(Joined(after), Joined(Without(before, TAKEN)), "taking a planned pickup leaves the town's other pickups")

-- A pinned quest a lap cannot plan (The Family and the Fishing Pole, 1141, has an objective the data does not place)
-- stands at Auberdine as one of the town's offers. Taking it used to drop it from the pool, lower the town's mean and
-- put a pickup back on the route the plan had left off.
local PINNED, AUBERDINE = 1141, "town:1439:442"
local elwynn = Setup("human12_elwynn", "zone:1439")
local pin = { [PINNED] = true }
local offered = Pickups(elwynn.Build(elwynn.baseLog, pin), AUBERDINE)
eq(Joined(offered), "958 983 1141 2118 98025", "a pinned quest a lap cannot plan is one of the town's offers")
local pinnedAfter = Pickups(elwynn.Build(elwynn.Take(elwynn.baseLog, PINNED), pin), AUBERDINE)
eq(Joined(pinnedAfter), Joined(Without(offered, PINNED)), "taking a pinned quest leaves the town's other pickups")

print(("lap_cutoff_spec: %d checks passed"):format(checks))
