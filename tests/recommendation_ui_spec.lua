local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(a, b, label)
	checks = checks + 1
	assert(a == b, label .. ": " .. tostring(a) .. " ~= " .. tostring(b))
end
for _, case in ipairs({
	{ "next", "journeys", 1 },
	{ "completion", "progress", 3 },
	{ "professions", "activities", 2 },
	{ "pvp", "activities", 2 },
	{ "dungeons", "activities", 2 },
}) do
	local h = harness.load({
		db = { window = { tab = case[1], dungeon = 36, profession = 164 } },
		charDB = { recommendationFocus = "training" },
	})
	h.ns.OpenWindow()
	h.flush()
	equal(#h.ns.Window.Tabs(), 3, "three destinations")
	equal(h.G.AdventureGuideForeverWindow.selectedTab, case[3], "saved page migrates")
	equal(h.ns.WindowDB().tab, case[2], "migrated page persists")
	equal(h.ns.WindowDB().dungeon, 36, "dungeon selection preserved")
	equal(h.ns.WindowDB().profession, 164, "profession selection preserved")
	equal(h.ns.Prefs().recommendationFocus, nil, "obsolete focus removed")
	if case[2] == "activities" then
		equal(h.ns.WindowDB().activity, case[1], "category preserved")
	end
	equal(#h.errors, 0, "migration no errors")
end
local h = harness.load({ db = { autoStart = false } })
h.ns.OpenWindow()
h.flush()
equal(h.G.AdventureGuideForeverWindow.selectedTab, 1, "Journeys first")
equal(h.G.AdventureGuideForeverNextFocusbalanced, nil, "no focus row")
local before = h.ns.Prefs().journey
h.ns.Window.SelectActivity("dungeons")
h.flush()
equal(h.ns.Prefs().journey, before, "browsing preserves journey")
equal(h.ns.WindowDB().activity, "dungeons", "dungeons opens")
h.ns.Window.SelectActivity("professions")
h.flush()
equal(h.ns.Prefs().journey, before, "profession browsing preserves journey")
equal(#h.errors, 0, "browsing no errors")
h.ns.Window.Select(1)
h.flush()
local card = h.Find(function(frame)
	return frame:IsVisible() and frame.Action and frame.journey
end)[1]
equal(card.Action:IsEnabled(), true, "journey action begins enabled")
h.combat = true
h.fire("PLAYER_REGEN_DISABLED")
h.tick()
equal(card.Action:IsEnabled(), false, "journey action disables in combat")
h.combat = false
h.fire("PLAYER_REGEN_ENABLED")
h.tick()
equal(card.Action:IsEnabled(), true, "journey action returns without a quest event")
print("recommendation_ui_spec: " .. checks .. " checks passed")
