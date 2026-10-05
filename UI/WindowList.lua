---@type string, AGFNamespace
local _, ns = ...
local Window = ns.Window
local HEADING_H = 22
-- A heading that carries an info line under its title (a boss and its level over its loot) is two lines tall.
local HEADING_INFO_H = 38

---@alias AGFListExtent fun(value: table): number

---@class AGFListContainer : Frame
---@field row? AGFDungeonRow

-- An element's height: the caller's own measure, else a heading's two lines or the list's row height.
---@param widget AGFDungeonListWidget
---@param value table
---@return number
local function ElementHeight(widget, value)
	if widget.extent then
		return widget.extent(value)
	end
	if not value.heading then
		return widget.rowHeight
	end
	return (value.info and value.info ~= "" and HEADING_INFO_H) or widget.headingHeight
end

--[[ The window's shared list: a WowScrollBoxList of pooled rows and a MinimalScrollBar, the way every Encounter
     Journal list scrolls. The scroll box makes a row only for the elements its viewport shows, positions it, and
     hands it back to the pool when it leaves, so the list keeps no rows of its own and culls nothing by hand. A
     caller gives `create` (one row frame, drawn once) and `paint` (a row's element); headings and any other
     variable row are measured by `extent`. ]]

---@param parent Frame
---@param x number
---@param y number
---@param width number
---@param height number
---@param rowHeight number
---@param paint fun(row: AGFDungeonRow, value: table)
---@param click fun(value: table)
---@param create fun(parent: Frame, width: number, rowHeight: number, click: fun(value: table)): AGFDungeonRow
---@param extent? AGFListExtent an element's height, in place of the heading rule
---@return AGFDungeonListWidget
function Window.CreateList(parent, x, y, width, height, rowHeight, paint, click, create, extent)
	local scroll = CreateFrame("Frame", nil, parent, "WowScrollBoxList") --[[@as AGFScrollBox]]
	scroll:SetPoint("TOPLEFT", x, -y)
	scroll:SetSize(width, height)
	local scrollBar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar") --[[@as Frame]]
	scrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 2, 0)
	scrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 2, 0)
	local widget = {
		frame = scroll,
		scrollBox = scroll,
		scrollBar = scrollBar,
		rows = {},
		values = {},
		tops = {},
		heights = {},
		height = height,
		rowHeight = rowHeight,
		headingHeight = HEADING_H,
		extent = extent,
		paint = paint,
	} --[[@as AGFDungeonListWidget]]
	local view = CreateScrollBoxListLinearView()
	view:SetElementExtentCalculator(function(_, value)
		return ElementHeight(widget, value)
	end)
	---@param container AGFListContainer
	---@param value table
	local function Initialize(container, value)
		if not container.row then
			container.row = create(container, width, rowHeight, click)
			container.row:ClearAllPoints()
			container.row:SetPoint("TOPLEFT")
			widget.rows[#widget.rows + 1] = container.row
		end
		-- A caller that measures its own elements sets its rows' heights in `create`; a heading's taller element
		-- is the list's to size.
		if value.heading or not widget.extent then
			container.row:SetHeight(ElementHeight(widget, value) - 2)
		end
		container.row.value = value
		widget.paint(container.row, value)
	end
	view:SetElementInitializer("Frame", Initialize)
	ScrollUtil.InitScrollBoxListWithScrollBar(scroll, scrollBar, view)
	-- The bar is the box's sibling, so it follows the box's own show and hide; a list the page hides takes its bar
	-- with it, as the scroll frame's bar did.
	scrollBar:SetShown(scroll:IsShown())
	scroll:HookScript("OnShow", function()
		scrollBar:Show()
	end)
	scroll:HookScript("OnHide", function()
		scrollBar:Hide()
	end)
	-- Callers written against the old ScrollFrameTemplate read and reset the scroll in pixels; the scroll box
	-- takes a percentage, so the widget keeps the same accessors for them.
	scroll.GetVerticalScroll = function(self)
		return self:GetDerivedScrollOffset()
	end
	scroll.SetVerticalScroll = function(self, value)
		self:ScrollToOffset(value)
	end
	return widget
end

-- `values` into the list: the element heights, their tops for callers that ask where an element is, then the
-- scroll box's own data provider, which lays the rows out and pools them.
---@param widget AGFDungeonListWidget
---@param values table[]
function Window.SetList(widget, values)
	widget.values = values
	local heights, tops, total = {}, {}, 0
	for index, value in ipairs(values) do
		local height = ElementHeight(widget, value)
		heights[index] = height
		tops[index] = total
		total = total + height
	end
	widget.heights, widget.tops = heights, tops
	widget.scrollBox:SetDataProvider(CreateDataProvider(values), true)
end

---@param widget AGFDungeonListWidget
---@param index integer
function Window.ScrollListTo(widget, index)
	widget.scrollBox:ScrollToOffset(widget.tops[index])
end
