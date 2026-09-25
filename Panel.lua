---@type string, AGFNamespace
local _, ns = ...
local L = ns.L

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
-- The scroll child above the cards: the header 4px down and 34px tall, then 6px to the first card.
local LIST_TOP = 4 + 34 + 6
-- Blizzard's QUEST_TAG_ATLAS icons (Blizzard_FrameXMLBase/Constants.lua:514-527); the next zone gets the map's "!",
-- the calling the quest log's class icon from the same sheet (CSV:9385).
local KIND_ICONS = {
	carry = "questlog-questtypeicon-quest",
	story = "questlog-questtypeicon-story",
	nextzone = "QuestNormal",
	dungeon = "questlog-questtypeicon-dungeon",
	calling = "questlog-questtypeicon-class",
	-- The minimap's battlemaster mark (CSV:1319).
	battleground = "battlemaster",
}
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
local ASIDE_HEIGHT, ASIDE_GAP = 14, 2
local FOOTER = 40
-- The overview (docs/design.md §2.2), with no card chosen: the first card featured over its first steps, then the
-- others two across. Every card there is the Journeys renown card, its art drawn ART_BLEED outside the button, since
-- the atlas keeps an empty margin about that wide, and sliced so its rim keeps its width at any size.
local OVERVIEW_WIDTH, ART_BLEED, ART_SLICE = 288, 6, 12
local FEATURED_HEIGHT, FEATURED_ICON, FEATURED_BADGE, FEATURED_SPAN = 82, 40, 16, 420
local PREVIEW_ROWS, PREVIEW_HEIGHT, PREVIEW_TEXT = 3, 22, 27
local DIVIDER_HEIGHT = 10
local GRID_GAP, GRID_HEIGHT, GRID_ICON, GRID_BADGE, GRID_SPAN = 5, 92, 30, 13, 240
local GRID_WIDTH = (OVERVIEW_WIDTH - GRID_GAP) / 2
-- A grid card's text sits GRID_INSET in from its rim: the title beside the icon, the reason under both, the footer
-- on the bottom inset.
local GRID_INSET, GRID_TOP, GRID_TITLE_X, GRID_FOOT = 14, 12, 14 + 30 + 9, 92 - 12 - 10
-- GameFontNormal's line height.
local TITLE_LINE = 13
-- The Journeys renown bar is 18 tall at its own scale, too tall for a card: its frame is scaled to draw it 7 tall.
local BAR_HEIGHT, BAR_ART = 7, 18
-- The featured card's counts, after the map's own turn-in and quest marks.
local READY_MARK, UNDERWAY_MARK, COUNT_GAP = "|A:QuestTurnin:12:12|a ", "|A:QuestNormal:12:12|a ", "  "

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
-- Defined with the card's refresh; the cards' OnEnter needs it.
local CardTooltip
---@type FontString?
local emptyText
-- One line per aside the player still wants (Asides.All), from the top of the list.
---@type AGFAsideLine[]
local asideLines = {}
-- The overview (docs/design.md §2.2): the featured card, its first steps, the divider and the other cards.
---@type AGFOverviewCard?
local featured
---@type AGFPreviewRow[]
local previews = {}
---@type Texture?
local divider
---@type AGFOverviewCard[]
local gridCards = {}
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

---@param step AGFStep
local function FocusStep(step)
	WorldMapFrame:SetMapID(step.map)
	-- The map's data providers (Pins.lua among them) refresh in response to SetMapID; wait a
	-- frame so the pin exists before it's asked to flash.
	C_Timer.After(0, function()
		ns.Pins.Ping(step.key)
	end)
end

---@param owner Frame
---@param lines string[]
local function ShowTooltip(owner, lines)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, lines[1])
	for index = 2, #lines do
		GameTooltip_AddNormalLine(GameTooltip, lines[index])
	end
	GameTooltip:Show()
end

-- The aside's line above the cards.
---@class AGFSkipButton : Button
---@field Icon Texture the X, shaded apart from the highlight

---@class AGFAsideLine : Button
---@field Icon Texture
---@field Text FontString
---@field Skip AGFSkipButton
---@field aside? AGFAside the aside it draws

---@class AGFRouteRow : Button
---@field Selected Texture
---@field Ring Texture
---@field Number Texture
---@field Title FontString
---@field Detail FontString
---@field Group Texture
---@field Tag FontString
---@field SkipButton AGFSkipButton
---@field step? AGFStep
---@field index? integer

---@param row AGFRouteRow
---@param atlas string
---@param tip fun(): string
---@param action fun(step: AGFStep)
---@return AGFSkipButton
local function CreateRowIcon(row, atlas, tip, action)
	local button = CreateFrame("Button", nil, row) --[[@as AGFSkipButton]]
	button:SetSize(18, 18)
	button.Icon = button:CreateTexture(nil, "ARTWORK")
	button.Icon:SetAtlas(atlas)
	button.Icon:SetAllPoints()
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

-- A step row's lines: the ring's; a row after step 1 asks Shortest Path for its travel line once, on hover.
---@param self AGFRouteRow|AGFPreviewRow
local function RowEnter(self)
	local step, index = self.step, self.index
	if not (step and index) then
		return
	end
	local travel = index == 1 and ns.Integrations.Travel(step) or ns.Integrations.TravelLine(step)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	ns.Pins.StepTooltip(GameTooltip, step, index, travel)
	GameTooltip:Show()
end

-- A quest in the log opens its details; any other step turns the map to it. Right-click is the step menu.
---@param self AGFRouteRow|AGFPreviewRow
---@param mouseButton string
local function RowClick(self, mouseButton)
	if not self.step then
		return
	end
	if mouseButton == "RightButton" then
		ns.Menu.Open(self, "MENU_ADVENTURE_GUIDE_FOREVER_STEP", self.step)
	elseif not ns.ShowQuest(self.step) then
		FocusStep(self.step)
	end
end

---@param parent Frame
---@return AGFRouteRow
local function CreateRow(parent)
	local row = CreateFrame("Button", nil, parent) --[[@as AGFRouteRow]]
	row:SetHeight(ROW_HEIGHT)
	-- The Classic mount and pet collection list rows: background, hover and selected art.
	local background = row:CreateTexture(nil, "BACKGROUND")
	background:SetAtlas("PetList-ButtonBackground")
	background:SetAllPoints()
	row:SetHighlightAtlas("PetList-ButtonHighlight")
	row.Selected = row:CreateTexture(nil, "OVERLAY")
	row.Selected:SetAtlas("PetList-ButtonSelect")
	row.Selected:SetAllPoints()

	row.SkipButton = CreateRowIcon(row, "common-icon-redx", function()
		return ns.L.SKIP_STEP
	end, function(step)
		ns.Skip(step.key, step.title)
	end)
	row.SkipButton:SetSize(14, 14)
	row.SkipButton:SetPoint("TOPRIGHT", -6, -7)

	row.Ring = row:CreateTexture(nil, "ARTWORK")
	row.Ring:SetAtlas("adventureguide-ring")
	row.Ring:SetSize(26, 26)
	row.Ring:SetPoint("LEFT", 6, 0)
	row.Number = row:CreateTexture(nil, "OVERLAY")
	row.Number:SetSize(22, 25)
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
	return row
end

-- One of the first card's steps under it in the overview: the chosen view's row made small, the Classic pet list's
-- art at 22 tall with the ring, number and title on one line and the detail after it, and the same tooltip, click
-- and menu. No skip: the step menu has it.
---@class AGFPreviewRow : Button
---@field Ring Texture
---@field Number Texture
---@field Title FontString
---@field Detail FontString
---@field step? AGFStep
---@field index? integer

---@param parent Frame
---@return AGFPreviewRow
local function CreatePreview(parent)
	local row = CreateFrame("Button", nil, parent) --[[@as AGFPreviewRow]]
	row:SetSize(OVERVIEW_WIDTH, PREVIEW_HEIGHT)
	local background = row:CreateTexture(nil, "BACKGROUND")
	background:SetAtlas("PetList-ButtonBackground")
	background:SetAllPoints()
	row:SetHighlightAtlas("PetList-ButtonHighlight")
	row.Ring = row:CreateTexture(nil, "ARTWORK")
	row.Ring:SetAtlas("adventureguide-ring")
	row.Ring:SetSize(18, 18)
	row.Ring:SetPoint("TOPLEFT", 4, -2)
	row.Number = row:CreateTexture(nil, "OVERLAY")
	row.Number:SetSize(15, 17.5)
	row.Number:SetPoint("CENTER", row.Ring)
	row.Title = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	row.Title:SetPoint("TOPLEFT", PREVIEW_TEXT, -5)
	row.Title:SetJustifyH("LEFT")
	row.Title:SetWordWrap(false)
	row.Detail = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.Detail:SetPoint("BOTTOMLEFT", row.Title, "BOTTOMRIGHT", 5, 0)
	row.Detail:SetJustifyH("LEFT")
	row.Detail:SetWordWrap(false)
	row:SetScript("OnEnter", RowEnter)
	row:SetScript("OnLeave", GameTooltip_Hide)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetScript("OnClick", RowClick)
	return row
end

-- Back to every suggestion: clears the choice, so the guide draws the first card again with the others as rows above
-- it (docs/design.md §2.2), and stops the route AGF started for it, as any cleared choice does (ns.Choose).
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
	row.Star:SetAtlas("tradeskills-star")
	row.Star:SetSize(14, 13)
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

-- Choosing a journey shows its route and turns the map to it, and with the setting on starts it (ns.Choose, once the
-- rebuild has its steps). The map turns before the invalidation, so its redraw reads the route as it is and the one
-- rebuild waits a frame. The chosen card is no toggle: the header's back arrow goes back to the overview and the
-- footer's Stop stops the route, so a click on it only turns the map to it again, or resumes its route while that is
-- paused. Right-click offers "Not interested", except on what the player carries.
---@param self AGFCardButton
---@param mouseButton string
local function CardClick(self, mouseButton)
	local journey = self.journey
	if not journey then
		return
	end
	if mouseButton == "RightButton" then
		if journey.kind ~= "carry" then
			GameTooltip_Hide()
			ns.Menu.Journey(self, journey)
		end
		return
	end
	if self.state == "chosen" and ns.Paused() then
		ns.StartRoute()
	elseif self.state == "chosen" then
		WorldMapFrame:SetMapID(journey.map)
	else
		WorldMapFrame:SetMapID(journey.map)
		ns.Choose(journey.key, ns.Setting("titleStartsRoute"))
	end
	-- Its tooltip spoke for the state the click just left.
	GameTooltip_Hide()
end

-- A card in the overview (docs/design.md §2.2): the renown card's art round a zone icon, its title, its reason and,
-- featured, its counts and "Suggested"; in the grid, a footer. The renown bar only where a journey has come some way.
---@class AGFOverviewCard : AGFCardButton
---@field Icon AGFZoneIcon
---@field New Texture
---@field Title FontString
---@field Reason FontString
---@field Counts? FontString the featured card's
---@field Tag? FontString the featured card's
---@field Foot? FontString a grid card's
---@field Bar AGFProgressBar

---@class AGFProgressBar : Frame
---@field Fill Texture

---@param parent Frame
---@return AGFProgressBar
local function CreateBar(parent)
	local bar = CreateFrame("Frame", nil, parent) --[[@as AGFProgressBar]]
	bar:SetScale(BAR_HEIGHT / BAR_ART)
	bar:SetHeight(BAR_ART)
	local back = bar:CreateTexture(nil, "BACKGROUND")
	back:SetAtlas("UI-Journeys-renown-progressbar-BG")
	back:SetAllPoints()
	bar.Fill = bar:CreateTexture(nil, "ARTWORK")
	bar.Fill:SetAtlas("UI-Journeys-renown-progressbar-fill")
	bar.Fill:SetPoint("TOPLEFT")
	bar.Fill:SetPoint("BOTTOMLEFT")
	local rim = bar:CreateTexture(nil, "OVERLAY")
	rim:SetAtlas("UI-Journeys-renown-progressbar-frame")
	rim:SetAllPoints()
	return bar
end

-- The bar `width` wide at (x, y) in its card, filled to `value` (0-1]; a scaled frame's offsets and size are in its
-- own units.
---@param bar AGFProgressBar
---@param x number
---@param y number
---@param width number
---@param value number
local function SetBar(bar, x, y, width, value)
	local scale = BAR_HEIGHT / BAR_ART
	bar:SetWidth(width / scale)
	bar:ClearAllPoints()
	bar:SetPoint("TOPLEFT", x / scale, -y / scale)
	bar.Fill:SetWidth(width / scale * math.min(value, 1))
	bar:Show()
end

---@param parent Frame
---@param isFeatured boolean
---@return AGFOverviewCard
local function CreateOverviewCard(parent, isFeatured)
	local card = CreateFrame("Button", nil, parent) --[[@as AGFOverviewCard]]
	card:SetSize(isFeatured and OVERVIEW_WIDTH or GRID_WIDTH, isFeatured and FEATURED_HEIGHT or GRID_HEIGHT)
	-- The renown art, and its highlight: the same art added.
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
	local size = isFeatured and FEATURED_ICON or GRID_ICON
	card.Icon = ns.ZoneIcon.Create(card, size, isFeatured and FEATURED_BADGE or GRID_BADGE)
	card.Icon:SetPoint("TOPLEFT", isFeatured and 18 or GRID_INSET, isFeatured and -14 or -GRID_TOP)
	card.New = card.Icon.Border:CreateTexture(nil, "OVERLAY", nil, 2)
	card.New:SetAtlas(NEW_MARK)
	card.New:SetSize(isFeatured and NEW_SIZE or NEW_COMPACT, isFeatured and NEW_SIZE or NEW_COMPACT)
	card.New:SetPoint("CENTER", card.Icon, "TOPRIGHT", -2, -2)
	card.Bar = CreateBar(card)
	if isFeatured then
		local left = 18 + FEATURED_ICON + 16
		card.Tag = card:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
		card.Tag:SetPoint("TOPRIGHT", -16, -13)
		card.Tag:SetText(L.SUGGESTED)
		card.Title = card:CreateFontString(nil, "ARTWORK", "GameFontNormalMed2")
		card.Title:SetPoint("TOPLEFT", left, -13)
		card.Title:SetPoint("RIGHT", card.Tag, "LEFT", -6, 0)
		card.Reason = card:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		card.Reason:SetPoint("TOPLEFT", left, -31)
		card.Reason:SetPoint("RIGHT", -16, 0)
		card.Counts = card:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		card.Counts:SetPoint("TOPLEFT", left, -47)
		card.Counts:SetPoint("RIGHT", -14, 0)
		for _, text in ipairs({ card.Title, card.Reason, card.Counts }) do
			text:SetJustifyH("LEFT")
			text:SetWordWrap(false)
		end
	else
		-- Wrapped, never cut: a title of three lines leaves the reason one.
		card.Title = card:CreateFontString(nil, "ARTWORK", "GameFontNormal")
		card.Title:SetPoint("TOPLEFT", GRID_TITLE_X, -GRID_TOP)
		card.Title:SetWidth(GRID_WIDTH - GRID_TITLE_X - GRID_INSET)
		card.Title:SetMaxLines(3)
		card.Reason = card:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		card.Reason:SetWidth(GRID_WIDTH - 2 * GRID_INSET)
		for _, text in ipairs({ card.Title, card.Reason }) do
			text:SetJustifyH("LEFT")
			text:SetWordWrap(true)
		end
		card.Foot = card:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		card.Foot:SetJustifyH("LEFT")
		card.Foot:SetWordWrap(false)
	end
	card:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	card:SetScript("OnClick", CardClick)
	card:SetScript("OnEnter", function(self)
		CardTooltip(self)
	end)
	card:SetScript("OnLeave", GameTooltip_Hide)
	return card
end

-- The overview under the asides: the featured card, its first steps, the divider and the grid.
---@param parent Frame
local function BuildOverview(parent)
	featured = CreateOverviewCard(parent, true)
	for index = 1, PREVIEW_ROWS do
		previews[index] = CreatePreview(parent)
	end
	divider = parent:CreateTexture(nil, "ARTWORK")
	divider:SetAtlas("UI-Journeys-Renown-divider")
	divider:SetSize(OVERVIEW_WIDTH, DIVIDER_HEIGHT)
	for index = 1, ns.Model.MAX_JOURNEYS - 1 do
		gridCards[index] = CreateOverviewCard(parent, false)
	end
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

-- Everything between the top bar and the footer scrolls, with the quest log's own scroll bar and offsets.
---@param panelFrame Frame
---@return Frame
local function BuildScroll(panelFrame)
	local body = CreateFrame("Frame", nil, panelFrame)
	body:SetPoint("TOPLEFT", 0, -TOP_BAR)
	body:SetPoint("BOTTOMRIGHT")
	CreateFrame("Frame", nil, body, "QuestLogBorderFrameTemplate")

	local scroll = CreateFrame("ScrollFrame", nil, body, "ScrollFrameTemplate") --[[@as AGFScrollFrame]]
	scroll:SetPoint("TOPLEFT")
	scroll:SetPoint("BOTTOMRIGHT", 0, FOOTER)
	scroll.ScrollBar:ClearAllPoints()
	scroll.ScrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 8, 2)
	scroll.ScrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 8, -4)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(1, 1)
	scroll:SetScrollChild(child)
	scroll:SetScript("OnSizeChanged", function(_, width)
		child:SetWidth(width)
	end)
	return child
end

---@param panelFrame Frame
local function BuildContent(panelFrame)
	BuildTopBar(panelFrame)
	content = BuildScroll(panelFrame)
	local header = BuildHeader(content)
	BuildJourneys(content, header)
	BuildFooter(panelFrame)
end

---@param row AGFRouteRow
---@param step AGFStep
---@param index integer
local function RefreshRow(row, step, index)
	row.index = index
	row.Number:SetAtlas("services-number-" .. index)
	row.Title:SetText(step.title)
	-- Step 1 adds how long it takes when Shortest Path knows (docs/plan.md §7.4); its tooltip gives the way.
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
	row.Selected:SetShown(index == 1)
end

-- A card's first stop and how many stops follow it, its third line when it has no reason.
---@param journey AGFJourney
---@return string?
local function HubLine(journey)
	local more = journey.more or 0
	if not journey.hub then
		return nil
	end
	return (more > 1 and L.HUB_MORE:format(journey.hub, more))
		or (more == 1 and L.HUB_MORE_ONE:format(journey.hub))
		or journey.hub
end

-- The log-full note (docs/design.md §2.18) on the card that has it: how many quests could go.
---@param journey AGFJourney
---@return string?
local function DropLine(journey)
	local drop = journey.drop and #journey.drop or 0
	return (drop == 1 and L.LOG_FULL_ONE) or (drop > 1 and L.LOG_FULL:format(drop)) or nil
end

-- Every card's tooltip, whole or one-line (docs/plan.md §7.4): its lines, the hub line when line 3 holds the reason
-- or is folded away, how many quests need a group, the quests the log-full note means, then what a click does. The
-- chosen card points to the back arrow; a card whose click would replace someone else's journey warns
-- first, as Go did (docs/design.md §2.9).
---@param card AGFCardButton
function CardTooltip(card)
	local journey = card.journey
	if not journey then
		return
	end
	local starts = ns.Setting("titleStartsRoute")
	local chosen = card.state == "chosen"
	GameTooltip:SetOwner(card, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, journey.title)
	GameTooltip_AddNormalLine(GameTooltip, journey.subline)
	if journey.reason then
		GameTooltip_AddHighlightLine(GameTooltip, journey.reason)
	end
	local hub = HubLine(journey)
	if hub and (journey.reason or journey.drop or card.state == "compact") then
		GameTooltip_AddHighlightLine(GameTooltip, hub)
	end
	local travel = ns.Integrations.CardTravel(journey)
	if travel and travel.line then
		GameTooltip_AddHighlightLine(GameTooltip, travel.line)
	end
	local group = journey.group or 0
	if group > 0 then
		GameTooltip_AddHighlightLine(GameTooltip, group == 1 and L.GROUP_ONE or L.GROUP_MANY:format(group))
	end
	if journey.drop then
		local log = ns.State.Log()
		GameTooltip_AddNormalLine(GameTooltip, L.LOG_FULL_LIST)
		for _, id in ipairs(journey.drop) do
			local entry = log[id]
			GameTooltip_AddHighlightLine(GameTooltip, entry and entry.title or ns.Data.quests[id].title)
		end
	end
	local resumes = chosen and ns.Paused()
	if not chosen then
		GameTooltip_AddInstructionLine(GameTooltip, L.CLICK_TO_CHOOSE)
	elseif resumes then
		GameTooltip_AddInstructionLine(GameTooltip, L.CLICK_TO_RESUME)
	end
	if chosen then
		GameTooltip_AddInstructionLine(GameTooltip, L.BACK_TO_ALL)
	end
	if (resumes or not chosen and starts) and ns.Integrations.ReplacesJourney() then
		GameTooltip_AddInstructionLine(GameTooltip, L.REPLACES_JOURNEY)
	end
	if journey.kind ~= "carry" then
		GameTooltip_AddInstructionLine(GameTooltip, L.RIGHT_CLICK_NOT_INTERESTED)
	end
	GameTooltip:Show()
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
	card.IconFrame.Icon:SetSize(compact and COMPACT_ICON or CARD_ICON, compact and COMPACT_ICON or CARD_ICON)
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
	card.IconFrame.Icon:SetAtlas(KIND_ICONS[journey.kind])
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
	if GameTooltip:IsOwned(card) then
		CardTooltip(card)
	end
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

-- The shown card's rows, from `top` down; `hidden` (a search, or no card) hides them all.
---@param route AGFRoute
---@param top number
---@param hidden? boolean
---@return number top below the last row shown
local function LayoutRows(route, top, hidden)
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
		end
	end
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

-- How far a journey has come, when it has come some way: a story's chapters done of a chain the data proves the length
-- of, Loose ends' quests ready of all it holds. The bar's value and the grid footer's words.
---@param journey AGFJourney
---@return number? value
---@return string? label
local function Progress(journey)
	local story = journey.story
	if story and story.total and story.chapter > 1 then
		return (story.chapter - 1) / story.total, L.CHAPTERS_DONE:format(story.chapter - 1, story.total)
	end
	local ready, underway = journey.ready or 0, journey.underway or 0
	if journey.kind == "carry" and ready > 0 then
		return ready / (ready + underway), L.READY_OF:format(ready, ready + underway)
	end
end

-- The zone icon's centre: the card's first town on its zone, else its first stop.
---@param journey AGFJourney
---@return AGFStep?
local function IconStep(journey)
	for _, step in ipairs(journey.steps) do
		if step.kind == "town" and step.map == journey.map then
			return step
		end
	end
	return journey.steps[1]
end

---@param card AGFOverviewCard
---@param journey AGFJourney
---@param span number
local function RefreshIcon(card, journey, span)
	local step = IconStep(journey)
	ns.ZoneIcon.Set(card.Icon, KIND_ICONS[journey.kind], step and step.map, step and step.x, step and step.y, span)
	card.New:SetShown(ns.Moments.IsNew(journey.key))
end

-- The featured card: its title, its reason, then its counts with the map's marks, else its subline.
---@param card AGFOverviewCard
---@param journey AGFJourney
local function RefreshFeatured(card, journey)
	card.journey, card.state = journey, "shown"
	RefreshIcon(card, journey, FEATURED_SPAN)
	card.Title:SetText(journey.title)
	card.Reason:SetText(DropLine(journey) or journey.reason or HubLine(journey) or "")
	local ready, underway, counts = journey.ready or 0, journey.underway or 0, {}
	counts[#counts + 1] = ready > 0 and READY_MARK .. L.CARRY_READY:format(ready) or nil
	counts[#counts + 1] = underway > 0 and UNDERWAY_MARK .. L.CARRY_IN_PROGRESS:format(underway) or nil
	(card.Counts --[[@as FontString]]):SetText(#counts > 0 and table.concat(counts, COUNT_GAP) or journey.subline)
	local value = Progress(journey)
	if value then
		SetBar(card.Bar, 16, FEATURED_HEIGHT - 19, OVERVIEW_WIDTH - 32, value)
	else
		card.Bar:Hide()
	end
	if GameTooltip:IsOwned(card) then
		CardTooltip(card)
	end
end

-- A grid card's footer when it has come no way: the level a zone to head to fits, else how many stops it has.
---@param journey AGFJourney
---@return string
local function Stops(journey)
	local stops = journey.more and journey.more + 1 or #journey.steps
	return stops == 1 and L.STOPS_ONE or L.STOPS:format(stops)
end

-- A grid card: its title in up to three lines beside the icon, its reason under both in what room is left, and the
-- footer on the bottom inset, after the bar when the journey has come some way.
---@param card AGFOverviewCard
---@param journey AGFJourney
local function RefreshGrid(card, journey)
	card.journey, card.state = journey, "shown"
	RefreshIcon(card, journey, GRID_SPAN)
	card.Title:SetText(journey.title)
	local lines = math.min(math.max(card.Title:GetNumLines(), 1), 3)
	local value, label = Progress(journey)
	local foot = label or (journey.level and L.NEXT_ZONE_LEVEL:format(journey.level)) or Stops(journey)
	local reason = journey.reason ~= foot and journey.reason or nil
	card.Reason:SetText(DropLine(journey) or reason or HubLine(journey) or journey.subline)
	card.Reason:SetMaxLines(lines >= 3 and 1 or 2)
	card.Reason:ClearAllPoints()
	card.Reason:SetPoint("TOPLEFT", GRID_INSET, -math.max(GRID_TOP + lines * TITLE_LINE + 4, GRID_TOP + GRID_ICON + 3))
	local footer = card.Foot --[[@as FontString]]
	footer:SetText(foot)
	footer:ClearAllPoints()
	if value then
		footer:SetPoint("TOPRIGHT", -GRID_INSET, -GRID_FOOT)
		local width = GRID_WIDTH - 2 * GRID_INSET - footer:GetUnboundedStringWidth() - 6
		SetBar(card.Bar, GRID_INSET, GRID_FOOT + 2, width, value)
	else
		footer:SetPoint("TOPLEFT", GRID_INSET, -GRID_FOOT)
		card.Bar:Hide()
	end
	if GameTooltip:IsOwned(card) then
		CardTooltip(card)
	end
end

-- One step under the featured card: its title, then as much of its detail as fits after it.
---@param row AGFPreviewRow
---@param step AGFStep
---@param index integer
local function RefreshPreview(row, step, index)
	row.step, row.index = step, index
	row.Number:SetAtlas("services-number-" .. index)
	row.Title:SetText(step.title)
	local room = OVERVIEW_WIDTH - PREVIEW_TEXT - 6
	local title = math.min(row.Title:GetUnboundedStringWidth(), room)
	row.Title:SetWidth(title)
	row.Detail:SetText(step.detail)
	local left = room - title - 5
	row.Detail:SetShown(left >= 30)
	row.Detail:SetWidth(math.max(math.min(row.Detail:GetUnboundedStringWidth(), left), 0))
	row:SetAlpha(step.optional and 0.6 or 1)
end

-- With no card chosen (docs/design.md §2.2): the first card featured with its first steps, the divider, then the
-- others two across, from `top` down; `shown` false hides it all. The first card is the one the route follows, so
-- its steps are the route's.
---@param route AGFRoute
---@param top number
---@param shown boolean
---@return number top below the last card
local function LayoutOverview(route, top, shown)
	---@cast featured -?
	---@cast divider -?
	---@cast list -?
	local first, others = nil, {}
	for _, journey in ipairs(shown and route.journeys or {}) do
		if not first and journey.key == route.journey then
			first = journey
		else
			others[#others + 1] = journey
		end
	end
	-- The route follows the first card while none is chosen; one it does not name is the first all the same.
	if not first and #others > 0 then
		first = table.remove(others, 1)
	end
	featured:SetShown(first ~= nil)
	divider:SetShown(first ~= nil and #others > 0)
	for index, row in ipairs(previews) do
		local step = first and route.steps[index] or nil
		row:SetShown(step ~= nil)
		if step then
			RefreshPreview(row, step, index)
			row:SetPoint("TOP", list, "TOP", 0, -(top + FEATURED_HEIGHT + 3 + (index - 1) * (PREVIEW_HEIGHT + ROW_GAP)))
		end
	end
	for index, card in ipairs(gridCards) do
		card:SetShown(first ~= nil and others[index] ~= nil)
	end
	if not first then
		return top
	end
	RefreshFeatured(featured, first)
	featured:SetPoint("TOP", list, "TOP", 0, -top)
	top = top + FEATURED_HEIGHT + 3 + math.min(#route.steps, PREVIEW_ROWS) * (PREVIEW_HEIGHT + ROW_GAP)
	if #others == 0 then
		return top + CARD_GAP
	end
	divider:SetPoint("TOP", list, "TOP", 0, -top)
	top = top + DIVIDER_HEIGHT
	for index, journey in ipairs(others) do
		local card = gridCards[index]
		local column, row = (index - 1) % 2, math.floor((index - 1) / 2)
		RefreshGrid(card, journey)
		card:SetPoint(
			"TOPLEFT",
			list,
			"TOP",
			-OVERVIEW_WIDTH / 2 + column * (GRID_WIDTH + GRID_GAP),
			-(top + row * (GRID_HEIGHT + GRID_GAP))
		)
	end
	return top + math.ceil(#others / 2) * (GRID_HEIGHT + GRID_GAP) - GRID_GAP + CARD_GAP
end

-- The others first as one-line rows in their order, then the shown card (the chosen one, else the first, which the
-- guide draws on its own: docs/design.md §2.2) with its track and rows, so its steps start at the same place whichever
-- card it is and no card sits between them. Or the search's results. The scroll child's height is summed, not
-- measured, so it is right before the client has laid anything out.
---@param route AGFRoute
---@return boolean searching
---@return integer found
local function LayoutJourneys(route)
	---@cast searchBox -?
	---@cast list -?
	---@cast content -?
	---@cast track -?
	local query = strtrim(searchBox:GetText())
	-- Characters, not bytes: a character is one byte that doesn't continue a UTF-8 sequence.
	local _, characters = query:gsub("[^\128-\191]", "")
	-- Not before completion data loads: every chain quest would read as locked.
	local searching = characters >= SEARCH_MIN and ns.State.Ready()
	local top, found = LayoutResults(searching and query or nil)
	track:Hide()
	-- Every aside the player still wants, a line each (docs/design.md §2.11).
	local asides = not searching and ns.Asides.All() or {}
	for index = 1, math.max(#asides, #asideLines) do
		local aside = asides[index]
		local line = asideLines[index] or CreateAsideLine(list)
		asideLines[index] = line
		line.aside = aside
		line:SetShown(aside ~= nil)
		if aside then
			if aside.texture then
				line.Icon:SetTexture(aside.texture)
			else
				line.Icon:SetAtlas(aside.icon)
			end
			line.Text:SetText(aside.text)
			line:SetPoint("TOPLEFT", 10, -top)
			top = top + ASIDE_HEIGHT + ASIDE_GAP
		end
	end
	top = top + (#asides > 0 and CARD_GAP - ASIDE_GAP or 0)
	-- The empty line goes under the asides, never over them; the search's results, when it has any, hide it.
	---@cast emptyText -?
	local emptyTop = #asides > 0 and top or 0
	emptyText:SetPoint("TOPLEFT", 10, -emptyTop - 8)
	top = LayoutOverview(route, top, not searching and not route.chosen)
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
		top = math.max(top, emptyTop + 40)
	end
	-- Honest coverage: quests here the data lacks, so the cards can't be every story.
	---@cast unlistedText -?
	local state = ns.State
	local unlisted = not searching and ns.Model.Unlisted(ns.Data, state.Player().map, state.Completed(), state.Log())
	unlistedText:SetShown(unlisted)
	if unlisted then
		unlistedText:SetPoint("TOPLEFT", 10, -top)
		top = top + UNLISTED_HEIGHT + CARD_GAP
	end
	local skipped = not searching and #ns.Skipped() or 0
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
	return searching, found
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
	local searching, found = LayoutJourneys(route)
	emptyText:SetText((not ready and L.LOADING) or (searching and L.SEARCH_NONE) or L.NO_JOURNEY)
	emptyText:SetShown(not ready or (searching and found == 0) or (not searching and #route.journeys == 0))

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
	background:SetAtlas("QuestLog-main-background")
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
	-- The footer's Stop follows Shortest Path ending our journey and the player clearing or moving the waypoint through
	-- Integrations.OnGuidanceChange (below), on the frame after the super-tracking events.
	panel:RegisterEvent("QUEST_DATA_LOAD_RESULT")
	panel:SetScript("OnEvent", function(_, _, questID)
		if requested[questID] then
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
