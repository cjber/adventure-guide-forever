local harness = dofile("tests/harness.lua")
local h = harness.load({ db = { showMapPins = true, showQuestGivers = true } })
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": " .. tostring(actual))
end
h.G.C_Map.OpenWorldMap()
h.flush()
h.map:SetMapID(1413)
h.flush()
local pins = h.ns.Pins
pins.Refresh()
local before = h.counts.SetMouseClickEnabled
h.combat = true
pins.Refresh()
h.map:SetMapID(1442)
h.flush()
pins.Refresh()
equal(h.counts.SetMouseClickEnabled, before, "combat never reconfigures pin mouse input")
for _, pin in ipairs(h.ns.Pins.Active()) do
	equal(pin:IsVisible(), false, "old map pin hidden")
end
h.combat = false
h.fire("PLAYER_REGEN_ENABLED")
equal(h.counts.SetMouseClickEnabled > before, true, "combat end refreshes current map")
for _, pin in ipairs(h.Pins("AdventureGuideForeverGiverPinTemplate")) do
	equal(pin.giver.map, 1442, "uses new map")
end
-- Combat can begin between requesting the map reveal and the next-frame ping.
h.ns.Pins.Reveal({ map = 1442, x = 0.5, y = 0.5 })
before = h.counts.SetMouseClickEnabled
h.combat = true
h.flush()
equal(h.counts.SetMouseClickEnabled, before, "deferred ping rechecks lockdown")
pins.Refresh()
h.map:Hide()
h.combat = false
h.fire("PLAYER_REGEN_ENABLED")
equal(h.counts.SetMouseClickEnabled, before, "hidden map stays idle after combat")
h.map:Show()
h.flush()
equal(h.counts.SetMouseClickEnabled > before, true, "opening map restores pins")
h.map:Hide()
h.ns.Pins.Reveal({ map = 1442, x = 0.5, y = 0.5 })
h.flush()
equal(#h.Pins("AdventureGuideForeverPingPinTemplate"), 1, "reopening the same map retains the reveal ping")
h.map.ScrollContainer:SetSize(1000, 600)
h.flush()
equal(#h.Pins("AdventureGuideForeverPingPinTemplate"), 1, "resizing the canvas retains the active ping")
h.map:SetMapID(1454)
h.flush()
equal(#h.Pins("AdventureGuideForeverPingPinTemplate"), 0, "changing maps releases the previous map ping")
local openMap = h.G.OpenWorldMap
h.G.OpenWorldMap = function() end
h.ns.Pins.Reveal({ map = 1413, x = 0.5, y = 0.5 })
h.map:SetMapID(1411)
h.flush()
h.map:SetMapID(1413)
h.flush()
equal(#h.Pins("AdventureGuideForeverPingPinTemplate"), 0, "a superseded reveal does not play on a later map visit")
h.G.OpenWorldMap = openMap
equal(#h.errors, 0, table.concat(h.errors, "\n"))
print("combat_pins_spec: " .. checks .. " checks passed")
