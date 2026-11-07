local harness = dofile("tests/harness.lua")
local MARKER = "Interface\\AddOns\\AdventureGuideForever\\media\\Numbers\\"
local h = harness.load({ log = { { id = 99999, title = "Unknown quest", level = 18 } } })
local ns = h.ns
ns.OpenPanel()
h.flush()
local panel, route = h.G.AdventureGuideForeverPanel, ns.Route()
local template = route.journeys[1]
local journeys = {}
for index = 1, 12 do
	local journey = {}
	for key, value in pairs(template) do
		journey[key] = value
	end
	journey.key = "fit:" .. index
	journey.title = "Head to Stonetalon Mountains and the farthest reaches of the world"
	journey.reason = "A long detail naming several towns and people waiting there"
	journeys[index] = journey
end
route.journeys = journeys
for _, height in ipairs({ 185, 389, 600 }) do
	panel.rect = { 0, 0, 306, height }
	h.call(panel:GetScript("OnSizeChanged"), panel, panel:GetWidth(), height)
	local function Cards()
		return h.Find(function(frame)
			return frame:IsVisible() and frame.Icon and frame.Icon.Clip and frame.journey
		end)
	end
	local header = h.Find(function(frame)
		return frame:IsVisible() and frame.key ~= nil and frame.Name ~= nil
	end)[1]
	assert(#Cards() <= 2, "folded sections show at most two cards")
	assert(header.Next == nil and header.Previous == nil, "no paging arrows")
	h.Click(header)
	h.flush()
	assert(#Cards() == 12, "expansion exposes all destinations through scrolling")
	for _, card in ipairs(Cards()) do
		assert(card.Title.wordWrap == false and card.Title.maxLines == 1, "long titles stay on one line")
		h.Hover(card)
		assert(h.tooltip[1] == "title: " .. card.journey.title, "tooltip retains full title")
	end
	h.Click(header)
	h.flush()
	assert(#Cards() <= 2, "folding restores the cap")
	assert(#h.Find(function(frame)
		return frame:GetObjectType() == "ScrollFrame" and frame:IsVisible()
	end) == 1, "home uses the stock scroll frame")
end
ns.Invalidate()
h.flush()
ns.Choose(ns.Route().journeys[1].key, false)
h.flush()
ns.Choose(nil)
h.flush()
assert(#h.Find(function(frame)
	return frame:GetObjectType() == "ScrollFrame" and frame:IsVisible()
end) == 1, "returning home preserves scrolling")
assert(#h.errors == 0, table.concat(h.errors, "\n"))
-- A fresh gnome sees the active loop plus a clearly non-navigable continuation in the map panel.
local fresh = harness.load({
	player = {
		level = 1,
		faction = "Alliance",
		raceID = 7,
		classID = 8,
		map = 1426,
		x = 0.28,
		y = 0.67,
	},
	log = {},
})
fresh.ns.OpenPanel()
fresh.flush()
fresh.ns.Choose("zone:1426", false)
fresh.flush()
local previews = fresh.Find(function(row)
	return row:IsVisible() and row.Title and (row.step or row.questID)
end)
assert(#previews == 10, "map panel shows ten active and upcoming rows")
local active, future, seen = 0, 0, {}
for _, row in ipairs(previews) do
	if row.questID then
		future = future + 1
		assert(not row:IsEnabled(), "future quest cannot start a premature route")
		assert(not row.Number:IsShown(), "future quests are distinct from active stops")
		assert(row.Detail:GetText() == fresh.ns.L.GUIDE_OUTLINE, "future quest explicitly labelled")
		seen[row.questID] = true
	else
		active = active + 1
		assert(row.Number.file == MARKER .. row.index .. ".tga", "an active row wears our numbered marker")
	end
end
assert(active == #fresh.ns.Route().steps and future > 0, "outline never mutates the active navigation route")
assert(seen[3114] and not seen[3112], "gnome mage preview uses the appropriate class chain")
fresh.ns.Choose(nil)
fresh.flush()
for _, row in ipairs(previews) do
	if row.questID then
		assert(not row:IsVisible(), "leaving the guide hides continuation rows")
	end
end
-- The tenth marker is our own art, not a font, and recycled rows restore their numbered marker.
local parent = fresh.G.CreateFrame("Frame")
local number = parent:CreateTexture()
number:SetSize(20, 20)
number:SetPoint("CENTER", parent)
fresh.ns.Art.SetStepMarker(number, 10, 26)
assert(number.file == MARKER .. "10.tga", "ten has a marker texture of its own")
local labelled
for _, region in ipairs({ parent:GetRegions() }) do
	if region.GetText and region:GetText() == "10" then
		labelled = region
	end
end
assert(not labelled, "ten draws no font")
assert(number:GetWidth() == 26 and number:GetHeight() == 26, "ten keeps the route row's square")
fresh.ns.Art.SetStepMarker(number, 1, 26)
assert(number.file == MARKER .. "1.tga", "recycling ten to one reuses the marker art")
assert(#fresh.errors == 0, table.concat(fresh.errors, "\n"))
print("panel_fit_spec: destinations and ten-step continuation accessible")
