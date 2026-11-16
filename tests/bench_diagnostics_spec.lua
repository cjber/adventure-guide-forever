-- Deterministic attribution: no real benchmark or corpus is needed.
local D = dofile("tests/bench_diagnostics.lua")
local cpu, wall = 0, 0
local function advance(c, w)
	cpu, wall = cpu + c, wall + w
end
local clock = {
	cpu = function()
		return cpu
	end,
	wall = function()
		return wall
	end,
}
local h = { G = { coroutine = coroutine }, errors = {} }
function h.call(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		h.errors[#h.errors + 1] = err
	end
end
local originalCall, originalCoroutine = h.call, h.G.coroutine
local thread = coroutine.create(function(value)
	advance(2, 3)
	value = coroutine.yield(value, nil, "yield")
	advance(4, 5)
	return value, nil, "done"
end)
local function timer()
	local ok, value, hole, tail = h.G.coroutine.resume(thread, 17)
	assert(ok and value == 17 and hole == nil and tail == "yield")
	ok, value, hole, tail = h.G.coroutine.resume(thread, 23)
	assert(ok and value == 23 and hole == nil and tail == "done")
	advance(1, 2)
end
local frame = { scripts = {} }
frame.scripts.OnUpdate = function()
	advance(3, 7)
end
function h.tick()
	h.call(timer)
	h.call(function()
		advance(1, 1)
		error("callback sentinel", 0)
	end)
	h.call(frame.scripts.OnUpdate, frame, 1 / 60)
	return 2, nil, "tick"
end
local d = D.new(clock, true)
local record, ran, hole, tail = d:tick(h, { profile = "P", sample = 2, frame = 3 })
assert(ran == 2 and hole == nil and tail == "tick")
assert(record.profile == "P" and record.sample == 2 and record.frame == 3)
assert(record.cpu == 11 and record.wall == 18)
assert(#record.spans == 5)
assert(record.spans[1].kind == "timer" and record.spans[1].cpu == 7)
assert(record.spans[2].kind == "resume" and record.spans[2].cpu == 2)
assert(record.spans[3].kind == "resume" and record.spans[3].cpu == 4)
assert(record.spans[4].cpu == 1 and record.spans[5].kind == "OnUpdate")
assert(record.spans[2].parent == 1 and record.spans[3].parent == 1)
assert(record.spans[1].source:find("bench_diagnostics_spec.lua", 1, true))
assert(record.spans[1].line > 0 and record.finish == "unavailable")
assert(#h.errors == 1 and h.errors[1] == "callback sentinel")
assert(h.call == originalCall and h.G.coroutine == originalCoroutine)
assert(coroutine.resume == originalCoroutine.resume)
-- A thrown tick must restore owned wrappers and retain the failed frame.
h.tick = function()
	h.call(timer)
	error("tick sentinel", 0)
end
local ok, err = pcall(function()
	d:tick(h, { profile = "error", sample = 1, frame = 1 })
end)
assert(not ok and err == "tick sentinel")
assert(h.call == originalCall and h.G.coroutine == originalCoroutine)
assert(#d.frames == 2 and d.frames[2].error == "tick sentinel")
-- Ordinary mode records every whole tick without touching callback/coroutine ownership.
h.tick = function()
	assert(h.call == originalCall)
	advance(5, 9)
	return 0
end
local light = D.new(clock, false)
local r = light:tick(h, { profile = "light", sample = 1, frame = 1 })
assert(r.cpu == 5 and r.wall == 9 and r.spans == nil)
assert(light:format():find("FinishRebuild=unavailable", 1, true))
-- Choose the actual maximum, retaining the owning sample/frame rather than the last sample.
d:consider("rebuild", record, record.cpu)
d:consider("rebuild", r, r.cpu)
assert(d.worst.rebuild.record == record)
assert(d:format():find("worst rebuild: P sample=2 frame=3", 1, true))
-- Summary identities follow the supplied budget score, even when raw CPU ranks differently.
local summary = D.new(clock, false)
local costly = { profile = "CPU", sample = 1, frame = 1, cpu = 9, wall = 12, modelled = 0 }
local modelled = { profile = "model", sample = 2, frame = 2, cpu = 1, wall = 2, modelled = 4 }
for _, phase in ipairs({ "rebuild", "travel", "catalogue" }) do
	summary:consider(phase, costly, costly.cpu / 3 + costly.modelled)
	summary:consider(phase, modelled, modelled.cpu / 3 + modelled.modelled)
	assert(summary.worst[phase].record == modelled)
	assert(summary:format():find("worst " .. phase .. ": model sample=2 frame=2", 1, true))
end
assert(summary:format():find("cpu=1.000000 wall=2.000000 modelled=4.000000", 1, true))
-- Real harness dispatch: two queued timers, a visible OnUpdate and real coroutine resumes.
local harness = dofile("tests/harness.lua")
local real = harness.load()
real.flush()
local visible = real.G.CreateFrame("Frame")
visible:SetScript("OnUpdate", function()
	advance(3, 7)
end)
visible:Show()
local worker = coroutine.create(function()
	advance(2, 3)
	coroutine.yield()
	advance(4, 5)
	error("resume sentinel", 0)
end)
real.G.C_Timer.After(0, function()
	assert(real.G.coroutine.resume(worker))
end)
real.G.C_Timer.After(0, function()
	local resumed, message = real.G.coroutine.resume(worker)
	assert(not resumed and message == "resume sentinel")
end)
local realCall, realCo = real.call, rawget(real.G, "coroutine")
local actual = D.new(clock, true)
local measured, count = actual:tick(real, { profile = "real", sample = 1, frame = 1 })
assert(count >= 2 and measured.cpu == 9 and measured.wall == 15)
local resumes, updates = 0, 0
for _, span in ipairs(measured.spans) do
	if span.kind == "resume" then
		resumes = resumes + 1
	end
	if span.kind == "OnUpdate" and span.cpu == 3 then
		updates = updates + 1
	end
end
assert(resumes == 2 and updates == 1)
assert(real.call == realCall and rawget(real.G, "coroutine") == realCo)
assert(#real.errors == 0)
-- The real harness catches callback errors after instrumentation returns. Preserve the
-- nested failure stack in the span before unwinding, including error(message, 0).
local function nestedFailure()
	error("nested callback sentinel", 0)
end
local function outerCallback()
	nestedFailure()
	advance(0, 0) -- Keep the nested call on the stack rather than tail-calling it.
end
real.G.C_Timer.After(0, outerCallback)
local failed = actual:tick(real, { profile = "nested", sample = 2, frame = 1 })
assert(#real.errors == 1 and real.errors[1]:find("nested callback sentinel", 1, true))
local callbackSpan = failed.spans[1]
local failureLine = debug.getinfo(nestedFailure, "S").linedefined + 1
assert(callbackSpan.error == "nested callback sentinel")
assert(callbackSpan.traceback:find("bench_diagnostics_spec.lua:" .. failureLine, 1, true))
assert(callbackSpan.traceback:find("nestedFailure", 1, true))
local callerLine = debug.getinfo(outerCallback, "S").linedefined + 1
assert(callbackSpan.traceback:find("bench_diagnostics_spec.lua:" .. callerLine, 1, true))
assert(actual:format():find(callbackSpan.traceback, 1, true))
assert(real.call == realCall and rawget(real.G, "coroutine") == realCo)
-- Diagnostic text must not replace the original error object passed to h.call.
local errorObject = {}
local caught
real.call = function(fn)
	local success, value = pcall(fn)
	if not success then
		caught = value
	end
end
real.G.C_Timer.After(0, function()
	error(errorObject, 0)
end)
actual:tick(real, { profile = "object", sample = 3, frame = 1 })
assert(caught == errorObject)
real.call = realCall
local realClock = D.clock()
assert(realClock.wall() <= realClock.wall())
print("bench_diagnostics_spec: passed")
