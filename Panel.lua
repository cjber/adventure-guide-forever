---@type string, AGFNamespace
local _, ns = ...
local L = ns.L

local PAD = 8
local ROW_HEIGHT = 44
local ROW_GAP = 2
local CARD_HEIGHT = 86
local CARD_GAP = 4
local MAX_JOURNEYS = 3
-- The scroll child above the cards: the header 4px down and 34px tall, then 6px to the first card.
local LIST_TOP = 4 + 34 + 6
-- Blizzard's QUEST_TAG_ATLAS icons (Blizzard_FrameXMLBase/Constants.lua:514-527); the next zone gets the map's "!".
local KIND_ICONS = {
	carry = "questlog-questtypeicon-quest",
	story = "questlog-questtypeicon-story",
	nextzone = "QuestNormal",
	dungeon = "questlog-questtypeicon-group",
}
local CARD_ART, CARD_ART_CHOSEN = "ui-journeys-renown-button", "ui-journeys-renown-button-pressed"
-- The chapter track (docs/design.md §2.3): Blizzard's delve squares at 12px, with their meanings kept
-- (RewardTrackTemplates.lua:427-436): done, the one most recently finished in green, the rest grey.
local TRACK_MAX, SQUARE, SQUARE_GAP = 8, 12, 3
-- The search (docs/design.md §2.4): 3 characters or more put up to 10 quests in place of the cards; a locked one lists
-- why, unmet lines first, up to 6 (its tooltip has them all).
local SEARCH_MIN, SEARCH_ROWS, WHY_LINES, RESULT_HEIGHT, WHY_HEIGHT = 3, 10, 6, 24, 14
-- The quest log's own geometry: a 29px search bar above the list, a 40px footer below it for the Go button.
local TOP_BAR = 29
local FOOTER = 40

---@type Frame?
local panel
---@type AGFTabButton?
local guideTab
---@type AGFTabButton?
local questsTab
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
---@type FontString?
local countText
-- Defined below the builders; the search box's handler needs it.
local Refresh
---@type FontString?
local emptyText
---@type Button?
local goButton
---@type Button?
local stopButton
---@type AGFSearchRow[]
local results = {}
---@type Frame?
local track
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

---@class AGFRouteRow : Button
---@field Selected Texture
---@field Ring Texture
---@field Number Texture
---@field Title FontString
---@field Detail FontString
---@field Tag FontString
---@field PinButton Button
---@field SkipButton Button
---@field step? AGFStep

---@param row AGFRouteRow
---@param atlas string
---@param tip fun(): string
---@param action fun(key: string)
---@return Button
local function CreateRowIcon(row, atlas, tip, action)
	local button = CreateFrame("Button", nil, row)
	button:SetSize(18, 18)
	button:SetNormalAtlas(atlas)
	button:SetHighlightAtlas(atlas, "ADD")
	button:SetScript("OnClick", function()
		if row.step then
			action(row.step.key)
		end
	end)
	button:SetScript("OnEnter", function(self)
		ShowTooltip(self, { tip() })
	end)
	button:SetScript("OnLeave", GameTooltip_Hide)
	return button
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
		return "Skip this step for now"
	end, ns.Skip)
	row.SkipButton:SetSize(14, 14)
	row.SkipButton:SetPoint("TOPRIGHT", -6, -7)
	row.PinButton = CreateRowIcon(row, "Waypoint-MapPin-Untracked", function()
		return (row.step and row.step.pinned) and "Unpin this step" or "Pin this step to the top of the route"
	end, ns.TogglePin)
	row.PinButton:SetPoint("RIGHT", row.SkipButton, "LEFT", -6, 0)

	row.Ring = row:CreateTexture(nil, "ARTWORK")
	row.Ring:SetAtlas("adventureguide-ring")
	row.Ring:SetSize(26, 26)
	row.Ring:SetPoint("LEFT", 6, 0)
	row.Number = row:CreateTexture(nil, "OVERLAY")
	row.Number:SetSize(22, 25)
	row.Number:SetPoint("CENTER", row.Ring)

	row.Title = row:CreateFontString(nil, "ARTWORK", "GameFontNormalMed3")
	row.Title:SetPoint("TOPLEFT", row.Ring, "TOPRIGHT", 8, 4)
	row.Title:SetPoint("RIGHT", row.PinButton, "LEFT", -4, 0)
	row.Title:SetJustifyH("LEFT")
	row.Title:SetWordWrap(false)

	row.Detail = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.Detail:SetPoint("TOPLEFT", row.Title, "BOTTOMLEFT", 0, -4)
	row.Detail:SetJustifyH("LEFT")
	row.Detail:SetWordWrap(false)
	row.Tag = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	row.Tag:SetPoint("LEFT", row.Detail, "RIGHT", 6, 0)
	row.Tag:SetText("optional")

	-- A quest in the log opens its details; any other step turns the map to it.
	row:SetScript("OnClick", function()
		if row.step and not ns.ShowQuest(row.step) then
			FocusStep(row.step)
		end
	end)
	return row
end

---@param parent Frame
---@return Frame
local function BuildHeader(parent)
	local header = CreateFrame("Frame", nil, parent)
	header:SetPoint("TOPLEFT", PAD, -4)
	header:SetPoint("RIGHT", -PAD, 0)
	header:SetHeight(34)
	local compass = header:CreateTexture(nil, "ARTWORK")
	compass:SetAtlas("islands-queue-prop-compass")
	compass:SetSize(30, 30)
	compass:SetPoint("LEFT", 2, 0)
	local title = header:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("CENTER", 14, 0)
	title:SetText(ns.TITLE)
	return header
end

---@class AGFJourneyCardIcon : Frame
---@field Border Texture
---@field Icon Texture

-- AdventureGuideForeverJourneyCardTemplate (Panel.xml).
---@class AGFJourneyCard : Button
---@field NormalTexture Texture
---@field PushedTexture Texture
---@field IconFrame AGFJourneyCardIcon
---@field Title FontString
---@field Subline FontString
---@field Reason FontString
---@field UpdateHighlightForState fun(self: AGFJourneyCard)
---@field journey? AGFJourney

-- One search result: the quest and where it starts, and for a locked one a lock and why (docs/design.md §2.4).
---@class AGFSearchRow : Frame
---@field Lock Texture
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
	row.Zone = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.Zone:SetPoint("TOPRIGHT", -4, -6)
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
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	return row
end

-- The cards, and the chosen card's step rows under it; the list lays them out from its top.
---@param parent Frame
---@param below Region
local function BuildJourneys(parent, below)
	list = CreateFrame("Frame", nil, parent)
	list:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -6)
	list:SetPoint("RIGHT", parent, "RIGHT", -PAD, 0)
	for index = 1, MAX_JOURNEYS do
		local card = CreateFrame("Button", nil, list, "AdventureGuideForeverJourneyCardTemplate") --[[@as AGFJourneyCard]]
		-- Choosing a journey shows its route and turns the map to it; it never starts guidance, only Go does. The map
		-- turns before the invalidation, so its redraw reads the route as it is and the one rebuild waits a frame.
		card:SetScript("OnClick", function(self)
			local journey = self.journey
			if journey then
				ns.Prefs().journey = journey.key
				WorldMapFrame:SetMapID(journey.map)
				ns.Invalidate()
			end
		end)
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
	emptyText = list:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	emptyText:SetPoint("TOPLEFT", 10, -8)
	emptyText:SetPoint("RIGHT", -10, 0)
	emptyText:SetJustifyH("LEFT")
end

---@param parent Frame
local function BuildFooter(parent)
	goButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate") --[[@as Button]]
	goButton:SetSize(190, 26)
	goButton:SetPoint("BOTTOMLEFT", PAD, 8)
	goButton:SetScript("OnClick", function()
		local step = ns.Route().steps[1]
		if step then
			ns.Integrations.Navigate(step)
			Refresh()
		end
	end)
	-- Shown only while Go's guidance runs (design §2.1): it never stops what the player or another addon started.
	stopButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate") --[[@as Button]]
	stopButton:SetSize(90, 26)
	stopButton:SetPoint("BOTTOMRIGHT", -PAD, 8)
	stopButton:SetText(L.STOP)
	stopButton:SetScript("OnClick", function()
		ns.Integrations.Cancel()
		Refresh()
	end)
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
	Pref("Quests", "quests")
	Pref("Dungeons", "dungeons")
	Setting("Show map pins", "showMapPins")
	-- Givers draw only with map pins on, so the box is grayed until they are (the menu polls a function).
	Setting("Show quest givers", "showQuestGivers"):SetEnabled(function()
		return ns.Setting("showMapPins")
	end)
	Setting("Show in objective tracker", "showTracker")
	menu:CreateButton("More settings", function()
		if ns.OpenSettings then
			ns.OpenSettings()
		end
	end)
end

-- The quest log's top bar: a search box for any quest, a count box and the settings cog.
---@param panelFrame Frame
local function BuildTopBar(panelFrame)
	local count = CreateFrame("Frame", nil, panelFrame, "InputBoxVisualTemplate") --[[@as Frame]]
	count:SetSize(100, 20)
	count:SetPoint("TOPRIGHT", -3, -2)
	countText = count:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	countText:SetPoint("RIGHT", -5, 0)

	searchBox = CreateFrame("EditBox", nil, panelFrame, "SearchBoxTemplate") --[[@as AGFSearchBox]]
	searchBox.Instructions:SetText(L.SEARCH_QUESTS)
	searchBox:SetHeight(20)
	searchBox:SetPoint("TOPLEFT", 6, -2)
	searchBox:SetPoint("RIGHT", count, "LEFT", -3, 0)
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
	row.Number:SetAtlas("services-number-" .. index)
	row.Title:SetText(step.title)
	row.Detail:SetText(step.detail)
	row.Tag:SetShown(step.optional == true)
	row:SetAlpha(step.optional and 0.6 or 1)
	row.PinButton:SetNormalAtlas(step.pinned and "Waypoint-MapPin-Tracked" or "Waypoint-MapPin-Untracked")
	row.Selected:SetShown(index == 1)
end

---@param card AGFJourneyCard
---@param journey AGFJourney
---@param chosen boolean
local function RefreshCard(card, journey, chosen)
	card.journey = journey
	card.IconFrame.Icon:SetAtlas(KIND_ICONS[journey.kind])
	card.Title:SetText(journey.title)
	card.Subline:SetText(journey.subline)
	card.Reason:SetText(journey.reason or "")
	card.NormalTexture:SetAtlas(chosen and CARD_ART_CHOSEN or CARD_ART)
	card:UpdateHighlightForState()
	-- The pressed art alone reads as the same brown card in game: the chosen card also keeps its hover highlight
	-- (its own art, added) lit, the way a stock list keeps its selected row lit.
	if chosen then
		card:LockHighlight()
	else
		card:UnlockHighlight()
	end
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

-- The chosen card's rows, from `top` down; `hidden` (no journey chosen, or a search) hides them all.
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

-- One result from `top` down. A quest the player can take now is a plain row; a locked one gets the lock and its
-- lines, unmet first. No ring and no Go: the search only explains.
---@param row AGFSearchRow
---@param id integer
---@param top number
---@return number top below it
local function RefreshResult(row, id, top)
	local state, data = ns.State, ns.Data
	local names = { title = QuestTitle, race = state.RaceName, class = state.ClassName }
	local why = ns.Model.Why(data, state.Player(), state.Completed(), state.Log(), id, names)
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
	row.why = shown
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

-- The cards in order, the chosen one followed by its rows, or the search's results; the scroll child's height is
-- summed, not measured, so it is right before the client has laid anything out.
---@param route AGFRoute
---@return boolean searching
---@return integer found
local function LayoutJourneys(route)
	---@cast searchBox -?
	---@cast countText -?
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
	for index, card in ipairs(cards) do
		local journey = not searching and route.journeys[index] or nil
		card:SetShown(journey ~= nil)
		if journey then
			RefreshCard(card, journey, journey.key == route.journey)
			card:SetPoint("TOP", list, "TOP", 0, -top)
			top = top + CARD_HEIGHT + CARD_GAP
			if journey.key == route.journey then
				top = LayoutTrack(journey, top)
				top = LayoutRows(route, top) + CARD_GAP
			end
		end
	end
	if searching or not route.journey then
		LayoutRows(route, top, true)
		top = math.max(top, 40)
	end
	countText:SetText(("Steps: %d"):format(#route.steps))
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
	---@cast goButton -?
	---@cast stopButton -?
	local route = ns.Route()

	local ready = ns.State.Ready()
	local searching, found = LayoutJourneys(route)
	emptyText:SetText((not ready and L.LOADING) or (searching and L.SEARCH_NONE) or L.NOTHING_NEARBY)
	emptyText:SetShown(not ready or (searching and found == 0) or (not searching and #route.journeys == 0))

	-- Go follows the chosen journey, which the search hides: it waits until the search is cleared.
	local provider = ns.Integrations.Provider()
	goButton:SetText(provider and ("Go (%s)"):format(provider) or "Set waypoint")
	goButton:SetEnabled(route.steps[1] ~= nil and not searching)
	stopButton:SetShown(ns.Integrations.Owns())
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
	BuildContent(panel)
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
