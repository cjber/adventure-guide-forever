-- Run from the repository root: luajit tests/rxp_tracker_spec.lua
-- A RestedXP guide in the tracker section (#351, #353): RestedXP's coloured words in the client's colours, quest names
-- in gold, items in their quality's colour, progress as the tracker writes it and a mark for each line's kind; the
-- step under way in full with its first open line lit; ongoing steps one line each, without what the step under way
-- or the quest tracker already shows; and what does not fit in the section's room counted, never cut.
local harness = dofile("tests/harness.lua")

local checks = 0
local function check(value, label)
	checks = checks + 1
	if not value then
		error(label, 2)
	end
end

local h = harness.load({
	db = { autoStart = false, restedxpChoiceMade = true, restedxpGuide = true },
	completed = { 376 },
	player = { level = 4, raceID = 5, classID = 1, map = 1420, x = 0.3161, y = 0.656 },
	log = {
		{ id = 3902, title = "Scavenging Deathknell", level = 3, complete = false },
		{ id = 404, title = "A Putrid Task", level = 3, complete = false },
	},
	items = { [2672] = { name = "Stringy Wolf Meat", quality = 1 }, [5503] = { name = "Clam Meat", quality = 2 } },
})
h.flush()

local current = {
	index = 5,
	active = true,
	title = "Step 5",
	elements = {
		{ text = "Accept Marla's Last Wish", tag = "accept", questId = 6395 },
		{ text = "Kill |cFFFF5722Rattlecage Skeletons|r and loot their goods", tag = "complete", questId = 3902 },
		{ text = "|cFF00BCD4Clam Meat|r: 3/7", tag = "collect", id = 5503, questId = 3902 },
		{ text = "Speak with |cFF00FF25Executor Arren|r", completed = true },
	},
}
local function Sticky(index, text, questId)
	return {
		index = index,
		active = true,
		sticky = true,
		title = "Step " .. index,
		elements = { { text = text, tag = "complete", questId = questId } },
	}
end
local sameWork = Sticky(2, "Rattlecage Skeletons: 1/6", 3902)
local watched = Sticky(3, "Duskbat Pelt: 2/5", 404)
local twin1 = Sticky(1, "Gather supplies: 1/4")
local twin2 = Sticky(4, "Gather supplies: 1/4")
local extras = {}
for index = 6, 11 do
	extras[#extras + 1] = Sticky(index + 10, "Errand " .. index .. ": 0/1")
end
local active = { twin1, sameWork, watched, twin2, current }
for _, step in ipairs(extras) do
	active[#active + 1] = step
end
local steps = {}
for _, step in ipairs(active) do
	steps[step.index] = step
	for _, element in ipairs(step.elements) do
		element.step = step
	end
end
for index = 1, 30 do
	steps[index] = steps[index] or { index = index, title = "Step " .. index, elements = {} }
end
steps[6] = { index = 6, title = "Follow the road", elements = { { text = "Go on" } } }
local frame = h.G.CreateFrame("Frame", nil, h.G.UIParent)
frame.activeSteps = active
h.G.RXP = {
	RXPFrame = frame,
	currentGuide = { name = "Example: Tirisfal", group = "Example guides", steps = steps },
	guideTextColors = {
		default = {
			RXP_FRIENDLY_ = "FF00FF25",
			RXP_ENEMY_ = "FFFF5722",
			RXP_LOOT_ = "FF00BCD4",
			RXP_WARN_ = "FFFCDC00",
		},
		RXP_ENEMY_ = "FFFF5722",
	},
	GetGuideProgress = function()
		return 5
	end,
	SetStep = function() end,
	UpdateMap = function() end,
	settings = { profile = { showEnabled = true } },
}
h.watched = { 404 }
h.fire("ADDON_LOADED", "RXPGuides")
h.flush()
local key = "guide:14:Example guides:17:Example: Tirisfal"
check(h.ns.StartJourney(key), "the guide's card starts")
h.flush()

local route = h.ns.Route()
check(route.steps[1].rxpIndex == 5, "the step under way leads")
h.tracker:MarkDirty()
local main = h.tracker.liveBlocks[route.steps[1].key]
check(main and main.used, "the step under way has its block")
local accept, kill, collect, done = main.lines[1], main.lines[2], main.lines[3], main.lines[4]

-- Rich text in the client's colours (#351).
check(accept:find("^|A:QuestNormal:"), "a pickup line wears the pickup mark")
check(accept:find("|cffffd100Marla's Last Wish|r", 1, true), "the quest it takes is named in gold")
check(kill:find("^|A:questobjective:"), "an objective line wears the objective mark")
check(kill:find("|cffcc4c38Rattlecage Skeletons|r", 1, true), "enemies take the hostile reaction colour")
check(collect:find("^|A:QuestObjective:"), "a collect line wears the quest objective mark")
check(collect:find("3/7 |cff1eff00Clam Meat|r", 1, true), "progress first, the item in its quality's colour")
check(done:find("Speak with Executor Arren", 1, true), "a done line greys whole")
local snapshotLine
for _, row in ipairs(h.ns.RestedXP.Snapshot().steps) do
	snapshotLine = row.index == 5 and row.lines[4].text or snapshotLine
end
check(snapshotLine:find("|cff009919Executor Arren|r", 1, true), "a friendly NPC takes the friendly reaction colour")

-- The step under way in full, its first open line lit, done lines greyed (#353).
for _, index in ipairs({ 1, 2, 3, 4 }) do
	check(main.full[index] == true, "every line of the step under way wraps in full: " .. index)
end
check(main.styles[1] == h.G.OBJECTIVE_TRACKER_COLOR.NormalHighlight, "the first open line is lit")
check(main.styles[2] == h.G.OBJECTIVE_TRACKER_COLOR.Normal, "the other open lines are the tracker's own")
check(main.styles[4] == h.G.OBJECTIVE_TRACKER_COLOR.Complete, "a done line is greyed")
check(main.lines[main.order[#main.order]]:find("Follow the road", 1, true), "the next step closes the block")

-- Ongoing steps, one line each, without repeats (#353).
local ongoing = h.tracker.liveBlocks["rxp-ongoing"]
check(ongoing and ongoing.used, "the ongoing steps have their block")
local text = table.concat(ongoing.lines, "\n")
check(not text:find("Rattlecage", 1, true), "an ongoing step the step under way works on is left out")
check(not text:find("Duskbat", 1, true), "an ongoing step the quest tracker shows is left out")
local _, twins = text:gsub("1/4 Gather supplies", "")
check(twins == 1, "two ongoing steps with one line show once")
check(#ongoing.order == 7, "the twin and six errands, one line each")
for _, line in pairs(ongoing.lines) do
	check(not line:find("\n", 1, true), "each ongoing step is one line")
end

-- Little room: what does not fit is counted, never cut (#353).
-- The step under way takes 139 (a header, the guide's progress line and bar, five lines, a gap); 211 leaves the
-- ongoing block its header, two lines and the count, which is no room for a third line with the count still under it.
h.trackerRoom = 211
h.tracker:MarkDirty()
ongoing = h.tracker.liveBlocks["rxp-ongoing"]
check(ongoing.used, "the ongoing block still shows")
check(#ongoing.order == 3, "two lines and the count fit: got " .. #ongoing.order)
check(ongoing.lines[3] == h.ns.L.RXP_MORE_STEPS:format(5), "the rest is counted: " .. tostring(ongoing.lines[3]))
h.trackerRoom = nil

check(#h.errors == 0, table.concat(h.errors, "\n"))
print(("rxp_tracker_spec: %d checks passed"):format(checks))
