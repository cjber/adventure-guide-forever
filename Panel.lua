---@type string, AGFNamespace
local _, ns = ...
local L = ns.L
local Art = ns.Art
local Overview = ns.Overview
local KIND_ICONS, ShowTooltip = Overview.KIND_ICONS, Overview.ShowTooltip
local RowEnter, RowClick, CardClick, CardTooltip =
	Overview.RowEnter, Overview.RowClick, Overview.CardClick, Overview.CardTooltip
local HubLine, DropLine, Progress, IconStep, Stops =
	Overview.HubLine, Overview.DropLine, Overview.Progress, Overview.IconStep, Overview.Stops
local CreateBar, SetBar = Overview.CreateBar, Overview.SetBar

local PAD = 8
local ROW_HEIGHT = 44
-- A row's detail runs under the skip button, to 10px short of the row's edge; the tag follows it within that room.
local DETAIL_WIDTH = 230
local GROUP_ICON = 12
local ROW_GAP = 2
local CARD_HEIGHT = 86
local CARD_GAP = 4
-- A card not chosen while another is (docs/design.md §2.2): the Settings list's collapsible category header, its "+"
-- saying the row opens, at its own 26px height (ROW_ART the tiling middle, ROW_CAPS the caps at their atlas size),
-- with the kind icon alone, so nothing is squashed and the chosen card's steps start near the top.
local COMPACT_HEIGHT, COMPACT_ICON = 26, 16
local ROW_ART = "_options_listexpand_middle"
local ROW_CAPS = { { "options_listexpand_left", 12, "LEFT" }, { "options_listexpand_right", 28, "RIGHT" } }
local CARD_RING, CARD_ICON = 46, 18
-- A card's text column: its title, subline and reason are this wide. The minutes and group tag at its right sit this
-- far inside it, clear of the card's bevel (Panel.xml).
local CARD_TEXT, CARD_INSET = 212, 8
-- The honest-coverage line under the cards: two lines of GameFontDisableSmall.
local UNLISTED_HEIGHT = 26
local EMPTY_HEIGHT = 40
-- The content above the cards: the header 4px down and 34px tall, then 6px to the first card.
local LIST_TOP = 4 + 34 + 6
-- Something new (docs/design.md §2.13): the Adventure Guide's own "new" mark (CSV:2024) on a card the character
-- hasn't been offered before, over its ring's top-right, or beside a one-line row's "+"; its micro button's alert
-- (CSV:2025) on the tab.
local NEW_MARK, NEW_SIZE, NEW_COMPACT = "adventureguide-icon-whatsnew", 24, 18
local TAB_PIP = "adventureguide-microbutton-alert"
-- The chosen card keeps this art and is lit instead: the renown card's pressed art is drawn a few pixels over, which
-- reads as the card slipping out of line.
local CARD_ART = "ui-journeys-renown-button"
-- The chapter track (docs/design.md §2.3): Blizzard's delve squares at 12px, with their meanings kept
-- (RewardTrackTemplates.lua:427-436): done, the one most recently finished in green, the rest grey.
local TRACK_MAX, SQUARE, SQUARE_GAP = 8, 12, 3
-- The search (docs/design.md §2.4): 3 characters or more put up to 10 quests in place of the cards; a locked one lists
-- why, unmet lines first, up to 6 (its tooltip has them all).
local SEARCH_MIN, SEARCH_ROWS, WHY_LINES, RESULT_HEIGHT, WHY_HEIGHT = 3, 10, 6, 24, 14
-- The quest log's own geometry: a 29px search bar above the list, a 40px footer below it for the Go button.
local TOP_BAR = 29
local SKIPPED_HEIGHT = 16
-- A step's kind badge (Overview.CreateBadge) on its 26 ring.
local BADGE, BADGE_OUT = 14, 3
local ORDER_HEIGHT, SESSION_EMPTY_HEIGHT, CHECK_LEFT = 16, 30, 46
local ASIDE_HEIGHT, ASIDE_GAP = 14, 2
local FOOTER = 40
-- The map overview uses compact full-width rows. The renown atlas has a 6px empty margin;
-- slicing its rim keeps the same card art at this shorter height.
local ART_BLEED, ART_SLICE = 6, 12
local OVERVIEW_WIDTH = 288 -- The chosen journey's checklist width.
local OVERVIEW_HEIGHT, OVERVIEW_GAP, OVERVIEW_ICON, OVERVIEW_BADGE, OVERVIEW_SPAN = 64, 4, 30, 13, 240
local OVERVIEW_INSET, OVERVIEW_TEXT = 12, 54

---@type Frame?
local panel
---@type AGFTabButton?
local guideTab
---@type AGFTabButton?
local questsTab
---@type Texture?
local tabPip
---@type AGFRouteRow[]
local rows = {}
---@type AGFJourneyCard[]
local cards = {}
---@type Frame?
local list
---@type Frame?
local content
---@type AGFSearchBox?
local searchBox
-- Defined below the builders; the search box's handler needs it.
local Refresh
---@type FontString?
local emptyText
-- One line per aside the player still wants (Asides.All), from the top of the list.
---@type AGFAsideLine[]
local asideLines = {}
---@type AGFOverviewCard[]
local overviewCards = {}
---@type Button
local moreButton
---@type FontString
local moreText
---@type Frame
local viewport
---@type AGFScrollFrame?
local scroll
---@type Frame?
local scrollContent
-- The header's title, and the player's zone and level under it in the overview.
---@type FontString?
local headerTitle
---@type FontString?
local subtitle
---@type FontString?
local unlistedText
---@type FontString?
local queuedText
---@type Button?
local stopButton
-- The header's back arrow, and the compass it pushes aside while a card is chosen.
---@type Button?
local backButton
---@type Texture?
local compass
---@type AGFSearchRow[]
local results = {}
---@type Frame?
local track
---@type Button?
local skippedButton
---@type Texture[]
local squares = {}
-- The chosen journey's order line over its rows while the order is the player's (docs/design.md §2.20).
---@type Frame
local orderLine
-- The empty session's line in place of the rows.
---@type FontString
local sessionEmpty
-- The town checklist's lines under their rows.
---@type AGFCheckLine[]
local checks = {}

-- The aside's line above the cards.
---@class AGFSkipButton : Button
---@field Icon Texture the X, shaded apart from the highlight

---@class AGFAsideLine : Button
---@field Icon Texture
---@field Text FontString
---@field Skip AGFSkipButton
---@field aside? AGFAside the aside it draws

---@class AGFRouteRow : Button, AGFDraggableRow
---@field Selected AGFArtSlice
---@field Ring Texture
---@field Number Texture
---@field Title FontString
---@field Detail FontString
---@field Group Texture
---@field Tag FontString
---@field SkipButton AGFSkipButton
---@field Kind AGFBadge the step's kind, badged on its ring
---@field step? AGFStep
---@field index? integer

---@param row AGFRouteRow
---@param atlas string a square icon, so the button's highlight is the icon itself
---@param size number
---@param tip fun(): string
---@param action fun(step: AGFStep)
---@return AGFSkipButton
local function CreateRowIcon(row, atlas, size, tip, action)
	local button = CreateFrame("Button", nil, row) --[[@as AGFSkipButton]]
	button:SetSize(size, size)
	button.Icon = button:CreateTexture(nil, "ARTWORK")
	Art.Fit(button.Icon, atlas, size, size)
	button.Icon:SetPoint("CENTER")
	button:SetHighlightAtlas(atlas, "ADD")
	button:SetScript("OnClick", function()
		if row.step then
			action(row.step)
		end
	end)
	button:SetScript("OnEnter", function(self)
		ShowTooltip(self, { tip() })
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	return button
end

-- A red X at rest reads as an error, so a skip shows only while its line is under the mouse: grey, then red once the
-- mouse is on it, as the stock lists do. Right-click keeps the same skip in the menu.
---@param button AGFSkipButton
---@param line Frame
local function HoverOnly(button, line)
	local function Shade()
		local on = button:IsMouseOver()
		button:SetAlpha((on or line:IsMouseOver()) and 1 or 0)
		button.Icon:SetDesaturated(not on)
		button.Icon:SetAlpha(on and 1 or 0.6)
	end
	Shade()
	line:HookScript("OnEnter", Shade)
	line:HookScript("OnLeave", Shade)
	button:HookScript("OnEnter", Shade)
	button:HookScript("OnLeave", Shade)
end

---@param parent Frame
---@return AGFRouteRow
local function CreateRow(parent)
	local row = CreateFrame("Button", nil, parent) --[[@as AGFRouteRow]]
	row:SetHeight(ROW_HEIGHT)
	-- The Classic mount and pet collection list rows: background, hover and selected art.
	row.Selected = ns.Window.RowArt(row, true) --[[@as AGFArtSlice]]

	row.SkipButton = CreateRowIcon(row, "common-icon-redx", 14, function()
		return ns.L.SKIP_STEP
	end, function(step)
		ns.Skip(step.key, step.title)
	end)
	row.SkipButton:SetPoint("TOPRIGHT", -6, -7)

	row.Ring = row:CreateTexture(nil, "ARTWORK")
	row.Ring:SetAtlas("adventureguide-ring")
	row.Ring:SetSize(26, 26)
	row.Ring:SetPoint("LEFT", 6, 0)
	row.Number = row:CreateTexture(nil, "OVERLAY")
	row.Number:SetPoint("CENTER", row.Ring)

	row.Title = row:CreateFontString(nil, "ARTWORK", "GameFontNormalMed3")
	row.Title:SetPoint("TOPLEFT", row.Ring, "TOPRIGHT", 8, 4)
	row.Title:SetPoint("RIGHT", row.SkipButton, "LEFT", -4, 0)
	row.Title:SetJustifyH("LEFT")
	row.Title:SetWordWrap(false)

	row.Detail = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.Detail:SetPoint("TOPLEFT", row.Title, "BOTTOMLEFT", 0, -4)
	row.Detail:SetJustifyH("LEFT")
	row.Detail:SetWordWrap(false)
	-- Blizzard's group quest tag (QUEST_TAG_ATLAS), after the detail when a quest at the stop needs a group.
	row.Group = row:CreateTexture(nil, "ARTWORK")
	row.Group:SetAtlas("questlog-questtypeicon-group")
	row.Group:SetSize(GROUP_ICON, GROUP_ICON)
	row.Group:SetPoint("LEFT", row.Detail, "RIGHT", 4, 0)
	row.Tag = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	row.Tag:SetText(ns.L.OPTIONAL)

	row:SetScript("OnEnter", RowEnter)
	row:SetScript("OnLeave", GameTooltip_Hide)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetScript("OnClick", RowClick)
	HoverOnly(row.SkipButton, row)
	row.Kind = Overview.CreateBadge(row, row.Ring, BADGE, BADGE_OUT)
	Overview.Draggable(row, rows, function()
		Refresh()
	end)
	return row
end

-- Back to every suggestion: clears the choice and stops the route AGF started for it (ns.Choose).
local function Back()
	if ns.Route().chosen then
		GameTooltip_Hide()
		ns.Choose(nil)
	end
end

---@param parent Frame
---@return Frame
local function BuildHeader(parent)
	local header = CreateFrame("Frame", nil, parent)
	header:SetPoint("TOPLEFT", PAD, -4)
	header:SetPoint("RIGHT", -PAD, 0)
	header:SetHeight(34)
	-- The game's own back arrow (CSV:4624), as Forever's character creation draws on its Back button; shown only while
	-- a card is chosen (Refresh). A right-click anywhere on the header goes back too.
	backButton = CreateFrame("Button", nil, header) --[[@as Button]]
	backButton:SetSize(22, 22)
	backButton:SetPoint("LEFT", 0, 0)
	backButton:SetNormalAtlas("common-icon-backarrow")
	backButton:SetHighlightAtlas("common-icon-backarrow", "ADD")
	backButton:SetScript("OnClick", Back)
	backButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, L.ALL_SUGGESTIONS)
		if ns.Integrations.Owns() then
			GameTooltip_AddNormalLine(GameTooltip, L.BACK_STOPS_ROUTE)
		end
		GameTooltip:Show()
	end)
	backButton:SetScript("OnLeave", GameTooltip_Hide)
	backButton:Hide()
	header:EnableMouse(true)
	header:SetScript("OnMouseUp", function(_, mouseButton)
		if mouseButton == "RightButton" then
			Back()
		end
	end)
	-- The guide in its own window (Window.lua): the map frame's maximize art at 22, mirroring the compass at the left.
	local expand = CreateFrame("Button", nil, header)
	-- 22 high at the art's own 18x19.
	expand:SetSize(22 * 18 / 19, 22)
	expand:SetPoint("RIGHT", -4, 0)
	expand:SetNormalAtlas("RedButton-Expand")
	expand:SetPushedAtlas("RedButton-Expand-Pressed")
	expand:SetHighlightAtlas("RedButton-Highlight", "ADD")
	expand:SetScript("OnClick", function()
		ns.OpenWindow()
	end)
	expand:SetScript("OnEnter", function(self)
		ShowTooltip(self, { L.OPEN_IN_WINDOW })
	end)
	expand:SetScript("OnLeave", GameTooltip_Hide)
	compass = header:CreateTexture(nil, "ARTWORK")
	compass:SetAtlas("islands-queue-prop-compass")
	compass:SetSize(30, 30)
	compass:SetPoint("LEFT", 2, 0)
	headerTitle = header:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	headerTitle:SetText(ns.TITLE)
	-- In the overview, the player's zone and level under the title (Refresh).
	subtitle = header:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	subtitle:SetPoint("TOP", headerTitle, "BOTTOM", 0, -3)
	return header
end

---@class AGFJourneyCardIcon : Frame
---@field Border Texture
---@field Icon Texture

-- What a card's click and tooltip read, on the chosen view's cards and the overview's alike.
---@class AGFCardButton : Button
---@field journey? AGFJourney
---@field state? "shown"|"chosen"|"compact"
---@field detail? string the map overview row's full detail

-- AdventureGuideForeverJourneyCardTemplate (Panel.xml).
---@class AGFJourneyCard : AGFCardButton
---@field NormalTexture Texture
---@field PushedTexture Texture
---@field IconFrame AGFJourneyCardIcon
---@field Title FontString
---@field Subline FontString
---@field Reason FontString
---@field Group Texture
---@field Travel FontString
---@field UpdateHighlightForState fun(self: AGFJourneyCard)
---@field Caps Texture[]
---@field New Texture

-- One search result: the quest and where it starts, and for a locked one a lock and why (docs/design.md §2.4). One
-- open now joins the route with a shift-click, and wears the tradeskill favourite's star while it does (§2.18); an
-- orange or red one, which no route takes, does not (`open` false).
---@class AGFSearchRow : Frame
---@field Lock Texture
---@field Star Texture
---@field id? integer
---@field open? boolean
---@field Title FontString
---@field Zone FontString
---@field Checks Texture[]
---@field Lines FontString[]
---@field why AGFWhyLine[]

---@param parent Frame
---@return AGFSearchRow
local function CreateResult(parent)
	local row = CreateFrame("Frame", nil, parent) --[[@as AGFSearchRow]]
	row:EnableMouse(true)
	row.why = {}
	row.Lock = row:CreateTexture(nil, "ARTWORK")
	row.Lock:SetAtlas("questlog-questtypeicon-lock")
	row.Lock:SetSize(18, 18)
	row.Lock:SetPoint("TOPLEFT", 4, -2)
	row.Star = row:CreateTexture(nil, "ARTWORK")
	Art.Fit(row.Star, "tradeskills-star", 14, 14)
	row.Star:SetPoint("TOPRIGHT", -4, -5)
	row.Zone = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.Zone:SetPoint("TOPRIGHT", -22, -6)
	row.Zone:SetJustifyH("RIGHT")
	row.Title = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	row.Title:SetPoint("TOPLEFT", 26, -4)
	row.Title:SetPoint("RIGHT", row.Zone, "LEFT", -6, 0)
	row.Title:SetJustifyH("LEFT")
	row.Title:SetWordWrap(false)
	row.Checks, row.Lines = {}, {}
	for index = 1, WHY_LINES do
		local top = -(RESULT_HEIGHT + (index - 1) * WHY_HEIGHT) + 2
		local check = row:CreateTexture(nil, "ARTWORK")
		check:SetAtlas("ui-questtracker-tracker-check")
		check:SetSize(12, 12)
		check:SetPoint("TOPLEFT", 26, top)
		local line = row:CreateFontString(nil, "ARTWORK", "GameFontRedSmall")
		line:SetPoint("TOPLEFT", 40, top)
		line:SetPoint("RIGHT", -4, 0)
		line:SetJustifyH("LEFT")
		line:SetWordWrap(false)
		row.Checks[index], row.Lines[index] = check, line
	end
	-- Every line as a tooltip, in the game's own error and disabled voices.
	row:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, self.Title:GetText())
		for _, why in ipairs(self.why) do
			if why.met then
				GameTooltip_AddDisabledLine(GameTooltip, why.text)
			else
				GameTooltip_AddErrorLine(GameTooltip, why.text)
			end
		end
		if self.open and self.id then
			GameTooltip_AddInstructionLine(GameTooltip, ns.Pinned({ self.id }) and L.SHIFT_REMOVE or L.SHIFT_ADD)
		end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	row:SetScript("OnMouseUp", function(self, mouseButton)
		if mouseButton == "LeftButton" and IsShiftKeyDown() and self.open and self.id then
			ns.TogglePinned({ self.id })
			GameTooltip_Hide()
		end
	end)
	return row
end

-- An aside (Asides.lua) above the cards: its icon, its line and a row's skip. Its click goes to its place when it
-- has one; right-click is its menu.
---@param parent Frame
---@return AGFAsideLine
local function CreateAsideLine(parent)
	local line = CreateFrame("Button", nil, parent) --[[@as AGFAsideLine]]
	line:SetHeight(ASIDE_HEIGHT)
	line:SetPoint("RIGHT", -10, 0)
	line.Icon = line:CreateTexture(nil, "ARTWORK")
	line.Icon:SetSize(ASIDE_HEIGHT, ASIDE_HEIGHT)
	line.Icon:SetPoint("LEFT")
	line.Skip = CreateFrame("Button", nil, line) --[[@as AGFSkipButton]]
	line.Skip:SetSize(ASIDE_HEIGHT, ASIDE_HEIGHT)
	line.Skip:SetPoint("RIGHT")
	line.Skip.Icon = line.Skip:CreateTexture(nil, "ARTWORK")
	line.Skip.Icon:SetAtlas("common-icon-redx")
	line.Skip.Icon:SetAllPoints()
	line.Skip:SetHighlightAtlas("common-icon-redx", "ADD")
	line.Skip:SetScript("OnClick", function()
		if line.aside then
			ns.Asides.Skip(line.aside.key)
		end
	end)
	line.Skip:SetScript("OnEnter", function(self)
		ShowTooltip(self, { L.SKIP })
	end)
	line.Skip:SetScript("OnLeave", GameTooltip_Hide)
	line.Text = line:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	line.Text:SetPoint("LEFT", line.Icon, "RIGHT", 4, 0)
	line.Text:SetPoint("RIGHT", line.Skip, "LEFT", -4, 0)
	line.Text:SetJustifyH("LEFT")
	line.Text:SetWordWrap(false)
	line:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	line:SetScript("OnClick", function(self, mouseButton)
		local aside = self.aside
		if aside and mouseButton == "RightButton" then
			ns.Asides.Open(self, "MENU_ADVENTURE_GUIDE_FOREVER_ASIDE", aside)
		elseif aside then
			ns.Asides.Go(aside)
		end
	end)
	-- A long line is cut short, so its tooltip has it whole, and says where a click goes when it goes anywhere.
	line:SetScript("OnEnter", function(self)
		local aside = self.aside
		if not aside then
			return
		end
		local provider = ns.Integrations.Provider()
		local lines = { aside.text }
		lines[2] = aside.place
				and not ns.Setting("wanderer")
				and (provider and L.CLICK_TRAVEL:format(provider) or L.CLICK_WAYPOINT)
			or nil
		ShowTooltip(self, lines)
	end)
	line:SetScript("OnLeave", GameTooltip_Hide)
	HoverOnly(line.Skip, line)
	return line
end

---@class AGFOverviewCard : AGFCardButton
---@field Icon AGFZoneIcon
---@field New Texture
---@field Title FontString
---@field Reason FontString
---@field Foot FontString
---@field Bar AGFProgressBar

---@param parent Frame
---@return AGFOverviewCard
local function CreateOverviewCard(parent)
	local card = CreateFrame("Button", nil, parent) --[[@as AGFOverviewCard]]
	card:SetHeight(OVERVIEW_HEIGHT)
	for _, layer in ipairs({ "BACKGROUND", "HIGHLIGHT" }) do
		local art = card:CreateTexture(nil, layer)
		art:SetAtlas(CARD_ART)
		art:SetTextureSliceMargins(ART_SLICE, ART_SLICE, ART_SLICE, ART_SLICE)
		art:SetPoint("TOPLEFT", -ART_BLEED, ART_BLEED)
		art:SetPoint("BOTTOMRIGHT", ART_BLEED, -ART_BLEED)
		if layer == "HIGHLIGHT" then
			art:SetBlendMode("ADD")
			art:SetAlpha(0.4)
		end
	end
	card.Icon = ns.ZoneIcon.Create(card, OVERVIEW_ICON, OVERVIEW_BADGE)
	card.Icon:SetPoint("TOPLEFT", OVERVIEW_INSET, -14)
	card.New = card.Icon.Border:CreateTexture(nil, "OVERLAY", nil, 2)
	card.New:SetAtlas(NEW_MARK)
	card.New:SetSize(NEW_COMPACT, NEW_COMPACT)
	card.New:SetPoint("CENTER", card.Icon, "TOPRIGHT", -2, -2)
	card.Bar = CreateBar(card)
	card.Title = card:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	card.Title:SetPoint("TOPLEFT", OVERVIEW_TEXT, -10)
	card.Title:SetPoint("RIGHT", -OVERVIEW_INSET, 0)
	card.Reason = card:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	card.Reason:SetPoint("TOPLEFT", OVERVIEW_TEXT, -27)
	card.Reason:SetPoint("RIGHT", -OVERVIEW_INSET, 0)
	card.Foot = card:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	card.Foot:SetPoint("TOPRIGHT", -OVERVIEW_INSET, -44)
	card.Foot:SetJustifyH("RIGHT")
	for _, text in ipairs({ card.Title, card.Reason, card.Foot }) do
		text:SetWordWrap(false)
		text:SetMaxLines(1)
	end
	card.Title:SetJustifyH("LEFT")
	card.Reason:SetJustifyH("LEFT")
	card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	card:SetScript("OnClick", CardClick)
	card:SetScript("OnEnter", CardTooltip)
	card:SetScript("OnLeave", GameTooltip_Hide)
	return card
end

---@param parent Frame
local function BuildOverview(parent)
	for index = 1, ns.Model.MAX_JOURNEYS do
		overviewCards[index] = CreateOverviewCard(parent)
	end
	moreButton = CreateFrame("Button", nil, parent) --[[@as Button]]
	moreButton:SetHeight(OVERVIEW_HEIGHT)
	moreText = moreButton:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	local text = moreText
	text:SetPoint("LEFT", OVERVIEW_INSET, 0)
	text:SetPoint("RIGHT", -OVERVIEW_INSET, 0)
	text:SetJustifyH("LEFT")
	text:SetWordWrap(false)
	text:SetMaxLines(1)
	moreButton:SetScript("OnClick", function()
		ns.OpenWindow()
		ns.Window.Select(1)
	end)
	moreButton:SetScript("OnEnter", function(self)
		ShowTooltip(self, { moreText:GetText() })
	end)
	moreButton:SetScript("OnLeave", GameTooltip_Hide)
end

-- The cards, and the chosen card's step rows under it; the list lays them out from its top.
---@param parent Frame
---@param below Region
local function BuildJourneys(parent, below)
	list = CreateFrame("Frame", nil, parent)
	list:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -6)
	list:SetPoint("RIGHT", parent, "RIGHT", -PAD, 0)
	for index = 1, ns.Model.MAX_JOURNEYS do
		local card = CreateFrame("Button", nil, list, "AdventureGuideForeverJourneyCardTemplate") --[[@as AGFJourneyCard]]
		card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		card:SetScript("OnClick", CardClick)
		card:HookScript("OnEnter", CardTooltip)
		card:HookScript("OnLeave", GameTooltip_Hide)
		card.Caps = {}
		for _, cap in ipairs(ROW_CAPS) do
			local texture = card:CreateTexture(nil, "OVERLAY")
			texture:SetAtlas(cap[1])
			texture:SetSize(cap[2], COMPACT_HEIGHT)
			texture:SetPoint(cap[3])
			card.Caps[#card.Caps + 1] = texture
		end
		card.New = card:CreateTexture(nil, "OVERLAY", nil, 2)
		card.New:SetAtlas(NEW_MARK)
		cards[index] = card
	end
	track = CreateFrame("Frame", nil, list)
	track:SetSize(TRACK_MAX * (SQUARE + SQUARE_GAP), SQUARE)
	for index = 1, TRACK_MAX do
		local square = track:CreateTexture(nil, "ARTWORK")
		square:SetSize(SQUARE, SQUARE)
		square:SetPoint("LEFT", (index - 1) * (SQUARE + SQUARE_GAP), 0)
		squares[index] = square
	end
	for index = 1, ns.Model.MAX_STEPS do
		rows[index] = CreateRow(list)
	end
	for index = 1, SEARCH_ROWS do
		results[index] = CreateResult(list)
	end
	-- "Your order" over the chosen journey's rows while the player has moved one, and the way back as a small gold
	-- text button (docs/design.md §2.20).
	orderLine = CreateFrame("Frame", nil, list)
	orderLine:SetHeight(ORDER_HEIGHT)
	local tag = orderLine:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	tag:SetPoint("LEFT", 4, 0)
	tag:SetText(L.ORDER_CUSTOM)
	local reset = CreateFrame("Button", nil, orderLine) --[[@as Button]]
	reset:SetHeight(ORDER_HEIGHT)
	reset:SetNormalFontObject("GameFontNormalSmall")
	reset:SetHighlightFontObject("GameFontHighlightSmall")
	reset:SetText(L.ORDER_RESET)
	reset:SetWidth(reset:GetTextWidth() + 4)
	reset:SetPoint("RIGHT", -4, 0)
	reset:SetScript("OnClick", function()
		ns.Order.Reset()
	end)
	sessionEmpty = list:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	sessionEmpty:SetPoint("RIGHT", -10, 0)
	sessionEmpty:SetJustifyH("LEFT")
	sessionEmpty:SetText(L.SESSION_EMPTY)
	-- "Skipped (n)" under the cards (design §2.1), a small gold text button that opens the Skipped submenu on its own.
	skippedButton = CreateFrame("Button", nil, list) --[[@as Button]]
	skippedButton:SetHeight(SKIPPED_HEIGHT)
	skippedButton:SetNormalFontObject("GameFontNormalSmall")
	skippedButton:SetHighlightFontObject("GameFontHighlightSmall")
	skippedButton:SetScript("OnClick", function(self)
		MenuUtil.CreateContextMenu(self, function(_, root)
			root:SetTag("MENU_ADVENTURE_GUIDE_FOREVER_SKIPPED")
			ns.Menu.Skipped(root)
		end)
	end)
	emptyText = list:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	emptyText:SetPoint("TOPLEFT", 10, -8)
	emptyText:SetPoint("RIGHT", -10, 0)
	emptyText:SetJustifyH("LEFT")
	unlistedText = list:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	unlistedText:SetPoint("RIGHT", -10, 0)
	unlistedText:SetJustifyH("LEFT")
	unlistedText:SetText(L.UNLISTED)
	BuildOverview(list)
end

---@param parent Frame
local function BuildFooter(parent)
	-- No Go: choosing a card starts its route. A choice made in combat says it waits, so it never reads as failed, and
	-- a route that stopped says its card resumes it.
	queuedText = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	queuedText:SetPoint("BOTTOMLEFT", PAD, 15)
	-- Shown only while our guidance runs (design §2.1): it never stops what the player or another addon started.
	stopButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate") --[[@as Button]]
	stopButton:SetSize(90, 26)
	stopButton:SetPoint("BOTTOMRIGHT", -PAD, 8)
	stopButton:SetText(L.STOP)
	stopButton:SetScript("OnClick", ns.Stop)
end

---@param _ AGFDropdown
---@param menu AGFMenu
local function BuildSettingsMenu(_, menu)
	local function Setting(label, key)
		return menu:CreateCheckbox(label, function()
			return ns.Setting(key)
		end, function()
			ns.SetSetting(key, not ns.Setting(key))
		end)
	end
	local function Pref(label, key)
		menu:CreateCheckbox(label, function()
			return ns.Prefs()[key]
		end, function()
			local prefs = ns.Prefs()
			prefs[key] = not prefs[key]
			ns.Invalidate()
		end)
	end
	Pref(ns.L.MENU_QUESTS, "quests")
	Pref(ns.L.MENU_DUNGEONS, "dungeons")
	Pref(ns.L.MENU_BATTLEGROUNDS, "battlegrounds")
	Setting(ns.L.MENU_MAP_PINS, "showMapPins")
	-- Givers draw only with map pins on, so the box is grayed until they are (the menu polls a function).
	Setting(ns.L.MENU_GIVERS, "showQuestGivers"):SetEnabled(function()
		return ns.Setting("showMapPins")
	end)
	Setting(ns.L.MENU_TRACKER, "showTracker")
	-- Skipped steps, journeys not wanted (roadmap #17) and asides turned down, each with Show again.
	local skipped = #ns.Skipped()
	if skipped > 0 then
		ns.Menu.Skipped(menu:CreateButton(ns.L.SKIPPED:format(skipped)))
	end
	menu:CreateButton(ns.L.MENU_MORE_SETTINGS, function()
		if ns.OpenSettings then
			ns.OpenSettings()
		end
	end)
end

-- The quest log's top bar: a search box for any quest across its width, and the settings cog. No step count
-- (docs/design.md §1).
---@param panelFrame Frame
local function BuildTopBar(panelFrame)
	searchBox = CreateFrame("EditBox", nil, panelFrame, "SearchBoxTemplate") --[[@as AGFSearchBox]]
	searchBox.Instructions:SetText(L.SEARCH_QUESTS)
	searchBox:SetHeight(20)
	searchBox:SetPoint("TOPLEFT", 6, -2)
	searchBox:SetPoint("TOPRIGHT", -3, -2)
	searchBox:SetMaxLetters(60)
	searchBox:HookScript("OnTextChanged", function()
		Refresh()
	end)

	local cog = CreateFrame("DropdownButton", nil, panelFrame, "UIPanelIconDropdownButtonTemplate") --[[@as AGFDropdown]]
	cog:SetPoint("TOPRIGHT", 19, 25 - TOP_BAR)
	cog:SetupMenu(BuildSettingsMenu)
end

-- Only the chosen journey and search retain the quest log's scrolling behavior. The overview's
-- content is parented directly to the viewport, with no ScrollFrame or scrollbar in its view.
---@param scrolling boolean
local function SetScrolling(scrolling)
	---@cast content -?
	if scrolling and not scroll then
		scroll = CreateFrame("ScrollFrame", nil, viewport, "ScrollFrameTemplate") --[[@as AGFScrollFrame]]
		scroll:SetAllPoints()
		scroll.ScrollBar:ClearAllPoints()
		scroll.ScrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 8, 2)
		scroll.ScrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 8, -4)
		scrollContent = CreateFrame("Frame", nil, scroll)
		scroll:SetScrollChild(scrollContent)
		scroll:SetScript("OnSizeChanged", function(_, width)
			scrollContent:SetWidth(width)
		end)
	end
	local parent = scrolling and scrollContent or viewport
	if content:GetParent() ~= parent then
		content:SetParent(parent)
		content:ClearAllPoints()
		content:SetPoint("TOPLEFT")
		content:SetPoint("RIGHT")
	end
	if scroll then
		scroll:SetShown(scrolling)
	end
end

---@param panelFrame Frame
local function BuildContent(panelFrame)
	BuildTopBar(panelFrame)
	local body = CreateFrame("Frame", nil, panelFrame)
	body:SetPoint("TOPLEFT", 0, -TOP_BAR)
	body:SetPoint("BOTTOMRIGHT")
	CreateFrame("Frame", nil, body, "QuestLogBorderFrameTemplate")
	viewport = CreateFrame("Frame", nil, body)
	viewport:SetPoint("TOPLEFT")
	viewport:SetPoint("BOTTOMRIGHT", 0, FOOTER)
	content = CreateFrame("Frame", nil, viewport)
	content:SetPoint("TOPLEFT")
	content:SetPoint("RIGHT")
	local header = BuildHeader(content)
	BuildJourneys(content, header)
	BuildFooter(panelFrame)
end

---@param row AGFRouteRow
---@param step AGFStep
---@param index integer
local function RefreshRow(row, step, index)
	row.index = index
	ns.Window.SetNumber(row.Number, index)
	row.Title:SetText(step.title)
	-- Step 1 adds how long it takes when Shortest Path knows; its tooltip gives the way.
	local minutes = index == 1 and ns.Integrations.TravelMinutes(step)
	row.Detail:SetText(minutes and L.TRAVEL:format(step.detail, minutes) or step.detail)
	local group = (step.group or 0) > 0
	row.Group:SetShown(group)
	row.Tag:SetShown(step.optional == true)
	row.Tag:ClearAllPoints()
	row.Tag:SetPoint("LEFT", group and row.Group or row.Detail, "RIGHT", group and 4 or 6, 0)
	-- The detail has no right anchor, so the icon and tag can follow its text; a width cap cuts it short with "..."
	-- instead.
	local room = DETAIL_WIDTH
		- (group and GROUP_ICON + 4 or 0)
		- (row.Tag:IsShown() and row.Tag:GetUnboundedStringWidth() + (group and 4 or 6) or 0)
	row.Detail:SetWidth(math.min(row.Detail:GetUnboundedStringWidth(), room))
	row:SetAlpha(step.optional and 0.6 or 1)
	Art.SetSliceShown(row.Selected, index == 1)
	Overview.SetVerbIcon(row.Kind, step)
end

-- `state`: "shown" (whole: the guide drew it with none chosen), "chosen" (whole and lit) or "compact" (another is
-- shown: icon and title only).
---@param card AGFJourneyCard
---@param journey AGFJourney
---@param state "shown"|"chosen"|"compact"
---@return number height
local function RefreshCard(card, journey, state)
	local compact, chosen = state == "compact", state == "chosen"
	card.journey, card.state = journey, state
	card:SetHeight(compact and COMPACT_HEIGHT or CARD_HEIGHT)
	local ring = compact and COMPACT_ICON or CARD_RING
	card.IconFrame:SetSize(ring, ring)
	card.IconFrame:SetPoint("LEFT", compact and 12 or 15, 0)
	card.IconFrame.Border:SetShown(not compact)
	for _, cap in ipairs(card.Caps) do
		cap:SetShown(compact)
	end
	card.New:SetShown(ns.Moments.IsNew(journey.key))
	card.New:ClearAllPoints()
	if compact then
		card.New:SetSize(NEW_COMPACT, NEW_COMPACT)
		card.New:SetPoint("RIGHT", -ROW_CAPS[2][2], 0)
	else
		card.New:SetSize(NEW_SIZE, NEW_SIZE)
		card.New:SetPoint("CENTER", card.IconFrame, "TOPRIGHT", -4, -4)
	end
	local icon = compact and COMPACT_ICON or CARD_ICON
	Art.Fit(card.IconFrame.Icon, KIND_ICONS[journey.kind], icon, icon)
	card.Title:SetText(journey.title)
	card.Title:ClearAllPoints()
	if compact then
		card.Title:SetPoint("LEFT", card.IconFrame, "RIGHT", 6, 0)
	else
		card.Title:SetPoint("TOPLEFT", card.IconFrame, "TOPRIGHT", 6, 4)
	end
	card.Subline:SetShown(not compact)
	card.Reason:SetShown(not compact)
	card.Subline:SetText(journey.subline)
	card.Reason:SetText(DropLine(journey) or journey.reason or HubLine(journey) or "")
	-- Shortest Path's minutes, naming a boat or zeppelin when the subline leaves room for it.
	local travel = not compact and ns.Integrations.CardTravel(journey) or nil
	local minutes = travel and travel.minutes
	card.Travel:SetShown(minutes ~= nil)
	card.Subline:ClearAllPoints()
	card.Subline:SetPoint("TOPLEFT", card.Title, "BOTTOMLEFT", 0, -2)
	if travel and minutes then
		local crossing = travel.crossing
		local long = (crossing == "boat" and L.CARD_BY_BOAT) or (crossing == "zeppelin" and L.CARD_BY_ZEPPELIN)
		card.Travel:SetText((long or L.CARD_MINUTES):format(minutes))
		local room = CARD_TEXT - CARD_INSET - 6 - card.Subline:GetUnboundedStringWidth()
		if long and card.Travel:GetUnboundedStringWidth() > room then
			card.Travel:SetText(L.CARD_MINUTES:format(minutes))
		end
		card.Subline:SetPoint("RIGHT", card.Travel, "LEFT", -6, 0)
	end
	-- The dungeon card's own icon already says it needs a group.
	local group = not compact and (journey.group or 0) > 0 and journey.kind ~= "dungeon"
	card.Group:SetShown(group)
	card.Reason:ClearAllPoints()
	card.Reason:SetPoint("TOPLEFT", card.Subline, "BOTTOMLEFT", 0, -2)
	if group then
		card.Reason:SetPoint("RIGHT", card.Group, "LEFT", -4, 0)
	end
	-- The pushed art is the normal art, so a press moves nothing; the highlight follows it (AlphaHighlightButton).
	local art = compact and ROW_ART or CARD_ART
	card.NormalTexture:SetAtlas(art)
	card.PushedTexture:SetAtlas(art)
	card:UpdateHighlightForState()
	-- The chosen card keeps its hover highlight (its own art, added) lit, the way a stock list keeps its selected row
	-- lit, and never moves.
	if chosen then
		card:LockHighlight()
	else
		card:UnlockHighlight()
	end
	-- A card under the pointer can change journey (Not interested, a rebuild): its tooltip speaks for the new one.
	Overview.RefreshCardTooltip(card)
	return compact and COMPACT_HEIGHT or CARD_HEIGHT
end

-- The story's squares under its card, from `top` down, when the data proves the chain's length and it is 8 or fewer;
-- otherwise the card's "Chapter N" says all there is. Squares only: the card's subline already names the chapter.
---@param journey AGFJourney
---@param top number
---@return number top below the track
local function LayoutTrack(journey, top)
	---@cast track -?
	local story = journey.story
	local total = story and story.total
	local shown = total ~= nil and total <= TRACK_MAX
	track:SetShown(shown)
	if not (story and shown) then
		return top
	end
	for index, square in ipairs(squares) do
		square:SetShown(index <= total)
		square:SetAtlas(
			(index >= story.chapter and "ui-journeys-delve-level-square-grey")
				or (index == story.chapter - 1 and "ui-journeys-delve-level-square-green")
				or "ui-journeys-delve-level-square"
		)
	end
	track:SetPoint("TOPLEFT", 14, -top)
	return top + SQUARE + CARD_GAP
end

-- The shown card's rows, from `top` down, each town's checklist under its row; over them the order line while the
-- chosen journey's order is the player's, or in their place the empty session's line. `hidden` (a search, or no
-- card) hides them all.
---@param route AGFRoute
---@param top number
---@param hidden? boolean
---@return number top below the last row shown
local function LayoutRows(route, top, hidden)
	---@cast orderLine -?
	---@cast sessionEmpty -?
	local custom = not hidden and route.chosen and ns.Order.IsCustom()
	orderLine:SetShown(custom)
	if custom then
		orderLine:SetPoint("TOPLEFT", 6, -top)
		orderLine:SetPoint("TOPRIGHT", -6, -top)
		top = top + ORDER_HEIGHT + ROW_GAP
	end
	local empty = not hidden and route.chosen and ns.Session.Info().empty
	sessionEmpty:SetShown(empty)
	if empty then
		sessionEmpty:SetPoint("TOPLEFT", 10, -(top + 4))
		top = top + SESSION_EMPTY_HEIGHT
	end
	local check = 1
	for index, row in ipairs(rows) do
		---@type AGFStep?
		local step = not hidden and route.steps[index] or nil
		row.step = step
		row:SetShown(step ~= nil)
		if step then
			RefreshRow(row, step, index)
			row:SetPoint("TOPLEFT", 6, -top)
			row:SetPoint("TOPRIGHT", -6, -top)
			top = top + ROW_HEIGHT + ROW_GAP
			if step.checklist then
				---@cast list -?
				top, check = Overview.LayoutChecklist(
					checks,
					check,
					list,
					step,
					CHECK_LEFT,
					top,
					OVERVIEW_WIDTH - CHECK_LEFT - 6
				)
				top = top + ROW_GAP
			end
		end
	end
	Overview.HideChecklist(checks, check)
	return top
end

-- The client's title, asked for once when it has none cached; the search redraws as titles arrive (Attach).
---@type table<integer, boolean>
local requested = {}
---@param questID integer
---@return string?
local function QuestTitle(questID)
	local title = ns.State.QuestTitle(questID)
	if not title and not requested[questID] then
		requested[questID] = true
		C_QuestLog.RequestLoadQuestByID(questID)
	end
	return title
end

-- One result from `top` down. A quest the player can take now is a plain row, starred once added to the route; a locked
-- one gets the lock and its lines, unmet first. No ring and no Go: the search explains, and adds with a shift-click.
---@param row AGFSearchRow
---@param id integer
---@param top number
---@return number top below it
local function RefreshResult(row, id, top)
	local state, data = ns.State, ns.Data
	local names = {
		title = QuestTitle,
		race = state.RaceName,
		class = state.ClassName,
		skill = state.SkillName,
		faction = state.FactionName,
		standing = state.StandingName,
	}
	local player = state.Player()
	local why = ns.Model.Why(data, player, state.Completed(), state.Log(), id, names)
	local shown = {}
	for _, met in ipairs({ false, true }) do
		for _, line in ipairs(why) do
			if line.met == met then
				shown[#shown + 1] = line
			end
		end
	end
	-- Every line met is the quest open now: nothing to explain.
	if not (shown[1] and not shown[1].met) then
		shown = {}
	end
	row.why, row.id = shown, id
	row.open = shown[1] == nil and not ns.Model.Hard(data.quests[id], player)
	row.Star:SetShown(row.open and ns.Pinned({ id }))
	local quest = data.quests[id]
	local map = quest.zone or (quest.start and quest.start.map)
	local zone = map and (data.zones[map] or data.maps[map])
	row.Title:SetText(QuestTitle(id) or quest.title)
	row.Zone:SetText(map and (state.MapName(map) or (zone and zone.name)) or "")
	row.Lock:SetShown(shown[1] ~= nil)
	for index, line in ipairs(row.Lines) do
		local entry = shown[index]
		line:SetShown(entry ~= nil)
		row.Checks[index]:SetShown(entry ~= nil and entry.met)
		if entry then
			line:SetFontObject(entry.met and "GameFontDisableSmall" or "GameFontRedSmall")
			line:SetText(entry.text)
		end
	end
	local height = RESULT_HEIGHT + math.min(#shown, WHY_LINES) * WHY_HEIGHT
	row:SetHeight(height)
	row:SetPoint("TOPLEFT", 6, -top)
	row:SetPoint("TOPRIGHT", -6, -top)
	return top + height + ROW_GAP
end

-- The search's results in place of the cards, from the list's top; no `query` hides them.
---@param query? string
---@return number top below the last result
---@return integer found
local function LayoutResults(query)
	local found = query and ns.Model.Search(ns.Data, ns.State.Player(), query, ns.State.QuestTitle) or {}
	local top = 0
	for index, row in ipairs(results) do
		row:SetShown(found[index] ~= nil)
		if found[index] then
			top = RefreshResult(row, found[index], top)
		end
	end
	return top, #found
end

---@param card AGFOverviewCard
---@param journey AGFJourney
---@param span number
local function RefreshIcon(card, journey, span)
	local step = IconStep(journey)
	ns.ZoneIcon.Set(card.Icon, KIND_ICONS[journey.kind], step and step.map, step and step.x, step and step.y, span)
	card.New:SetShown(ns.Moments.IsNew(journey.key))
end

---@param card AGFOverviewCard
---@param journey AGFJourney
---@param width number
local function RefreshOverviewCard(card, journey, width)
	card.journey, card.state = journey, "shown"
	card:SetWidth(width)
	RefreshIcon(card, journey, OVERVIEW_SPAN)
	card.Title:SetText(journey.title)
	local value, label = Progress(journey)
	local foot = label or (journey.level and L.NEXT_ZONE_LEVEL:format(journey.level)) or Stops(journey)
	local reason = journey.reason ~= foot and journey.reason or nil
	card.detail = DropLine(journey) or reason or HubLine(journey) or journey.subline
	card.Reason:SetText(card.detail)
	card.Foot:SetText(foot)
	card.Foot:SetWidth(width - OVERVIEW_TEXT - OVERVIEW_INSET)
	local room = width - OVERVIEW_TEXT - OVERVIEW_INSET - card.Foot:GetUnboundedStringWidth() - 8
	if value and room > 0 then
		SetBar(card.Bar, OVERVIEW_TEXT, 46, math.min(room, 60), value)
	else
		card.Bar:Hide()
	end
	Overview.RefreshCardTooltip(card)
end

---@param route AGFRoute
---@param top number
---@param shown boolean
---@param bottom number
---@return number
local function LayoutOverview(route, top, shown, bottom)
	---@cast panel -?
	---@cast list -?
	local slots = shown and math.max(0, math.floor((bottom - top + OVERVIEW_GAP) / (OVERVIEW_HEIGHT + OVERVIEW_GAP)))
		or 0
	local overflow = shown and #route.journeys > slots
	local count = math.min(#route.journeys, math.max(0, slots - (overflow and 1 or 0)))
	local width = math.max(0, panel:GetWidth() - 2 * PAD)
	for index, card in ipairs(overviewCards) do
		card:SetShown(index <= count)
		if index <= count then
			RefreshOverviewCard(card, route.journeys[index], width)
			card:SetPoint("TOPLEFT", 0, -top)
			top = top + OVERVIEW_HEIGHT + OVERVIEW_GAP
		end
	end
	moreButton:SetShown(overflow and slots > 0)
	if overflow and slots > 0 then
		local key = GetBindingKey("ADVENTUREGUIDEFOREVER_WINDOW")
		local keyText = key and GetBindingText(key, "KEY_")
		moreText:SetText(keyText and L.MORE_IN_GUIDE_KEY:format(keyText) or L.MORE_IN_GUIDE)
		moreButton:SetWidth(width)
		moreButton:SetPoint("TOPLEFT", 0, -top)
		top = top + OVERVIEW_HEIGHT + OVERVIEW_GAP
	end
	return top
end

-- The overview fits whole rows in the viewport. A chosen journey keeps the other cards folded
-- above its steps; its scroll height and the search's are summed before the client lays them out.
---@param route AGFRoute
---@return boolean searching
---@return integer found
---@return boolean emptyFits
local function LayoutJourneys(route)
	---@cast searchBox -?
	---@cast list -?
	---@cast content -?
	---@cast track -?
	---@cast panel -?
	local query = strtrim(searchBox:GetText())
	-- Characters, not bytes: a character is one byte that doesn't continue a UTF-8 sequence.
	local _, characters = query:gsub("[^\128-\191]", "")
	-- Not before completion data loads: every chain quest would read as locked.
	local searching = characters >= SEARCH_MIN and ns.State.Ready()
	local scrolling = searching or route.chosen
	SetScrolling(scrolling)
	local bottom = scrolling and math.huge or math.max(0, panel:GetHeight() - TOP_BAR - FOOTER - LIST_TOP - PAD)
	local top, found = LayoutResults(searching and query or nil)
	track:Hide()
	-- Every aside the player still wants, a line each (docs/design.md §2.11).
	local asides = not searching and ns.Asides.All() or {}
	for index = 1, math.max(#asides, #asideLines) do
		local reserve = not scrolling and (#route.journeys > 0 and OVERVIEW_HEIGHT or EMPTY_HEIGHT) + CARD_GAP or 0
		local aside = top + ASIDE_HEIGHT + CARD_GAP + reserve <= bottom and asides[index] or nil
		local line = asideLines[index] or CreateAsideLine(list)
		asideLines[index] = line
		line.aside = aside
		line:SetShown(aside ~= nil)
		if aside then
			if aside.texture then
				line.Icon:SetTexture(aside.texture)
				line.Icon:SetSize(ASIDE_HEIGHT, ASIDE_HEIGHT)
			else
				Art.Fit(line.Icon, aside.icon, ASIDE_HEIGHT, ASIDE_HEIGHT)
			end
			line.Text:SetText(aside.text)
			line:SetPoint("TOPLEFT", 10, -top)
			top = top + ASIDE_HEIGHT + ASIDE_GAP
		end
	end
	top = top + (top > 0 and #asides > 0 and CARD_GAP - ASIDE_GAP or 0)
	-- The empty line goes under the asides, never over them; the search's results, when it has any, hide it.
	---@cast emptyText -?
	local emptyTop = #asides > 0 and top or 0
	emptyText:SetPoint("TOPLEFT", 10, -emptyTop - 8)
	emptyText:SetMaxLines(scrolling and 0 or 2)
	top = LayoutOverview(route, top, not scrolling, bottom)
	local shownCard, shownJourney, compactRows = nil, nil, 0
	for index, card in ipairs(cards) do
		local journey = not searching and route.chosen and route.journeys[index] or nil
		card:SetShown(journey ~= nil)
		if journey and journey.key == route.journey then
			shownCard, shownJourney = card, journey
		elseif journey then
			card:SetPoint("TOP", list, "TOP", 0, -top)
			top = top + RefreshCard(card, journey, "compact") + ROW_GAP
			compactRows = compactRows + 1
		end
	end
	if shownCard and shownJourney then
		-- The one-line rows sit a row's gap apart, and a card's gap above the shown card.
		top = top + (compactRows > 0 and CARD_GAP - ROW_GAP or 0)
		RefreshCard(shownCard, shownJourney, route.chosen and "chosen" or "shown")
		shownCard:SetPoint("TOP", list, "TOP", 0, -top)
		top = LayoutTrack(shownJourney, top + CARD_HEIGHT + CARD_GAP)
		top = LayoutRows(route, top) + CARD_GAP
	else
		LayoutRows(route, top, true)
		top = math.min(bottom, math.max(top, emptyTop + EMPTY_HEIGHT))
	end
	-- Honest coverage: quests here the data lacks, so the cards can't be every story.
	---@cast unlistedText -?
	local state = ns.State
	local unlisted = not searching and ns.Model.Unlisted(ns.Data, state.Player().map, state.Completed(), state.Log())
	unlistedText:SetMaxLines(scrolling and 0 or 2)
	unlisted = unlisted and top + UNLISTED_HEIGHT <= bottom
	unlistedText:SetShown(unlisted)
	if unlisted then
		unlistedText:SetPoint("TOPLEFT", 10, -top)
		top = top + UNLISTED_HEIGHT + CARD_GAP
	end
	local skipped = not searching and top + SKIPPED_HEIGHT <= bottom and #ns.Skipped() or 0
	---@cast skippedButton -?
	skippedButton:SetShown(skipped > 0)
	if skipped > 0 then
		skippedButton:SetText(L.SKIPPED:format(skipped))
		skippedButton:SetWidth(skippedButton:GetTextWidth() + 4)
		skippedButton:SetPoint("TOPLEFT", 10, -top)
		top = top + SKIPPED_HEIGHT + CARD_GAP
	end
	list:SetHeight(top)
	content:SetHeight(LIST_TOP + top + PAD)
	if scrolling and scrollContent then
		scrollContent:SetSize(panel:GetWidth(), LIST_TOP + top + PAD)
	end
	return searching, found, emptyTop + EMPTY_HEIGHT <= bottom
end

function Refresh()
	if not (panel and panel:IsShown()) then
		return
	end
	-- BuildContent() always sets every upvalue below before Attach() registers this listener.
	---@cast emptyText -?
	---@cast queuedText -?
	---@cast stopButton -?
	local route = ns.Route()

	local ready = ns.State.Ready()
	local searching, found, emptyFits = LayoutJourneys(route)
	emptyText:SetText((not ready and L.LOADING) or (searching and L.SEARCH_NONE) or L.NO_JOURNEY)
	emptyText:SetShown(
		emptyFits and (not ready or (searching and found == 0) or (not searching and #route.journeys == 0))
	)

	local queued = ns.StartPending() and InCombatLockdown()
	queuedText:SetText(queued and L.STARTS_AFTER_COMBAT or L.ROUTE_PAUSED)
	queuedText:SetShown(queued or ns.Paused())
	stopButton:SetShown(ns.Integrations.Owns())
	---@cast backButton -?
	---@cast compass -?
	backButton:SetShown(route.chosen)
	compass:SetPoint("LEFT", route.chosen and 22 or 2, 0)
	-- The overview names where the player is under the title.
	---@cast headerTitle -?
	---@cast subtitle -?
	local player = ns.State.Player()
	local zone = player.map and (ns.State.MapName(player.map) or (ns.Data.zones[player.map] or {}).name)
	local where = not route.chosen and zone ~= nil
	subtitle:SetShown(where)
	subtitle:SetText(where and L.OVERVIEW_WHERE:format(zone, player.level) or "")
	headerTitle:ClearAllPoints()
	if where then
		headerTitle:SetPoint("TOP", 14, -1)
	else
		headerTitle:SetPoint("CENTER", 14, 0)
	end
end

-- Blizzard's displayMode and TabButtons are never written: the guide lays over the quest log
-- by hiding its content frames, and puts them back exactly as displayMode says when it closes.
---@param showGuide boolean
local function ShowGuide(showGuide)
	---@cast panel -?
	---@cast guideTab -?
	local map = QuestMapFrame
	for _, frame in ipairs(map.ContentFrames) do
		frame:SetShown(not showGuide and frame.displayMode == map.displayMode)
	end
	guideTab:SetChecked(showGuide)
	if questsTab then
		questsTab:SetChecked(not showGuide)
	end
	panel:SetShown(showGuide)
	if showGuide then
		Refresh()
	end
end

---@param name string
---@param tooltip string
---@param onClick fun()
---@return AGFTabButton
local function CreateTab(name, tooltip, onClick)
	local tab = CreateFrame("Frame", name, QuestMapFrame, "LargeSideTabButtonTemplate") --[[@as AGFTabButton]]
	tab.tooltipText = tooltip
	tab:SetCustomOnMouseUpHandler(function(_, mouseButton, upInside)
		if mouseButton == "LeftButton" and upInside then
			onClick()
		end
	end)
	return tab
end

-- Forever's quest log (the "camelot" UI flavour) hides every stock tab, so the guide brings its
-- own Quests tab to switch back; on a client that shows the stock tabs it sits below them instead.
local function CreateTabs()
	local map = QuestMapFrame
	guideTab = CreateTab("AdventureGuideForeverTab", ns.TITLE, function()
		ShowGuide(true)
	end)
	guideTab.Icon:SetAtlas("islands-queue-prop-compass")
	guideTab.Icon:SetSize(30, 30)
	tabPip = guideTab:CreateTexture(nil, "OVERLAY")
	tabPip:SetAtlas(TAB_PIP)
	tabPip:SetSize(20, 20)
	tabPip:SetPoint("CENTER", guideTab, "TOPRIGHT", -8, -8)
	tabPip:SetShown(ns.Moments.Unseen())
	if QuestMapFrameOverrides.questTabHidden then
		questsTab = CreateTab("AdventureGuideForeverQuestsTab", QUESTS_LABEL, function()
			ShowGuide(false)
		end)
		questsTab.activeAtlas = "questlog-tab-icon-quest"
		questsTab.inactiveAtlas = "questlog-tab-icon-quest-inactive"
		questsTab:SetPoint("TOPLEFT", map, "TOPRIGHT", QuestMapFrameOverrides.GetQuestsTabAnchorOffset())
		guideTab:SetPoint("TOP", questsTab, "BOTTOM", 0, -3)
	else
		local last = map.MapLegendTab:IsShown() and map.MapLegendTab or map.QuestsTab
		guideTab:SetPoint("TOP", last, "BOTTOM", 0, -3)
	end
	guideTab:SetChecked(false)
	if questsTab then
		questsTab:SetChecked(true)
	end
end

local function Attach()
	local map = QuestMapFrame
	panel = CreateFrame("Frame", "AdventureGuideForeverPanel", map)
	panel:SetPoint("TOPLEFT", map.ContentsAnchor)
	panel:SetPoint("BOTTOMRIGHT", map.ContentsAnchor, -22, 0)
	-- The quest list's own background and gold frame, so the guide reads as another page of the same log.
	local background = panel:CreateTexture(nil, "BACKGROUND")
	background:SetPoint("TOPLEFT", 0, -TOP_BAR)
	background:SetPoint("BOTTOMRIGHT")
	-- Above the quest details view, which is not one of the content frames ShowGuide hides.
	panel:SetFrameLevel(map:GetFrameLevel() + 20)
	panel:EnableMouse(true)
	panel:Hide()
	-- The rings preview the chosen journey only while the guide is visible: its tab, the quest sidebar collapsing
	-- and the map closing all come through here.
	panel:HookScript("OnShow", ns.Pins.Refresh)
	panel:HookScript("OnHide", ns.Pins.Refresh)
	panel:HookScript("OnHide", Overview.HideTooltipWithin)
	-- The cards' minutes, while the guide is open: on opening it and on each new route.
	local function QueueCards()
		if panel:IsShown() then
			ns.Integrations.RefreshCards(ns.Route().journeys)
		end
	end
	panel:HookScript("OnShow", QueueCards)
	-- Something new: seen once the guide shows; its cards' marks go when it closes.
	panel:HookScript("OnShow", ns.Moments.Opened)
	panel:HookScript("OnHide", ns.Moments.Closed)
	ns.OnRouteChange(QueueCards)
	BuildContent(panel)
	panel:SetScript("OnSizeChanged", Refresh)
	Art.CoverFrame(panel, background, "QuestLog-main-background", 0, TOP_BAR)
	-- The footer's Stop follows Shortest Path ending our journey and the player clearing or moving the waypoint through
	-- Integrations.OnGuidanceChange (below), on the frame after the super-tracking events.
	panel:RegisterEvent("QUEST_DATA_LOAD_RESULT")
	panel:RegisterEvent("UPDATE_BINDINGS")
	panel:SetScript("OnEvent", function(_, event, questID)
		if event == "UPDATE_BINDINGS" or requested[questID] then
			Refresh()
		end
	end)
	CreateTabs()

	EventRegistry:RegisterCallback("QuestLog.SetDisplayMode", function()
		if panel:IsShown() then
			ShowGuide(false)
		end
	end, panel)
	-- Opening a tracked quest asks for Quests mode, but SetDisplayMode returns early when the mode is unchanged,
	-- so the callback above never fires for it.
	hooksecurefunc("QuestMapFrame_ShowQuestDetails", function()
		if panel:IsShown() then
			ShowGuide(false)
		end
	end)
	ns.OnRouteChange(Refresh)
	ns.Integrations.OnGuidanceChange(Refresh)
	ns.Integrations.OnTravelChange(Refresh)
	ns.Integrations.OnCardTravel(Refresh)
	ns.Asides.OnChange(Refresh)
	ns.Moments.OnChange(function()
		---@cast tabPip -?
		tabPip:SetShown(ns.Moments.Unseen())
		Refresh()
	end)

	function ns.PanelShown()
		return panel:IsVisible()
	end

	function ns.OpenPanel()
		-- Also brings back a collapsed quest sidebar, which hides QuestMapFrame and so the panel inside it.
		OpenQuestLog()
		ShowGuide(true)
	end
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", Attach)
