-- Run from the repository root: luajit tests/guide_slot_level_spec.lua
-- The guide panel sits above whatever the quest log slot holds (#956): a skin add-on that draws its own journal page
-- into QuestMapFrame at a high frame level must not cover the guide, and with the skin gone the panel returns to its
-- usual level above the stock views.
local harness = dofile("tests/harness.lua")
local h = harness.load()
h.flush()
local map = h.G.QuestMapFrame
local skin = h.G.CreateFrame("Frame", nil, map)
skin:SetFrameLevel(500)
skin:Show()
h.ns.OpenPanel()
h.flush()
local panel = h.G.AdventureGuideForeverPanel
assert(panel:GetFrameLevel() > 500, "the guide rises above a skin's page in the quest log slot")
skin:Hide()
h.G.WorldMapFrame:SetQuestLogPanelShown(false)
h.G.WorldMapFrame:SetQuestLogPanelShown(true)
h.flush()
assert(panel:GetFrameLevel() == map:GetFrameLevel() + 20, "with the skin gone the guide returns to its usual level")
assert(#h.errors == 0, table.concat(h.errors, "\n"))
print("guide_slot_level_spec: the guide rises above a skin's page")
