---@type string, AGFNamespace
local _, ns = ...
local Window, Overview, L = ns.Window, ns.Overview, ns.L
local LEFT, TOP = Window.LEFT, 50
local WIDTH = Window.INSET_WIDTH - Window.LEFT - Window.RIGHT
local SIDE_LEFT, SIDE_WIDTH = LEFT + 438, WIDTH - 438
local ROWS, PITCH = 6, 38
---@type AGFJourney?
local journey
---@type AGFWindowStepRow[]
local rows = {}
---@type FontString
local title, reason, status, empty, stepHeading, detailHeading, detailHint, pageText, estimate
---@type Button
local start, stop, entrance, guide, session, reset, previous, nextPage
---@type AGFDungeonListWidget
local details
---@type AGFJourneyBanner
local banner
---@type AGFRingIcon
local bannerIcon
local page = 1
local Refresh
local lootInstance, lootSource
local lootRows, lootHint = {}, nil
local detailRoute, detailValues

---@class AGFWindowStepRow : AGFWindowRow, AGFDraggableRow
---@field step? AGFStep
---@field index? integer

---@param label string
---@param x number
---@param action fun()
---@return Button
local function Button(parent, label, x, action)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate") --[[@as Button]]
	button:SetSize(100, 22)
	button:SetPoint("TOPLEFT", x, -112)
	button:SetText(label)
	button:SetScript("OnClick", action)
	return button
end

local function ShowMap()
	local step = ns.Guidance.CurrentStep() or ns.Route().steps[1]
	if step then
		Overview.ShowOnMap(step)
	end
end

---@return table[], string?
local function DetailRows()
	if not journey then
		return {}, nil
	elseif journey.instance then
		if
			lootInstance ~= journey.instance
			or lootSource ~= AtlasLoot
			or (lootHint ~= nil and lootHint ~= L.DUNGEON_LOOT_UNKNOWN)
		then
			lootInstance, lootSource = journey.instance, AtlasLoot
			local bosses
			bosses, lootHint = ns.DungeonLoot.Bosses(journey.instance)
			lootRows = {}
			for _, boss in ipairs(bosses) do
				lootRows[#lootRows + 1] = { heading = true, title = boss.name }
				for _, id in ipairs(boss.items) do
					lootRows[#lootRows + 1] = { item = id }
				end
			end
		end
		return lootRows, lootHint
	end
	local route = ns.Route()
	if detailRoute == route then
		return detailValues, nil
	end
	local data, player = ns.Data, ns.State.Player()
	local log, completed = ns.State.Log(), ns.State.Completed()
	local values, seen = {}, {}
	for _, step in ipairs(ns.Route().steps) do
		for _, id in ipairs(step.quests) do
			if not seen[id] then
				seen[id] = true
				local quest = data.quests[id]
				values[#values + 1] = { quest = id, title = ns.State.QuestTitle(id) or (quest and quest.title) or "" }
			end
		end
	end
	for _, id in ipairs(Window.GuideOutline(data, player, completed, journey, ns.Route().steps)) do
		values[#values + 1] = { quest = id, title = data.quests[id].title, future = true }
	end
	for _, value in ipairs(values) do
		local entry = log[value.quest]
		value.info = value.future and L.GUIDE_OUTLINE
			or entry and (entry.complete and L.READY_TO_HAND_IN or L.QUESTS_IN_PROGRESS)
			or L.DUNGEON_PICKUP
	end
	detailRoute, detailValues = route, values
	return values, nil
end

---@param minutes integer
local function SessionLabel(minutes)
	return minutes == 0 and L.SESSION_UNLIMITED or L.SESSION_MINUTES:format(minutes)
end

-- Forever build 70009 crashes in Blizzard_Menu.AcquireMenu when opening the native picker.
-- Keep this small selector entirely in addon-owned frames, outside the native menu pool.
---@param content Frame
---@return Button
local function CreateSessionPicker(content)
	local button = CreateFrame("Button", nil, content, "UIPanelButtonTemplate") --[[@as Button]]
	button:SetSize(100, 22)
	button:SetPoint("BOTTOMRIGHT", -Window.RIGHT, 5)
	local popup = CreateFrame("Frame", "AdventureGuideForeverSessionPicker", button)
	popup:SetSize(144, #ns.Session.LENGTHS * 26 + 12)
	popup:SetPoint("BOTTOMRIGHT", button, "TOPRIGHT", 0, 2)
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

local function Build(parent)
	banner = Window.CreateCard(parent, true) --[[@as AGFJourneyBanner]]
	Window.SizeCard(banner, WIDTH, 56, 0.65)
	banner:SetPoint("TOPLEFT", LEFT, -TOP)
	local inner = CreateFrame("Frame", nil, banner)
	inner:SetAllPoints()
	inner:SetFrameLevel(banner:GetFrameLevel() + 5)
	bannerIcon = Window.CreateRingIcon(inner, 36)
	bannerIcon:SetPoint("TOPLEFT", 12, -10)
	title = inner:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
	title:SetPoint("TOPLEFT", 60, -8)
	title:SetWidth(WIDTH - 180)
	title:SetJustifyH("LEFT")
	title:SetMaxLines(1)
	reason = inner:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	reason:SetPoint("TOPLEFT", 60, -30)
	reason:SetWidth(WIDTH - 80)
	reason:SetJustifyH("LEFT")
	reason:SetMaxLines(1)
	status = inner:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
	status:SetPoint("TOPRIGHT", -12, -10)
	banner:SetScript("OnClick", function()
		if journey then
			Window.OpenGuide(journey, parent)
		end
	end)
	banner:HookScript("OnEnter", function(self)
		if journey then
			Overview.ShowTooltip(self, { journey.title, L.GUIDE_OPEN })
		end
	end)
	banner:HookScript("OnLeave", GameTooltip_Hide)
	start = Button(parent, L.START_ADVENTURE, LEFT, function()
		if journey and not InCombatLockdown() then
			if ns.Route().chosen then
				ns.StartRoute()
			else
				ns.Choose(journey.key, true)
			end
		end
	end)
	stop = Button(parent, L.STOP, LEFT + 106, ns.Stop)
	guide = Button(parent, L.GUIDE_OPEN, LEFT + 212, function()
		if journey then
			Window.OpenGuide(journey, parent)
		end
	end)
	guide:SetWidth(112)
	entrance = Button(parent, L.GO_TO_ENTRANCE, SIDE_LEFT, function()
		if journey and journey.instance then
			ns.Dungeons.GoEntrance(journey.instance)
		end
	end)
	entrance:SetWidth(112)
	estimate = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	estimate:SetPoint("TOPRIGHT", parent, "TOPLEFT", LEFT + 420, -142)
	stepHeading = Window.Heading(parent, L.DO_THIS_NEXT)
	stepHeading:SetPoint("TOPLEFT", LEFT, -142)
	detailHeading = Window.Heading(parent, L.JOURNEY_QUESTS)
	detailHeading:SetPoint("TOPLEFT", SIDE_LEFT, -142)
	for index = 1, ROWS do
		local row = Window.CreateStepRow(parent, 36) --[[@as AGFWindowStepRow]]
		row:SetPoint("TOPLEFT", LEFT, -(166 + (index - 1) * PITCH))
		row:SetWidth(420)
		row:SetScript("OnEnter", Overview.RowEnter)
		row:SetScript("OnLeave", Overview.RowLeave)
		row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
		row:SetScript("OnClick", function(self, button)
			if self.step then
				if button == "RightButton" then
					Overview.StepMenu(self, self.step, self.index)
				elseif not ns.ShowQuest(self.step) then
					Overview.ShowOnMap(self.step)
				end
			end
		end)
		rows[index] = row
	end
	Overview.Draggable(rows[1], rows, Window.Refresh)
	for index = 2, ROWS do
		Overview.Draggable(rows[index], rows, Window.Refresh)
	end
	details = Window.CreateList(parent, SIDE_LEFT, 166, SIDE_WIDTH - 12, 226, 36, function(row, value)
		row.Title:SetText(value.title or (value.item and C_Item.GetItemNameByID(value.item)) or L.ITEM_LOADING)
		row.Info:SetText(value.info or "")
		row.Info:SetFontObject(value.future and "GameFontDisableSmall" or "GameFontHighlightSmall")
		local itemIcon = value.item and C_Item.GetItemIconByID(value.item)
		row.Icon:SetShown(itemIcon ~= nil)
		row:SetEnabled(not value.future and not value.heading)
		row:SetMotionScriptsWhileDisabled(true)
		if value.item then
			if itemIcon then
				ns.Art.Icon(row.Icon, itemIcon, 28)
			end
			if not C_Item.GetItemNameByID(value.item) then
				ns.Dungeons.RequestItem(value.item)
			end
		end
		row.Title:ClearAllPoints()
		row.Title:SetPoint("TOPLEFT", value.item and 36 or 4, -3)
		row.Title:SetWidth(SIDE_WIDTH - (value.item and 54 or 22))
		row.Title:SetFontObject(value.heading and "GameFontNormalSmall" or "GameFontHighlightSmall")
	end, function(value)
		if value.quest and ns.State.Log()[value.quest] then
			for _, step in ipairs(ns.Route().steps) do
				for _, id in ipairs(step.quests) do
					if id == value.quest then
						ns.ShowQuest(step)
						return
					end
				end
			end
		end
	end, function(parentFrame, width, height, click)
		local row = CreateFrame("Button", nil, parentFrame) --[[@as AGFDungeonRow]]
		row:SetSize(width, height)
		row.Icon = row:CreateTexture(nil, "ARTWORK")
		row.Icon:SetPoint("LEFT", 3, 0)
		row.Title = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
		row.Title:SetJustifyH("LEFT")
		row.Title:SetMaxLines(1)
		row.Info = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
		row.Info:SetPoint("BOTTOMLEFT", 4, 2)
		row.Info:SetWidth(width - 8)
		row.Info:SetJustifyH("LEFT")
		row:SetScript("OnClick", function(self)
			click(self.value)
		end)
		row:SetScript("OnEnter", function(self)
			if self.value.item then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip:SetItemByID(self.value.item)
				GameTooltip:Show()
			elseif self.value.title then
				Overview.ShowTooltip(self, { self.value.title, self.value.info })
			end
		end)
		row:SetScript("OnLeave", GameTooltip_Hide)
		row:SetScript("OnHide", GameTooltip_Hide)
		return row
	end)
	detailHint = parent:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	detailHint:SetPoint("TOPLEFT", SIDE_LEFT, -166)
	detailHint:SetWidth(SIDE_WIDTH - 12)
	detailHint:SetJustifyH("LEFT")
	empty = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	empty:SetPoint("TOPLEFT", LEFT, -170)
	empty:SetWidth(420)
	empty:SetJustifyH("LEFT")
	previous, nextPage, pageText = Window.CreatePager(parent, function()
		page = math.max(1, page - 1)
		Refresh()
	end, function()
		page = page + 1
		Refresh()
	end)
	previous:ClearAllPoints()
	previous:SetPoint("BOTTOMLEFT", LEFT, 5)
	nextPage:ClearAllPoints()
	nextPage:SetPoint("LEFT", previous, "RIGHT", 70, 0)
	pageText:ClearAllPoints()
	pageText:SetPoint("LEFT", previous, "RIGHT", 8, 0)
	session = CreateSessionPicker(parent)
	reset = Button(parent, L.ORDER_RESET, LEFT + 260, ns.Order.Reset)
	reset:ClearAllPoints()
	reset:SetPoint("LEFT", nextPage, "RIGHT", 10, 0)
	reset:SetWidth(160)
end

Refresh = function()
	local route = ns.Route()
	local first = Overview.Split(route)
	if not journey or not first or journey.key ~= first.key then
		page = 1
	end
	journey = first
	local chosen = first and route.chosen and first.key == route.journey
	local current = chosen and ns.Guidance.CurrentStep()
	local begin = 1
	if current then
		for index, step in ipairs(route.steps) do
			if step.key == current.key then
				begin = index
				break
			end
		end
	end
	local total = first and math.max(0, #route.steps - begin + 1) or 0
	local pages
	page, pages = Window.ClampPage(page, total, ROWS)
	for index, row in ipairs(rows) do
		local position = begin + (page - 1) * ROWS + index - 1
		local step = first and route.steps[position]
		row.step, row.index = step, step and position or nil
		row:SetShown(step ~= nil)
		if step then
			Window.SetStepRow(row, position, step.title, step.detail, step)
			local active = position == begin
			ns.Art.SetSliceShown(row.Selected, active)
			row.Title:SetFontObject(active and "GameFontNormalMed3" or "GameFontHighlight")
			row.Title:SetAlpha(step.optional and not active and 0.75 or 1)
		end
	end
	banner:SetShown(first ~= nil)
	if first then
		Window.SetRingIcon(bannerIcon, Overview.KIND_ICONS[first.kind])
		local place = Overview.IconStep(first)
		ns.ZoneIcon.SetBackdrop(
			banner.Art --[[@as AGFZoneBackdrop]],
			WIDTH - 4,
			52,
			place and place.map,
			place and place.x,
			place and place.y,
			640
		)
		title:SetText(first.title)
		reason:SetText(Overview.VisitWarning(first) or Overview.DropLine(first) or first.reason or first.subline or "")
		local _, label = Overview.Progress(first)
		banner.journey = first
		status:SetText(chosen and ns.Order.IsCustom() and L.ORDER_CUSTOM or chosen and L.YOUR_CHOICE or L.RECOMMENDED)
		if label then
			reason:SetText(reason:GetText() .. L.SEPARATOR .. label)
		end
	end
	start:SetShown(first ~= nil)
	local actionText = (
		(ns.Guidance.Owns() or ns.Setting("wanderer")) and L.SHOW_ON_MAP
		or ns.Guidance.Status() == "paused" and L.RESUME_ADVENTURE
		or L.START_ADVENTURE
	)
	start:SetText(actionText)
	start:SetEnabled(
		first ~= nil
			and total > 0
			and not InCombatLockdown()
			and not ns.Setting("wanderer")
			and not ns.Session.Info().pending
	)
	start:SetScript("OnClick", (ns.Guidance.Owns() or ns.Setting("wanderer")) and ShowMap or function()
		if journey and start:IsEnabled() and not InCombatLockdown() then
			if ns.Route().chosen then
				ns.StartRoute()
			else
				ns.Choose(journey.key, true)
			end
		end
	end)
	stop:SetShown(chosen == true)
	stop:SetEnabled(not InCombatLockdown())
	guide:ClearAllPoints()
	guide:SetPoint("LEFT", chosen and stop or start, "RIGHT", 6, 0)
	guide:SetShown(first ~= nil)
	entrance:SetShown(first ~= nil and first.instance ~= nil)
	entrance:SetEnabled(
		first ~= nil
			and first.instance ~= nil
			and ns.Dungeons.Entrance(first.instance) ~= nil
			and not InCombatLockdown()
			and not ns.Setting("wanderer")
	)
	stepHeading:SetShown(first ~= nil)
	empty:SetShown(total == 0)
	empty:SetText(
		(ns.SourceHint and ns.SourceHint()) or (ns.Session.Info().empty and L.SESSION_EMPTY) or L.JOURNEY_CHOOSE
	)
	local values, hint = DetailRows()
	Window.SetList(details, values)
	details.frame:SetShown(#values > 0)
	detailHeading:SetShown(first ~= nil)
	detailHeading:SetText(first and first.instance and L.DUNGEON_BOSSES_LOOT or L.JOURNEY_QUESTS)
	detailHint:SetShown(hint ~= nil)
	detailHint:SetText(hint or "")
	previous:SetShown(pages > 1)
	nextPage:SetShown(pages > 1)
	pageText:SetShown(pages > 1)
	previous:SetEnabled(page > 1)
	nextPage:SetEnabled(page < pages)
	pageText:SetText(L.JOURNEY_PAGE:format(page, pages))
	reset:SetShown(chosen and ns.Order.IsCustom() or false)
	local info = ns.Session.Info()
	local line = chosen
			and (info.pending and L.SESSION_PENDING or info.seconds and L.SESSION_ABOUT:format(
				math.ceil(info.seconds / 60)
			))
		or nil
	estimate:SetText(line or "")
	estimate:SetShown(line ~= nil)
	session:SetShown(first ~= nil)
	local minutes = ns.Session.Get()
	session:SetText(minutes == 0 and L.SESSION_UNLIMITED or L.SESSION_MINUTES:format(minutes))
end

Window.AddTab({ key = "journeys", label = L.TAB_JOURNEYS, Build = Build, Refresh = Refresh })
