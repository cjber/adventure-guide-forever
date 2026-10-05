-- Run from the repository root: luajit tests/list_spec.lua
-- The window's shared list (UI/WindowList.lua): a WowScrollBoxList whose rows are pooled by the scroll box, so a
-- list makes a row only for the elements its viewport shows and never keeps a row of its own.
local harness = dofile("tests/harness.lua")
local checks = 0

local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

local h = harness.load()
local ns = h.ns
local created = 0

-- A list row in the shape the dungeon pages make: a Button that keeps the element it paints.
local function CreateRow(parent, width, rowHeight)
	created = created + 1
	local row = h.G.CreateFrame("Button", nil, parent)
	row:SetSize(width, rowHeight - 2)
	return row
end

local list = ns.Window.CreateList(h.G.CreateFrame("Frame"), 0, 0, 200, 100, 20, function(row, value)
	row.Title = row.Title or ""
	row.value = value
end, function() end, CreateRow)
equal(list.frame, list.scrollBox, "the widget's frame is the scroll box")
equal(list.scrollBar:IsObjectType("Frame"), true, "with the minimal scrollbar beside it")
equal(list.frame.stockTemplate, "WowScrollBoxList", "the frame is the client's list scroll box")
equal(created, 0, "no row before the list has values")

local values = {}
for index = 1, 20 do
	values[index] = { text = "row " .. index }
end
ns.Window.SetList(list, values)
equal(#list.values, 20, "the values are kept")
equal(list.tops[1], 0, "the first element sits at the top")
equal(list.tops[2], 20, "the next at the row height")
equal(list.heights[1], 20, "an element's height is the row height")
equal(list.scrollBox:GetFrameCount(), 5, "only the viewport's five rows are made")
equal(created, 5, "and each is a pooled row")
local shown = {}
for _, row in ipairs(list.rows) do
	shown[row.value.text] = true
end
for index = 1, 5 do
	equal(shown["row " .. index], true, "the viewport shows element " .. index)
end
equal(shown["row 6"], nil, "and nothing past it")

-- A second list of the same elements reuses the pool instead of making rows again.
ns.Window.SetList(list, values)
equal(created, 5, "a redraw pools its rows")
equal(list.scrollBox:GetFrameCount(), 5, "and shows the same window of them")

-- A short list makes no more rows than it has elements.
local short = { { text = "only" }, { text = "two" } }
ns.Window.SetList(list, short)
equal(list.scrollBox:GetFrameCount(), 2, "a short list makes one row an element")

-- The pixel accessors the dungeon pages read still answer in pixels.
ns.Window.SetList(list, values)
ns.Window.ScrollListTo(list, 1)
equal(list.frame:GetVerticalScroll(), 0, "the top of the list is offset 0")
ns.Window.ScrollListTo(list, 20)
equal(list.frame:GetVerticalScroll(), 300, "a jump past the end clamps to the pan extent")
list.frame:SetVerticalScroll(0)
equal(list.frame:GetVerticalScroll(), 0, "and the reset accessor scrolls back")

equal(#h.errors, 0, "no errors")
print(("list_spec: %d checks passed"):format(checks))
