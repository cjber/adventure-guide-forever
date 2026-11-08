-- Run from the repository root: luajit tests/chosen_zone_spec.lua
-- A chosen zone journey stays chosen across a /reload (#503). The choice is saved, and the first build after login can
-- recommend no new pickup there (QuestieDB's live policy has not joined the catalogue yet); the zone's log quests are
-- the steps the choice stands on, so the card is still built and Route keeps the journey.
local harness = dofile("tests/harness.lua")
local checks = 0
local function check(value, label)
	assert(value, label)
	checks = checks + 1
end

-- Hel Io's saved character: a level 16 Alliance hunter in Menethil Harbor (Wetlands), with the Loch Modan journey
-- chosen and the story last led by Darkshore. The log holds the Loch Modan work the guide was showing.
local LOG = {
	{ id = 257, title = "A Hunter's Boast", level = 16, complete = false, poi = { map = 1432, x = 0.35, y = 0.45 } },
	{ id = 385, title = "Crocolisk Hunting", level = 15, complete = false, poi = { map = 1432, x = 0.40, y = 0.55 } },
}
local data = harness.data()
local h = harness.load({
	-- QuestieDB's catalogue without its live policy: every quest is provider-gated, so no new pickup is recommended.
	questiedb = harness.questieMirror(data),
	charDB = {
		journey = "zone:1432",
		guided = "zone:1432",
		lead = 1439,
		left = 1432,
		dungeons = true,
		quests = true,
		battlegrounds = false,
		professions = false,
		notInterested = {},
		skipped = {},
		pinned = {},
		camps = {},
	},
	player = { level = 16, faction = "Alliance", raceID = 4, classID = 3, map = 1437, x = 0.10, y = 0.60 },
	completed = {},
	log = LOG,
	db = { autoStart = false },
})
h.flush()
local route = h.ns.Route()
check(route.journey == "zone:1432", "the chosen zone leads after the reload: " .. tostring(route.journey))
check(route.chosen, "and the route counts it as the player's choice")
check(h.ns.Prefs().journey == "zone:1432", "the choice is kept, not cleared")
local card
for _, journey in ipairs(route.journeys) do
	card = journey.key == "zone:1432" and journey or card
end
check(card ~= nil and #card.steps > 0, "the zone has a card with its log quests")
check(#h.errors == 0, table.concat(h.errors, "\n"))

print("chosen_zone_spec: " .. checks .. " checks passed")
