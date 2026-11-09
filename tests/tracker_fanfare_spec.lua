-- Blizzard's fanfare block restarts every used line's FadeInAnim when it plays its add animation (#539). The module
-- pairs ObjectiveTrackerAnimBlockTemplate with the line template that carries FadeInAnim, so a journey-complete,
-- moment or aside block laid out with a fanfare plays it without raising "attempt to index field 'FadeInAnim'".
local harness = dofile("tests/harness.lua")
local checks = 0
local function check(value, label)
	assert(value, label)
	checks = checks + 1
end

local function Load()
	return harness.load({
		spf = "v1",
		db = { autoStart = false },
		charDB = { journey = "zone:1413" },
		completed = { 844 },
		log = {
			{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
			{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
		},
	})
end

-- One fanfare block carrying a line, laid out the way the module lays its blocks out: the block's key needs a
-- fanfare, so its layout plays AddAnim, which restarts FadeInAnim on every line it uses.
local function FanfareWithLine(h, id, header, text)
	local module = h.tracker
	module.availableHeight, module.contentsHeight = math.huge, 0
	local block = module:GetBlock(id)
	block:SetHeader(header)
	block:AddObjective(1, text)
	module:SetNeedsFanfare(id)
	check(module:LayoutBlock(block), id .. ": the block fits")
	check(block.AddAnim.plays == 1, id .. ": its add animation plays")
	local line = block.frames[1]
	check(line ~= nil, id .. ": it acquired a line")
	check(line.template == "ObjectiveTrackerAnimLineTemplate", id .. ": from the module's anim line template")
	check(line.FadeInAnim.restarts == 1, id .. ": the line fades in with the block")
end

-- The journey's end: the block AG lays out on a turn-in always carries its next-zone line.
do
	local h = Load()
	h.ns.OnJourneyComplete("Head to Stonetalon Mountains")
	check(#h.errors == 0, "journey complete: no error\n" .. table.concat(h.errors, "\n"))
	local block = h.tracker.liveBlocks["journey-complete"]
	check(block ~= nil and block.header == h.ns.L.JOURNEY_COMPLETE, "journey complete: the block")
	check(block.lines[1] == h.ns.L.JOURNEY_NEXT:format("Head to Stonetalon Mountains"), "journey complete: its line")
	local line = block.frames[1]
	check(line ~= nil and line.template == "ObjectiveTrackerAnimLineTemplate", "journey complete: an anim line")
	check(block.AddAnim.plays == 1, "journey complete: its add animation plays")
	check(line.FadeInAnim.restarts == 1, "journey complete: the line's FadeInAnim restarts")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

-- The templates Blizzard pairs (Blizzard_ObjectiveTrackerAnimTemplates.xml:3, :74).
do
	local h = Load()
	check(h.tracker.blockTemplate == "ObjectiveTrackerAnimBlockTemplate", "the module is an anim block module")
	check(h.tracker.lineTemplate == "ObjectiveTrackerAnimLineTemplate", "its lines are the anim block's own")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

-- Something new and an aside, each carrying a line and glowing.
do
	local h = Load()
	FanfareWithLine(h, "moment", "Duskwood is now for your level", "Duskwood is now for your level")
	FanfareWithLine(h, "aside", "Visit your class trainer", "Visit your class trainer · 1 new spell")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

-- A block laid out without a fanfare: the line is still an anim line, nothing plays, and ObjectiveTrackerAnimLineMixin
-- leaves its icon hidden and its glows clear. Releasing it (OnFree) is a no-op that raises nothing.
do
	local h = Load()
	local module = h.tracker
	module.availableHeight, module.contentsHeight = math.huge, 0
	local block = module:GetBlock("moment")
	block:SetHeader("Duskwood is now for your level")
	block:AddObjective(1, "Duskwood is now for your level")
	check(module:LayoutBlock(block), "no fanfare: the block fits")
	local line = block.frames[1]
	check(line ~= nil and line.template == "ObjectiveTrackerAnimLineTemplate", "no fanfare: an anim line")
	check(block.AddAnim.plays == 0, "no fanfare: no add animation")
	check(line.FadeInAnim.restarts == 0, "no fanfare: no fade in")
	check(line.state == nil, "no fanfare: no animation state")
	check(line.Icon.shown == false, "no fanfare: the icon stays hidden")
	check(line.Glow.alpha == 0 and line.CheckGlow.alpha == 0, "no fanfare: the glows stay clear")
	line.used = false
	block:FreeUnusedLines()
	check(block.frames[1] == nil, "no fanfare: the released line goes")
	check(line.Icon.shown == false, "no fanfare: it is released still hidden")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

print("tracker_fanfare_spec: " .. checks .. " checks passed")
