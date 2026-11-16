-- Empty snapshots do no urgency work; nonempty snapshots retain exact selection and route behavior.
local harness = dofile("tests/harness.lua")
local function same(a, b, path)
	path = path or "output"
	assert(type(a) == type(b), path .. " type")
	if type(a) ~= "table" then
		assert(a == b, path .. " value")
		return
	end
	for key, value in pairs(b) do
		same(a[key], value, path .. "." .. tostring(key))
	end
	for key in pairs(a) do
		assert(b[key] ~= nil, path .. " extra " .. tostring(key))
	end
end

local ns = {}
harness.model(ns)
local handins, calls = ns.Model.Handins, 0
ns.Model.Handins = function(step)
	calls = calls + 1
	return handins(step)
end
assert(ns.Planner.Laps.Urgent({}, { handins = { 1 }, objectives = { { id = 2 } } }) == nil)
assert(calls == 0, "empty snapshot reached Handins")
ns.Model.Handins = handins
local step = { handins = { 1, 2 }, objectives = { { id = 3 }, { id = 4 } } }
local cases = {
	{ {}, nil },
	{ { [1] = { id = 1, complete = true } }, nil },
	{ { [1] = { id = 1, complete = false, deadline = 1 } }, nil },
	{ { [3] = { id = 3, complete = true, deadline = 1 } }, nil },
	{ { [1] = { id = 1, complete = true, expiring = true } }, 1 },
	{ { [3] = { id = 3, complete = false, expiring = true } }, 3 },
	{ { [1] = { id = 1, complete = true, deadline = 20 }, [3] = { id = 3, deadline = 10 } }, 3 },
	{ { [1] = { id = 1, complete = true, deadline = 10 }, [3] = { id = 3, deadline = 10 } }, 1 },
	{ { [1] = { id = 1, complete = true, expiring = true }, [3] = { id = 3, deadline = 20 } }, 3 },
	{ { [1] = { id = 1, complete = true, expiring = true }, [3] = { id = 3, expiring = true } }, 1 },
}
for _, case in ipairs(cases) do
	assert(ns.Planner.Laps.Urgent(case[1], step) == case[1][case[2]], "urgency selection")
end

-- Load the pre-guard algorithm in a fresh namespace, keeping all other modules identical.
local file = assert(io.open("Planning/Laps.lua"))
local source = file:read("*a")
file:close()
local guard = "\tif next(log) == nil then\n\t\treturn nil\n\tend\n"
local before, count = source:gsub(guard:gsub("(%W)", "%%%1"), "", 1)
assert(count == 1, "expected one empty-log guard")
local function run(log, planned, baseline)
	local model = {}
	local loader = loadfile
	if baseline then
		_G.loadfile = function(path)
			if path == "Planning/Laps.lua" then
				return loadstring(before, "@before/Planning/Laps.lua")
			end
			return loader(path)
		end
	end
	harness.model(model)
	_G.loadfile = loader
	local world = {
		quests = {},
		zones = { [1] = { name = "Here", min = 10, max = 20 } },
		maps = { [1] = { name = "Here", continent = 1, cx = 0, cy = 0, sx = 1000, sy = 1000 } },
		continents = { [1] = { x = 0, y = 0 } },
	}
	for id = 1, 4 do
		world.quests[id] = {
			title = "Quest " .. id,
			level = 16,
			min = 10,
			side = 2,
			zone = 1,
			start = { map = 1, x = 0.4, y = 0.5, name = "Giver" },
			finish = { map = 1, x = 0.6, y = 0.5, name = "Ender" },
			need = { [1] = 2 },
			obj = { { 1, id * 100, 500, 10, 1 } },
		}
	end
	local snapshot = {}
	for id, entry in pairs(log) do
		local copy = { title = "Quest " .. id, level = 16, map = 1, x = 0.4 + id * 0.02, y = 0.5 }
		for key, value in pairs(entry) do
			copy[key] = value
		end
		copy.objectives =
			{ { text = "Work", have = copy.complete and 2 or 0, need = 2, done = copy.complete or false } }
		snapshot[id] = copy
	end
	local result
	local thread = coroutine.create(function()
		result = model.Model.Plan(
			world,
			{ level = 16, maxLevel = 60, side = 2, raceBit = 2, classBit = 64, map = 1, x = 0.5, y = 0.5 },
			{},
			snapshot,
			{ quests = true, dungeons = true, skipped = {}, optimisedRoute = planned },
			nil,
			nil,
			{ orders = { turnins = { "stale", picked = { [77] = true }, taken = { [88] = true } } } }
		)
	end)
	local yields = 0
	repeat
		local ok, err = coroutine.resume(thread)
		assert(ok, err)
		if coroutine.status(thread) ~= "dead" then
			yields = yields + 1
		end
	until coroutine.status(thread) == "dead"
	return result, yields
end
for _, case in ipairs(cases) do
	for _, planned in ipairs({ false, true }) do
		local actual, yields = run(case[1], planned, false)
		local baseline, oldYields = run(case[1], planned, true)
		assert(#actual.steps > 0 and yields > 0, "fixture must exercise route work and yields")
		same(actual.orders, baseline.orders, "orders")
		same(actual, baseline)
		assert(yields == oldYields, "yield count")
	end
end
print("empty_urgency_spec: empty work guard, 10 urgency selections, 20 full Plan/order/yield comparisons passed")
