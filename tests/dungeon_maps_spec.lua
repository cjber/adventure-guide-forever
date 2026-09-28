local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local h = harness.load()
local ns = h.ns
equal(#ns.Window.DungeonMaps(48), 0, "Atlas absent")
h.G.AtlasMaps = {}
local function record(lfg, title)
	return { Module = "Atlas_ClassicWoW", DungeonID = lfg, ZoneName = { title }, { "|cffffffff1) Boss|r" } }
end
local keys = {
	[33] = "ShadowfangKeep",
	[34] = "TheStockade",
	[36] = "TheDeadmines",
	[43] = "WailingCaverns",
	[47] = "RazorfenKraul",
	[48] = "BlackfathomDeepsA",
	[70] = "Uldaman",
	[90] = "Gnomeregan",
	[109] = "TheSunkenTemple",
	[129] = "RazorfenDowns",
	[189] = "SMLibrary",
	[209] = "ZulFarrak",
	[229] = "BlackrockSpireLower",
	[230] = "BlackrockDepths",
	[289] = "Scholomance",
	[329] = "Stratholme",
	[349] = "Maraudon",
	[389] = "RagefireChasm",
	[429] = "DireMaulEast",
}
local count = 0
for id, instance in pairs(ns.Data.instances) do
	if not instance.raid then
		local key = "CL_" .. keys[id]
		h.G.AtlasMaps[key] = record(instance.lfg, instance.name)
		local maps = ns.Window.DungeonMaps(id)
		equal(#maps, 1, "map for instance " .. id)
		equal(maps[1].texture, "Interface\\AddOns\\Atlas_ClassicWoW\\Images\\" .. key, "provider artwork path")
		equal(maps[1].legend, "|cffffffff1) Boss|r", "provider legend markup retained")
		count = count + 1
	end
end
equal(count, 19, "whole Classic dungeon catalogue")
h.G.AtlasMaps.CL_BlackrockSpireUpper = record(43, "Upper Blackrock Spire")
equal(#ns.Window.DungeonMaps(229), 2, "both Blackrock Spire wings share the instance")
h.G.AtlasMaps.CL_DireMaulWest = record(35, "Dire Maul West")
h.G.AtlasMaps.CL_Maraudon.DungeonID = 35
equal(#ns.Window.DungeonMaps(349), 1, "shared numeric IDs never mix different dungeons")
equal(#ns.Window.DungeonMaps(429), 2, "separate wing IDs remain together")
h.G.AtlasMaps = {
	CL_BlackfathomDeepsC = record(9, "Blackfathom Deeps C"),
	CL_BlackfathomDeepsA = record(9, "Blackfathom Deeps A"),
	CL_BlackfathomDeepsB = record(9, "Blackfathom Deeps B"),
	CL_Bad = false,
	CL_WrongModule = { Module = "Other", DungeonID = 9, ZoneName = { "Other" } },
	RetailVersion = record(9, "Wrong expansion"),
	["CL_../other"] = record(9, "Invalid texture path"),
}
local maps = ns.Window.DungeonMaps(48)
equal(#maps, 3, "only matching Classic module maps")
equal(maps[1].key, "CL_BlackfathomDeepsA", "provider keys give stable floor order")
equal(maps[3].key, "CL_BlackfathomDeepsC", "all interior pages included")
ns.Window.OpenDungeon(48)
h.flush()
local function find(frame, text)
	if frame.GetText and frame:GetText() == text then
		return frame
	end
	for _, child in ipairs({ frame:GetChildren() }) do
		local result = find(child, text)
		if result then
			return result
		end
	end
end
local window = h.G.AdventureGuideForeverWindow
local button = assert(find(window, ns.L.DUNGEON_MAPS_TAB))
equal(button:IsEnabled(), true, "Maps tab starts unselected")
h.Click(button)
equal(button:IsEnabled(), false, "Maps tab is selected while its overlay is open")
local panel = h.G.AdventureGuideForeverDungeonMaps
equal(panel:IsVisible(), true, "Maps tab opens interior panel")
local view = assert(panel.DungeonMapView, "map view is exposed for its parent")
equal(view.mapCard.Shade:IsShown(), false, "map artwork retains provider brightness")
equal(view.mapCard.Fade:IsShown(), false, "map artwork has no decorative gradient")
equal(view.mapCard.Rim[5]:IsShown(), false, "map artwork hides the center card fill")
equal(view.legendCard.Shade:IsShown(), false, "legend text is not darkened by the card shade")
equal(view.legendCard.Fade:IsShown(), false, "legend text has no decorative fade")
equal(view.legendCard.Rim[5]:IsShown(), false, "legend hides the center card fill")
equal(view.legendCard.Rim[1]:IsShown(), true, "legend keeps the outer card border")
view:SetMaps({ { title = "Provider legend", texture = "map", legendLines = { "|cff6666ffEntrance|r" } } })
equal(view.rows[1]:GetText(), "|cff6666ffEntrance|r", "provider legend colours are retained")
view:SetInstance(48)
local firstRow = view.rows[1]
equal(view.scroll:IsShown(), true, "short legends keep their viewport visible")
equal(view.scroll.mouseWheelEnabled, false, "short legends do not enable scrolling")
local previous = assert(find(panel, ns.L.PREVIOUS_PAGE))
local nextPage = assert(find(panel, ns.L.NEXT_PAGE))
equal(previous:IsEnabled(), false, "first page")
h.Click(nextPage)
equal(view.rows[1], firstRow, "legend rows are reused between pages")
h.Click(nextPage)
equal(nextPage:IsEnabled(), false, "last page")
equal(previous:IsEnabled(), true, "can return to earlier floor")
h.Click(previous)
local longLines = {}
for i = 1, 30 do
	longLines[i] = "Legend entry " .. i
end
view:SetMaps({ { title = "Long map", texture = "map", legendLines = longLines } })
equal(view.scroll.mouseWheelEnabled, true, "long legends enable scrolling")
local oldMapSize = view.mapCard:GetWidth()
panel:SetSize(500, 500)
panel:GetScript("OnSizeChanged")(panel, 500, 500)
equal(view.mapCard:GetWidth() <= 440, true, "map art remains bounded on wide parents")
equal(view.mapCard:GetWidth(), view.mapCard:GetHeight(), "map art remains square after resize")
equal(view.mapCard:GetWidth() ~= oldMapSize, true, "map view responds to parent resize")
panel:GetScript("OnSizeChanged")(panel, 830, 230)
equal(view.mapCard:GetHeight() <= 146, true, "short parent bounds artwork height")
equal(view.rows[1]:GetWidth(), view.legendWidth - 24, "resize reflows legend width")
h.Click(assert(find(panel, ns.L.DUNGEON_MAP_BACK)))
equal(panel:IsShown(), false, "back returns to dungeon")
equal(button:IsEnabled(), true, "Maps tab clears selection after returning")
h.Click(button)
equal(previous:IsEnabled(), false, "reopening resets floor")
h.Click(window.Tabs[1])
equal(panel:IsVisible(), false, "switching main tabs hides map")
h.Click(window.Tabs[5])
equal(panel:IsShown(), false, "returning restores dungeon details")
h.G.AtlasMaps = nil
h.Click(button)
equal(nextPage:IsEnabled(), false, "missing provider has no pages")
equal(#h.errors, 0, table.concat(h.errors, "\n"))
print("dungeon_maps_spec: " .. checks .. " checks passed")
