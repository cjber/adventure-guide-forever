---@type string, AGFNamespace
local _, ns = ...
local L = ns.L
local Window, Overview = ns.Window, ns.Overview

-- The window's Journeys tab (docs/design.md §2.19): the panel's overview at the window's size. The card the route
-- follows is featured over its zone's map with its next steps beside it, and the others run four across under the
-- divider. The cards, steps and Show on Map choose and guide exactly as the panel's do.

local FEATURED_WIDTH, FEATURED_HEIGHT, FEATURED_SPAN, FEATURED_RING = 440, 178, 640, 44
local STEP_ROWS, STEP_GAP, STEP_HEAD = 3, 5, 18
local COLUMNS, GRID_GAP, GRID_SPAN, GRID_RING, GRID_PAD = 4, 10, 320, 30, 14
local DIVIDER_GAP = 8
local BUTTON_WIDTH, BUTTON_HEIGHT = 104, 22
local BAR_LABEL_GAP = 8

---@class AGFWindowJourneyCard : AGFWindowCard, AGFCardButton
---@field Icon AGFRingIcon
---@field Title FontString
---@field Reason FontString
---@field Counts? FontString
---@field Tag? FontString
---@field Foot FontString
---@field Bar AGFProgressBar
---@field ShowButton? Button

---@class AGFWindowStepRow : AGFWindowRow
---@field step? AGFStep
---@field index? integer

---@type AGFWindowJourneyCard
local featured
---@type AGFWindowStepRow[]
local rows = {}
---@type AGFWindowJourneyCard[]
local grid = {}
---@type FontString
local heading
---@type Texture
local divider
---@type FontString
local emptyText

local LEFT, TOP = Window.LEFT, Window.TOP
local WIDTH = Window.INSET_WIDTH - LEFT - Window.RIGHT
local GRID_TOP = TOP + FEATURED_HEIGHT + DIVIDER_GAP + 14
local GRID_WIDTH = (WIDTH - (COLUMNS - 1) * GRID_GAP) / COLUMNS
local GRID_HEIGHT = Window.INSET_HEIGHT - 12 - GRID_TOP
local STEPS_LEFT = LEFT + FEATURED_WIDTH + 12
local STEPS_WIDTH = WIDTH - FEATURED_WIDTH - 12
local ROW_HEIGHT = (FEATURED_HEIGHT - STEP_HEAD - (STEP_ROWS - 1) * STEP_GAP) / STEP_ROWS

-- Show on Map: the featured card's first step on the world map, choosing the card first as its click would, or
-- resuming its paused route.
---@param card AGFWindowJourneyCard
local function ShowOnMap(card)
	local journey, route = card.journey, ns.Route()
	if not journey then
		return
	end
	if not route.chosen or route.journey ~= journey.key then
		ns.Choose(journey.key, ns.Setting("titleStartsRoute"))
	elseif ns.Paused() then
		ns.StartRoute()
	end
	local step = route.steps[1]
	if step then
		Overview.ShowOnMap(step)
	end
end

---@param parent Frame
---@param isFeatured boolean
---@return AGFWindowJourneyCard
local function CreateCard(parent, isFeatured)
	local card = Window.CreateCard(parent, true) --[[@as AGFWindowJourneyCard]]
	local width, height = isFeatured and FEATURED_WIDTH or GRID_WIDTH, isFeatured and FEATURED_HEIGHT or GRID_HEIGHT
	Window.SizeCard(card, width, height, 0.75)
	local content = CreateFrame("Frame", nil, card)
	content:SetAllPoints()
	content:SetFrameLevel(card:GetFrameLevel() + 5)
	local ring = isFeatured and FEATURED_RING or GRID_RING
	card.Icon = Window.CreateRingIcon(content, ring)
	card.Bar = Overview.CreateBar(content)
	card.Foot = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	card.Foot:SetJustifyH(isFeatured and "RIGHT" or "LEFT")
	card.Foot:SetWordWrap(false)
	if isFeatured then
		local left = 18 + ring + 14
		card.Icon:SetPoint("TOPLEFT", 18, -18)
		card.Tag = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		card.Tag:SetPoint("TOPRIGHT", -16, -16)
		card.Tag:SetText(L.SUGGESTED)
		card.Title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalHuge")
		card.Title:SetPoint("TOPLEFT", left, -16)
		card.Title:SetPoint("RIGHT", card.Tag, "LEFT", -8, 0)
		card.Reason = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
		card.Reason:SetPoint("TOPLEFT", left, -42)
		card.Reason:SetPoint("RIGHT", -16, 0)
		card.Counts = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		card.Counts:SetPoint("TOPLEFT", 18, -(height - 64))
		card.Counts:SetPoint("RIGHT", -18, 0)
		for _, text in ipairs({ card.Title, card.Reason, card.Counts }) do
			text:SetJustifyH("LEFT")
			text:SetWordWrap(false)
		end
		local button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate") --[[@as Button]]
		button:SetSize(BUTTON_WIDTH, BUTTON_HEIGHT)
		button:SetPoint("BOTTOMRIGHT", -16, 22)
		button:SetText(L.SHOW_ON_MAP)
		button:SetScript("OnClick", function()
			ShowOnMap(card)
		end)
		card.ShowButton = button
		card.Foot:SetPoint("RIGHT", button, "LEFT", -BAR_LABEL_GAP, 0)
	else
		card.Icon:SetPoint("TOPLEFT", GRID_PAD, -GRID_PAD)
		-- Wrapped, never cut: up to three lines beside the ring, centred on it.
		card.Title = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		card.Title:SetPoint("LEFT", card.Icon, "RIGHT", 10, 0)
		card.Title:SetWidth(GRID_WIDTH - GRID_PAD * 2 - ring - 10)
		card.Title:SetMaxLines(3)
		card.Reason = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		card.Reason:SetPoint("TOPLEFT", GRID_PAD, -60)
		card.Reason:SetWidth(GRID_WIDTH - 2 * GRID_PAD)
		card.Reason:SetMaxLines(3)
		for _, text in ipairs({ card.Title, card.Reason }) do
			text:SetJustifyH("LEFT")
			text:SetWordWrap(true)
		end
	end
	card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	card:SetScript("OnClick", Overview.CardClick)
	card:SetScript("OnEnter", Overview.CardTooltip)
	card:SetScript("OnLeave", GameTooltip_Hide)
	return card
end

-- The card's zone map round its next town, its kind in the ring, its title.
---@param card AGFWindowJourneyCard
---@param journey AGFJourney
---@param span number
local function RefreshCard(card, journey, span)
	card.journey, card.state = journey, "shown"
	local step = Overview.IconStep(journey)
	local width, height = card:GetSize(true)
	ns.ZoneIcon.SetBackdrop(
		card.Art --[[@as AGFZoneBackdrop]],
		width - 4,
		height - 4,
		step and step.map,
		step and step.x,
		step and step.y,
		span
	)
	Window.SetRingIcon(card.Icon, Overview.KIND_ICONS[journey.kind])
	card.Title:SetText(journey.title)
	if GameTooltip:IsOwned(card) then
		Overview.CardTooltip(card)
	end
end

---@param journey AGFJourney
local function RefreshFeatured(journey)
	RefreshCard(featured, journey, FEATURED_SPAN)
	featured.Reason:SetText(Overview.DropLine(journey) or journey.reason or Overview.HubLine(journey) or "")
	local counts = featured.Counts --[[@as FontString]]
	counts:SetText(Overview.Counts(journey))
	local value, label = Overview.Progress(journey)
	featured.Foot:SetShown(value ~= nil)
	if value then
		featured.Foot:SetText(label)
		local room = FEATURED_WIDTH - 36 - BUTTON_WIDTH - featured.Foot:GetUnboundedStringWidth() - 2 * BAR_LABEL_GAP
		Overview.SetBar(featured.Bar, 18, FEATURED_HEIGHT - 38, room, value)
	else
		featured.Bar:Hide()
	end
end

-- A grid card's reason, then its footer: how far it has come beside the bar, else the level or its stops.
---@param card AGFWindowJourneyCard
---@param journey AGFJourney
local function RefreshGrid(card, journey)
	RefreshCard(card, journey, GRID_SPAN)
	local value, label = Overview.Progress(journey)
	local foot = label or (journey.level and L.NEXT_ZONE_LEVEL:format(journey.level)) or Overview.Stops(journey)
	local reason = journey.reason ~= foot and journey.reason or nil
	card.Reason:SetText(Overview.DropLine(journey) or reason or Overview.HubLine(journey) or journey.subline)
	card.Foot:SetText(foot)
	card.Foot:ClearAllPoints()
	local bottom = GRID_HEIGHT - GRID_PAD - 10
	if value then
		card.Foot:SetPoint("TOPRIGHT", -GRID_PAD, -bottom)
		local room = GRID_WIDTH - 2 * GRID_PAD - card.Foot:GetUnboundedStringWidth() - 6
		Overview.SetBar(card.Bar, GRID_PAD, bottom + 2, room, value)
	else
		card.Foot:SetPoint("TOPLEFT", GRID_PAD, -bottom)
		card.Bar:Hide()
	end
end

---@param parent Frame
---@return AGFWindowStepRow
local function CreateStepRow(parent)
	local row = Window.CreateStepRow(parent, ROW_HEIGHT) --[[@as AGFWindowStepRow]]
	row:SetWidth(STEPS_WIDTH)
	row:SetScript("OnEnter", Overview.RowEnter)
	row:SetScript("OnLeave", GameTooltip_Hide)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	-- As the panel's rows, but a step not in the log opens the map to it: the window has no map under it.
	row:SetScript("OnClick", function(self, mouseButton)
		local step = self.step
		if not step then
			return
		elseif mouseButton == "RightButton" then
			ns.Menu.Open(self, "MENU_ADVENTURE_GUIDE_FOREVER_STEP", step)
		elseif not ns.ShowQuest(step) then
			Overview.ShowOnMap(step)
		end
	end)
	return row
end

---@param content Frame
local function Build(content)
	featured = CreateCard(content, true)
	featured:SetPoint("TOPLEFT", LEFT, -TOP)
	heading = Window.Heading(content, L.NEXT_STEPS)
	heading:SetPoint("TOPLEFT", STEPS_LEFT + 2, -TOP)
	for index = 1, STEP_ROWS do
		local row = CreateStepRow(content)
		row:SetPoint("TOPLEFT", STEPS_LEFT, -(TOP + STEP_HEAD + (index - 1) * (ROW_HEIGHT + STEP_GAP)))
		rows[index] = row
	end
	divider = content:CreateTexture(nil, "ARTWORK")
	divider:SetAtlas("UI-Journeys-Renown-divider")
	divider:SetSize(WIDTH, 10)
	divider:SetPoint("TOPLEFT", LEFT, -(TOP + FEATURED_HEIGHT + DIVIDER_GAP))
	for index = 1, COLUMNS do
		local card = CreateCard(content, false)
		card:SetPoint("TOPLEFT", LEFT + (index - 1) * (GRID_WIDTH + GRID_GAP), -GRID_TOP)
		grid[index] = card
	end
	emptyText = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	emptyText:SetPoint("TOPLEFT", LEFT + 4, -(TOP + 8))
	emptyText:SetWidth(WIDTH - 8)
	emptyText:SetJustifyH("LEFT")
end

local function Refresh()
	local route = ns.Route()
	local first, others = Overview.Split(route)
	local ready = ns.State.Ready()
	emptyText:SetShown(first == nil)
	emptyText:SetText(ready and L.NO_JOURNEY or L.LOADING)
	featured:SetShown(first ~= nil)
	heading:SetShown(first ~= nil and #route.steps > 0)
	divider:SetShown(first ~= nil and #others > 0)
	if first then
		RefreshFeatured(first)
	end
	for index, row in ipairs(rows) do
		local step = first and route.steps[index] or nil
		row:SetShown(step ~= nil)
		if step then
			row.step, row.index = step, index
			Window.SetStepRow(row, index, step.title, step.detail)
			row:SetAlpha(step.optional and 0.6 or 1)
		end
	end
	for index, card in ipairs(grid) do
		local journey = others[index]
		card:SetShown(journey ~= nil)
		if journey then
			RefreshGrid(card, journey)
		end
	end
end

Window.AddTab({ key = "journeys", label = L.TAB_JOURNEYS, Build = Build, Refresh = Refresh })
