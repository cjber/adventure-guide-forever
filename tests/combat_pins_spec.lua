local harness = dofile("tests/harness.lua")
local h = harness.load({ db = { showMapPins = true, showQuestGivers = true } })
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": " .. tostring(actual))
end
-- A pin's right-button pass-through is protected in combat (the harness raises on it), so combat draws nothing new:
-- the pins hide and the map is drawn again once combat ends.
local function Visible()
	local count = 0
	for _, pin in ipairs(h.AllPins()) do
		count = count + (pin:IsVisible() and 1 or 0)
	end
	return count
end
h.G.C_Map.OpenWorldMap()
h.flush()
h.map:SetMapID(1413)
h.ns.Pins.Refresh()
equal(Visible() > 0, true, "pins on the open map")
local before = h.counts.passThrough
h.combat = true
h.ns.Pins.Refresh()
h.map:SetMapID(1442)
equal(h.counts.passThrough, before, "combat lays out no pin")
equal(Visible(), 0, "old map pins hidden")
h.combat = false
h.fire("PLAYER_REGEN_ENABLED")
equal(h.counts.passThrough > before, true, "combat end draws the current map")
equal(Visible() > 0, true, "and shows its pins")
for _, pin in ipairs(h.pins.AdventureGuideForeverGiverPinTemplate) do
	equal(pin.giver.map, 1442, "uses new map")
end
-- Combat can begin between requesting the map reveal and the next-frame ping.
h.ns.Pins.Reveal({ map = 1442, x = 0.5, y = 0.5 })
before = h.counts.passThrough
h.combat = true
h.flush()
equal(h.counts.passThrough, before, "deferred ping rechecks lockdown")
equal(#h.pins.AdventureGuideForeverPingPinTemplate, 0, "no ping in combat")
h.ns.Pins.Refresh()
h.map:Hide()
h.combat = false
h.fire("PLAYER_REGEN_ENABLED")
equal(h.counts.passThrough, before, "hidden map stays idle after combat")
h.map:Show()
h.flush()
equal(h.counts.passThrough > before, true, "opening map restores pins")
equal(Visible() > 0, true, "and shows them")
equal(h.counts.mapWrites, 0, "nothing written into the map")
equal(#h.errors, 0, table.concat(h.errors, "\n"))
print("combat_pins_spec: " .. checks .. " checks passed")
