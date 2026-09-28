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
local function find(frame, text)
	if frame.GetText and frame:GetText() == text then
		return frame
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		local found = find(child, text)
		if found then
			return found
		end
	end
end
local back = assert(find(panel, h.ns.L.DUNGEON_MAP_WORLD_BACK))
h.Click(back)
equal(panel:IsShown(), false, "back exposes ordinary map")
map:RefreshAllDataProviders()
equal(panel:IsShown(), false, "provider refresh respects dismissal")
h.Click(assert(find(map.ScrollContainer, h.ns.L.DUNGEON_MAPS_TAB)))
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
print("world_dungeon_maps_spec: " .. checks .. " checks passed")
