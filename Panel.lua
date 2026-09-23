---@type string, AGFNamespace
local _, ns = ...

local MAX_STEPS = 5
local MAX_ZONES = 3
-- A sentinel that never equals a QuestLogDisplayMode enum value (0, 1 or 2) or any other
-- addon's own sentinel, so QuestLogMixin:SetDisplayMode always sees a real change and never
-- no-ops while our tab is showing (see ShowPanel/OnBlizzardDisplayModeChanged below).
local DISPLAY_MODE = {}

---@type AGFTabButton?
local tab
---@type Frame?
local panel
---@type FontString?
local levelText
---@type FontString?
local emptyText
---@type AGFCheckButton?
local chipQuests
---@type AGFCheckButton?
local chipDungeons
---@type AGFZoneButton[]
local zoneButtons = {}
---@type AGFRouteRow[]
local rows = {}
---@type Button?
local goButton

---@param step AGFStep
local function FocusStep(step)
	WorldMapFrame:SetMapID(step.map)
	-- The map's data providers (Pins.lua among them) refresh in response to SetMapID; wait a
	-- frame so the pin exists before it's asked to flash.
	C_Timer.After(0, function()
		ns.Pins.Ping(step.key)
	end)
end

---@param parent Frame
---@param label string
---@return AGFCheckButton
local function CreateChip(parent, label)
	local chip = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate") --[[@as AGFCheckButton]]
	chip:SetSize(24, 24)
	chip.text:SetText(label)
	return chip
end

---@class AGFZoneButton : Button
---@field zone? AGFZoneChoice

---@class AGFRouteRow : Button
---@field Number FontString
---@field Title FontString
---@field Detail FontString
---@field PinButton CheckButton
---@field SkipButton Button
---@field step? AGFStep

---@param parent Frame
---@return AGFRouteRow
local function CreateRow(parent)
	local row = CreateFrame("Button", nil, parent) --[[@as AGFRouteRow]]
	row:SetHeight(34)

	row.SkipButton = CreateFrame("Button", nil, row, "UIPanelCloseButton") --[[@as Button]]
	row.SkipButton:SetSize(20, 20)
	row.SkipButton:SetPoint("TOPRIGHT", 0, 2)
	row.SkipButton:SetScript("OnClick", function()
		if row.step then
			ns.Skip(row.step.key)
		end
	end)
	row.SkipButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText("Skip this step for now")
		GameTooltip:Show()
	end)
	row.SkipButton:SetScript("OnLeave", GameTooltip_Hide)

	row.PinButton = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate") --[[@as CheckButton]]
	row.PinButton:SetSize(20, 20)
	row.PinButton:SetPoint("RIGHT", row.SkipButton, "LEFT", -2, 0)
	row.PinButton:SetScript("OnClick", function()
		if row.step then
			ns.TogglePin(row.step.key)
		end
	end)
	row.PinButton:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(self:GetChecked() and "Unpin this step" or "Pin this step to the top of the route")
		GameTooltip:Show()
	end)
	row.PinButton:SetScript("OnLeave", GameTooltip_Hide)

	row.Number = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	row.Number:SetPoint("TOPLEFT", 2, -2)
	row.Number:SetWidth(18)
	row.Number:SetJustifyH("CENTER")

	-- Gold: GameFontNormal is already the game's warm gold-tan colour, so no manual recolour.
	row.Title = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	row.Title:SetPoint("TOPLEFT", row.Number, "TOPRIGHT", 4, 0)
	row.Title:SetPoint("RIGHT", row.PinButton, "LEFT", -4, 0)
	row.Title:SetJustifyH("LEFT")

	-- Grey: GameFontDisableSmall is the stock disabled/secondary colour.
	row.Detail = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	row.Detail:SetPoint("TOPLEFT", row.Title, "BOTTOMLEFT", 0, -2)
	row.Detail:SetPoint("RIGHT", row.Title, "RIGHT")
	row.Detail:SetJustifyH("LEFT")

	row:SetScript("OnClick", function()
		if row.step then
			FocusStep(row.step)
		end
	end)
	return row
end

---@param panelFrame Frame
local function BuildContent(panelFrame)
	local header = panelFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	header:SetPoint("TOPLEFT", 8, -8)
	header:SetText("Adventure Guide")

	levelText = panelFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	levelText:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)

	chipQuests = CreateChip(panelFrame, "Quests")
	chipQuests:SetPoint("TOPLEFT", levelText, "BOTTOMLEFT", -2, -8)
	chipQuests:SetScript("OnClick", function(self)
		ns.Prefs().quests = not not self:GetChecked()
		ns.Invalidate()
	end)

	chipDungeons = CreateChip(panelFrame, "Dungeons")
	chipDungeons:SetPoint("LEFT", chipQuests.text, "RIGHT", 16, 0)
	chipDungeons:SetScript("OnClick", function(self)
		ns.Prefs().dungeons = not not self:GetChecked()
		ns.Invalidate()
	end)

	local whereNext = panelFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	whereNext:SetPoint("TOPLEFT", chipQuests, "BOTTOMLEFT", 2, -10)
	whereNext:SetText("Where next?")

	---@type Region
	local previous = whereNext
	for index = 1, MAX_ZONES do
		local button = CreateFrame("Button", nil, panelFrame, "UIPanelButtonTemplate") --[[@as AGFZoneButton]]
		button:SetSize(96, 22)
		if index == 1 then
			button:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", -2, -6)
		else
			button:SetPoint("LEFT", zoneButtons[index - 1], "RIGHT", 6, 0)
		end
		button:SetScript("OnClick", function()
			local zone = button.zone
			if not zone then
				return
			end
			local prefs = ns.Prefs()
			prefs.zone = (prefs.zone == zone.map) and nil or zone.map
			ns.Invalidate()
		end)
		zoneButtons[index] = button
	end

	local routeLabel = panelFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	routeLabel:SetPoint("TOPLEFT", zoneButtons[1], "BOTTOMLEFT", 2, -12)
	routeLabel:SetText("Suggested route")

	previous = routeLabel
	for index = 1, MAX_STEPS do
		local row = CreateRow(panelFrame)
		row:SetPoint("TOPLEFT", previous, "BOTTOMLEFT", -2, index == 1 and -6 or 0)
		row:SetPoint("RIGHT", panelFrame, "RIGHT", -8, 0)
		rows[index] = row
		previous = row
	end

	emptyText = panelFrame:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	emptyText:SetPoint("TOPLEFT", routeLabel, "BOTTOMLEFT", 4, -20)
	emptyText:SetPoint("RIGHT", panelFrame, "RIGHT", -8, 0)
	emptyText:SetJustifyH("LEFT")
	emptyText:SetWordWrap(true)

	goButton = CreateFrame("Button", nil, panelFrame, "UIPanelButtonTemplate") --[[@as Button]]
	goButton:SetSize(140, 24)
	goButton:SetPoint("BOTTOMRIGHT", -8, 8)
	goButton:SetScript("OnClick", function()
		local step = ns.Route().steps[1]
		if step then
			ns.Integrations.Navigate(step)
		end
	end)
end

local function Refresh()
	if not (panel and panel:IsShown()) then
		return
	end
	-- BuildContent() always sets every upvalue below before Attach() registers this listener.
	---@cast chipQuests -?
	---@cast chipDungeons -?
	---@cast levelText -?
	---@cast emptyText -?
	---@cast goButton -?
	local route = ns.Route()
	local prefs = ns.Prefs()

	chipQuests:SetChecked(prefs.quests)
	chipDungeons:SetChecked(prefs.dungeons)

	local level = UnitLevel("player")
	local xp, xpMax = UnitXP("player"), UnitXPMax("player")
	if xpMax and xpMax > 0 then
		local rested = (GetXPExhaustion() or 0) > 0
		levelText:SetText(("Level %d - %d / %d XP%s"):format(level, xp, xpMax, rested and " (rested)" or ""))
	else
		levelText:SetText(("Level %d"):format(level))
	end

	for index, button in ipairs(zoneButtons) do
		local zone = route.zones[index]
		button.zone = zone
		if zone then
			button:Show()
			button:SetText(zone.best and ("%s (best fit)"):format(zone.name) or zone.name)
			if prefs.zone == zone.map then
				button:LockHighlight()
			else
				button:UnlockHighlight()
			end
		else
			button:Hide()
		end
	end

	if not ns.State.Ready() then
		emptyText:SetText("Loading your completed quests...")
		emptyText:Show()
	elseif #route.steps == 0 then
		emptyText:SetText("Nothing left here at your level - pick another zone.")
		emptyText:Show()
	else
		emptyText:Hide()
	end

	for index, row in ipairs(rows) do
		local step = route.steps[index]
		row.step = step
		if step then
			row:Show()
			row.Number:SetText(tostring(index))
			row.Title:SetText(step.title)
			row.Detail:SetText(step.detail)
			row.PinButton:SetChecked(not not step.pinned)
		else
			row:Hide()
		end
	end

	local provider = ns.Integrations.Provider()
	goButton:SetText(provider and ("Go (%s)"):format(provider) or "Set waypoint")
	goButton:SetEnabled(route.steps[1] ~= nil)
end

---@param displayMode table
local function OnBlizzardDisplayModeChanged(_, displayMode)
	-- Only ever registered as a callback from Attach(), which sets tab/panel first.
	---@cast tab -?
	---@cast panel -?
	if displayMode ~= DISPLAY_MODE then
		tab:SetChecked(false)
		panel:Hide()
	end
end

local function ShowPanel()
	-- ns.OpenPanel only exists once Attach() has set tab/panel (see the bottom of Attach()).
	---@cast tab -?
	---@cast panel -?
	local map = QuestMapFrame
	if map.displayMode == DISPLAY_MODE then
		return
	end
	for _, button in ipairs(map.TabButtons) do
		button:SetChecked(false)
	end
	for _, frame in ipairs(map.ContentFrames) do
		frame:Hide()
	end
	map.displayMode = DISPLAY_MODE
	tab:SetChecked(true)
	panel:Show()
	if not WorldMapFrame:IsShown() then
		ToggleWorldMap()
	end
	Refresh()
end

local function Attach()
	local map = QuestMapFrame

	tab = CreateFrame("Frame", "AdventureGuideForeverTab", map, "QuestLogTabButtonTemplate") --[[@as AGFTabButton]]
	tab.activeAtlas = "UI-HUD-MicroMenu-AdventureGuide-Down"
	tab.inactiveAtlas = "UI-HUD-MicroMenu-AdventureGuide-Up"
	tab.tooltipText = "Adventure Guide"
	tab:SetPoint("TOP", map.MapLegendTab, "BOTTOM", 0, -3)
	tab:SetChecked(false)
	tab:SetCustomOnMouseUpHandler(function(_, mouseButton, upInside)
		if mouseButton == "LeftButton" and upInside then
			ShowPanel()
		end
	end)

	panel = CreateFrame("Frame", "AdventureGuideForeverPanel", map)
	panel:SetPoint("TOPLEFT", map.ContentsAnchor, 0, -29)
	panel:SetPoint("BOTTOMRIGHT", map.ContentsAnchor, -22, 0)
	panel:Hide()
	BuildContent(panel)

	-- Never inserted into map.TabButtons/ContentFrames: QuestLogMixin:SetDisplayMode only ever
	-- touches those two arrays, so it never needs to know we exist. Instead we read them (never
	-- write) to hide Blizzard's own tab/content when ours takes over, and listen for its event to
	-- hide ours back when the player picks Quests/Events/Map Legend again.
	EventRegistry:RegisterCallback("QuestLog.SetDisplayMode", OnBlizzardDisplayModeChanged, panel)
	ns.OnRouteChange(Refresh)

	function ns.OpenPanel()
		ShowPanel()
	end
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", Attach)
