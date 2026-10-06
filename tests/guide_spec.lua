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
local journey = { key = "zone:1426", zone = 1426, title = "Dun Morogh" }
local steps = {
	{ quests = { 179 }, title = "Pick up Dwarven Outfitters", kind = "pickup" },
	{ quests = { 179 }, title = "Complete Dwarven Outfitters", kind = "work" },
	{ quests = { 179 }, title = "Turn in Dwarven Outfitters", kind = "turnin" },
}
local function outline(completed, active)
	return table.concat(ns.Widgets.GuideOutline(data, player, completed or {}, journey, active or steps), ",")
end
equal(outline(), "3114,233,234", "fresh gnome sees follow-ups after its active quest")
equal(outline({ [3114] = true, [233] = true }), "234", "completed quests omitted")
equal(outline({}, {}), "179,3114,233,234", "prerequisite precedes lower-level successor")
equal(#ns.Widgets.GuideOutline(data, player, {}, { key = "carry" }, steps), 0, "non-zone route has no invented outline")
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

equal(#h.errors, 0, table.concat(h.errors, "\n"))
print("guide_spec: " .. checks .. " checks passed")
