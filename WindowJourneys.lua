---@type string, AGFNamespace
local _, ns = ...
local L = ns.L
local Window, Overview = ns.Window, ns.Overview

-- The window's Journeys tab (docs/design.md §2.19): the panel's overview at the window's size. The card the route
-- follows is featured over its zone's map with its next steps beside it, and the others run four across under the
-- divider. The cards, steps and Show on Map choose and guide exactly as the panel's do. Over the steps, how long the
-- player has (Session.lua); under them, how long it should take and, while the order is the player's own, the way back
-- to the suggested one (§2.20). A dungeon card has Go to entrance, from Tweaks Forever.

local FEATURED_WIDTH, FEATURED_HEIGHT, FEATURED_SPAN, FEATURED_RING = 440, 178, 640, 44
local STEP_ROWS, ROW_HEIGHT, STEP_GAP, STEP_HEAD, STEP_FOOT = 3, 44, 4, 18, 14
local COLUMNS, GRID_GAP, GRID_SPAN, GRID_RING, GRID_PAD = 4, 10, 320, 30, 14
local BUTTON_WIDTH, BUTTON_HEIGHT, ENTRANCE_WIDTH = 104, 22, 112
local BAR_LABEL_GAP = 8
-- The session picker (a stock WowStyle1 dropdown, 25 high as MenuTemplates.xml makes it) at the steps' top right,
-- raised level with the heading so it clears row 1: No limit, then minutes.
local SESSION_WIDTH, SESSION_HEIGHT, SESSION_RAISE = 96, 25, 8
local SESSIONS = { 0, 15, 30, 60 }
-- A town's checklist lines sit under its row, in from the ring.
local CHECK_LEFT = 40

---@class AGFWindowJourneyCard : AGFWindowCard, AGFCardButton
---@field Icon AGFRingIcon
---@field Title FontString
---@field Reason FontString
---@field Counts? FontString
---@field Tag? FontString
---@field Foot FontString
---@field Bar AGFProgressBar
---@field ShowButton? Button
---@field EntranceButton Button
---@field Note? FontString why Go to entrance is greyed, on the featured card

---@class AGFWindowStepRow : AGFWindowRow, AGFDraggableRow
---@field step? AGFStep
---@field index? integer

---@type AGFWindowJourneyCard
local featured
---@type AGFWindowStepRow[]
local rows = {}
---@type AGFCheckLine[]
local checks = {}
---@type AGFWindowJourneyCard[]
local grid = {}
---@type FontString
local heading
---@type Texture
local divider
---@type FontString
local emptyText
---@type AGFDropdown
local session
---@type FontString
local sessionText
---@type FontString
local sessionEmpty
---@type Button
local resetButton

local LEFT, TOP = Window.LEFT, Window.TOP
local WIDTH = Window.INSET_WIDTH - LEFT - Window.RIGHT
local GRID_TOP = TOP + FEATURED_HEIGHT + Window.DIVIDER_SPAN
local GRID_WIDTH = (WIDTH - (COLUMNS - 1) * GRID_GAP) / COLUMNS
local GRID_HEIGHT = Window.INSET_HEIGHT - 12 - GRID_TOP
local STEPS_LEFT = LEFT + FEATURED_WIDTH + 12
local STEPS_WIDTH = WIDTH - FEATURED_WIDTH - 12
local STEPS_BOTTOM = TOP + FEATURED_HEIGHT - STEP_FOOT - 2

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

-- Go to entrance: Tweaks Forever's point for the card's instance, as a waypoint; the card is not chosen by it.
---@param card AGFWindowJourneyCard
---@param parent Frame
---@return Button
local function CreateEntranceButton(card, parent)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate") --[[@as Button]]
	button:SetSize(ENTRANCE_WIDTH, BUTTON_HEIGHT)
	button:SetText(L.GO_TO_ENTRANCE)
	button:SetScript("OnClick", function()
		local instance = card.journey and Overview.Entrance(card.journey)
		if instance then
			ns.Providers.GoToEntrance(instance)
		end
	end)
	return button
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
	card.EntranceButton = CreateEntranceButton(card, content)
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
		card.EntranceButton:SetPoint("RIGHT", button, "LEFT", -6, 0)
		-- Two short lines at most, left of the greyed button.
		card.Note = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		card.Note:SetPoint("RIGHT", card.EntranceButton, "LEFT", -BAR_LABEL_GAP, 0)
		card.Note:SetWidth(FEATURED_WIDTH - 36 - BUTTON_WIDTH - ENTRANCE_WIDTH - 6 - BAR_LABEL_GAP)
		card.Note:SetJustifyH("RIGHT")
		card.Note:SetWordWrap(true)
		card.Note:SetMaxLines(2)
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
		card.EntranceButton:SetPoint("BOTTOMRIGHT", -GRID_PAD + 4, GRID_PAD - 6)
	end
	card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	card:SetScript("OnClick", Overview.CardClick)
	card:SetScript("OnEnter", Overview.CardTooltip)
	card:SetScript("OnLeave", GameTooltip_Hide)
	return card
end

-- The card's zone map round its next town, its kind in the ring, its title, and a dungeon's Go to entrance: greyed
-- while Tweaks Forever can't say where the entrance is. Returns why, for the featured card to say.
---@param card AGFWindowJourneyCard
---@param journey AGFJourney
---@param span number
---@return string? note
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
	local instance, point, note = Overview.Entrance(journey)
	card.EntranceButton:SetShown(instance ~= nil)
	card.EntranceButton:SetEnabled(point ~= nil and not ns.Setting("wanderer"))
	Overview.RefreshCardTooltip(card)
	return note
end

---@param journey AGFJourney
---@param custom boolean the player's own order
local function RefreshFeatured(journey, custom)
	local note = RefreshCard(featured, journey, FEATURED_SPAN)
	local tag = featured.Tag --[[@as FontString]]
	tag:SetText(custom and L.ORDER_CUSTOM or L.SUGGESTED)
	featured.Reason:SetText(Overview.DropLine(journey) or journey.reason or Overview.HubLine(journey) or "")
	local counts = featured.Counts --[[@as FontString]]
	counts:SetText(Overview.Counts(journey))
	local notes = featured.Note --[[@as FontString]]
	notes:SetShown(note ~= nil)
	notes:SetText(note or "")
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
			Overview.StepMenu(self, step, self.index)
		elseif not ns.ShowQuest(step) then
			Overview.ShowOnMap(step)
		end
	end)
	Overview.Draggable(row, rows, Window.Refresh)
	return row
end

-- The session picker's menu: a radio a length, the player's choice ticked (Session.lua keeps it per character).
---@param root SharedMenuDescriptionProxy
local function SessionMenu(_, root)
	root:SetTag("MENU_ADVENTURE_GUIDE_FOREVER_SESSION")
	root:CreateTitle(L.SESSION_LABEL)
	for _, minutes in ipairs(SESSIONS) do
		root:CreateRadio(minutes == 0 and L.SESSION_UNLIMITED or L.SESSION_MINUTES:format(minutes), function()
			return ns.Session.Get() == minutes
		end, function()
			ns.Session.Set(minutes)
		end, minutes)
	end
end

---@param content Frame
local function Build(content)
	featured = CreateCard(content, true)
	featured:SetPoint("TOPLEFT", LEFT, -TOP)
	heading = Window.Heading(content, L.NEXT_STEPS)
	heading:SetPoint("TOPLEFT", STEPS_LEFT + 2, -TOP)
	session = CreateFrame("DropdownButton", nil, content, "WowStyle1DropdownTemplate") --[[@as AGFDropdown]]
	session:SetSize(SESSION_WIDTH, SESSION_HEIGHT)
	session:SetPoint("TOPRIGHT", content, "TOPLEFT", STEPS_LEFT + STEPS_WIDTH, -(TOP - SESSION_RAISE))
	session:SetupMenu(SessionMenu)
	session:HookScript("OnEnter", function(self)
		ns.Overview.ShowTooltip(self, { L.SESSION_LABEL })
	end)
	session:HookScript("OnLeave", GameTooltip_Hide)
	for index = 1, STEP_ROWS do
		rows[index] = CreateStepRow(content)
	end
	sessionEmpty = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	sessionEmpty:SetPoint("TOPLEFT", STEPS_LEFT + 4, -(TOP + STEP_HEAD + 8))
	sessionEmpty:SetWidth(STEPS_WIDTH - 8)
	sessionEmpty:SetJustifyH("LEFT")
	sessionEmpty:SetText(L.SESSION_EMPTY)
	sessionText = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	sessionText:SetPoint("TOPLEFT", STEPS_LEFT + 2, -(STEPS_BOTTOM + 4))
	sessionText:SetJustifyH("LEFT")
	-- Back to suggested order: a small gold text button, as the panel's Skipped (n).
	resetButton = CreateFrame("Button", nil, content) --[[@as Button]]
	resetButton:SetHeight(STEP_FOOT)
	resetButton:SetNormalFontObject("GameFontNormalSmall")
	resetButton:SetHighlightFontObject("GameFontHighlightSmall")
	resetButton:SetText(L.ORDER_RESET)
	resetButton:SetWidth(resetButton:GetTextWidth() + 4)
	resetButton:SetPoint("TOPRIGHT", content, "TOPLEFT", STEPS_LEFT + STEPS_WIDTH, -(STEPS_BOTTOM + 2))
	resetButton:SetScript("OnClick", function()
		ns.Order.Reset()
	end)
	divider = Window.CreateDivider(content, TOP + FEATURED_HEIGHT)
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

-- The steps beside the featured card, each town's checklist under its row, as many as fit above the footer.
---@param content Frame
---@param steps AGFStep[]
local function RefreshSteps(content, steps)
	local top, check = TOP + STEP_HEAD, 1
	for index, row in ipairs(rows) do
		local step = steps[index]
		local fits = step ~= nil and top + ROW_HEIGHT <= STEPS_BOTTOM
		row:SetShown(fits)
		row.step, row.index = fits and step or nil, fits and index or nil
		if fits then
			---@cast step -?
			row:SetPoint("TOPLEFT", STEPS_LEFT, -top)
			Window.SetStepRow(row, index, step.title, step.detail, step)
			row:SetAlpha(step.optional and 0.6 or 1)
			top = top + ROW_HEIGHT
			if step.checklist then
				top, check = Overview.LayoutChecklist(
					checks,
					check,
					content,
					step,
					STEPS_LEFT + CHECK_LEFT,
					top + 2,
					STEPS_WIDTH - CHECK_LEFT - 8,
					STEPS_BOTTOM
				)
			end
			top = top + STEP_GAP
		end
	end
	Overview.HideChecklist(checks, check)
end

---@param content Frame
local function Refresh(content)
	local route = ns.Route()
	local first, others = Overview.Split(route)
	local ready = ns.State.Ready()
	-- The featured card is the chosen journey's: the one its session and order belong to.
	local chosen = first ~= nil and route.chosen and first.key == route.journey
	local info = ns.Session.Info()
	local empty = chosen and info.empty
	local custom = chosen and ns.Order.IsCustom()
	emptyText:SetShown(first == nil)
	emptyText:SetText(ready and L.NO_JOURNEY or L.LOADING)
	featured:SetShown(first ~= nil)
	heading:SetShown(first ~= nil)
	session:SetShown(first ~= nil)
	session:GenerateMenu()
	divider:SetShown(first ~= nil and #others > 0)
	if first then
		RefreshFeatured(first, custom)
	end
	sessionEmpty:SetShown(empty)
	RefreshSteps(content, (first and not empty) and route.steps or {})
	-- How long the steps should take, a heuristic: "About 25 min".
	local line
	if chosen and info.pending then
		line = L.SESSION_PENDING
	elseif chosen and info.seconds then
		line = L.SESSION_ABOUT:format(math.ceil(info.seconds / 60))
	end
	sessionText:SetShown(line ~= nil)
	sessionText:SetText(line or "")
	resetButton:SetShown(custom)
	for index, card in ipairs(grid) do
		local journey = others[index]
		card:SetShown(journey ~= nil)
		if journey then
			RefreshGrid(card, journey)
		end
	end
end

Window.AddTab({ key = "journeys", label = L.TAB_JOURNEYS, Build = Build, Refresh = Refresh })
