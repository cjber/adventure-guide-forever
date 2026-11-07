---@type string, AGFNamespace
local _, ns = ...
local Art = ns.Art
---@class AGFWidgets
local Widgets = {}
ns.Widgets = Widgets
local BADGE, BADGE_OUT = 16, 3

-- Shared map rows.

---@class AGFWindowRow : Button
---@field Selected Texture
---@field Number Texture
---@field Kind AGFBadge the step's kind, badged on the marker
---@field Title FontString
---@field Detail FontString

---@param row Frame
---@param left number
---@param titleFont string
---@return FontString, FontString
local function RowText(row, left, titleFont)
	local title = row:CreateFontString(nil, "ARTWORK", titleFont)
	title:SetPoint("BOTTOMLEFT", row, "LEFT", left, 1)
	title:SetPoint("RIGHT", -8, 0)
	local detail = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	detail:SetPoint("TOPLEFT", row, "LEFT", left, -3)
	detail:SetPoint("RIGHT", -8, 0)
	detail:SetTextColor(0.8, 0.8, 0.8)
	for _, text in ipairs({ title, detail }) do
		text:SetJustifyH("LEFT")
		text:SetWordWrap(false)
	end
	return title, detail
end

-- A numbered step on the right of a card: the route rows' art (Panel.lua), the gold marker at 26, the step's kind
-- badged on it.
---@param parent Frame
---@param height number
---@return AGFWindowRow
function Widgets.CreateStepRow(parent, height)
	local row = CreateFrame("Button", nil, parent) --[[@as AGFWindowRow]]
	row:SetHeight(height)
	row.Selected = Art.RowArt(row, true) --[[@as Texture]]
	row.Number = row:CreateTexture(nil, "OVERLAY")
	Art.SetStepMarker(row.Number, 1, 26)
	row.Number:SetPoint("LEFT", 6, 0)
	row.Kind = ns.Overview.CreateBadge(row, row.Number, BADGE, BADGE_OUT)
	row.Title, row.Detail = RowText(row, 40, "GameFontNormalMed3")
	return row
end

---@param row AGFWindowRow
---@param index integer
---@param title string
---@param detail? string
---@param step? AGFStep a route step, for its kind's badge
function Widgets.SetStepRow(row, index, title, detail, step)
	Art.SetStepMarker(row.Number, index, 26)
	row.Title:SetText(title)
	row.Detail:SetText(detail or "")
	row.Selected:SetShown(index == 1)
	if step then
		ns.Overview.SetVerbIcon(row.Kind, step)
	else
		row.Kind:Hide()
	end
end
