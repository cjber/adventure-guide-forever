---@type string, AGFNamespace
local _, ns = ...
local L = ns.L
local Window, Overview = ns.Window, ns.Overview

-- The window's Journeys tab (docs/design.md §2.19): the panel's overview at the window's size. The card the route
-- follows is featured over its zone's map with its next steps beside it, and the others run four across under the
-- divider. The cards, steps and Show on Map choose and guide exactly as the panel's do. Over the steps, how long the
-- player has (Session.lua); under them, how long it should take and, while the order is the player's own, the way back
-- to the suggested one (§2.20). A dungeon card has Go to entrance, from Tweaks Forever.

local FEATURED_WIDTH, FEATURED_HEIGHT, FEATURED_SPAN = Window.Cards.width, Window.Cards.height, 640
local STEP_ROWS, ROW_HEIGHT, STEP_GAP, STEP_HEAD, STEP_FOOT = 3, 44, 4, 18, 14
local COLUMNS, GRID_GAP, GRID_SPAN, GRID_PAD = Window.Cards.columns, Window.Cards.gap, 320, Window.Cards.pad
local BUTTON_WIDTH, BUTTON_HEIGHT, ENTRANCE_WIDTH = 104, 22, 112
local BAR_LABEL_GAP = 8
-- The session picker sits above the first step, beside the heading.
local SESSION_WIDTH, SESSION_HEIGHT, SESSION_RAISE = 96, 25, 8
-- A town's checklist lines sit under its row, in from the ring.
local CHECK_LEFT = 40

---@class AGFWindowJourneyCard : AGFWindowFeatureCard, AGFCardButton
---@field Counts? FontString
---@field Foot FontString
---@field Bar AGFProgressBar
---@field EntranceButton Button
---@field DungeonButton Button
---@field GuideButton? Button
---@field Action? Button
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
---@type FontString
local alternatives
---@type Texture
local divider
---@type FontString
local emptyText
---@type Button
local session
---@type FontString
local sessionText
---@type FontString
local sessionEmpty
---@type Button
local resetButton
local page = 1
local Refresh
---@type Button
local previousPage
---@type Button
local nextPage
---@type FontString
local pageText

local LEFT, TOP = Window.LEFT, Window.TOP
local WIDTH = Window.Cards.available
local GRID_TOP = Window.Cards.gridTop + 24
local GRID_WIDTH = Window.Cards.gridWidth
local GRID_HEIGHT = Window.INSET_HEIGHT - 40 - GRID_TOP
local STEPS_LEFT = Window.Cards.sideLeft
local STEPS_WIDTH = Window.Cards.sideWidth
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
	elseif ns.Guidance.Status() == "paused" then
		ns.StartRoute()
	end
	local step = ns.Route().steps[1]
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
			ns.Dungeons.GoEntrance(instance)
		end
	end)
	return button
end

---@param parent Frame
---@param isFeatured boolean
---@return AGFWindowJourneyCard
local function CreateCard(parent, isFeatured)
	local feature, content = Window.CreateFeatureCard(parent, isFeatured, GRID_HEIGHT)
	local card = feature --[[@as AGFWindowJourneyCard]]
	local height = isFeatured and FEATURED_HEIGHT or GRID_HEIGHT
	card.Bar = Overview.CreateBar(content)
	card.Foot = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	card.Foot:SetJustifyH(isFeatured and "RIGHT" or "LEFT")
	card.Foot:SetWordWrap(false)
	card.EntranceButton = CreateEntranceButton(card, content)
	card.DungeonButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate") --[[@as Button]]
	card.DungeonButton:SetSize(112, BUTTON_HEIGHT)
	card.DungeonButton:SetText(L.DUNGEON_OPEN_PAGE)
	card.DungeonButton:SetPoint("BOTTOMLEFT", 12, isFeatured and 2 or 28)
	card.DungeonButton:SetScript("OnClick", function()
		local instance = card.journey and Overview.Entrance(card.journey)
		if instance then
			Window.OpenDungeon(instance)
		end
	end)
	if isFeatured then
		card.GuideButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate") --[[@as Button]]
		card.GuideButton:SetSize(112, BUTTON_HEIGHT)
		card.GuideButton:SetPoint("BOTTOMLEFT", 12, 2)
		card.GuideButton:SetText(L.GUIDE_OPEN)
		card.GuideButton:SetScript("OnClick", function()
			if card.journey then
				Window.OpenGuide(card.journey, assert(card:GetParent()))
			end
		end)
		card.Tag = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		card.Tag:SetPoint("TOPRIGHT", -16, -16)
		card.Tag:SetText(L.SUGGESTED)
		card.Title = content:CreateFontString(nil, "ARTWORK", Window.FONT_TITLE)
		card.Title:SetTextColor(Window.TITLE_INK[1], Window.TITLE_INK[2], Window.TITLE_INK[3])
		card.Reason = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
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
		card.Action = button
		button:SetText(L.START_ADVENTURE)
		button:SetScript("OnClick", function()
			local route = ns.Route()
			if card.journey and not ns.Setting("wanderer") and not ns.Guidance.Owns() then
				if route.chosen and route.journey == card.journey.key then
					ns.StartRoute()
				else
					ns.Choose(card.journey.key, true)
				end
			else
				ShowOnMap(card)
			end
		end)
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
		-- Wrapped, never cut: up to three lines beside the ring, centred on it.
		card.Title = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		card.Reason = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		for _, text in ipairs({ card.Title, card.Reason }) do
			text:SetJustifyH("LEFT")
			text:SetWordWrap(true)
		end
		card.EntranceButton:SetPoint("BOTTOMRIGHT", -GRID_PAD + 4, GRID_PAD - 6)
	end
	Window.LayoutCardHeading(card, isFeatured, 3)
	if isFeatured then
		card.Title:ClearAllPoints()
		card.Title:SetPoint("TOPLEFT", 76, -32)
		card.Title:SetPoint("RIGHT", -16, 0)
		card.Title:SetWordWrap(true)
		card.Title:SetMaxLines(2)
		card.Reason:ClearAllPoints()
		card.Reason:SetPoint("TOPLEFT", 18, -82)
		card.Reason:SetPoint("RIGHT", -18, 0)
		card.Reason:SetWordWrap(true)
		card.Reason:SetMaxLines(2)
	end
	card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	card.noBack = true
	card:SetScript("OnClick", Overview.CardClick)
	card:HookScript("OnEnter", Overview.CardTooltip)
	card:HookScript("OnLeave", GameTooltip_Hide)
	return card
end

-- The card's zone map round its next town, its kind in the ring, its title, and a dungeon's Go to entrance: greyed
-- while Tweaks Forever can't say where the entrance is. Returns why, for the featured card to say.
---@param card AGFWindowJourneyCard
---@param journey AGFJourney
---@param span number
---@return string? note
local function RefreshCard(card, journey, span)
	local route = ns.Route()
	card.journey, card.state = journey, route.chosen and route.journey == journey.key and "chosen" or "shown"
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
	card.DungeonButton:SetShown(instance ~= nil)
	card.EntranceButton:SetEnabled(point ~= nil and not ns.Setting("wanderer"))
	Overview.RefreshCardTooltip(card)
	return note
end

---@param journey AGFJourney
---@param custom boolean the player's own order
local function RefreshFeatured(journey, custom)
	featured.GuideButton:SetShown(Overview.Entrance(journey) == nil)
	local note = RefreshCard(featured, journey, FEATURED_SPAN)
	local tag = featured.Tag --[[@as FontString]]
	local route = ns.Route()
	local step = route.steps[1]
	tag:SetText(custom and L.ORDER_CUSTOM or (route.chosen and L.YOUR_CHOICE or L.RECOMMENDED))
	featured.Title:SetText(step and step.title or journey.title)
	featured.Reason:SetText(
		Overview.DropLine(journey) or (step and step.reason) or journey.reason or Overview.HubLine(journey) or ""
	)
	local action = assert(featured.Action)
	local status = ns.Guidance.Status()
	local paused = status == "paused"
	local actionText = (ns.Setting("wanderer") or ns.Guidance.Owns()) and L.SHOW_ON_MAP
		or paused and L.RESUME_ADVENTURE
		or L.START_ADVENTURE
	action:SetText(actionText)
	action:SetEnabled(step ~= nil)
	local counts = featured.Counts --[[@as FontString]]
	counts:SetText(journey.title)
	counts:SetShown(step ~= nil)
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
	local foot = label or Overview.Stops(journey)
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
	row:SetScript("OnLeave", ns.Overview.RowLeave)
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

local function SessionLabel(minutes)
	return minutes == 0 and L.SESSION_UNLIMITED or L.SESSION_MINUTES:format(minutes)
end

-- Forever build 70009 crashes in Blizzard_Menu.AcquireMenu when opening the native picker.
-- Keep this small selector entirely in addon-owned frames, outside the native menu pool.
---@param content Frame
---@return Button
local function CreateSessionPicker(content)
	local button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate") --[[@as Button]]
	button:SetSize(SESSION_WIDTH, SESSION_HEIGHT)
	button:SetPoint("TOPRIGHT", content, "TOPLEFT", STEPS_LEFT + STEPS_WIDTH, -(TOP - SESSION_RAISE))
	local popup = CreateFrame("Frame", "AdventureGuideForeverSessionPicker", button)
	popup:SetSize(144, #ns.Session.LENGTHS * 26 + 12)
	popup:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -2)
	popup:SetFrameStrata("DIALOG")
	popup:EnableMouse(true)
	local background = popup:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0.04, 0.03, 0.02, 1)
	local choices = {}
	for index, minutes in ipairs(ns.Session.LENGTHS) do
		local choice = CreateFrame("Button", nil, popup, "UIPanelButtonTemplate")
		choice:SetSize(132, 24)
		choice:SetPoint("TOPLEFT", 6, -6 - (index - 1) * 26)
		choice:SetText(SessionLabel(minutes))
		choice:SetScript("OnClick", function()
			popup:Hide()
			ns.Session.Set(minutes)
			button:SetText(SessionLabel(ns.Session.Get()))
		end)
		choices[index] = choice
	end
	popup:SetScript("OnShow", function(self)
		for index, minutes in ipairs(ns.Session.LENGTHS) do
			choices[index]:SetEnabled(ns.Session.Get() ~= minutes)
		end
		self:RegisterEvent("GLOBAL_MOUSE_DOWN")
	end)
	popup:SetScript("OnHide", function(self)
		self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
	end)
	popup:SetScript("OnEvent", function(self)
		if not self:IsMouseOver() and not button:IsMouseOver() then
			self:Hide()
		end
	end)
	popup:Hide()
	table.insert(UISpecialFrames, "AdventureGuideForeverSessionPicker")
	button:SetScript("OnClick", function()
		popup:SetShown(not popup:IsShown())
	end)
	button:HookScript("OnHide", function()
		popup:Hide()
	end)
	return button
end

---@param content Frame
local function Build(content)
	featured = CreateCard(content, true)
	featured:SetPoint("TOPLEFT", LEFT, -TOP)
	heading = Window.Heading(content, L.DO_THIS_NEXT)
	heading:SetPoint("TOPLEFT", STEPS_LEFT + 2, -TOP)
	session = CreateSessionPicker(content)
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
	alternatives = Window.Heading(content, L.OTHER_ADVENTURES)
	alternatives:SetPoint("TOPLEFT", LEFT + 2, -(Window.Cards.gridTop + 3))
	for index = 1, COLUMNS do
		local card = CreateCard(content, false)
		card:SetPoint("TOPLEFT", LEFT + (index - 1) * (GRID_WIDTH + GRID_GAP), -GRID_TOP)
		grid[index] = card
	end
	previousPage, nextPage, pageText = Window.CreatePager(content, function()
		page = math.max(1, page - 1)
		Refresh(content)
	end, function()
		page = page + 1
		Refresh(content)
	end)
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
Refresh = function(content)
	local route = ns.Route()
	local first, others = Overview.Split(route)
	local ready = ns.State.Ready()
	-- The featured card is the chosen journey's: the one its session and order belong to.
	local chosen = first ~= nil and route.chosen and first.key == route.journey
	local info = ns.Session.Info()
	local empty = chosen and info.empty
	local custom = chosen and ns.Order.IsCustom()
	emptyText:SetShown(first == nil)
	emptyText:SetText((ns.SourceHint and ns.SourceHint()) or (ready and L.NO_JOURNEY or L.LOADING))
	featured:SetShown(first ~= nil)
	heading:SetShown(first ~= nil)
	session:SetShown(first ~= nil)
	session:SetText(SessionLabel(ns.Session.Get()))
	divider:SetShown(first ~= nil and #others > 0)
	alternatives:SetShown(#others > 0)
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
	local pages
	page, pages = Window.ClampPage(page, #others, COLUMNS)
	previousPage:SetShown(pages > 1)
	nextPage:SetShown(pages > 1)
	pageText:SetShown(pages > 1)
	previousPage:SetEnabled(page > 1)
	nextPage:SetEnabled(page < pages)
	pageText:SetText(L.JOURNEY_PAGE:format(page, pages))
	for index, card in ipairs(grid) do
		local journey = others[(page - 1) * COLUMNS + index]
		card:SetShown(journey ~= nil)
		if journey then
			RefreshGrid(card, journey)
		end
	end
end

Window.AddTab({ key = "journeys", label = L.TAB_JOURNEYS, Build = Build, Refresh = Refresh })
