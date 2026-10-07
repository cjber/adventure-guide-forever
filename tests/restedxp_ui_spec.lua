local harness = dofile("tests/harness.lua")
local h = harness.load({ spf = "v1", db = { autoStart = false } })
local ns = h.ns
dofile("tests/rxp_fixture.lua")(h)
local guide = assert(ns.RestedXP.Journey())
ns.Choose(guide.key)
h.flush()
ns.OpenPanel()
h.flush()
assert(#h.errors == 0, table.concat(h.errors, "\n"))
local panel = h.G.AdventureGuideForeverPanel
local height = panel:GetHeight()
local rows = h.Find(function(frame)
	return frame.step and frame.step.rxpIndex
end)
assert(#rows > 0, "guide instructions use the existing step rows")
local checks = h.Find(function(frame)
	return frame.Tick and frame.Text and frame.Text:GetText():find("quartermaster", 1, true)
end)
assert(#checks > 0, "guide objectives use the existing checklist")
h.tracker:LayoutContents()
local main = h.tracker.liveBlocks[guide.steps[1].key]
local sticky = h.tracker.liveBlocks[guide.steps[2].key]
assert(main and sticky, "the ordinary tracker shows current and ongoing guide steps")
assert(main.lines[1]:find("quartermaster", 1, true), "instruction text reaches the tracker")
ns.SetSetting("restedxpGuide", false)
h.flush()
assert(panel:GetHeight() == height, "changing the guide source preserves panel height")
assert(#h.errors == 0, table.concat(h.errors, "\n"))
print("restedxp_ui_spec: existing cards, checklist and tracker passed")

local preview = harness.load({ spf = "v1", db = { autoStart = false, showMapPins = true } })
local markers = {}
local radius = 1000
preview.G.C_Minimap = {
	GetViewRadius = function()
		return radius
	end,
}
preview.G.Minimap = preview.G.CreateFrame("Frame")
preview.G.Minimap:SetWidth(100)
preview.ns.Data.maps[1413].sx = 1000
preview.ns.Data.maps[1413].sy = 1000
preview.G.LibStub = {
	GetLibrary = function()
		return {
			RemoveAllWorldMapIcons = function() end,
			RemoveAllMinimapIcons = function(_, owner)
				markers[owner] = {}
			end,
			AddMinimapIconMap = function(_, owner, icon, map, x, y)
				markers[owner] = markers[owner] or {}
				markers[owner][#markers[owner] + 1] = { icon = icon, map = map, x = x, y = y }
			end,
		}
	end,
}
dofile("tests/rxp_fixture.lua")(preview, 10)
local upcoming = assert(preview.ns.RestedXP.Journey())
preview.ns.Choose(upcoming.key, true)
preview.flush()
preview.G.WorldMapFrame:Hide()
preview.ns.Pins.Refresh()
local numbered
for _, owned in pairs(markers) do
	if #owned > 0 then
		numbered = owned
	end
end
local represented = 0
for _, marker in ipairs(assert(numbered)) do
	represented = represented + #marker.icon.visits
	assert(marker.icon.Stack:IsShown() == (#marker.icon.visits > 1), "minimap uses stacked rings for shared visits")
end
assert(represented == 10 and #numbered < 10, "all ten destinations are represented by grouped minimap markers")
local groupedCount = #numbered
radius = 10
preview.ns.Pins.Refresh()
for _, owned in pairs(markers) do
	if #owned > 0 then
		assert(#owned > groupedCount, "minimap zoom separates nearby guide markers")
	end
end
local future = upcoming.steps[2]
assert(future.preview and not preview.ns.StartRoute(future), "a preview click cannot start out-of-order guidance")
assert(not preview.ns.RestedXP.Skip(future.rxpIndex), "future guide steps cannot be skipped")
preview.ns.OpenPanel()
preview.flush()
local futureRows = preview.Find(function(frame)
	return frame.step and frame.step.preview
end)
assert(#futureRows >= 9, "the existing map guide panel displays upcoming steps")
preview.tracker:LayoutContents()
local currentBlock = preview.tracker.liveBlocks[upcoming.steps[1].key]
local nextBlock = preview.tracker.liveBlocks[upcoming.steps[2].key]
assert(currentBlock and nextBlock, "the quest tracker shows current and next guide steps")
assert(not preview.tracker.liveBlocks[upcoming.steps[3].key], "later preview steps stay in the world map panel")
local ongoingBlock = preview.tracker.liveBlocks[upcoming.steps[#upcoming.steps].key]
assert(ongoingBlock, "the quest tracker retains active ongoing objectives")
assert(#preview.errors == 0, table.concat(preview.errors, "\n"))
print("restedxp_ui_spec: ten-step preview and minimap guidance passed")

local map = preview.G.WorldMapFrame
local canvas = preview.G.CreateFrame("Frame")
canvas:SetSize(1000, 1000)
local zoom = 1
map.GetCanvas = function()
	return canvas
end
map.GetCanvasScale = function()
	return zoom
end
map:SetMapID(1413)
map:Show()
preview.ns.Pins.Refresh()
local worldMinimap = 0
for _, owned in pairs(markers) do
	for _, marker in ipairs(owned) do
		worldMinimap = worldMinimap + #marker.icon.visits
	end
end
assert(worldMinimap == 10, "world map refresh preserves minimap guide markers")
local ringPins = preview.pins.AdventureGuideForeverPinTemplate
local grouped = false
for _, pin in ipairs(ringPins or {}) do
	if pin.visits and #pin.visits > 1 then
		grouped = true
		assert(pin.Stack and pin.Stack:IsShown(), "grouped markers use stacked rings without extra count labels")
	end
end
assert(grouped, "nearby steps share a readable marker at normal zoom")
local count = #ringPins
zoom = 4
local pinProvider
for _, candidate in ipairs(preview.providers) do
	if candidate.RefreshAllData and candidate.OnCanvasScaleChanged then
		pinProvider = candidate
	end
end
assert(pinProvider, "map zoom has a data-provider callback")
pinProvider:OnCanvasScaleChanged()
assert(#preview.pins.AdventureGuideForeverPinTemplate > count, "zooming in separates nearby guide markers")
print("restedxp_ui_spec: nearby markers group and split with zoom")
