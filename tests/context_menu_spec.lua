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
equal(#h.errors, 0, table.concat(h.errors, "\n"))
print("context_menu_spec: " .. checks .. " checks passed")
