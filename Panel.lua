---@type string, AGFNamespace
local _, ns = ...

local MAX_STEPS = 5
local MAX_ZONES = 3
local PAD = 8
local ROW_HEIGHT = 44
local ROW_GAP = 2
local ROUTE_TOP = 34
local CARD_HEIGHT = 64
-- Classic's XP bar colours: blue while rested XP remains, purple once it runs out.
local XP_RESTED = { 0, 0.39, 0.88 }
local XP_NORMAL = { 0.58, 0, 0.55 }
local BUBBLES = 20

---@type Frame?
local panel
---@type AGFTabButton?
local guideTab
---@type AGFTabButton?
local questsTab
---@type FontString?
local levelText
---@type StatusBar?
local xpBar
---@type StatusBar?
local restedBar
---@type AGFChip[]
local chips = {}
---@type AGFZoneCard[]
local cards = {}
---@type FontString?
local routeLabel
---@type AGFRouteRow[]
local rows = {}
-- How many route rows fit the panel at its current height; the rest stay hidden.
local visibleRows = MAX_STEPS
-- Defined below the builders; the route section's resize handler needs it.
local Refresh
---@type FontString?
local emptyText
---@type Button?
local goButton

---@class AGFEdgeFrame : Frame, BackdropTemplate

---@class AGFEdged : Frame
---@field Edge AGFEdgeFrame

-- Classic frame edges, taken from the stock backdrops (tooltip edge for cards, toast edge for
-- the XP bar) on a child frame, so the edge draws over the art it frames.
---@param frame AGFEdged
---@param backdrop {edgeFile: string, edgeSize: number}
---@param outset number
local function AddEdge(frame, backdrop, outset)
	local edge = CreateFrame("Frame", nil, frame, "BackdropTemplate") --[[@as AGFEdgeFrame]]
	edge:SetPoint("TOPLEFT", -outset, outset)
	edge:SetPoint("BOTTOMRIGHT", outset, -outset)
	edge:SetBackdrop({ edgeFile = backdrop.edgeFile, edgeSize = backdrop.edgeSize, tileEdge = true })
	frame.Edge = edge
end

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

---@class AGFChip : Button
---@field pref "quests"|"dungeons"

---@param parent Frame
---@param label string
---@param pref "quests"|"dungeons"
---@return AGFChip
local function CreateChip(parent, label, pref)
	local chip = CreateFrame("Button", nil, parent, "UIMenuButtonStretchTemplate") --[[@as AGFChip]]
	chip.pref = pref
	chip:SetHeight(24)
	chip:SetText(label)
	-- A locked highlight is the template's own "on" state; gold text marks it like the mockup.
	chip:SetHighlightFontObject("GameFontNormal")
	chip:SetScript("OnClick", function()
		local prefs = ns.Prefs()
		prefs[pref] = not prefs[pref]
		ns.Invalidate()
	end)
	return chip
end

---@class AGFZoneCard : Button, AGFEdged
---@field Art Texture
---@field Name FontString
---@field Range FontString
---@field BestFit Frame
---@field art? integer uiMapID whose art is loaded
---@field zone? AGFZoneChoice

-- The card shows a crop of the zone's own world-map art: the middle tile of its base layer,
-- trimmed to the card's aspect. No per-zone artwork has to ship with the addon.
---@param card AGFZoneCard
---@param mapID integer
local function SetZoneArt(card, mapID)
	if card.art == mapID then
		return
	end
	card.art = mapID
	local layer = (C_Map.GetMapArtLayers(mapID) or {})[1]
	local textures = C_Map.GetMapArtLayerTextures(mapID, 1)
	if not (layer and textures and #textures > 0) then
		card.Art:SetColorTexture(0.12, 0.1, 0.08, 1)
		return
	end
	local columns = math.ceil(layer.layerWidth / layer.tileWidth)
	local tileRows = math.ceil(layer.layerHeight / layer.tileHeight)
	local index = math.floor(tileRows / 2) * columns + math.floor(columns / 2) + 1
	card.Art:SetTexture(textures[index] or textures[1])
	local width, height = card:GetSize()
	local trim = (1 - math.min(1, height / width)) / 2
	card.Art:SetTexCoord(0, 1, trim, 1 - trim)
end

---@param parent Frame
---@return AGFZoneCard
local function CreateZoneCard(parent)
	local card = CreateFrame("Button", nil, parent) --[[@as AGFZoneCard]]
	card:SetHeight(CARD_HEIGHT)
	card.Art = card:CreateTexture(nil, "BACKGROUND")
	card.Art:SetAllPoints()
	local veil = card:CreateTexture(nil, "BORDER")
	veil:SetAllPoints()
	veil:SetColorTexture(0, 0, 0, 0.35)
	local hover = card:CreateTexture(nil, "HIGHLIGHT")
	hover:SetAllPoints()
	hover:SetColorTexture(1, 1, 1, 0.1)

	card.Name = card:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	card.Name:SetPoint("LEFT", 4, 0)
	card.Name:SetPoint("RIGHT", -4, 0)
	card.Name:SetPoint("TOP", 0, -14)
	card.Name:SetShadowOffset(1, -1)
	card.Range = card:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	card.Range:SetPoint("TOP", card.Name, "BOTTOM", 0, -2)
	card.Range:SetShadowOffset(1, -1)

	card.BestFit = CreateFrame("Frame", nil, card)
	card.BestFit:SetPoint("BOTTOMLEFT", 1, 1)
	card.BestFit:SetPoint("BOTTOMRIGHT", -1, 1)
	card.BestFit:SetHeight(15)
	local band = card.BestFit:CreateTexture(nil, "BACKGROUND")
	band:SetAllPoints()
	band:SetColorTexture(0, 0, 0, 0.7)
	local best = card.BestFit:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	best:SetPoint("CENTER")
	best:SetText("Best fit")

	AddEdge(card, BACKDROP_TUTORIAL_16_16, 3)
	card:SetScript("OnClick", function()
		local zone = card.zone
		if not zone then
			return
		end
		local prefs = ns.Prefs()
		if prefs.zone == zone.map or zone.best then
			prefs.zone = nil
		else
			prefs.zone = zone.map
		end
		ns.Invalidate()
	end)
	card:SetScript("OnEnter", function(self)
		local zone = self.zone
		if zone then
			ShowTooltip(self, {
				zone.name,
				("Levels %d-%d"):format(zone.min, zone.max),
				("%d quests you can pick up"):format(zone.quests),
			})
		end
	end)
	card:SetScript("OnLeave", GameTooltip_Hide)
	return card
end

---@class AGFRouteRow : Button
---@field Selected Texture
---@field Ring Texture
---@field Number FontString
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
	row.Number = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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

	row:SetScript("OnClick", function()
		if row.step then
			FocusStep(row.step)
		end
	end)
	return row
end

---@param parent Frame
---@param below Region
---@param height number
---@return Frame
local function CreateSection(parent, below, height)
	local section = CreateFrame("Frame", nil, parent, "InsetFrameTemplate") --[[@as AGFInset]]
	-- The inset's marble fill reads as a grey slab on the quest log's parchment; keep only its edge.
	section.Bg:Hide()
	section:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -6)
	section:SetPoint("RIGHT", parent, "RIGHT", -PAD, 0)
	section:SetHeight(height)
	return section
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

---@param parent Frame
---@param below Region
---@return Frame
local function BuildExperience(parent, below)
	local section = CreateSection(parent, below, 48)
	levelText = section:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	levelText:SetPoint("TOP", 0, -8)

	restedBar = CreateFrame("StatusBar", nil, section)
	restedBar:SetPoint("TOPLEFT", 10, -26)
	restedBar:SetPoint("RIGHT", -10, 0)
	restedBar:SetHeight(12)
	restedBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	restedBar:SetStatusBarColor(XP_RESTED[1], XP_RESTED[2], XP_RESTED[3], 0.35)
	local trough = restedBar:CreateTexture(nil, "BACKGROUND")
	trough:SetAllPoints()
	trough:SetColorTexture(0, 0, 0, 0.6)
	AddEdge(restedBar --[[@as AGFEdged]], BACKDROP_TOAST_12_12, 4)

	xpBar = CreateFrame("StatusBar", nil, restedBar)
	xpBar:SetAllPoints()
	xpBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
	local label = xpBar:CreateFontString(nil, "OVERLAY", "TextStatusBarText")
	label:SetPoint("CENTER", 0, 1)
	label:SetText("XP")
	return section
end

---@param parent Frame
---@param below Region
---@return Frame
local function BuildChips(parent, below)
	local strip = CreateFrame("Frame", nil, parent)
	strip:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -8)
	strip:SetPoint("RIGHT", parent, "RIGHT", -PAD, 0)
	strip:SetHeight(24)
	chips[1] = CreateChip(strip, "Quests", "quests")
	chips[1]:SetPoint("TOPLEFT")
	chips[1]:SetPoint("RIGHT", strip, "CENTER", -3, 0)
	chips[2] = CreateChip(strip, "Dungeons", "dungeons")
	chips[2]:SetPoint("TOPRIGHT")
	chips[2]:SetPoint("LEFT", strip, "CENTER", 3, 0)
	return strip
end

---@param parent Frame
---@param below Region
---@return Frame
local function BuildZones(parent, below)
	local section = CreateSection(parent, below, CARD_HEIGHT + 40)
	local label = section:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
	label:SetPoint("TOPLEFT", 10, -9)
	label:SetText("Where next?")
	for index = 1, MAX_ZONES do
		local card = CreateZoneCard(section)
		card:SetPoint("TOP", 0, -32)
		if index == 1 then
			card:SetPoint("LEFT", 8, 0)
		else
			card:SetPoint("LEFT", cards[index - 1], "RIGHT", 6, 0)
		end
		cards[index] = card
	end
	section:SetScript("OnSizeChanged", function(_, width)
		for _, card in ipairs(cards) do
			card:SetWidth((width - 16 - 6 * (MAX_ZONES - 1)) / MAX_ZONES)
			-- The crop depends on the card's aspect, so redo it at the new width.
			card.art = nil
			if card.zone then
				SetZoneArt(card, card.zone.map)
			end
		end
	end)
	return section
end

---@param parent Frame
---@param below Region
local function BuildRoute(parent, below)
	local section = CreateSection(parent, below, 0)
	section:SetPoint("BOTTOM", parent, "BOTTOM", 0, 40)
	routeLabel = section:CreateFontString(nil, "ARTWORK", "GameFontHighlightMedium")
	routeLabel:SetPoint("TOPLEFT", 10, -9)
	for index = 1, MAX_STEPS do
		local row = CreateRow(section)
		local top = -ROUTE_TOP - (index - 1) * (ROW_HEIGHT + ROW_GAP)
		row:SetPoint("TOPLEFT", 6, top)
		row:SetPoint("TOPRIGHT", -6, top)
		rows[index] = row
	end
	-- Show only the rows that fit: the panel's height depends on the map size and UI scale.
	section:SetScript("OnSizeChanged", function(_, _, height)
		local fit = math.floor((height - ROUTE_TOP - 6 + ROW_GAP) / (ROW_HEIGHT + ROW_GAP))
		visibleRows = math.max(1, math.min(MAX_STEPS, fit))
		Refresh()
	end)
	emptyText = section:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	emptyText:SetPoint("TOPLEFT", routeLabel, "BOTTOMLEFT", 0, -16)
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
		end
	end)

	local why = CreateFrame("Button", nil, parent)
	why:SetSize(90, 26)
	why:SetPoint("BOTTOMRIGHT", -PAD, 8)
	why:SetNormalFontObject("GameFontNormal")
	why:SetHighlightFontObject("GameFontHighlight")
	why:SetText("Why these?")
	why:SetScript("OnEnter", function(self)
		local lines = { "Why these steps?" }
		for index, step in ipairs(ns.Route().steps) do
			lines[#lines + 1] = ("%d. %s - %s"):format(index, step.title, step.reason)
		end
		ShowTooltip(self, lines)
	end)
	why:SetScript("OnLeave", GameTooltip_Hide)
end

---@param panelFrame Frame
local function BuildContent(panelFrame)
	local header = BuildHeader(panelFrame)
	local experience = BuildExperience(panelFrame, header)
	local strip = BuildChips(panelFrame, experience)
	local zones = BuildZones(panelFrame, strip)
	BuildRoute(panelFrame, zones)
	BuildFooter(panelFrame)
end

local function RefreshExperience()
	---@cast levelText -?
	---@cast xpBar -?
	---@cast restedBar -?
	local level = UnitLevel("player")
	local xp, xpMax = UnitXP("player"), UnitXPMax("player")
	if not (xpMax and xpMax > 0) then
		levelText:SetText(("|cffffd100Level %d|r"):format(level))
		xpBar:SetMinMaxValues(0, 1)
		xpBar:SetValue(1)
		restedBar:SetValue(0)
		return
	end
	local rested = GetXPExhaustion() or 0
	local text = ("|cffffd100Level %d|r - %d%% to %d"):format(level, math.floor(xp / xpMax * 100), level + 1)
	if rested > 0 then
		text = ("%s - Rested %.1f bubbles"):format(text, rested / (xpMax / BUBBLES))
	end
	levelText:SetText(text)
	local color = rested > 0 and XP_RESTED or XP_NORMAL
	xpBar:SetStatusBarColor(color[1], color[2], color[3])
	xpBar:SetMinMaxValues(0, xpMax)
	xpBar:SetValue(xp)
	restedBar:SetMinMaxValues(0, xpMax)
	restedBar:SetValue(math.min(xpMax, xp + rested))
end

---@param route AGFRoute
---@param prefs AGFPrefs
local function RefreshChoices(route, prefs)
	for _, chip in ipairs(chips) do
		local on = prefs[chip.pref]
		chip:SetNormalFontObject(on and "GameFontNormal" or "GameFontDisable")
		if on then
			chip:LockHighlight()
		else
			chip:UnlockHighlight()
		end
	end
	for index, card in ipairs(cards) do
		local zone = route.zones[index]
		card.zone = zone
		card:SetShown(zone ~= nil)
		if zone then
			SetZoneArt(card, zone.map)
			card.Name:SetText(zone.name)
			card.Range:SetText(("%d-%d"):format(zone.min, zone.max))
			card.BestFit:SetShown(zone.best)
			if zone.map == route.zone then
				card.Edge:SetBackdropBorderColor(NORMAL_FONT_COLOR:GetRGB())
			else
				card.Edge:SetBackdropBorderColor(GRAY_FONT_COLOR:GetRGB())
			end
		end
	end
end

---@param row AGFRouteRow
---@param step AGFStep
---@param index integer
local function RefreshRow(row, step, index)
	row.Number:SetText(tostring(index))
	row.Title:SetText(step.title)
	row.Detail:SetText(step.detail)
	row.Tag:SetShown(step.optional == true)
	row:SetAlpha(step.optional and 0.6 or 1)
	row.PinButton:SetNormalAtlas(step.pinned and "Waypoint-MapPin-Tracked" or "Waypoint-MapPin-Untracked")
	row.Selected:SetShown(index == 1)
end

function Refresh()
	if not (panel and panel:IsShown()) then
		return
	end
	-- BuildContent() always sets every upvalue below before Attach() registers this listener.
	---@cast routeLabel -?
	---@cast emptyText -?
	---@cast goButton -?
	local route = ns.Route()
	RefreshExperience()
	RefreshChoices(route, ns.Prefs())

	routeLabel:SetText(route.minutes and ("Suggested route - about %d min"):format(route.minutes) or "Suggested route")
	if not ns.State.Ready() then
		emptyText:SetText("Loading your completed quests...")
	elseif #route.steps == 0 then
		emptyText:SetText("Nothing left here at your level - pick another zone.")
	end
	emptyText:SetShown(not ns.State.Ready() or #route.steps == 0)
	for index, row in ipairs(rows) do
		local step = index <= visibleRows and route.steps[index] or nil
		row.step = step
		row:SetShown(step ~= nil)
		if step then
			RefreshRow(row, step, index)
		end
	end

	local provider = ns.Integrations.Provider()
	goButton:SetText(provider and ("Go (%s)"):format(provider) or "Set waypoint")
	goButton:SetEnabled(route.steps[1] ~= nil)
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
	panel:SetPoint("TOPLEFT", map.ContentsAnchor, 0, -29)
	panel:SetPoint("BOTTOMRIGHT", map.ContentsAnchor, -22, 0)
	-- The quest list's own background and gold frame, so the guide reads as another page of the same log.
	local background = panel:CreateTexture(nil, "BACKGROUND")
	background:SetAtlas("QuestLog-main-background")
	background:SetAllPoints()
	CreateFrame("Frame", nil, panel, "QuestLogBorderFrameTemplate")
	-- Above the quest details view, which is not one of the content frames ShowGuide hides.
	panel:SetFrameLevel(map:GetFrameLevel() + 20)
	panel:EnableMouse(true)
	panel:Hide()
	BuildContent(panel)
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

	function ns.OpenPanel()
		-- Also brings back a collapsed quest sidebar, which hides QuestMapFrame and so the panel inside it.
		OpenQuestLog()
		ShowGuide(true)
	end
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", Attach)
