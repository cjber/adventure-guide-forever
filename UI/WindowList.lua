---@type string, AGFNamespace
local _, ns = ...
local Window = ns.Window
local HEADING_H = 22
-- A heading that carries an info line under its title (a boss and its level over its loot) is two lines tall.
local HEADING_INFO_H = 38

---@param widget AGFDungeonListWidget
local function PaintList(widget)
	local scroll = widget.frame:GetVerticalScroll()
	local values, tops, heights = widget.values, widget.tops, widget.heights
	local first = 1
	while first <= #values and tops[first] + heights[first] <= scroll do
		first = first + 1
	end
	for _, row in ipairs(widget.rows) do
		row.value = nil
		row:Hide()
	end
	local bottom, rowIndex = scroll + widget.height, 0
	for index = first, #values do
		if tops[index] >= bottom then
			break
		end
		rowIndex = rowIndex + 1
		local row = widget.rows[rowIndex]
		if not row then
			break
		end
		local value = values[index]
		row.value = value
		row:ClearAllPoints()
		row:SetHeight(heights[index] - 2)
		row:SetPoint("TOPLEFT", 0, -tops[index])
		row:Show()
		widget.paint(row, value)
	end
end

---@param parent Frame
---@param x number
---@param y number
---@param width number
---@param height number
---@param rowHeight number
---@param paint fun(row: AGFDungeonRow, value: table)
---@param click fun(value: table)
---@param create fun(parent: Frame, width: number, rowHeight: number, click: fun(value: table)): AGFDungeonRow
---@return AGFDungeonListWidget
function Window.CreateList(parent, x, y, width, height, rowHeight, paint, click, create)
	local scroll = CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate") --[[@as AGFScrollFrame]]
	scroll:SetPoint("TOPLEFT", x, -y)
	scroll:SetSize(width, height)
	scroll.ScrollBar:ClearAllPoints()
	scroll.ScrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 3, 0)
	scroll.ScrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 3, 0)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(width, height)
	scroll:SetScrollChild(child)
	local widget = {
		frame = scroll,
		child = child,
		rows = {},
		values = {},
		tops = {},
		heights = {},
		height = height,
		rowHeight = rowHeight,
		headingHeight = HEADING_H,
		paint = paint,
	}
	for index = 1, math.ceil(height / math.min(rowHeight, HEADING_H)) + 1 do
		local row = create(child, width, rowHeight, click)
		widget.rows[index] = row
	end
	scroll:HookScript("OnVerticalScroll", function()
		PaintList(widget)
	end)
	return widget
end

---@param widget AGFDungeonListWidget
---@param values table[]
function Window.SetList(widget, values)
	widget.values = values
	local heights, tops, total = {}, {}, 0
	for index, value in ipairs(values) do
		local heading = value.info and value.info ~= "" and HEADING_INFO_H or widget.headingHeight
		heights[index] = value.heading and heading or widget.rowHeight
		tops[index] = total
		total = total + heights[index]
	end
	widget.heights, widget.tops = heights, tops
	widget.child:SetHeight(math.max(widget.height, total))
	-- The scroll range is otherwise measured a frame late, and a jump made now would stop at the old list's end.
	widget.frame:UpdateScrollChildRect()
	widget.frame.ScrollBar:SetShown(total > widget.height)
	PaintList(widget)
end

---@param widget AGFDungeonListWidget
---@param index integer
function Window.ScrollListTo(widget, index)
	widget.frame:SetVerticalScroll(math.min(widget.tops[index], math.max(0, widget.child:GetHeight() - widget.height)))
end
