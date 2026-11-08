-- A town visit's numbered stop keeps its place, and every other NPC or object the visit covers gets its own small map
-- mark (issue #476). Buzzbox 411 is handed in deep in Bashal'Aran, away from the visit's stop at Asterion.
local harness = dofile("tests/harness.lua")
local h = harness.load({
	player = { level = 16, faction = "Alliance", raceID = 4, classID = 3, map = 1439, x = 0.37, y = 0.44 },
	log = {
		{ id = 1001, title = "Buzzbox 411", level = 12, complete = true, map = 1439, x = 0.4196, y = 0.2862 },
		{ id = 955, title = "Bashal'Aran", level = 12, complete = true, map = 1439, x = 0.4417, y = 0.3629 },
	},
	db = { showMapPins = true, showQuestGivers = true },
})
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

h.flush()
local ns = h.ns
local visit
for _, step in ipairs(ns.Route().steps) do
	if step.kind == "town" and step.key == "town:1439:446" then
		visit = step
	end
end
equal(visit ~= nil, true, "the route visits Bashal'Aran")

local buzzbox
for _, spot in ipairs(visit.visitSpots or {}) do
	if spot.name == "Buzzbox 411" then
		buzzbox = spot
	end
end
equal(buzzbox ~= nil, true, "the visit carries the Buzzbox spot")
equal(buzzbox.map, 1439, "the spot is on Darkshore")
equal(buzzbox.x, 0.4196, "the spot keeps its x")
equal(buzzbox.y, 0.2862, "the spot keeps its y")
equal(#buzzbox.handins, 1, "one quest is handed in there")
equal(buzzbox.handins[1], 1001, "Buzzbox 411 is handed in there")
equal(#buzzbox.pickups, 0, "nothing is picked up there")
equal(visit.x ~= buzzbox.x or visit.y ~= buzzbox.y, true, "the numbered stop sits elsewhere")

h.G.C_Map.OpenWorldMap()
h.flush()
h.map:SetMapID(1439)
h.flush()
ns.Pins.Refresh()
local marker
for _, pin in ipairs(h.Pins("AdventureGuideForeverSpotPinTemplate")) do
	if pin.spot and pin.spot.name == "Buzzbox 411" then
		marker = pin
	end
end
equal(marker ~= nil, true, "the map draws a mark at the Buzzbox")
equal(marker.mapX, 0.4196, "the mark is where the hand-in is")
equal(marker.mapY, 0.2862, "the mark is where the hand-in is, down the map")
equal(marker.Icon:GetAtlas(), "QuestTurnin", "a hand-in wears the game's turn-in mark")
equal(marker.Icon:GetAlpha(), 0.7, "a later stop fades as the route's marks do")
for _, pin in ipairs(h.Pins("AdventureGuideForeverSpotPinTemplate")) do
	equal(pin.spot.name == "Asterion", false, "the numbered stop's own spot draws no second mark")
end

h.Hover(marker)
equal(h.tooltip[1], "title: Buzzbox 411", "the mark names the object")
equal(h.tooltip[2]:find("|A:questturnin:", 1, true) ~= nil, true, "its tooltip carries the hand-in mark")
equal(h.tooltip[2]:find("Buzzbox 411", 1, true) ~= nil, true, "and names the quest handed in")
marker:OnMouseLeave()

equal(#h.errors, 0, table.concat(h.errors, "\n"))
print("visit_spot_spec: " .. checks .. " checks passed")
