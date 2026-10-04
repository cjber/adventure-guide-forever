local ui = dofile("tests/ui_helpers.lua")
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local h = harness.load({ instanceType = "party" })
local map = h.G.WorldMapFrame
h.instanceID = 36
map:Show()
equal(h.G.AdventureGuideForeverWorldDungeonMap, nil, "no overlay without Atlas")
h.G.AtlasMaps = {
	CL_TheDeadmines = { Module = "Atlas_ClassicWoW", ZoneName = { "The Deadmines" }, { "1) Boss" } },
}
map:RefreshAllDataProviders()
local panel = assert(h.G.AdventureGuideForeverWorldDungeonMap)
equal(panel:IsVisible(), true, "current dungeon opens in world map")

local back = assert(ui.FindText(panel, h.ns.L.DUNGEON_MAP_WORLD_BACK))
h.Click(back)
equal(panel:IsShown(), false, "back exposes ordinary map")
map:RefreshAllDataProviders()
equal(panel:IsShown(), false, "provider refresh respects dismissal")
h.Click(assert(ui.FindText(map.ScrollContainer, h.ns.L.DUNGEON_MAPS_TAB)))
equal(panel:IsVisible(), true, "map button reopens interior")
local current = map:GetMapID()
map:SetMapID(947)
equal(panel:IsShown(), false, "continent navigation hides dungeon")
map:SetMapID(current)
equal(panel:IsVisible(), true, "return to current dungeon restores interior")
h.combat = true
h.fire("PLAYER_REGEN_DISABLED")
h.flush()
equal(panel:IsShown(), false, "combat hides overlay without protected map calls")
h.combat = false
h.fire("PLAYER_REGEN_ENABLED")
h.flush()
equal(panel:IsVisible(), true, "combat exit restores current dungeon")
h.instanceID = 389
h.fire("ZONE_CHANGED_NEW_AREA")
h.flush()
equal(panel:IsShown(), false, "unsupported dungeon never keeps previous interior")
h.instanceType = "none"
h.fire("ZONE_CHANGED_NEW_AREA")
h.flush()
equal(panel:IsShown(), false, "leaving instance restores normal map")
equal(#h.errors, 0, table.concat(h.errors, "\n"))

-- A dungeon the guide offers is pinned at its entrance; clicking the pin opens its interior from outside.
local p = harness.load({
	charDB = { journey = "dungeon:389", dungeons = true },
	entrances = { [389] = { map = 1411, x = 0.52, y = 0.49 } },
})
p.flush()
local offered
for _, journey in ipairs(p.ns.Route().journeys) do
	if journey.kind == "dungeon" then
		offered = journey.instance
	end
end
equal(offered, 389, "the guide offers Ragefire Chasm")
local pmap = p.G.WorldMapFrame
pmap:Show()
pmap:SetMapID(1411)
equal(#(p.pins.AdventureGuideForeverDungeonPinTemplate or {}), 0, "no pin without Atlas")
p.G.AtlasMaps = {
	CL_RagefireChasm = { Module = "Atlas_ClassicWoW", ZoneName = { "Ragefire Chasm" }, { "1) Boss" } },
}
pmap:RefreshAllDataProviders()
local pins = p.pins.AdventureGuideForeverDungeonPinTemplate
pins = assert(pins and #pins == 1 and pins, "the offered dungeon's entrance is pinned")
equal(pins[1].x, 0.52, "the pin sits on the entrance")
equal(pins[1].y, 0.49, "the pin sits on the entrance")
pins[1]:OnMouseEnter()
equal(p.tooltip[1], "title: Ragefire Chasm", "the pin names the instance")
equal(
	p.tooltip[2],
	"instruction: " .. p.ns.L.DUNGEON_MAP_OPEN:format("Ragefire Chasm"),
	"the pin says what a click does"
)
pins[1]:OnMouseLeave()
pins[1]:OnClick("LeftButton")
local over = assert(p.G.AdventureGuideForeverWorldDungeonMap, "the click opens the interior on the map")
equal(over:IsVisible(), true, "the click opens the interior on the map")
local overView = assert(p.G.AdventureGuideForeverDungeonMaps, "the overlay exposes its view").DungeonMapView
equal(overView.maps[1].title, "Ragefire Chasm", "the overlay shows the instance's map")
equal(overView.floor:IsShown(), false, "one Atlas map has no floor selector")
p.Click(assert(ui.FindText(over, p.ns.L.DUNGEON_MAP_WORLD_BACK)))
pmap:RefreshAllDataProviders()
equal(over:IsShown(), false, "the pin's interior respects dismissal")
equal(#p.errors, 0, table.concat(p.errors, "\n"))
print("world_dungeon_maps_spec: " .. checks .. " checks passed")
