-- Quest relationships must remain visible when Shortest Path owns navigation.
local harness = dofile("tests/harness.lua")
local h = harness.load({
	spf = "v1",
	charDB = { journey = "zone:1413" },
	completed = { 844 },
	log = {
		{ id = 845, title = "The Zhevra", level = 13, complete = true },
		{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
	},
})
local ns = h.ns
local step = {
	key = "related-quests",
	kind = "area",
	title = "Complete objectives",
	quests = { 845, 843 },
	reason = "quests in progress",
}
ns.Integrations.CurrentStep = function()
	return step
end
ns.Integrations.Guiding = function()
	return true
end
for _, kind in ipairs({ "area", "dungeon", "town" }) do
	step.kind, step.key = kind, "related-quests-" .. kind
	h.tracker:LayoutContents()
	local block = h.tracker.liveBlocks[step.key]
	assert(block.header == step.title, kind .. ": action remains the header")
	assert(block.lines[1]:find("[13] The Zhevra", 1, true), kind .. ": first quest identified")
	assert(block.lines[2]:find("[23] Gann's Reclamation", 1, true), kind .. ": second quest identified")
	assert(block.lines[1]:find("|cff3fbf3f", 1, true), kind .. ": lower-level quest is green")
	assert(block.lines[2]:find("|cffff1919", 1, true), kind .. ": high-level quest is red")
	assert(block.lines[3] == step.reason, kind .. ": reason follows related quests")
end
assert(#h.errors == 0, table.concat(h.errors, "\n"))
print("tracker_quests_spec: grouped quest names, levels and colours stay visible while guiding")
