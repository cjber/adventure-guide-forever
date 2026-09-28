-- QuestieDB's Coldridge mail/class prerequisite contracts, read from installed
-- Camelot metadata on 2026-09-28; this is not a captured live availability policy.
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local h = harness.load()
local ns = h.ns
local player = { side = 1, raceBit = 64, classBit = 128, level = 1 }
local function quest(title, level, pre)
	return { title = title, level = level, min = 1, side = 1, zone = 1426, preAny = pre }
end
local data = {
	quests = {
		[179] = quest("Dwarven Outfitters", 1),
		[233] = quest("Coldridge Valley Mail Delivery", 3, { 179 }),
		[234] = quest("Coldridge Valley Mail Delivery", 4, { 233 }),
		[3114] = quest("Glyphic Memorandum", 1, { 179 }),
		[3112] = quest("Simple Memorandum", 1, { 179 }),
	},
}
data.quests[3114].classes, data.quests[3114].races = 128, 64
data.quests[3112].classes, data.quests[3112].races = 1, 64
local journey = { key = "zone:1426", title = "Dun Morogh" }
local steps = {
	{ quests = { 179 }, title = "Pick up Dwarven Outfitters", kind = "pickup" },
	{ quests = { 179 }, title = "Complete Dwarven Outfitters", kind = "work" },
	{ quests = { 179 }, title = "Turn in Dwarven Outfitters", kind = "turnin" },
}
local function outline(completed, active)
	return table.concat(ns.Window.GuideOutline(data, player, completed or {}, journey, active or steps), ",")
end
equal(outline(), "3114,233,234", "fresh gnome sees follow-ups after its active quest")
equal(outline({ [3114] = true, [233] = true }), "234", "completed quests omitted")
equal(outline({}, {}), "179,3114,233,234", "prerequisite precedes lower-level successor")
equal(#ns.Window.GuideOutline(data, player, {}, { key = "carry" }, steps), 0, "non-zone route has no invented outline")
data.quests[233].preAny = { 234 }
equal(outline(), "3114,234,233", "cyclic provider data terminates deterministically")
data.quests[233].preAny = { 179, 99999, -42 }
equal(outline(), "3114,233,234", "missing and negative prerequisites do not create quests")
for _, field in ipairs({ "repeatable", "dungeon" }) do
	data.quests[233][field] = true
	equal(outline(), "3114,234", field .. " omitted")
	data.quests[233][field] = nil
end
data.quests[233].side = 2
equal(outline(), "3114,234", "other faction omitted")
data.quests[233].side = 1
data.quests[233].races = 4
equal(outline(), "3114,234", "other race omitted")
data.quests[233].races = nil

-- Exercise real rows, paging and tab lifecycle without allowing the outline to
-- feed locked quests into the active route or navigation.
ns.OpenWindow()
h.flush()
local window = h.G.AdventureGuideForeverWindow
local function find(frame, text)
	if frame.GetText and frame:GetText() == text then
		return frame
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		local result = find(child, text)
		if result then
			return result
		end
	end
end
local open = assert(find(window, ns.L.GUIDE_OPEN))
-- The button is parented to the card's content. Use the actual card's parent.
local card = open:GetParent():GetParent()
local tabParent = card:GetParent()
ns.Data.quests = data.quests
for id = 4000, 4020 do
	data.quests[id] = quest("Later quest " .. id, 5)
end
local route = { journey = journey.key, steps = steps, journeys = {} }
local originalRoute, originalPlayer = ns.Route, ns.State.Player
ns.Route = function()
	return route
end
ns.State.Player = function()
	return player
end
ns.State.Completed = function()
	return {}
end
ns.Window.OpenGuide(journey, tabParent)
local guide = h.G.AdventureGuideForeverFullGuide
local function visibleRows()
	local rows = {}
	for _, child in ipairs({ guide:GetChildren() }) do
		if child.Title and child:IsShown() then
			rows[#rows + 1] = child
		end
	end
	return rows
end
local rows = visibleRows()
equal(#rows, 10, "ten rows per page")
equal(rows[1].step, steps[1], "active step retained")
equal(rows[4].questID, 3114, "class follow-up in outline")
equal(rows[4]:IsEnabled(), false, "future quest cannot be clicked")
equal(rows[4].Number:IsShown(), false, "future quest has no active step number")
equal(#route.steps, 3, "outline does not change active route")
local nextPage = assert(find(guide, ns.L.NEXT_PAGE))
local previous = assert(find(guide, ns.L.PREVIOUS_PAGE))
equal(previous:IsEnabled(), false, "previous disabled on first page")
h.Click(nextPage)
equal(#visibleRows(), 10, "second page has ten rows")
h.Click(nextPage)
equal(#visibleRows(), 7, "last page has remainder")
equal(nextPage:IsEnabled(), false, "next disabled on last page")
ns.State.Completed = function()
	local completed = {}
	for id in pairs(data.quests) do
		completed[id] = true
	end
	return completed
end
h.Click(previous)
equal(#visibleRows(), 3, "page clamps after progress changes")
equal(previous:IsEnabled(), false, "clamped to first page")
ns.Route, ns.State.Player = originalRoute, originalPlayer
h.Click(window.Tabs[2])
equal(guide:IsVisible(), false, "switching tab hides guide")
h.Click(window.Tabs[1])
equal(guide:IsShown(), false, "returning tab restores journey cards")
equal(#h.errors, 0, table.concat(h.errors, "\n"))
print("guide_spec: " .. checks .. " checks passed")
