-- Run from the repository root: luajit tests/group_lines_spec.lua
-- Group lines (Model.GroupNeed, Overview.GroupNote, docs/design.md §2.27): a step says why it wants a group, from
-- what AGF already knows: "Dungeon: X" or "Raid: X" for a quest filed under an instance, "Group of N" when the quest
-- log suggests a group of 2 or more, "Elite: group advised" for any other elite quest; each once, after the reason,
-- in the step's tooltip and in the tracker's step block. A quest done alone says nothing.
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local h = harness.load({
	spf = "v1",
	charDB = { journey = "zone:1413" },
	completed = { 844 },
	log = {
		{ id = 845, title = "The Zhevra", level = 13, complete = true },
		{ id = 843, title = "Gann's Reclamation", level = 23, complete = false, groupSize = 3 },
		-- A suggested group of 1 is a quest done alone, as the log's 0 is.
		{ id = 6, title = "Bounty on Garrick Padfoot", level = 5, complete = false, groupSize = 1 },
	},
})
h.flush()
local ns, L = h.ns, h.ns.L
local data, Model = ns.Data, ns.Model
local log = ns.State.Log()

-- The quests this spec names: 1446 is Sunken Temple's, 8190 Zul'Gurub's (a raid), 8755 a raid quest filed under no
-- instance the data has; 843 and 6 are under way (the log suggests 3 for 843, 1 for 6), 845 is ready to hand in. The
-- spec makes 843, 6 and 845 elite where it says so.
local function Name(id)
	local instance = data.quests[id].dungeon
	return ns.State.InstanceName(instance) or data.instances[instance].name
end
local function Need(id)
	local kind, value = Model.GroupNeed(data, log, id)
	return tostring(kind) .. ":" .. tostring(value)
end

-- The model's reasons, most telling first: an instance, then an elite quest's size from the log, then the tag.
do
	equal(Need(1446), "dungeon:" .. data.quests[1446].dungeon, "a dungeon's quest names its instance")
	equal(Need(8190), "raid:" .. data.quests[8190].dungeon, "a raid's quest names its instance")
	equal(Need(8755), "raid:nil", "a raid quest with no instance")
	equal(Need(843), "nil:nil", "a suggested size alone, without the elite tag, is no group quest")
	equal(Need(6), "nil:nil", "a quest done alone")
	equal(Need(999999), "nil:nil", "an unknown quest")
	for _, id in ipairs({ 843, 6, 845 }) do
		data.quests[id].elite = true
	end
	equal(Need(843), "size:3", "an elite quest's suggested size")
	equal(Need(6), "elite:nil", "an elite quest the log suggests 1 for")
	equal(Need(845), "nil:nil", "ready to hand in: the group work is done")
	data.quests[1446].elite = true
	equal(Need(1446), "dungeon:" .. data.quests[1446].dungeon, "an instance beats the elite tag")
	data.quests[1446].elite = nil
end

-- In words.
do
	local Overview = ns.Overview
	equal(Overview.GroupNote(1446), L.GROUP_NEED_DUNGEON:format(Name(1446)), "Dungeon: X")
	equal(Overview.GroupNote(8190), L.GROUP_NEED_RAID:format(Name(8190)), "Raid: X")
	equal(Overview.GroupNote(8755), L.GROUP_NEED_RAID_ANY, "Raid with no instance")
	equal(Overview.GroupNote(843), L.GROUP_NEED_SIZE:format(3), "Group of 3")
	equal(Overview.GroupNote(6), L.GROUP_NEED_ELITE, "Elite: group advised")
	equal(Overview.GroupNote(845), nil, "a hand-in: nothing")
	equal(L.GROUP_NEED_ELITE, "Elite: group advised", "the elite line's words")
	equal(L.GROUP_NEED_SIZE:format(3), "Group of 3", "the size line's words")
	-- Each note once, in the step's quest order.
	local notes = Overview.GroupNotes({ quests = { 845, 6, 843, 6, 1446 } })
	equal(
		table.concat(notes, "|"),
		table.concat({ L.GROUP_NEED_ELITE, L.GROUP_NEED_SIZE:format(3), L.GROUP_NEED_DUNGEON:format(Name(1446)) }, "|"),
		"a step's notes, each once"
	)
	equal(#Overview.GroupNotes({ quests = { 845 } }), 0, "a step with nothing left to do in a group has none")
end

-- The step's tooltip (its ring and its row): the notes follow the reason.
local shared = {
	key = "area:6:0:g",
	kind = "area",
	title = "Complete 2 objectives · The Barrens",
	quests = { 6, 843 },
	reason = "2 quests here",
	objectives = {
		{ id = 6, have = 0, need = 1 },
		{ id = 843, have = 1, need = 5 },
	},
}
do
	local lines = {}
	local tooltip = setmetatable({}, {
		__index = function()
			return function() end
		end,
	})
	h.G.GameTooltip_AddHighlightLine = function(_, text)
		lines[#lines + 1] = "highlight: " .. text
	end
	h.G.GameTooltip_AddNormalLine = function(_, text)
		lines[#lines + 1] = "normal: " .. text
	end
	ns.Pins.StepTooltip(tooltip, shared, 1)
	equal(lines[1], "highlight: " .. shared.reason, "tooltip: the reason first")
	equal(lines[2], "normal: " .. L.GROUP_NEED_ELITE, "tooltip: then the elite line")
	equal(lines[3], "normal: " .. L.GROUP_NEED_SIZE:format(3), "tooltip: then the size line")
end

-- The tracker's step block, guided or not: the notes follow the reason, before what comes next.
ns.Guidance.CurrentStep = function()
	return shared
end
for _, guiding in ipairs({ false, true }) do
	ns.Integrations.Guiding = function()
		return guiding
	end
	h.tracker:LayoutContents()
	local block = h.tracker.liveBlocks[shared.key]
	local label = guiding and "tracker, guided" or "tracker"
	local reasonAt
	for index, line in ipairs(block.lines) do
		reasonAt = reasonAt or (line == shared.reason and index) or nil
	end
	assert(reasonAt, label .. ": the reason is shown\n" .. table.concat(block.lines, "\n"))
	equal(block.lines[reasonAt + 1], L.GROUP_NEED_ELITE, label .. ": the elite line after the reason")
	equal(block.lines[reasonAt + 2], L.GROUP_NEED_SIZE:format(3), label .. ": the size line after it")
end

-- A RestedXP guide step says it too, after its checklist.
do
	local guided = {
		key = "rxp:1",
		kind = "area",
		title = "Guide step",
		quests = { 843 },
		reason = "",
		rxpIndex = 1,
		checklist = { { text = "Kill things", done = false } },
	}
	ns.Guidance.CurrentStep = function()
		return guided
	end
	h.tracker:LayoutContents()
	local lines = h.tracker.liveBlocks[guided.key].lines
	equal(lines[1], "Kill things", "guide step: the checklist first")
	equal(lines[2], L.GROUP_NEED_SIZE:format(3), "guide step: then the group line")
end

-- A step done alone adds no line.
data.quests[6].elite, data.quests[843].elite = nil, nil
local alone = { key = "area:6:0", kind = "area", title = "Alone", quests = { 6 }, reason = "1 quest here" }
ns.Guidance.CurrentStep = function()
	return alone
end
ns.Integrations.Guiding = function()
	return false
end
h.tracker:LayoutContents()
for _, line in ipairs(h.tracker.liveBlocks[alone.key].lines) do
	equal(line:find("group", 1, true), nil, "alone: no group line")
end

equal(#h.errors, 0, "errors\n" .. table.concat(h.errors, "\n"))
print(("group_lines_spec: %d checks passed"):format(checks))
