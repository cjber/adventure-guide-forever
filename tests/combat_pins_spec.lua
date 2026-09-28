local harness = dofile("tests/harness.lua")
local h = harness.load({ db = { showMapPins = true, showQuestGivers = true } })
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": " .. tostring(actual))
end
h.G.OpenQuestLog()
h.flush()
h.map:SetMapID(1413)
local provider = h.providers[1]
provider:RefreshAllData()
local before = h.counts.AcquirePin
h.combat = true
provider:RefreshAllData()
h.map:SetMapID(1442)
provider:RefreshAllData()
equal(h.counts.AcquirePin, before, "combat never acquires protected pins")
for _, pins in pairs(h.pins) do
	for _, pin in ipairs(pins) do
		equal(pin:IsShown(), false, "old map pin hidden")
	end
end
h.combat = false
h.fire("PLAYER_REGEN_ENABLED")
equal(h.counts.AcquirePin > before, true, "combat end refreshes current map")
for _, pin in ipairs(h.pins.AdventureGuideForeverGiverPinTemplate) do
	equal(pin.giver.map, 1442, "uses new map")
end
-- Combat can begin between requesting the map reveal and the next-frame ping.
h.ns.Pins.Reveal({ map = 1442, x = 0.5, y = 0.5 })
before = h.counts.AcquirePin
h.combat = true
h.flush()
equal(h.counts.AcquirePin, before, "deferred ping rechecks lockdown")
provider:RefreshAllData()
h.map:Hide()
h.combat = false
h.fire("PLAYER_REGEN_ENABLED")
equal(h.counts.AcquirePin, before, "hidden map stays idle after combat")
h.map:Show()
h.flush()
equal(h.counts.AcquirePin > before, true, "opening map restores pins")
equal(#h.errors, 0, table.concat(h.errors, "\n"))
print("combat_pins_spec: " .. checks .. " checks passed")
