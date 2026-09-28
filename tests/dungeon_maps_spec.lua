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
		equal(maps[1].legend, "|cffffffff1) Boss|r", "provider legend colours retained")
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
h.Click(button)
local panel = h.G.AdventureGuideForeverDungeonMaps
equal(panel:IsVisible(), true, "Maps tab opens interior panel")
local previous = assert(find(panel, ns.L.PREVIOUS_PAGE))
local nextPage = assert(find(panel, ns.L.NEXT_PAGE))
equal(previous:IsEnabled(), false, "first page")
h.Click(nextPage)
h.Click(nextPage)
equal(nextPage:IsEnabled(), false, "last page")
equal(previous:IsEnabled(), true, "can return to earlier floor")
h.Click(assert(find(panel, ns.L.DUNGEON_MAP_BACK)))
equal(panel:IsShown(), false, "back returns to dungeon")
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
