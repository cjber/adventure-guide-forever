-- Run from the repository root: luajit tests/login_guide_spec.lua
-- A login that has to build the QuestieDB catalogue (#373): with a RestedXP guide chosen, the tracker shows the guide's
-- step while the catalogue builds, since the guide's steps come from RestedXP; once the catalogue lands, the full
-- build keeps the same step and fills in its quests. Without a guide the loading line stands, as before.
local harness = dofile("tests/harness.lua")

local ready
local function Login(charDB)
	local data = harness.data()
	local h = harness.load({
		questiedb = harness.questieMirror(data),
		charDB = charDB,
		setup = function(loaded)
			loaded.G.Questie = {
				API = {
					isReady = false,
					RegisterOnReady = function(fn)
						ready = fn
					end,
				},
			}
			-- The harness runs every timer at once: hold back QuestieSource's wait for a Questie that never reports ready.
			local after = loaded.G.C_Timer.After
			loaded.G.C_Timer.After = function(delay, fn)
				if delay < 60 then
					after(delay, fn)
				end
			end
		end,
	})
	h.flush()
	return h
end

local function Loading(h)
	local loading = h.tracker.liveBlocks.loading
	return loading ~= nil and loading.used == true
end

-- A guide chosen on an earlier login, and the catalogue not built yet.
local first = Login()
dofile("tests/rxp_fixture.lua")(first)
local guide = assert(first.ns.RestedXP.Journey())
first.ns.Choose(guide.key)
first.flush()
local h = Login(first.G.AdventureGuideForeverCharDB)
dofile("tests/rxp_fixture.lua")(h)
h.flush()
assert(h.ns.QuestieBuilding(), "the catalogue waits for Questie")
local route = h.ns.Route()
assert(route.chosen and route.journey == guide.key, "the chosen guide stands while the catalogue builds")
assert(route.steps[1] and route.steps[1].rxpIndex == 2, "the guide's current step leads")
assert(h.ns.Guidance.CurrentStep() == route.steps[1], "the tracker's step is the guide's")
assert(not Loading(h), "the tracker shows the guide's step, not the loading line")
assert(#h.errors == 0, table.concat(h.errors, "\n"))

-- The catalogue lands: the full build keeps the guide's step.
h.G.Questie.API.isReady = true
ready()
h.flush()
assert(not h.ns.QuestieBuilding(), "the catalogue has landed")
route = h.ns.Route()
assert(route.journey == guide.key and route.steps[1].rxpIndex == 2, "the full build keeps the guide's step")
assert(#h.errors == 0, table.concat(h.errors, "\n"))

-- No guide: the loading line stands until the catalogue lands.
local plain = Login()
assert(plain.ns.QuestieBuilding(), "the catalogue waits for Questie")
assert(#plain.ns.Route().steps == 0, "no route is planned before the catalogue")
assert(Loading(plain), "the tracker shows the loading line")
print("login_guide_spec: passed")
