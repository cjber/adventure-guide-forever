-- Run from the repository root: luajit tests/guide_slot_level_spec.lua
-- The guide panel sits above whatever the quest log slot holds (#956): a skin add-on that draws its own journal page
-- into QuestMapFrame at a high frame level must not cover the guide, and with the skin gone the panel returns to its
-- usual level above the stock views.
local harness = dofile("tests/harness.lua")
local h = harness.load()
h.flush()
local map = h.G.QuestMapFrame
local skin = h.G.CreateFrame("Frame", nil, map)
skin.rect = { 90, 90, 40, 40 }
skin:SetFrameLevel(500)
skin:Show()
local outside = h.G.CreateFrame("Frame", nil, map)
outside.rect = { 200, 0, 40, 40 }
outside:SetFrameLevel(600)
outside:Show()
local unplaced = h.G.CreateFrame("Frame", nil, map)
unplaced:SetFrameLevel(700)
unplaced:Show()
local panel = h.G.AdventureGuideForeverPanel
panel.rect = { 0, 0, 100, 100 }
h.ns.OpenPanel()
h.flush()
assert(panel:GetFrameLevel() == 501, "the guide rises only above the overlapping skin's page")
skin:Hide()
h.fire("UPDATE_BINDINGS")
assert(panel:IsVisible(), "the guide stays visible during the refresh")
assert(panel:GetFrameLevel() == map:GetFrameLevel() + 20, "with the skin gone the guide returns to its usual level")
assert(#h.errors == 0, table.concat(h.errors, "\n"))
print("guide_slot_level_spec: the guide rises above a skin's page")
