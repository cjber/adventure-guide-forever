-- Run from the repository root: luajit tests/guide_progress_spec.lua
-- A running RestedXP guide (#364, #365): one card per guide, even when RestedXP lists a guide of the same name in
-- another group, and its progress as a bar on the card and in the tracker under its title. The note that the game's
-- quest areas are hidden (#363): it shows while questPOI is 0, a click turns them back on, a right-click hides it for
-- good, and nothing turns them on unasked.
local harness = dofile("tests/harness.lua")
local fixture = dofile("tests/rxp_fixture.lua")

local checks = 0
local function check(value, label)
	checks = checks + 1
	if not value then
		error(label, 2)
	end
end

local h = harness.load({ db = { autoStart = false }, player = { level = 12 } })
h.flush()
local rxp = fixture(h, 6)
-- RestedXP's own list holds the running guide's name twice: the speedrun group and a dungeon group (#364).
local guide = rxp.currentGuide
local twin = { name = guide.name, group = "Example dungeon guides", steps = {} }
rxp.guideList = {
	Example = { names_ = { { group = guide.group, name = guide.name } } },
	Dungeons = { names_ = { { group = twin.group, name = twin.name } } },
	Other = { names_ = { { group = "Example guides", name = "Example: Durotar" } } },
}
local other = { name = "Example: Durotar", group = "Example guides", steps = {} }
rxp.GetGuideTable = function(group, name)
	return (name == other.name and other) or (group == twin.group and twin) or guide
end
h.ns.Invalidate()
h.flush()

local route = h.ns.Route()
local named, others = 0, 0
for _, journey in ipairs(route.journeys) do
	if journey.kind == "guide" then
		named = named + (journey.title == guide.name and 1 or 0)
		others = others + (journey.title == other.name and 1 or 0)
	end
end
check(named == 1, "the running guide shows one card, not a second chooser card: got " .. named)
check(others == 1, "another guide still gets its chooser card")

-- The running guide's card carries its progress (#365): step 2 of 8, one step done.
local key = "guide:14:Example guides:20:Example: The Barrens"
local running
for _, journey in ipairs(route.journeys) do
	running = journey.key == key and journey or running
end
check(running and running.guideStep == 2 and running.guideSteps == 8, "the card knows the guide's step and length")
local value, label = h.ns.Overview.Progress(running)
check(value == 1 / 8, "the card's bar is the steps done: got " .. tostring(value))
check(label == h.ns.L.CHAPTERS_DONE:format(1, 8), "the card's footer counts them: got " .. tostring(label))

-- In the tracker, under the guide's title: "Step 2 of 8" and the tracker's own bar (#365).
check(h.ns.StartJourney(key), "the guide's card starts")
h.flush()
h.tracker:MarkDirty()
local block = h.tracker.liveBlocks[h.ns.Route().steps[1].key]
check(block and block.used, "the step under way has its block")
check(block.lines[block.order[1]] == h.ns.L.RXP_PROGRESS:format(2, 8), "the first line is the guide's progress")
check(block.bars and block.bars[block.order[1]] == 12, "the stock bar under it, at the steps done: 12%")

-- The game's quest areas are on: no note.
local note = h.tracker.liveBlocks["quest-areas"]
check(not (note and note.used), "no note while the quest areas show")
-- Off (Questie's objective types set this): the note leads the section and nothing turns them back on.
h.G.SetCVar("questPOI", "0")
note = h.tracker.liveBlocks["quest-areas"]
check(note and note.used and h.tracker.layoutOrder[1] == "quest-areas", "the note shows first")
check(note.header == h.ns.L.QUEST_AREAS_OFF, "it says the quest areas are hidden")
-- Its hover is ForeverCore.TrackerLine.SetHeaderTooltip's: a title, then one normal line.
h.tracker:OnBlockHeaderEnter(note)
check(h.tooltip[1] == "title: " .. h.ns.L.QUEST_AREAS_OFF, "hover names the note")
check(h.tooltip[2] == "normal: " .. h.ns.L.QUEST_AREAS_TOOLTIP, "and says what the areas show")
h.tracker:OnBlockHeaderLeave(note)
check(not h.G.GameTooltip:IsShown(), "the tooltip goes on leave")
check(h.cvars.questPOI == "0", "the CVar is left to the player")
-- A click in combat does nothing; out of combat it turns them on and the note goes.
h.combat = true
h.tracker:OnBlockHeaderClick(note, "LeftButton")
check(h.cvars.questPOI == "0", "not in combat")
h.combat = false
h.tracker:OnBlockHeaderClick(note, "LeftButton")
check(h.cvars.questPOI == "1", "a click shows the quest areas")
check(not h.tracker.liveBlocks["quest-areas"].used, "and the note goes")
-- Right-click hides the note for good, with the areas still off.
h.G.SetCVar("questPOI", "0")
h.tracker:OnBlockHeaderClick(h.tracker.liveBlocks["quest-areas"], "RightButton")
check(h.cvars.questPOI == "0", "a right-click leaves the CVar alone")
check(not h.tracker.liveBlocks["quest-areas"].used, "and hides the note")
h.G.SetCVar("questPOI", "1")
h.G.SetCVar("questPOI", "0")
check(not h.tracker.liveBlocks["quest-areas"].used, "for good")

check(#h.errors == 0, table.concat(h.errors, "\n"))
print(("guide_progress_spec: %d checks passed"):format(checks))
