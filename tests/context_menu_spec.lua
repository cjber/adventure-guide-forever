local harness = dofile("tests/harness.lua")
local h = harness.load()
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": " .. tostring(actual))
end
h.G.MenuUtil.CreateContextMenu = function()
	error("native menu acquisition can crash Forever 70009")
end
local owner = h.G.CreateFrame("Button", nil, h.G.UIParent)
local calls = 0
h.ns.ContextMenu(owner, function(_, root)
	root:CreateTitle("Title")
	root:CreateButton("Disabled", function()
		calls = calls + 100
	end):SetEnabled(false)
	local first = root:CreateButton("First")
	local second = first:CreateButton("Second")
	second:CreateButton("Action", function()
		calls = calls + 1
	end)
end)
local popup = h.G.AdventureGuideForeverContextMenu
assert(popup)
equal(popup:IsShown(), true, "owned menu opens")
equal(popup.rows[3]:GetHeight(), 20, "compact dropdown rows")
equal(popup.rows[3].fontString:GetText(), "First >", "button uses its compact text label")
equal(popup:GetParent(), h.G.UIParent, "popup escapes owner scroll clipping")
equal(popup.rows[1]:IsEnabled(), false, "title not actionable")
equal(popup.rows[2]:IsEnabled(), false, "disabled action stays disabled")
h.Click(popup.rows[3])
equal(popup.rows[1]:GetText(), "Back", "submenu has back")
h.Click(popup.rows[2])
h.Click(popup.rows[1])
equal(popup.rows[1]:GetText(), "Back", "deep back retains parent navigation")
h.Click(popup.rows[1])
equal(popup.rows[3]:GetText(), "First >", "back returns root")
h.Click(popup.rows[3])
h.Click(popup.rows[2])
h.Click(popup.rows[2])
equal(calls, 1, "leaf executes once")
equal(popup:IsShown(), false, "leaf closes menu")
h.ns.ContextMenu(owner, function(_, root)
	for i = 1, 40 do
		root:CreateButton("Entry " .. i, function() end)
	end
end)
equal(popup:GetHeight() <= 420, true, "long menus fit viewport")
equal(popup.body:GetHeight() > popup:GetHeight(), true, "long menu scrolls")
owner:Hide()
equal(popup:IsVisible(), false, "owner hide closes visible menu")
owner:Show()
equal(popup:IsShown(), false, "owner reshow does not reopen menu")
h.ns.ContextMenu(owner, function(_, root)
	root:CreateButton("Outside")
end)
popup.mouseOver = true
h.fire("GLOBAL_MOUSE_DOWN")
equal(popup:IsShown(), true, "inside click keeps menu open")
popup.mouseOver = false
owner.mouseOver = false
h.fire("GLOBAL_MOUSE_DOWN")
equal(popup:IsShown(), false, "outside click closes menu")
-- A long entry widens the whole menu rather than being cut: the aside lines in the guide's "+1 more" menu and a step
-- menu's title, "Complete objectives · ...", are the entries that need it.
local aside = "You haven't seen Overlook Standing yet: the overlook on the ridge"
h.ns.ContextMenu(owner, function(_, root)
	root:CreateTitle(aside)
	root:CreateButton("Short", function() end)
end)
equal(popup.body:GetWidth() > 296, true, "the body grows past its default")
equal(popup.body:GetWidth(), popup.rows[1]:GetWidth() + 12, "the body holds the longest row")
equal(popup:GetWidth(), popup.body:GetWidth() + 24, "the popup leaves room for the scroll bar")
equal(popup.rows[1]:GetWidth() + 20 >= popup.rows[1]:GetTextWidth(), true, "the longest row is not cut")
equal(popup:GetWidth() > 320, true, "the menu is wider than the old fixed width")

-- A row still cut at the width cap carries its whole text in a tooltip.
local huge = string.rep("Complete objectives · The Greenbelt ", 3)
h.ns.ContextMenu(owner, function(_, root)
	root:CreateButton(huge, function() end)
end)
local cut = popup.rows[1]
equal(cut:GetTextWidth() > cut:GetWidth() - 20, true, "the row is cut at the width cap")
h.Hover(cut)
equal(h.tooltip[1], "title: " .. huge, "a cut row's tooltip holds the whole text")

-- An entry that already has a tooltip keeps it: the row's own text is not shown over it.
h.ns.ContextMenu(owner, function(_, root)
	local entry = root:CreateButton(huge, function() end)
	entry:SetTooltip(function(tooltip)
		h.G.GameTooltip_SetTitle(tooltip, "Own tip")
	end)
end)
h.Hover(popup.rows[1])
equal(h.tooltip[1], "title: Own tip", "a row with its own tooltip keeps it")
equal(#h.errors, 0, table.concat(h.errors, "\n"))
-- Dungeon data stays reachable from the map card after removing the standalone window.
h.ns.DungeonLoot.Bosses = function(instance)
	equal(instance, 36, "the card asks for its own instance")
	return { { name = "Edwin VanCleef", npcID = 639, items = { 5191 } } }
end
h.G.C_Item.GetItemNameByID = function(id)
	return id == 5191 and "Cruel Barb" or nil
end
h.ns.Menu.Journey(owner, { title = "Deadmines", key = "dungeon:36", instance = 36 })
equal(popup.rows[2]:GetText(), "Bosses and loot >", "dungeon menu offers companion loot")
h.Click(popup.rows[2])
equal(popup.rows[2]:GetText(), "Edwin VanCleef >", "boss list uses AtlasLoot names")
h.Click(popup.rows[2])
equal(popup.rows[3]:GetText(), "Cruel Barb", "boss drops list cached item names")
h.Hover(popup.rows[3])
equal(h.tooltip[1], "item: 5191", "drop hover opens the native item tooltip")
h.ns.DungeonLoot.Bosses = function()
	return {}, h.ns.L.DUNGEON_LOOT_INSTALL
end
h.ns.Menu.Journey(owner, { title = "Deadmines", key = "dungeon:36", instance = 36 })
h.Click(popup.rows[2])
equal(popup.rows[2]:GetText(), h.ns.L.DUNGEON_LOOT_INSTALL, "missing companion has an explicit hint")

print("context_menu_spec: " .. checks .. " checks passed")
