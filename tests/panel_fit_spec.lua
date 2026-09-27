local harness = dofile("tests/harness.lua")
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
	local cards = h.Find(function(frame)
		return frame:IsVisible() and frame.Icon and frame.Icon.Clip and frame.journey
	end)
	assert(#cards == 12, "all destinations remain in the scroll content at every window height")
	local found = {}
	for _, card in ipairs(cards) do
		found[card.journey.key] = true
		assert(card.Title.wordWrap == false and card.Title.maxLines == 1, "long titles stay on one line")
		h.Hover(card)
		assert(h.tooltip[1] == "title: " .. card.journey.title, "tooltip retains full title")
	end
	assert(found["fit:12"], "the last destination is available, not truncated")
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
print("panel_fit_spec: all destinations accessible")
