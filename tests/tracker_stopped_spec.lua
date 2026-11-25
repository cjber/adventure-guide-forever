local harness = dofile("tests/harness.lua")

local function Login(charDB)
	local h = harness.load({
		spf = "v1",
		completed = { 844 },
		db = { autoStart = false },
		charDB = charDB,
		log = { { id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 } },
	})
	h.flush()
	return h
end

local function CheckStep(h)
	local step = assert(h.ns.Guidance.CurrentStep(), "the route has a current step")
	assert(h.tracker.liveBlocks[step.key] and h.tracker.liveBlocks[step.key].used, "the tracker lays out the step")
end

local fresh = Login({})
assert(not fresh.ns.Route().chosen, "the new character has no chosen journey")
CheckStep(fresh)

local key = "zone:1413"
local h = Login({ journey = key })
CheckStep(h)
h.ns.Stop()
h.flush()
assert(not h.ns.Route().chosen, "Stop clears the chosen journey")
assert(#h.tracker.layoutOrder == 0, "Stop removes all adventure blocks")
assert(h.tracker:GetContentsHeight() == 0, "the empty section reserves no space for its heading")

h.ns.Choose(key)
h.flush()
assert(h.ns.Route().chosen, "Choose restores the journey")
CheckStep(h)

assert(#fresh.errors == 0, table.concat(fresh.errors, "\n"))
assert(#h.errors == 0, table.concat(h.errors, "\n"))
print("tracker_stopped_spec: passed")
