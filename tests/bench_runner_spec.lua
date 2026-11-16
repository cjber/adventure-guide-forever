-- Exercise plan_bench's runner with two synthetic ticks, never running the planner or benchmark.
local D = dofile("tests/bench_diagnostics.lua")
local function runCase(detailed, uncaught)
	local output, diagnostics, ticks = {}, nil, 0
	local settling = false
	local sentinel = setmetatable({}, {
		__tostring = function()
			return "exceptional runner sentinel"
		end,
	})
	local h = {
		G = { coroutine = coroutine, ShortestPathForever = { API = {} } },
		counts = { CreateFrame = 0 },
		errors = {},
		ns = {
			OpenPanel = function() end,
			Route = function()
				return { steps = {} }
			end,
			Settling = function()
				return settling
			end,
			Invalidate = function()
				settling = true
			end,
		},
		flush = function() end,
		call = function(fn, ...)
			return fn(...) -- multi-value: synthetic harness dispatch
		end,
	}
	-- The first invalidation is warmup. The next starts the first sampled rebuild.
	local invalidations = 0
	h.ns.Invalidate = function()
		invalidations = invalidations + 1
		settling = invalidations > 1
	end
	h.tick = function()
		ticks = ticks + 1
		if ticks == 2 then
			error(sentinel, 0)
		end
		return 1
	end
	local originalCall, originalCoroutine = h.call, h.G.coroutine
	local env = setmetatable({
		dofile = function(path)
			if path == "tests/harness.lua" then
				return {
					data = function()
						return { quests = {} }
					end,
					load = function()
						return h
					end,
				}
			end
			assert(path == "tests/bench_diagnostics.lua")
			return {
				clock = function()
					return {
						cpu = function()
							return 0
						end,
						wall = function()
							return 0
						end,
					}
				end,
				new = function(clock, trace)
					assert(trace == detailed)
					diagnostics = D.new(clock, trace)
					return diagnostics
				end,
			}
		end,
		os = {
			getenv = function(name)
				return name == "AGF_BENCH_TRACE" and detailed and "1" or nil
			end,
		},
		print = function(value)
			output[#output + 1] = value
		end,
	}, { __index = _G })
	if uncaught then
		env.print = print
	end
	local runner = setfenv(assert(loadfile("tests/plan_bench.lua")), env)
	if uncaught then
		runner()
		error("exceptional runner unexpectedly returned")
	end
	local ok, err = pcall(runner)
	assert(not ok and err == sentinel, "runner must rethrow the original error object")
	assert(ticks == 2 and #diagnostics.frames == 2)
	local emitted = table.concat(output, "\n")
	assert(emitted:find("frame Alliance 1 sample=1 frame=1", 1, true), "preceding frame was not emitted")
	assert(emitted:find("frame Alliance 1 sample=1 frame=2", 1, true), "failed frame was not emitted")
	assert(emitted:find("error=exceptional runner sentinel", 1, true), "tick error was not emitted")
	assert(h.call == originalCall and h.G.coroutine == originalCoroutine)
end
-- This mode lets focused subprocess checks verify stdout survives a nonzero exit.
if arg[1] == "--exception" then
	runCase(arg[2] == "detailed", true)
end
runCase(false)
runCase(true)
-- Successful runners emit once and preserve nil-containing return tuples.
local d = D.new({}, false)
local emissions = 0
local a, b, c = d:run(function()
	return 7, nil, "tail"
end, function(text)
	emissions = emissions + 1
	assert(text == d:format())
end)
assert(a == 7 and b == nil and c == "tail" and emissions == 1)
print("bench_runner_spec: passed")
