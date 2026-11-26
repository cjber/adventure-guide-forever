-- Run from the repository root: luajit -joff tests/guide_slot_level_spec.lua
-- DaylightUI's journal veils the other quest log children and has higher-level details inside its page (#956).
local harness = dofile("tests/harness.lua")
local h = harness.load()
local map = h.G.QuestMapFrame
local panel = h.G.AdventureGuideForeverPanel
map.rect = { 0, 0, 122, 100 }
panel.rect = { 0, 0, 100, 100 }

local skin = h.G.CreateFrame("Frame", nil, map)
skin:SetAllPoints(map)
skin.rect = map.rect
skin:EnableMouse(true)
local list = h.G.CreateFrame("Frame", nil, skin)
list.rect = skin.rect
list:SetFrameLevel(501)
local row = h.G.CreateFrame("Button", nil, list)
row.rect = { 10, 10, 80, 20 }
row:SetFrameLevel(504)

local veils = 0
local function Veil()
	veils = veils + 1
	for _, child in ipairs({ map:GetChildren() }) do -- multi-value: every child of the quest log
		if child ~= skin then
			child:SetAlpha(0)
		end
	end
end
skin:SetScript("OnShow", function()
	skin:SetFrameLevel(500)
	Veil()
end)

local outside = h.G.CreateFrame("Frame", nil, map)
outside.rect = { 200, 0, 40, 40 }
outside:SetFrameLevel(600)
local clipped = h.G.CreateFrame("Frame", nil, map)
clipped.rect = { 95, 0, 20, 100 }
clipped:SetClipsChildren(true)
local clippedRow = h.G.CreateFrame("Frame", nil, clipped)
clippedRow.rect = row.rect
clippedRow:SetFrameLevel(650)
local unplaced = h.G.CreateFrame("Frame", nil, map)
unplaced:SetFrameLevel(700)
local hidden = h.G.CreateFrame("Frame", nil, skin)
hidden:SetAllPoints(skin)
hidden.rect = skin.rect
hidden:SetFrameLevel(800)
hidden:Hide()
local hiddenRow = h.G.CreateFrame("Frame", nil, hidden)
hiddenRow.rect = row.rect
hiddenRow:SetFrameLevel(801)

local failures = {}
local function CheckSurface(path, level)
	if panel:GetAlpha() ~= 1 then
		failures[#failures + 1] = path .. ": panel alpha is " .. panel:GetAlpha()
	end
	if panel:GetFrameLevel() ~= level then
		failures[#failures + 1] = ("%s: expected frame level %d, got %d"):format(path, level, panel:GetFrameLevel())
	end
end

h.G.C_Map.OpenWorldMap()
h.flush()
assert(veils == 1 and skin:IsVisible() and panel:GetAlpha() == 0, "opening the map veils the guide")
h.ClickTab(h.G.AdventureGuideForeverTab)
assert(h.ns.PanelShown(), "the guide is selected by clicking its tab")
CheckSurface("tab click", 505)

h.G.HideUIPanel(h.map)
assert(h.G.ForeverCore.QuestLogTabs.Selected() == "guide", "closing the map keeps the guide selected")
-- Blizzard fires WorldMapOnShow from the map's OnShow, before the journal's inherited OnShow.
h.map:SetScript("OnShow", function()
	h.TriggerEvent("WorldMapOnShow")
end)
h.map:Show()
assert(veils == 2 and h.ns.PanelShown(), "reopening the map runs the journal's OnShow with the guide selected")
h.flush()
CheckSurface("map reopen", 505)

h.map:SetQuestLogPanelShown(false)
h.map:SetQuestLogPanelShown(true)
assert(veils == 3 and h.ns.PanelShown(), "expanding the quest log runs the journal's OnShow again")
h.flush()
CheckSurface("quest log expand", 505)

row:SetFrameLevel(506)
Veil()
h.fire("UPDATE_BINDINGS")
CheckSurface("visible refresh", 507)
assert(skin:IsVisible() and skin:GetFrameLevel() == 500, "the journal page remains untouched")
assert(row:IsVisible() and row:GetFrameLevel() == 506, "the journal row remains untouched")

local overhang = h.G.CreateFrame("Frame", nil, outside)
overhang.rect = { 200, 20, 10, 20 }
overhang:SetScale(0.4)
overhang:SetFrameLevel(508)
h.fire("UPDATE_BINDINGS")
CheckSurface("unclipped child overlapping in screen coordinates", 509)
overhang:Hide()

skin:Hide()
h.fire("UPDATE_BINDINGS")
assert(panel:IsVisible(), "the guide stays visible during the refresh")
CheckSurface("stock slot", map:GetFrameLevel() + 20)
assert(#h.errors == 0, table.concat(h.errors, "\n"))
assert(#failures == 0, table.concat(failures, "\n"))
print("guide_slot_level_spec: the guide stays visible above the journal")
