-- Run from the repository root: luajit tests/suspend_pins_spec.lua
-- API.SuspendMapPins(owner) holds every world-map mark back for the session, several owners at once, and the marks
-- return when the last owner has resumed. Nothing is saved.
local harness = dofile("tests/harness.lua")
local h = harness.load({ db = { showMapPins = true, showQuestGivers = true } })
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, ("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)))
end
local API = h.G.AdventureGuideForever.API

h.G.C_Map.OpenWorldMap()
h.flush()
h.map:SetMapID(1413)
h.flush()
local function Marks()
	local count = 0
	for _, pin in ipairs(h.ns.Pins.Active()) do
		count = count + (pin:IsShown() and 1 or 0)
	end
	return count
end
h.ns.Pins.Refresh()
local shown = Marks()
equal(shown > 0, true, "the map draws marks to begin with")
local saved = {}
for key, value in pairs(h.G.AdventureGuideForeverDB) do
	saved[key] = value
end

equal(API.SuspendMapPins("gathering"), true, "suspend answers true")
equal(Marks(), 0, "one owner hides every mark")
equal(API.SuspendMapPins("gathering"), true, "a repeat call is accepted")
equal(API.SuspendMapPins("other"), true, "a second owner may hold too")
equal(API.ResumeMapPins("gathering"), true, "resume answers true")
equal(Marks(), 0, "the marks stay hidden while another owner holds them")
equal(API.ResumeMapPins("gathering"), true, "resuming an owner twice is harmless")
equal(Marks(), 0, "and does not release the other owner")
equal(API.ResumeMapPins("other"), true, "the last owner resumes")
equal(Marks(), shown, "the marks return")

-- A reveal's ping is a mark too: the map opens for the player's click, but nothing draws while an owner holds.
h.ns.Pins.Reveal({ map = 1413, x = 0.5, y = 0.5 })
h.flush()
equal(#h.Pins("AdventureGuideForeverPingPinTemplate"), 1, "a ping shows before the suspend")
API.SuspendMapPins("gathering")
equal(#h.Pins("AdventureGuideForeverPingPinTemplate"), 0, "suspending releases a showing ping")
h.ns.Pins.Reveal({ map = 1413, x = 0.5, y = 0.5 })
h.flush()
equal(#h.Pins("AdventureGuideForeverPingPinTemplate"), 0, "a reveal draws no ping while suspended")
API.ResumeMapPins("gathering")
h.ns.Pins.Reveal({ map = 1413, x = 0.5, y = 0.5 })
h.flush()
equal(#h.Pins("AdventureGuideForeverPingPinTemplate"), 1, "and does after the resume")

for key, value in pairs(saved) do
	equal(h.G.AdventureGuideForeverDB[key], value, "saved setting untouched: " .. key)
end
for key in pairs(h.G.AdventureGuideForeverDB) do
	equal(saved[key] ~= nil, true, "no saved key added: " .. key)
end

for _, bad in ipairs({ "", 1, true, {} }) do
	local ok, reason = API.SuspendMapPins(bad)
	equal(ok, false, "a bad owner is refused")
	equal(reason, "invalid", "with the invalid reason")
	equal((API.ResumeMapPins(bad)), false, "resume refuses it too")
end
equal(select("#", API.SuspendMapPins()), 2, "no owner is invalid")

print(("suspend_pins_spec: %d checks"):format(checks))
