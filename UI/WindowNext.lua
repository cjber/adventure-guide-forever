---@type string, AGFNamespace
local _, ns = ...
local L = ns.L
local Window = ns.Window

-- Next reads existing offers and delegates navigation to Recommendations (docs/design.md, Next page).

local Recommendations = ns.Recommendations
local TOP, LEFT = Window.TOP, Window.LEFT
local WIDTH = Window.INSET_WIDTH - LEFT - Window.RIGHT
local FOCUS_GAP, FOCUS_HEIGHT = 6, 22
local CARD_TOP, CARD_HEIGHT, RING, PAD = TOP + 48, 140, 44, 18
local ALTERNATIVES, ROW_HEIGHT, ROW_PITCH = 3, 36, 40
local ACTION_WIDTH, ACTION_HEIGHT = 110, 22
local BROWSE_WIDTH = 150
local FOCUS_LABELS = {
	balanced = L.NEXT_FOCUS_BALANCED,
	quests = L.NEXT_FOCUS_QUESTS,
	training = L.NEXT_FOCUS_TRAINING,
	professions = L.NEXT_FOCUS_PROFESSIONS,
	dungeons = L.NEXT_FOCUS_DUNGEONS,
}

---@class AGFNextAction : Button
---@field item? AGFRecommendation

---@class AGFNextCard : AGFWindowCard
---@field Advice FontString
---@field item? AGFRecommendation
---@field Icon AGFRingIcon
---@field Title FontString
---@field WhyHeading FontString
---@field Reason FontString
---@field Action AGFNextAction

---@class AGFNextRow : AGFWindowIconRow
---@field item? AGFRecommendation
---@field Action AGFNextAction
---@field Advice FontString

---@class AGFNextPage
---@field Focus table<string, Button>
---@field Card AGFNextCard
---@field Rows AGFNextRow[]
---@field Heading FontString
---@field Empty FontString
---@field Alternatives FontString

---@type AGFNextPage?
local page

---@param owner AGFNextCard|AGFNextRow
local function Enter(owner)
	if owner.item then
		ns.Overview.ShowTooltip(owner, { owner.item.title, owner.item.reason })
	end
end

-- The tab with `key`, as the Browse buttons jump to it.
---@param key string
local function GoTab(key)
	for index, tab in ipairs(Window.Tabs()) do
		if tab.key == key then
			Window.Select(index)
			return
		end
	end
end

---@param button AGFNextAction
local function Act(button)
	local item = button.item
	if item then
		Recommendations.Act(item)
	end
	Window.Refresh()
end

---@param parent Frame
---@param name string
---@param width number
---@return AGFNextAction
local function CreateAction(parent, name, width)
	local button = CreateFrame("Button", name, parent, "UIPanelButtonTemplate") --[[@as AGFNextAction]]
	button:SetSize(width, ACTION_HEIGHT)
	button:SetScript("OnClick", Act)
	return button
end

-- The action's label and whether it can be pressed; a text-only hint is advice, with nothing to press.
---@param button AGFNextAction
---@param advice FontString?
---@param item AGFRecommendation
local function SetAction(button, advice, item)
	button.item = item
	local aside = item.aside
	local text = aside and not aside.place
	button:SetShown(not text)
	button:SetText(Recommendations.ActionLabel(item))
	button:SetEnabled(Recommendations.CanAct(item))
	if advice then
		advice:SetShown(text)
	end
end

---@param content Frame
---@return AGFNextCard
local function CreateMain(content)
	local card = Window.CreateCard(content, false) --[[@as AGFNextCard]]
	Window.SizeCard(card, WIDTH, CARD_HEIGHT, 0.8)
	card:SetPoint("TOPLEFT", LEFT, -CARD_TOP)
	card:EnableMouse(true)
	card:SetScript("OnEnter", Enter)
	card:SetScript("OnLeave", GameTooltip_Hide)
	card:SetScript("OnHide", GameTooltip_Hide)
	local inner = CreateFrame("Frame", "AdventureGuideForeverNextCardInner", card)
	inner:SetAllPoints()
	inner:SetFrameLevel(card:GetFrameLevel() + 5)
	card.Icon = Window.CreateRingIcon(inner, RING)
	card.Icon:SetPoint("TOPLEFT", PAD, -PAD)
	local left = PAD + RING + 14
	card.Title = inner:CreateFontString(nil, "ARTWORK", Window.FONT_TITLE)
	card.Title:SetTextColor(Window.TITLE_INK[1], Window.TITLE_INK[2], Window.TITLE_INK[3])
	card.Title:SetPoint("TOPLEFT", left, -16)
	card.Title:SetPoint("RIGHT", -16, 0)
	card.WhyHeading = Window.Heading(inner, L.NEXT_WHY)
	card.WhyHeading:SetPoint("TOPLEFT", left, -62)
	card.Reason = inner:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	card.Reason:SetPoint("TOPLEFT", left, -80)
	card.Reason:SetPoint("RIGHT", -(ACTION_WIDTH + 28), 0)
	for _, text in ipairs({ card.Title, card.Reason }) do
		text:SetJustifyH("LEFT")
		text:SetWordWrap(true)
	end
	card.Title:SetMaxLines(2)
	card.Reason:SetMaxLines(3)
	card.Action = CreateAction(inner, "AdventureGuideForeverNextAction", ACTION_WIDTH)
	card.Action:SetPoint("BOTTOMRIGHT", -16, 14)
	card.Advice = inner:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	card.Advice:SetPoint("BOTTOMRIGHT", -16, 14)
	card.Advice:SetText(L.NEXT_ADVICE)
	return card
end

---@param content Frame
---@param index integer
---@return AGFNextRow
local function CreateRow(content, index)
	local row = Window.CreateIconRow(content, ROW_HEIGHT) --[[@as AGFNextRow]]
	row:SetWidth(WIDTH)
	row:EnableMouse(true)
	row:SetScript("OnEnter", Enter)
	row:SetScript("OnLeave", GameTooltip_Hide)
	row:SetScript("OnHide", GameTooltip_Hide)
	row:SetPoint("TOPLEFT", LEFT, -(CARD_TOP + CARD_HEIGHT + 28 + (index - 1) * ROW_PITCH))
	row.Title:SetPoint("RIGHT", -(ACTION_WIDTH + 20), 0)
	row.Detail:SetPoint("RIGHT", -(ACTION_WIDTH + 20), 0)
	row.Action = CreateAction(row, "AdventureGuideForeverNextRowAction" .. index, ACTION_WIDTH - 20)
	row.Action:SetPoint("RIGHT", -8, 0)
	row.Advice = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	row.Advice:SetPoint("RIGHT", -16, 0)
	row.Advice:SetText(L.NEXT_ADVICE)
	return row
end

---@class AGFNextContent : Frame
---@field NextEmpty FontString

---@param content AGFNextContent
local function Build(content)
	local heading = Window.Heading(content, L.NEXT_TITLE)
	heading:SetFontObject(Window.FONT_ROW)
	heading:SetPoint("TOPLEFT", LEFT + 2, -TOP)
	local focus = {}
	local width = (WIDTH - (#Recommendations.FOCUSES - 1) * FOCUS_GAP) / #Recommendations.FOCUSES
	for index, name in ipairs(Recommendations.FOCUSES) do
		local button = CreateFrame("Button", "AdventureGuideForeverNextFocus" .. name, content, "UIPanelButtonTemplate")
		button:SetSize(width, FOCUS_HEIGHT)
		button:SetPoint("TOPLEFT", LEFT + (index - 1) * (width + FOCUS_GAP), -(TOP + 20))
		button:SetText(FOCUS_LABELS[name])
		button:SetScript("OnClick", function()
			Recommendations.SetFocus(name)
		end)
		focus[name] = button
	end
	local card = CreateMain(content)
	local empty = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	content.NextEmpty = empty
	empty:SetPoint("TOPLEFT", LEFT + 40, -(CARD_TOP + 30))
	empty:SetWidth(WIDTH - 80)
	empty:SetHeight(48)
	empty:SetJustifyH("CENTER")
	local alternatives = Window.Heading(content, L.NEXT_ALTERNATIVES)
	alternatives:SetPoint("TOPLEFT", LEFT + 2, -(CARD_TOP + CARD_HEIGHT + 8))
	local rows = {}
	for index = 1, ALTERNATIVES do
		rows[index] = CreateRow(content, index)
	end
	local bottom = Window.INSET_HEIGHT - 12 - FOCUS_HEIGHT
	for index, browse in ipairs({
		{ key = "journeys", text = L.NEXT_BROWSE_JOURNEYS },
		{ key = "dungeons", text = L.NEXT_BROWSE_DUNGEONS },
	}) do
		local button =
			CreateFrame("Button", "AdventureGuideForeverNextBrowse" .. browse.key, content, "UIPanelButtonTemplate")
		button:SetSize(BROWSE_WIDTH, FOCUS_HEIGHT)
		button:SetPoint("TOPLEFT", LEFT + (index - 1) * (BROWSE_WIDTH + FOCUS_GAP), -bottom)
		button:SetText(browse.text)
		button:SetScript("OnClick", function()
			GoTab(browse.key)
		end)
	end
	page = {
		Focus = focus,
		Card = card,
		Rows = rows,
		Heading = heading,
		Empty = empty,
		Alternatives = alternatives,
	}
end

---@param row AGFNextRow
---@param item AGFRecommendation
local function SetRow(row, item)
	row.item = item
	Window.SetRingIcon(row.Icon, item.icon)
	row.Title:SetText(item.title)
	row.Detail:SetText(item.reason)
	SetAction(row.Action, row.Advice, item)
end

local function Refresh()
	if not page then
		return
	end
	local focus = Recommendations.Focus()
	for name, button in pairs(page.Focus) do
		button:SetEnabled(name ~= focus)
	end
	local items = Recommendations.Current()
	local lead = items[1]
	page.Card:SetShown(lead ~= nil)
	page.Empty:SetShown(lead == nil)
	page.Alternatives:SetShown(items[2] ~= nil)
	if lead then
		local card = page.Card
		card.item = lead
		Window.SetRingIcon(card.Icon, lead.icon)
		card.Title:SetText(lead.title)
		card.Reason:SetText(lead.reason)
		SetAction(card.Action, card.Advice, lead)
	else
		page.Empty:SetText(ns.RouteSettled() and L.NEXT_EMPTY or L.NEXT_LOADING)
	end
	for index, row in ipairs(page.Rows) do
		local item = items[index + 1]
		row:SetShown(item ~= nil)
		if item then
			SetRow(row, item)
		end
	end
end

Window.AddTab({ key = "next", label = L.TAB_NEXT, Build = Build, Refresh = Refresh })
