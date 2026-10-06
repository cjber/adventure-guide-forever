---@type string, AGFNamespace
local _, ns = ...
local Art = ns.Art
---@class AGFWidgets
local Widgets = {}
ns.Widgets = Widgets
local BADGE, BADGE_OUT = 16, 3
local GOLD = { 0.929, 0.788, 0.620 }

-- The Encounter Journal's dungeon button (UI-EJ-DungeonButton-Up, file 522972): pixels 1,439 to 175,535 of the 512 x
-- 1024 sheet, its rim 8 pixels wide, sliced into nine pieces so the rim keeps its width on any card.
local EJ_FILE, EJ_SHEET_W, EJ_SHEET_H = 522972, 512, 1024
local EJ_LEFT, EJ_TOP, EJ_RIGHT, EJ_BOTTOM, EJ_RIM = 1, 439, 175, 535, 8
-- The Suggested Content icon recipe: the icon cut to a circle on a dark disc inside the Adventure Guide's ring; an
-- atlas icon is inset so its own margin doesn't show.
local ATLAS_INSET = 0.16

-- Shared map rows and story notification art.

---@class AGFRingIcon : Frame
---@field Disc Texture
---@field Icon Texture
---@field Ring Texture
---@field Mask MaskTexture
---@field size number

---@param parent Frame
---@param size number
---@return AGFRingIcon
function Widgets.CreateRingIcon(parent, size)
	local ring = CreateFrame("Frame", nil, parent) --[[@as AGFRingIcon]]
	ring:SetSize(size, size)
	ring.size = size
	ring.Mask = Art.RingMask(ring)
	ring.Disc = ring:CreateTexture(nil, "BACKGROUND")
	ring.Disc:SetColorTexture(0.05, 0.04, 0.03, 1)
	ring.Disc:SetAllPoints()
	ring.Disc:AddMaskTexture(ring.Mask)
	ring.Icon = ring:CreateTexture(nil, "ARTWORK")
	ring.Icon:AddMaskTexture(ring.Mask)
	ring.Ring = Art.Ring(ring, size)
	return ring
end

-- An atlas (inset, at its own aspect) or a file icon (whole: a square icon) in the ring.
---@param ring AGFRingIcon
---@param icon string|integer?
function Widgets.SetRingIcon(ring, icon)
	ring.Icon:ClearAllPoints()
	if icon == nil then
		-- A flat dark ground in place of art the data has none of, never a question mark or a stand-in icon.
		ring.Icon:Hide()
		return
	end
	ring.Icon:Show()
	if type(icon) == "number" then
		Art.Icon(ring.Icon, icon, ring.size)
		ring.Icon:SetPoint("CENTER")
	else
		---@cast icon string
		local box = ring.size * (1 - 2 * ATLAS_INSET)
		Art.Fit(ring.Icon, icon, box, box)
		ring.Icon:SetPoint("CENTER")
	end
end

---@class AGFWindowCard : Button
---@field Fill Texture
---@field Art? AGFZoneBackdrop
---@field Picture Texture a still picture in place of the zone art (a profession's)
---@field Highlight Frame its hover, following the same nine-slice rim
---@field HoverRim Texture[]
---@field Shade Texture
---@field Fade Texture
---@field Rim Texture[] the nine pieces of the rim, row by row

-- A card on the tier art: black under the zone's map (or a picture), the map dimmed and faded to the left so text
-- reads over it, in the Encounter Journal's dungeon-button rim.
---@param parent Frame
---@param zoneArt boolean
---@return AGFWindowCard
function Widgets.CreateCard(parent, zoneArt)
	local card = CreateFrame("Button", nil, parent) --[[@as AGFWindowCard]]
	card.Fill = card:CreateTexture(nil, "BACKGROUND")
	card.Fill:SetColorTexture(0, 0, 0, 1)
	card.Fill:SetPoint("TOPLEFT", 2, -2)
	card.Fill:SetPoint("BOTTOMRIGHT", -2, 2)
	card.Picture = card:CreateTexture(nil, "BACKGROUND", nil, 1)
	card.Picture:SetAllPoints(card.Fill)
	card.Picture:Hide()
	if zoneArt then
		card.Art = ns.ZoneIcon.CreateBackdrop(card)
		card.Art:SetPoint("TOPLEFT", 2, -2)
	end
	-- Over the art, whichever frame level the client gives it.
	local cover = CreateFrame("Frame", nil, card)
	cover:SetAllPoints()
	cover:SetFrameLevel(card:GetFrameLevel() + 4)
	cover:EnableMouse(false)
	card.Shade = cover:CreateTexture(nil, "BACKGROUND")
	card.Shade:SetColorTexture(0, 0, 0, 0.5)
	card.Shade:SetAllPoints(card.Fill)
	card.Fade = cover:CreateTexture(nil, "BACKGROUND", nil, 1)
	card.Fade:SetColorTexture(1, 1, 1, 1)
	card.Fade:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0.6), CreateColor(0, 0, 0, 0))
	card.Fade:SetPoint("TOPLEFT", card.Fill)
	card.Fade:SetPoint("BOTTOMLEFT", card.Fill)
	local x = { EJ_LEFT, EJ_LEFT + EJ_RIM, EJ_RIGHT - EJ_RIM, EJ_RIGHT }
	local y = { EJ_TOP, EJ_TOP + EJ_RIM, EJ_BOTTOM - EJ_RIM, EJ_BOTTOM }
	card.Highlight = CreateFrame("Frame", nil, cover)
	card.Highlight:SetAllPoints()
	card.Highlight:SetFrameLevel(cover:GetFrameLevel() + 1)
	card.Highlight:EnableMouse(false)
	card.Highlight:Hide()
	card.Rim, card.HoverRim = {}, {}
	for row = 1, 3 do
		for column = 1, 3 do
			local piece = cover:CreateTexture(nil, "BORDER")
			piece:SetTexture(EJ_FILE) -- art-ok: a nine-slice piece of the journal's card, cropped below
			piece:SetTexCoord(
				x[column] / EJ_SHEET_W,
				x[column + 1] / EJ_SHEET_W,
				y[row] / EJ_SHEET_H,
				y[row + 1] / EJ_SHEET_H
			)
			card.Rim[#card.Rim + 1] = piece
			local glow = card.Highlight:CreateTexture(nil, "OVERLAY")
			glow:SetTexture(EJ_FILE) -- art-ok: the same piece's glow, cropped below
			glow:SetTexCoord(
				x[column] / EJ_SHEET_W,
				x[column + 1] / EJ_SHEET_W,
				y[row] / EJ_SHEET_H,
				y[row + 1] / EJ_SHEET_H
			)
			glow:SetAllPoints(piece)
			glow:SetBlendMode("ADD")
			glow:SetVertexColor(1, 0.82, 0.25)
			glow:SetAlpha(0.8)
			card.HoverRim[#card.HoverRim + 1] = glow
		end
	end
	card:HookScript("OnEnter", function(self)
		self.Highlight:SetShown(self:IsEnabled() and self:GetScript("OnClick") ~= nil)
	end)
	card:HookScript("OnLeave", function(self)
		self.Highlight:Hide()
	end)
	card:HookScript("OnHide", function(self)
		self.Highlight:Hide()
	end)
	card:HookScript("OnDisable", function(self)
		self.Highlight:Hide()
	end)
	return card
end

-- Sizes a card: `width` by `height`, its rim placed piece by piece, the fade over `fade` of its width.
---@param card AGFWindowCard
---@param width number
---@param height number
---@param fade number
function Widgets.SizeCard(card, width, height, fade)
	card:SetSize(width, height)
	card.Fade:SetWidth((width - 4) * fade)
	for row = 1, 3 do
		for column = 1, 3 do
			local piece = card.Rim[(row - 1) * 3 + column]
			piece:ClearAllPoints()
			local w = column == 2 and width - 2 * EJ_RIM or EJ_RIM
			local h = row == 2 and height - 2 * EJ_RIM or EJ_RIM
			local x = column == 1 and 0 or column == 2 and EJ_RIM or width - EJ_RIM
			local y = row == 1 and 0 or row == 2 and EJ_RIM or height - EJ_RIM
			piece:SetSize(w, h)
			piece:SetPoint("TOPLEFT", x, -y)
		end
	end
end

---@class AGFWindowRow : Button
---@field Selected AGFArtSlice
---@field Ring Texture
---@field Number Texture
---@field Kind AGFBadge the step's kind, badged on the ring
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

-- A numbered step on the right of a card: the route rows' art (Panel.lua), the ring and number at 26, the step's
-- kind badged on the ring.
---@param parent Frame
---@param height number
---@return AGFWindowRow
function Widgets.CreateStepRow(parent, height)
	local row = CreateFrame("Button", nil, parent) --[[@as AGFWindowRow]]
	row:SetHeight(height)
	row.Selected = Art.RowArt(row, true) --[[@as AGFArtSlice]]
	row.Ring = row:CreateTexture(nil, "ARTWORK")
	Art.Fit(row.Ring, "adventureguide-ring", 26, 26)
	row.Ring:SetPoint("LEFT", 6, 0)
	row.Number = row:CreateTexture(nil, "OVERLAY")
	row.Number:SetPoint("CENTER", row.Ring, "CENTER", 0, 0)
	row.Kind = ns.Overview.CreateBadge(row, row.Ring, BADGE, BADGE_OUT)
	row.Title, row.Detail = RowText(row, 40, "GameFontNormalMed3")
	return row
end

---@param row AGFWindowRow
---@param index integer
---@param title string
---@param detail? string
---@param step? AGFStep a route step, for its kind's badge
function Widgets.SetStepRow(row, index, title, detail, step)
	Art.SetNumber(row.Number, index)
	row.Title:SetText(title)
	row.Detail:SetText(detail or "")
	Art.SetSliceShown(row.Selected, index == 1)
	if step then
		ns.Overview.SetVerbIcon(row.Kind, step)
	else
		row.Kind:Hide()
	end
end

-- A tab's section header over a column: "Next steps", "Reagents". The Journal's gold over the art's own type.
---@param parent Frame
---@param text string
---@return FontString
function Widgets.Heading(parent, text)
	local heading = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	heading:SetJustifyH("LEFT")
	heading:SetText(text)
	heading:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	return heading
end
