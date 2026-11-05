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
local sticky = h.tracker.liveBlocks["rxp-ongoing"]
assert(main and sticky, "the ordinary tracker shows current and ongoing guide steps")
assert(sticky.lines[1]:find("3/10 Supplies collected", 1, true), "an ongoing step is one line of its progress")
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
-- Hovering a minimap marker names its step as the tracker words it; clicks still fall through to the minimap.
local hovered = numbered[1].icon
local first = hovered.visits[1]
local questID = next(preview.ns.Data.quests)
first.step.quests = { questID }
first.step.checklist[1].done = true
assert(hovered.mouseMotionEnabled and not hovered:IsMouseEnabled(), "minimap markers take hover, never clicks")
hovered:GetScript("OnEnter")(hovered)
local G = preview.G
assert(G.GameTooltip:GetOwner() == hovered and G.GameTooltip:IsShown(), "hover shows the native tooltip")
local lines = table.concat(preview.tooltip, "\n")
assert(lines:find("title: " .. first.index .. ". " .. first.step.title, 1, true), "the tooltip names the step number")
assert(lines:find("colored: " .. first.step.checklist[1].text, 1, true), "a done checklist line is greyed")
assert(
	lines:find(preview.ns.State.QuestTitle(questID) or preview.ns.Data.quests[questID].title, 1, true),
	"the tooltip names the quest"
)
assert(
	not lines:find("highlight: \n", 1, true) and not lines:find("highlight: $"),
	"a guide step adds no empty reason line"
)
if #hovered.visits > 1 then
	assert(lines:find("normal: Stop " .. hovered.visits[2].index, 1, true), "a shared marker lists every visit")
end
hovered:GetScript("OnLeave")(hovered)
assert(not G.GameTooltip:IsShown(), "leaving hides the tooltip")
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
local futureStep = preview.G.RXP.currentGuide.steps[future.rxpIndex]
assert(preview.ns.RestedXP.Skip(future.rxpIndex) and futureStep.completed, "a future guide step is passed over")
futureStep.completed = nil
-- The skip is kept on the character now, so the record goes with the mark (#374).
preview.ns.Prefs().guideSkips = {}
preview.ns.RestedXP.Refresh()
preview.flush()
preview.ns.OpenPanel()
preview.flush()
local futureRows = preview.Find(function(frame)
	return frame.step and frame.step.preview
end)
assert(#futureRows >= 9, "the existing map guide panel displays upcoming steps")
preview.tracker:LayoutContents()
local currentBlock = preview.tracker.liveBlocks[upcoming.steps[1].key]
local nextLine = currentBlock and currentBlock.lines[currentBlock.order[#currentBlock.order]]
assert(nextLine and nextLine:find(upcoming.steps[2].title, 1, true), "the step under way names the next step")
local later = upcoming.steps[3].title
for _, block in pairs(preview.tracker.liveBlocks) do
	for _, text in pairs(block.used and block.lines or {}) do
		assert(not text:find(later, 1, true), "later preview steps stay in the world map panel")
	end
end
local ongoingBlock = preview.tracker.liveBlocks["rxp-ongoing"]
assert(ongoingBlock and ongoingBlock.used, "the quest tracker retains active ongoing objectives")
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
local ringPins = preview.Pins("AdventureGuideForeverPinTemplate")
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
preview.flush()
assert(#preview.Pins("AdventureGuideForeverPinTemplate") > count, "zooming in separates nearby guide markers")
print("restedxp_ui_spec: nearby markers group and split with zoom")
