-- Run from the repository root: luajit tests/rxp_handoff_spec.lua
-- A RestedXP guide is handed to Shortest Path (#361, #368) and leads the tracked quests (#362).
local harness = dofile("tests/harness.lua")
local checks = 0
local function check(value, label)
	checks = checks + 1
	if not value then
		error(label, 2)
	end
end

local group, name = "Example guides", "Example: The Barrens"
local key = "guide:" .. #group .. ":" .. group .. ":" .. #name .. ":" .. name

-- #361: RestedXP's current step is one it hides from its window, so the step it shows next leads. It is handed on
-- after a /reload into the chosen guide, not left a read-only preview with a walk time and nothing guiding.
local hidden = harness.load({
	spf = "v1",
	charDB = { journey = key, guided = key },
	setup = function(client)
		local rxp = dofile("tests/rxp_fixture.lua")(client, 2)
		rxp.currentGuide.steps[2].hidewindow = true
		rxp.arrowFrame.element = nil
		rxp.guideTextColors = { default = { RXP_FRIENDLY_ = "FF00FF25" } }
		rxp.currentGuide.steps[3].title = nil
		rxp.currentGuide.steps[3].elements[1].text = "Talk to |cFF00FF25Ariyell Skyshadow|r"
	end,
})
for _ = 1, 2 do
	hidden.ns.Invalidate()
	hidden.flush()
end
local lead = hidden.ns.Route().steps[1]
check(lead.rxpIndex == 3 and not lead.preview, "the step RestedXP shows next leads, not as a preview")
check(hidden.spf.NavigateRoute > 0 and hidden.ns.Guidance.Owns(), "the step is handed to Shortest Path")
check(hidden.ns.Guidance.Status() ~= "paused", "the journey is not left paused")
check(lead.place == "Ariyell Skyshadow", "an untitled step is named by the NPC it is for, not as Step 3")
check(hidden.spfRoute.stops[1].title == "Ariyell Skyshadow", "Shortest Path's stop names the NPC too")
check(#hidden.errors == 0, table.concat(hidden.errors, "\n"))

-- #361: a paused journey says so in the tracker, under its walk time.
local paused = harness.load({
	spf = "v1",
	charDB = { journey = key, guided = key },
	setup = function(client)
		dofile("tests/rxp_fixture.lua")(client, 2)
		client.spfDeclines = true
	end,
})
paused.ns.Invalidate()
paused.flush()
check(paused.ns.Guidance.Status() == "paused", "a refused route is paused")
paused.tracker:MarkDirty()
local block = paused.tracker.liveBlocks[paused.ns.Route().steps[1].key]
local said = false
for _, line in pairs(block and block.lines or {}) do
	said = said or line:find(paused.ns.L.TRACKER_PAUSED, 1, true) ~= nil
end
check(said, "the tracker says the route is paused")

-- #368: RestedXP loads the guide after AGF's first full build (its empty guide while purchased guides import). The
-- choice waits for it, nothing else starts over it, and the guide is handed on once it loads.
local late = harness.load({
	spf = "v1",
	charDB = { journey = key, guided = key },
	setup = function(client)
		local rxp = dofile("tests/rxp_fixture.lua")(client)
		client.loaded, rxp.currentGuide, rxp.RXPFrame.activeSteps = rxp.currentGuide, nil, {}
	end,
})
late.ns.Invalidate()
late.flush()
check(late.ns.Prefs().journey == key and late.ns.Prefs().guided == key, "the chosen guide waits for RestedXP")
check(late.spf.NavigateRoute == 0, "no other journey starts over it")
local rxp = late.G.RXP
rxp.currentGuide = late.loaded
rxp.RXPFrame.activeSteps = { late.loaded.steps[1], late.loaded.steps[2] }
rxp.UpdateMap()
late.flush()
check(late.ns.Route().chosen and late.ns.Route().journey == key, "the guide is chosen once it loads")
check(late.spf.NavigateRoute > 0 and late.ns.Guidance.Owns(), "and handed to Shortest Path")

-- #368: the guide gone for one rebuild mid-session (between two loads) keeps the choice and its route.
local g = rxp.currentGuide
rxp.currentGuide = nil
rxp.UpdateMap()
late.flush()
check(late.ns.Prefs().journey == key and late.ns.Prefs().guided == key, "a guide between loads stays chosen")
rxp.currentGuide = g
rxp.UpdateMap()
late.flush()
check(late.ns.Route().chosen and late.ns.Guidance.Owns(), "and guides again")
check(#late.errors == 0, table.concat(late.errors, "\n"))

-- #362: while the guide leads, the tracker holds only the quests its step under way and its ongoing steps name.
local LOG = {
	{ id = 845, title = "The Zhevra", level = 13, complete = false },
	{ id = 846, title = "Revenge of Gann", level = 15, complete = false },
	{ id = 850, title = "Kolkar Leaders", level = 15, complete = false },
	{ id = 855, title = "Centaur Bracers", level = 15, complete = false },
}
local w = harness.load({
	spf = "v1",
	log = LOG,
	completed = { 844 },
	setup = function(client)
		local engine = dofile("tests/rxp_fixture.lua")(client)
		local steps = engine.currentGuide.steps
		steps[1].elements = { { text = "Zhevra: 0/4", tag = "complete", questId = 845 } }
		steps[2].elements[1] = { text = "Hand in Revenge of Gann", tag = "turnin", questId = 846 }
		client.watched = { 850, 855 }
	end,
})
local function watched(id)
	for _, each in ipairs(w.watched) do
		if each == id then
			return true
		end
	end
	return false
end
w.ns.StartJourney(key)
w.flush()
check(w.ns.Route().chosen and w.ns.Route().journey == key, "the guide leads")
check(watched(845) and watched(846), "the quests its current and ongoing steps name are tracked")
check(not watched(850) and not watched(855), "every other tracked quest is untracked")

-- The client tracks a quest on accept; one the guide does not name goes, one the player tracks by hand stays.
w.log[#w.log + 1] = { id = 851, title = "Lost in Battle", level = 15, complete = false }
w.watched[#w.watched + 1] = 851
w.fire("QUEST_ACCEPTED", 851)
w.ns.Invalidate()
w.flush()
check(not watched(851), "a quest the client tracked on accept, and the guide does not name, is untracked")
w.watched[#w.watched + 1] = 850
w.fire("QUEST_WATCH_LIST_CHANGED", 850, true)
w.ns.Invalidate()
w.flush()
check(watched(850), "a quest the player tracks by hand while the guide leads stays tracked")

-- The guide stops leading: the player's own list comes back, and what the guide tracked goes.
w.ns.SetSetting("guideTracksQuests", false)
w.flush()
check(watched(850) and watched(855), "the player's own tracked quests come back")
check(not watched(845) and not watched(846), "what the guide tracked goes")
check(w.ns.Prefs().guideWatch == nil, "nothing is kept once it is given back")
check(#w.errors == 0, table.concat(w.errors, "\n"))

print(("rxp_handoff_spec: %d checks passed"):format(checks))
