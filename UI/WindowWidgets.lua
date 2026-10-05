---@type string, AGFNamespace
local _, ns = ...
local L, Art = ns.L, ns.Art
---@class AGFWindow
local Window = {}
ns.Window = Window
Window.WIDTH, Window.HEIGHT = 800, 496
Window.INSET_TOP, Window.INSET_BOTTOM = 60, 5

-- A step row's kind badge on its 26 ring, Shortest Path's 16-on-22 scaled down; an icon row's ring.
local BADGE, BADGE_OUT, ICON_ROW_RING = 14, 3, 26
-- Where a tab's content starts in the inset, under the Today strip.
Window.TOP, Window.LEFT, Window.RIGHT = 50, 14, 30
Window.INSET_WIDTH, Window.INSET_HEIGHT = Window.WIDTH - 8, Window.HEIGHT - Window.INSET_TOP - Window.INSET_BOTTOM
-- The Encounter Journal's own type and palette (R3): a panel title, a list row's name, a gold section header, the
-- instance title's warm grey and the ink the Journal sets body text in on its paper.
Window.FONT_TITLE, Window.FONT_ROW, Window.FONT_HEADER = "GameFontNormalLarge2", "GameFontNormalMed3", "GameFontNormal"
Window.GOLD = { 0.929, 0.788, 0.620 }
Window.TITLE_INK = { 0.902, 0.788, 0.671 }
local GOLD, TITLE_INK = Window.GOLD, Window.TITLE_INK
-- The renown divider (UI-Journeys-Renown-divider, 733x16) under a tab's featured card, across the tab at its own
-- aspect: DIVIDER_GAP below the card, the grid DIVIDER_SPAN below it.
local DIVIDER_ATLAS, DIVIDER_GAP = "UI-Journeys-Renown-divider", 4
local DIVIDER_WIDTH = Window.INSET_WIDTH - Window.LEFT - Window.RIGHT
local DIVIDER_HEIGHT = DIVIDER_WIDTH * 16 / 733
Window.DIVIDER_SPAN = DIVIDER_GAP + math.ceil(DIVIDER_HEIGHT) + 1
-- The Encounter Journal's dungeon button (UI-EJ-DungeonButton-Up, file 522972): pixels 1,439 to 175,535 of the 512 x
-- 1024 sheet, its rim 8 pixels wide, sliced into nine pieces so the rim keeps its width on any card.
local EJ_FILE, EJ_SHEET_W, EJ_SHEET_H = 522972, 512, 1024
local EJ_LEFT, EJ_TOP, EJ_RIGHT, EJ_BOTTOM, EJ_RIM = 1, 439, 175, 535, 8
-- The Suggested Content icon recipe: the icon cut to a circle on a dark disc inside the Adventure Guide's ring; an
-- atlas icon is inset so its own margin doesn't show.
local ATLAS_INSET = 0.16

--[[ Shared pieces the tabs draw with ]]

---@class AGFRingIcon : Frame
---@field Disc Texture
---@field Icon Texture
---@field Ring Texture
---@field Mask MaskTexture
---@field size number

---@param parent Frame
---@param size number
---@return AGFRingIcon
function Window.CreateRingIcon(parent, size)
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
function Window.SetRingIcon(ring, icon)
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
function Window.CreateCard(parent, zoneArt)
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

-- The card's still picture over its whole fill at the picture's own aspect, cropped evenly; after Window.SizeCard.
---@param card AGFWindowCard
---@param atlas string
function Window.SetPicture(card, atlas)
	local width, height = card:GetSize()
	Art.Cover(card.Picture, atlas, width - 4, height - 4)
end

-- Sizes a card: `width` by `height`, its rim placed piece by piece, the fade over `fade` of its width.
---@param card AGFWindowCard
---@param width number
---@param height number
---@param fade number
function Window.SizeCard(card, width, height, fade)
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
function Window.CreateStepRow(parent, height)
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
function Window.SetStepRow(row, index, title, detail, step)
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

---@class AGFWindowIconRow : Button
---@field Icon AGFRingIcon
---@field Title FontString
---@field Detail FontString

-- A row with a ringed icon in place of a number (a battleground, a Legacy objective), in the step rows' art.
---@param parent Frame
---@param height number
---@return AGFWindowIconRow
function Window.CreateIconRow(parent, height)
	local row = CreateFrame("Button", nil, parent) --[[@as AGFWindowIconRow]]
	row:SetHeight(height)
	Art.RowArt(row)
	row.Icon = Window.CreateRingIcon(row, ICON_ROW_RING)
	row.Icon:SetPoint("LEFT", 8, 0)
	row.Title, row.Detail = RowText(row, 42, Window.FONT_ROW)
	return row
end

-- A tab's calm page while it has nothing to show (SkillUp, Legacy Forever or rank data missing): its art dimmed
-- behind one centred line, covering the page at its own aspect.
---@class AGFWindowEmpty
---@field Art Texture
---@field Text FontString

---@param parent Frame
---@param atlas string
---@return AGFWindowEmpty
function Window.CreateEmpty(parent, atlas)
	local width = Window.INSET_WIDTH - Window.LEFT - Window.RIGHT
	local height = Window.INSET_HEIGHT - 12 - Window.TOP
	local art = parent:CreateTexture(nil, "ARTWORK")
	-- The page's ground: a flat dark tile while the client has no art for it, never a question mark or a
	-- substituted picture.
	art:SetColorTexture(0.1, 0.09, 0.08, 1)
	art:SetPoint("TOPLEFT", Window.LEFT, -Window.TOP)
	art:SetSize(width, height)
	if C_Texture.GetAtlasInfo(atlas) then
		Art.Cover(art, atlas, width, height)
		art:SetAlpha(0.35)
	end
	local text = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	text:SetPoint("CENTER", art, "CENTER", 0, 0)
	text:SetWidth(width - 120)
	text:SetJustifyH("CENTER")
	return { Art = art, Text = text }
end

---@param empty AGFWindowEmpty
---@param line? string shown while set
function Window.SetEmpty(empty, line)
	empty.Art:SetShown(line ~= nil)
	empty.Text:SetShown(line ~= nil)
	empty.Text:SetText(line or "")
end

-- The divider under a featured card whose bottom is `below` from the tab's top.
---@param parent Frame
---@param below number
---@return Texture
function Window.CreateDivider(parent, below)
	local divider = parent:CreateTexture(nil, "ARTWORK")
	Art.Fit(divider, DIVIDER_ATLAS, DIVIDER_WIDTH, DIVIDER_HEIGHT)
	divider:SetPoint("TOPLEFT", Window.LEFT, -(below + DIVIDER_GAP))
	return divider
end

-- A tab's section header over a column: "Next steps", "Reagents". The Journal's gold over the art's own type.
---@param parent Frame
---@param text string
---@return FontString
function Window.Heading(parent, text)
	local heading = parent:CreateFontString(nil, "ARTWORK", Window.FONT_HEADER)
	heading:SetJustifyH("LEFT")
	heading:SetText(text)
	heading:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	return heading
end

--[[ The Journal's paper section header: the paper-overlay caps and tiled middle, gold type, and, when `onClick`
     is given, a "+"/"-" glyph that folds the section it heads. ]]

---@class AGFWindowSectionHeader : Button
---@field Label FontString
---@field Chevron FontString
---@field Left Texture
---@field Right Texture
---@field Mid Texture
---@field Open boolean

---@param parent Frame
---@param text string
---@param onClick? fun(open: boolean)
---@return AGFWindowSectionHeader
function Window.CreateSectionHeader(parent, text, onClick)
	local header = CreateFrame("Button", nil, parent) --[[@as AGFWindowSectionHeader]]
	header:SetHeight(24)
	header.Left = header:CreateTexture(nil, "BACKGROUND", "UI-PaperOverlay-PaperHeader-SelectUp-Left")
	header.Left:SetPoint("LEFT", -1, -1)
	header.Right = header:CreateTexture(nil, "BACKGROUND", "UI-PaperOverlay-PaperHeader-SelectUp-Right")
	header.Right:SetPoint("RIGHT", 1, -1)
	header.Mid = header:CreateTexture(nil, "BACKGROUND", "UI-PaperOverlay-PaperHeader-SelectUp-Mid", -2)
	header.Mid:SetPoint("LEFT", header.Left, "RIGHT", -32, 0)
	header.Mid:SetPoint("RIGHT", header.Right, "LEFT", 32, 0)
	header.Label = header:CreateFontString(nil, "ARTWORK", Window.FONT_HEADER)
	header.Label:SetPoint("LEFT", 14, 0)
	header.Label:SetPoint("RIGHT", -24, 0)
	header.Label:SetJustifyH("LEFT")
	header.Label:SetWordWrap(false)
	header.Label:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	header.Label:SetText(text)
	header.Chevron = header:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	header.Chevron:SetPoint("RIGHT", -8, 0)
	header.Chevron:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
	if onClick then
		header.Open = true
		header.Chevron:SetText("-")
		header:SetScript("OnClick", function(self)
			self.Open = not self.Open
			self.Chevron:SetText(self.Open and "-" or "+")
			onClick(self.Open)
		end)
	end
	return header
end

-- The tabs share the featured card and side column; a grid leaves room for its own footer.
Window.Cards = {
	width = 440,
	height = 178,
	ring = 44,
	columns = 4,
	gap = 10,
	gridRing = 30,
	pad = 14,
}
local cards = Window.Cards
cards.available = Window.INSET_WIDTH - Window.LEFT - Window.RIGHT
cards.gridTop = Window.TOP + cards.height + Window.DIVIDER_SPAN
cards.gridWidth = (cards.available - (cards.columns - 1) * cards.gap) / cards.columns
cards.sideLeft = Window.LEFT + cards.width + 12
cards.sideWidth = cards.available - cards.width - 12
cards.fullHeight = Window.INSET_HEIGHT - 12 - Window.TOP

---@class AGFWindowFeatureCard : AGFWindowCard
---@field Icon AGFRingIcon
---@field Title FontString
---@field Reason FontString
---@field Tag? FontString

---@param parent Frame
---@param featured boolean
---@param gridHeight number
---@return AGFWindowFeatureCard, Frame
function Window.CreateFeatureCard(parent, featured, gridHeight)
	local card = Window.CreateCard(parent, true) --[[@as AGFWindowFeatureCard]]
	Window.SizeCard(card, featured and cards.width or cards.gridWidth, featured and cards.height or gridHeight, 0.75)
	local inner = CreateFrame("Frame", nil, card)
	inner:SetAllPoints()
	inner:SetFrameLevel(card:GetFrameLevel() + 5)
	card.Icon = Window.CreateRingIcon(inner, featured and cards.ring or cards.gridRing)
	return card, inner
end

---@param card AGFWindowFeatureCard
---@param featured boolean
---@param titleLines integer
function Window.LayoutCardHeading(card, featured, titleLines)
	if featured then
		card.Icon:SetPoint("TOPLEFT", 18, -18)
		local left = 18 + cards.ring + 14
		card.Title:SetPoint("TOPLEFT", left, -16)
		if card.Tag then
			card.Title:SetPoint("RIGHT", card.Tag, "LEFT", -8, 0)
		else
			card.Title:SetPoint("RIGHT", -16, 0)
		end
		card.Reason:SetPoint("TOPLEFT", left, -42)
		card.Reason:SetPoint("RIGHT", -16, 0)
	else
		card.Icon:SetPoint("TOPLEFT", cards.pad, -cards.pad)
		card.Title:SetPoint("LEFT", card.Icon, "RIGHT", 10, 0)
		card.Title:SetWidth(cards.gridWidth - cards.pad * 2 - cards.gridRing - 10)
		card.Title:SetMaxLines(titleLines)
		card.Reason:SetPoint("TOPLEFT", cards.pad, -60)
		card.Reason:SetWidth(cards.gridWidth - 2 * cards.pad)
		card.Reason:SetMaxLines(3)
		card.Title:SetWordWrap(true)
		card.Reason:SetWordWrap(true)
	end
	card.Title:SetJustifyH("LEFT")
	card.Reason:SetJustifyH("LEFT")
end

---@class AGFWindowPictureCard : AGFWindowCard
---@field Icon AGFRingIcon
---@field Title FontString
---@field Range FontString
---@field Tag? FontString
---@field Bar AGFProgressBar
---@field BarLabel FontString

---@param parent Frame
---@param tag? string
---@return AGFWindowPictureCard, Frame
function Window.CreatePictureCard(parent, tag)
	local card = Window.CreateCard(parent, false) --[[@as AGFWindowPictureCard]]
	Window.SizeCard(card, cards.width, cards.fullHeight, 0.8)
	card:SetPoint("TOPLEFT", Window.LEFT, -Window.TOP)
	card.Shade:Hide()
	card.Picture:Show()
	card.Highlight:Hide()
	local inner = CreateFrame("Frame", nil, card)
	inner:SetAllPoints()
	inner:SetFrameLevel(card:GetFrameLevel() + 5)
	card.Icon = Window.CreateRingIcon(inner, cards.ring)
	card.Icon:SetPoint("TOPLEFT", 18, -18)
	if tag then
		card.Tag = inner:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		card.Tag:SetPoint("TOPRIGHT", -16, -16)
		card.Tag:SetText(tag)
	end
	card.Title = inner:CreateFontString(nil, "ARTWORK", Window.FONT_TITLE)
	card.Title:SetTextColor(TITLE_INK[1], TITLE_INK[2], TITLE_INK[3])
	card.Title:SetPoint("TOPLEFT", 18 + cards.ring + 14, -16)
	if card.Tag then
		card.Title:SetPoint("RIGHT", card.Tag, "LEFT", -8, 0)
	else
		card.Title:SetPoint("RIGHT", -16, 0)
	end
	card.Range = inner:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	card.Range:SetPoint("TOPLEFT", 18 + cards.ring + 14, -42)
	card.Range:SetPoint("RIGHT", -16, 0)
	for _, text in ipairs({ card.Title, card.Range }) do
		text:SetJustifyH("LEFT")
		text:SetWordWrap(false)
	end
	card.Bar = ns.Overview.CreateBar(inner)
	card.BarLabel = inner:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	card.BarLabel:SetPoint("TOPRIGHT", -18, -73)
	card.BarLabel:SetJustifyH("RIGHT")
	return card, inner
end

---@param card AGFWindowPictureCard
---@param progress number
function Window.SetPictureProgress(card, progress)
	local room = cards.width - 36 - card.BarLabel:GetUnboundedStringWidth() - 8
	ns.Overview.SetBar(card.Bar, 18, 76, room, progress)
end

---@param parent Frame
---@param previous fun()
---@param nextPage fun()
---@param mapStyle? boolean
---@return Button, Button, FontString
function Window.CreatePager(parent, previous, nextPage, mapStyle)
	local back = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate") --[[@as Button]]
	back:SetSize(90, 22)
	back:SetPoint("BOTTOMLEFT", Window.LEFT, 8)
	back:SetText(L.PREVIOUS_PAGE)
	back:SetScript("OnClick", previous)
	local forward = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate") --[[@as Button]]
	forward:SetSize(90, 22)
	forward:SetPoint("BOTTOMRIGHT", -(mapStyle and 14 or Window.RIGHT), 8)
	forward:SetText(L.NEXT_PAGE)
	forward:SetScript("OnClick", nextPage)
	local count = parent:CreateFontString(
		nil,
		mapStyle and "ARTWORK" or "OVERLAY",
		mapStyle and "GameFontHighlight" or "GameFontHighlightSmall"
	)
	count:SetPoint("BOTTOM", 0, 13)
	return back, forward, count
end

---@param page integer
---@param count integer
---@param size integer
---@return integer, integer
function Window.ClampPage(page, count, size)
	local pages = math.max(1, math.ceil(count / size))
	return math.min(page, pages), pages
end
