-- Test-only frame diagnostics. Inclusive spans are never added to whole-tick totals.
local D = {}
local function pack(...)
	return { n = select("#", ...), ... }
end
local function invoke(fn, ...)
	local args = pack(...)
	local traceback
	local values = pack(xpcall(function()
		return fn(unpack(args, 1, args.n))
	end, function(err)
		-- Capture while the failing call chain is still live; return the untouched error value.
		traceback = debug.traceback("", 2)
		return err
	end))
	values.traceback = traceback
	return values
end
local function result(values)
	if not values[1] then
		error(values[2], 0)
	end
	return unpack(values, 2, values.n) -- multi-value: preserve nils and all returns
end
function D.clock()
	-- LuaJIT on Linux, the benchmark's supported runner. No CPU/nonmonotonic fallback.
	local ffi = require("ffi")
	assert(ffi.os == "Linux" and ffi.abi("64bit"), "benchmark diagnostics require 64-bit Linux CLOCK_MONOTONIC")
	ffi.cdef([[int clock_gettime(int clockid, void *tp);]])
	local time = ffi.new("long[2]")
	return {
		cpu = function()
			return os.clock() * 1000
		end,
		wall = function()
			assert(ffi.C.clock_gettime(1, time) == 0, "CLOCK_MONOTONIC unavailable")
			return tonumber(time[0]) * 1000 + tonumber(time[1]) / 1e6
		end,
	}
end
function D.new(clock, detailed)
	return setmetatable({ clock = clock, detailed = detailed, frames = {}, worst = {} }, { __index = D })
end
function D:span(record, kind, fn, ...)
	local info = debug.getinfo(fn, "S")
	local span = { kind = kind, source = info.source, line = info.linedefined, parent = record.active }
	if kind == "resume" then
		local thread = (...)
		span.thread = tostring(thread)
		if type(thread) == "thread" then
			local body = debug.getinfo(thread, 1, "S")
			span.coroutineSource = body and body.source or "unavailable"
			span.coroutineLine = body and body.linedefined or -1
		end
	end
	local index = #record.spans + 1
	record.spans[index], record.active = span, index
	local cpu, wall = self.clock.cpu(), self.clock.wall()
	local values = invoke(fn, ...)
	span.cpu, span.wall = self.clock.cpu() - cpu, self.clock.wall() - wall
	if not values[1] then
		span.error = tostring(values[2])
		span.traceback = values.traceback
	elseif kind == "resume" and values[2] == false then
		span.error = tostring(values[3])
	end
	record.active = span.parent
	return result(values) -- multi-value: preserve original error values and return tuple
end
function D:tick(h, identity)
	local record = {
		profile = identity.profile,
		sample = identity.sample,
		frame = identity.frame,
		spans = self.detailed and {} or nil,
		finish = "unavailable",
	}
	local call, co = h.call, h.G.coroutine
	local ownCoroutine = rawget(h.G, "coroutine")
	if self.detailed then
		local copy = {}
		for key, value in pairs(co) do
			copy[key] = value
		end
		copy.resume = function(...)
			return self:span(record, "resume", co.resume, ...)
		end
		h.G.coroutine = copy
		h.call = function(fn, ...)
			local first = select(1, ...)
			local kind = type(first) == "table" and first.scripts and first.scripts.OnUpdate == fn and "OnUpdate"
				or "timer"
			return call(function(...)
				return self:span(record, kind, fn, ...)
			end, ...)
		end
	end
	local cpu, wall = self.clock.cpu(), self.clock.wall()
	local values = invoke(h.tick)
	record.cpuStart, record.wallStart = cpu, wall
	record.cpuEnd, record.wallEnd = self.clock.cpu(), self.clock.wall()
	record.cpu, record.wall = record.cpuEnd - cpu, record.wallEnd - wall
	if self.detailed then
		h.call, h.G.coroutine = call, ownCoroutine
	end
	if not values[1] then
		record.error = tostring(values[2])
	end
	self.frames[#self.frames + 1] = record
	return record, result(values) -- multi-value: tick's original return tuple
end
-- Emit retained history on both normal completion and unexpected profile/tick failures.
function D:run(fn, emit)
	local values = invoke(fn)
	local output = emit or print
	output(self:format(not values[1]))
	return result(values) -- multi-value: preserve original error values and return tuple
end
function D:consider(kind, record, score)
	local previous = self.worst[kind]
	if not previous or score > previous.score then
		self.worst[kind] = { record = record, score = score }
	end
end
function D:format(exceptional)
	local lines = {
		"AGF diagnostics: "
			.. (self.detailed and "detailed (overhead included)" or "lightweight")
			.. "; inclusive spans; FinishRebuild=unavailable"
			.. "; sample=0 frame=0 denotes initialization outside h.tick",
	}
	for _, kind in ipairs({ "rebuild", "travel", "catalogue" }) do
		local worst = self.worst[kind]
		if worst then
			local r = worst.record
			lines[#lines + 1] = ("worst %s: %s sample=%d frame=%d score=%.6f cpu=%.6f wall=%.6f modelled=%.6f"):format(
				kind,
				r.profile,
				r.sample,
				r.frame,
				worst.score,
				r.cpu,
				r.wall,
				r.modelled or 0
			)
		end
	end
	if not self.detailed and not exceptional then
		return table.concat(lines, "\n")
	end
	for _, r in ipairs(self.frames) do
		lines[#lines + 1] = (
			"frame %s sample=%d frame=%d phase=%s cpu=%.6f wall=%.6f modelled=%.6f"
			.. " cpuStart=%s wallStart=%s error=%s"
		):format(
			r.profile,
			r.sample,
			r.frame,
			r.phase or "unknown",
			r.cpu,
			r.wall,
			r.modelled or 0,
			tostring(r.cpuStart),
			tostring(r.wallStart),
			r.error or "none"
		)
		for i = 1, r.spans and #r.spans or 0 do
			local s = r.spans[i]
			lines[#lines + 1] = (
				" span=%d parent=%s kind=%s source=%s:%d cpu=%.6f wall=%.6f"
				.. " error=%s thread=%s coroutineSource=%s:%s"
			):format(
				i,
				tostring(s.parent),
				s.kind,
				s.source,
				s.line,
				s.cpu,
				s.wall,
				s.error or "none",
				s.thread or "none",
				s.coroutineSource or "unavailable",
				tostring(s.coroutineLine or -1)
			)
			if s.traceback then
				lines[#lines + 1] = " traceback=" .. s.traceback
			end
		end
	end
	return table.concat(lines, "\n")
end
return D
