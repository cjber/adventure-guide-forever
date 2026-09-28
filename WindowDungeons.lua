---@type string, AGFNamespace
local _, ns = ...
local L, Window, Dungeons = ns.L, ns.Window, ns.Dungeons

-- §2.21: the shared EJ frame, featured card and divider; fixed columns and recycled scrolling rows.
-- Work belongs to the visible page. Hiding it cancels its coroutine before any more source reads or drawing.
local LEFT, TOP = Window.LEFT, Window.TOP
local LIST_W, GAP, HEADER_H = 168, 28, 100
local RIGHT_X = LEFT + LIST_W + GAP
local PAGE_W = Window.INSET_WIDTH - Window.RIGHT - RIGHT_X
local BODY_Y, BODY_H, QUEST_W = TOP + HEADER_H + 38, 222, 272
local DETAIL_H = BODY_H - 52
local ROW_H, LIST_H, SLICE_MS = 52, 42, 1
---@type Frame
local content
---@type AGFWindowCard
local header
---@type AGFRingIcon
local dungeonIcon
---@type FontString
local title, location, summary, note
---@type Button
local entrance, journey
---@class AGFDungeonPlan : CheckButton
---@field Text FontString
---@type AGFDungeonPlan
local plan
---@type AGFWindowEmpty
local empty
---@type Frame
local detail
---@type FontString
local detailTitle, detailInfo, detailGiver, detailEnd, detailObjective, detailObjectives, detailRewards, detailChain
---@type Frame
local detailBody
---@type AGFScrollFrame
local detailScroll
---@type Texture
local detailDivider
---@type Button
local giver
---@type Button[]
local rewards = {}
---@type AGFTopTab[]
local subTabs = {}
---@type AGFDungeonListWidget
local list, quests, other
---@type AGFDungeon[]
local catalog = {}
---@type AGFDungeonPage?
local page
---@type AGFDungeonSource?
local source
---@type AGFData?
local sourceData
---@type AGFDungeonBoss[]?
local bosses
local listSelection
local journalIcon
local sourceRead, sourceError, generation, view = false, false, 0, "quests"
---@type integer?
local selectedQuest
---@type table<integer, boolean>
local expanded = {}
local Refresh, Draw, SelectQuest

---@param parent Frame
---@param text string
---@param x number
---@param y number
---@param width number
---@param font? string
---@return FontString
local function Text(parent, text, x, y, width, font)
	local label = parent:CreateFontString(nil, "ARTWORK", font or "GameFontHighlightSmall")
	label:SetPoint("TOPLEFT", x, -y)
	label:SetWidth(width)
	label:SetJustifyH("LEFT")
	label:SetText(text)
	return label
end

---@param parent Frame
---@param label string
---@param x number
---@param y number
---@param width number
---@param action fun()
---@return Button
local function Button(parent, label, x, y, width, action)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate") --[[@as Button]]
	button:SetSize(width, 22)
	button:SetPoint("TOPLEFT", x, -y)
	button:SetText(label)
	button:SetScript("OnClick", action)
	return button
end

---@param button Button
---@param place? fun(): AGFPoint|AGFPlace?
---@param row? Button
local function MapTooltip(button, place, row)
	local function Leave()
		if place then
			ns.Pins.Highlight(place(), false)
		end
		if row then
			row:UnlockHighlight()
		end
		GameTooltip_Hide()
	end
	button:SetMotionScriptsWhileDisabled(true)
	button:SetScript("OnEnter", function()
		if ns.Setting("wanderer") then
			ns.Overview.ShowTooltip(button, { L.DUNGEON_WANDERER })
		elseif place then
			ns.Pins.Highlight(place(), true)
			if row then
				row:LockHighlight()
			end
		end
	end)
	button:SetScript("OnLeave", Leave)
	button:SetScript("OnHide", Leave)
end

---@class AGFDungeonRow : Button
---@field Title FontString
---@field Info FontString
---@field Giver FontString
---@field Selected AGFArtSlice
---@field Map Button
---@field Expand AGFCollapseButton
---@field ItemIcon Texture
---@field value? table

---@class AGFDungeonListWidget
---@field frame AGFScrollFrame
---@field child Frame
---@field rows AGFDungeonRow[]
---@field values table[]
---@field height number
---@field rowHeight number
---@field width number
---@field paint fun(row: AGFDungeonRow, value: table)

---@param widget AGFDungeonListWidget
local function PaintList(widget)
	local offset = math.floor((widget.frame:GetVerticalScroll() or 0) / widget.rowHeight)
	for index, row in ipairs(widget.rows) do
		local position = offset + index
		local value = widget.values[position]
		row.value = value
		row:SetShown(value ~= nil)
		if value then
			row:ClearAllPoints()
			row:SetHeight(widget.rowHeight - 2)
			row:SetPoint("TOPLEFT", 0, -(position - 1) * widget.rowHeight)
			widget.paint(row, value)
		end
	end
end

---@param parent Frame
---@param x number
---@param y number
---@param width number
---@param height number
---@param rowHeight number
---@param paint fun(row: AGFDungeonRow, value: table)
---@param click fun(value: table)
---@return AGFDungeonListWidget
local function List(parent, x, y, width, height, rowHeight, paint, click)
	local scroll = CreateFrame("ScrollFrame", nil, parent, "ScrollFrameTemplate") --[[@as AGFScrollFrame]]
	scroll:SetPoint("TOPLEFT", x, -y)
	scroll:SetSize(width, height)
	scroll.ScrollBar:ClearAllPoints()
	scroll.ScrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 3, 0)
	scroll.ScrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 3, 0)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(width, height)
	scroll:SetScrollChild(child)
	local widget = {
		frame = scroll,
		child = child,
		rows = {},
		values = {},
		height = height,
		rowHeight = rowHeight,
		width = width,
		paint = paint,
	}
	for index = 1, math.ceil(height / rowHeight) + 1 do
		local row = CreateFrame("Button", nil, child) --[[@as AGFDungeonRow]]
		row:SetSize(width, rowHeight - 2)
		row.ItemIcon = row:CreateTexture(nil, "ARTWORK")
		row.ItemIcon:SetSize(24, 24)
		row.ItemIcon:SetPoint("TOPLEFT", 8, -5)
		row.ItemIcon:Hide()
		row.Selected = ns.Art.RowArt(row, true) --[[@as AGFArtSlice]]
		row.Title = Text(row, "", 8, 5, width - 16, "GameFontNormal")
		row.Title:SetWordWrap(false)
		row.Info = Text(row, "", 8, 21, width - 16)
		row.Info:SetWordWrap(false)
		row.Giver = Text(row, "", 8, 35, width - 16, "GameFontDisableSmall")
		row.Giver:SetWordWrap(false)
		row.Map = Button(row, L.DUNGEON_MAP, width - 48, 24, 46, function()
			if row.value and row.value.quest then
				Dungeons.Go(row.value.quest.id)
			end
		end)
		MapTooltip(row.Map)
		row.Expand = CreateFrame("Button", nil, row, "CollapseButtonTemplate") --[[@as AGFCollapseButton]]
		row.Expand:SetSize(20, 20)
		row.Expand:SetPoint("TOPLEFT", 3, -2)
		row.Expand:SetScript("OnClick", function()
			if row.value and row.value.quest then
				local id = row.value.quest.id
				expanded[id] = not expanded[id]
				Draw()
			end
		end)
		row:SetScript("OnClick", function()
			if row.value then
				click(row.value)
			end
		end)
		row:SetScript("OnEnter", function()
			local lines = { row.Title:GetText(), row.Info:GetText(), row.Giver:GetText() }
			ns.Overview.ShowTooltip(row, lines)
		end)
		row:SetScript("OnLeave", GameTooltip_Hide)
		widget.rows[index] = row
	end
	scroll:HookScript("OnVerticalScroll", function()
		PaintList(widget)
	end)
	return widget
end

---@param widget AGFDungeonListWidget
---@param values table[]
local function SetList(widget, values)
	widget.values = values
	widget.child:SetHeight(math.max(widget.height, #values * widget.rowHeight))
	widget.frame.ScrollBar:SetShown(#values * widget.rowHeight > widget.height)
	PaintList(widget)
end

---@param dungeon AGFDungeon
---@return string
local function Range(dungeon)
	if dungeon.low then
		return L.DUNGEON_QUEST_LEVELS:format(dungeon.low, dungeon.high)
	end
	return ""
end

---@param quest AGFDungeonQuest
---@return string
local function Status(quest)
	local labels = {
		done = L.DUNGEON_DONE,
		log = L.DUNGEON_IN_LOG,
		available = L.DUNGEON_PICKUP,
		pre = L.DUNGEON_PRE,
		unknown = L.DUNGEON_UNAVAILABLE,
	}
	return quest.status == "level" and L.DUNGEON_LEVEL:format(quest.requiredLevel) or labels[quest.status]
end

---@param place? AGFPlace
---@return string
local function Place(place)
	if not place or not place.name or place.name == "" then
		return ""
	end
	local hub = place.hub and ns.Data.hubs[place.hub]
	local name = hub and hub.name:match("^(.-),") or hub and hub.name or ns.State.ZoneName(place.map)
	return place.name .. (name and name ~= "" and L.SEPARATOR .. name or "")
end

---@param quest AGFDungeonQuest
---@return string
local function Giver(quest)
	local data = ns.Data.quests[quest.id]
	return Place(data and data.start)
end

local requestedItems = {}
---@param id integer
---@return integer?
local function ItemIcon(id)
	local icon = C_Item.GetItemIconByID(id)
	if not icon and not requestedItems[id] then
		requestedItems[id] = true
		C_Item.RequestLoadItemDataByID(id)
	end
	return icon
end

---@param row AGFDungeonRow
---@param value table
local function PaintQuest(row, value)
	local quest = value.quest
	row.Title:SetText((ns.State.QuestTitle(quest.id) or quest.title))
	row.Title:ClearAllPoints()
	row.Title:SetPoint("TOPLEFT", value.chain and 34 or 24, -5)
	row.Info:SetText(Status(quest))
	row.Giver:SetText(Giver(quest))
	row.Title:SetWidth(QUEST_W - (value.chain and 34 or 24) - 74 - 16)
	row.Info:ClearAllPoints()
	row.Info:SetPoint("TOPRIGHT", -8, -7)
	row.Info:SetWidth(74)
	row.Info:SetJustifyH("RIGHT")
	row.Giver:ClearAllPoints()
	row.Giver:SetPoint("TOPLEFT", value.chain and 34 or 24, -21)
	row.Giver:SetWidth(QUEST_W - (value.chain and 34 or 24) - 8)
	row.Map:SetShown(value.chain and quest.place ~= nil)
	row.Map:ClearAllPoints()
	row.Map:SetPoint("TOPRIGHT", -4, -18)
	row.Map:SetHeight(18)
	if value.chain and quest.place then
		row.Giver:SetWidth(QUEST_W - 34 - 58)
	end
	MapTooltip(row.Map, function()
		return quest.place
	end, row)
	row.Map:SetEnabled(quest.place ~= nil and not ns.Setting("wanderer"))
	row.Expand:SetShown(not value.chain and #Dungeons.Chain(ns.Data, quest.id, function() end) > 1)
	row.Expand:UpdateCollapsedState(not expanded[quest.id])
	row:SetScript("OnEnter", function()
		local lines = { row.Title:GetText(), Status(quest), Giver(quest) }
		if value.alternative then
			lines[#lines + 1] = L.DUNGEON_ALTERNATIVE
		end
		for _, reason in
			ipairs(ns.Model.Why(ns.Data, ns.State.Player(), ns.State.Completed(), ns.State.Log(), quest.id))
		do
			if not reason.met then
				lines[#lines + 1] = reason.text
			end
		end
		ns.Overview.ShowTooltip(row, lines)
	end)
	ns.Art.SetSliceShown(row.Selected, selectedQuest == quest.id)
end

local function QuestRows()
	if not page then
		return {}
	end
	local values = {}
	for _, quest in ipairs(page.quests) do
		values[#values + 1] = { quest = quest }
		if expanded[quest.id] then
			local chain = Dungeons.Chain(ns.Data, quest.id, function() end)
			local alternatives = {}
			for _, id in ipairs(chain) do
				for _, pre in ipairs((ns.Data.quests[id] or {}).preAny or {}) do
					alternatives[pre] = true
				end
			end
			for _, id in ipairs(chain) do
				if id ~= quest.id and Dungeons.ForCharacter(ns.Data.quests[id], ns.State.Player()) then
					values[#values + 1] = {
						quest = Dungeons.Quest(ns.Data, ns.State.Player(), ns.State.Completed(), ns.State.Log(), id),
						chain = true,
						alternative = alternatives[id],
					}
				end
			end
		end
	end
	return values
end

---@param row AGFDungeonRow
---@param value table
local function PaintOther(row, value)
	if not page then
		return
	end
	local instance = page.dungeon.id
	local icon = value.item and ItemIcon(value.item)
	row.ItemIcon:SetShown(icon ~= nil)
	if icon then
		row.ItemIcon:SetTexture(icon)
	end
	for _, text in ipairs({ row.Title, row.Info, row.Giver }) do
		text:ClearAllPoints()
	end
	row.Title:SetPoint("TOPLEFT", icon and 44 or 8, -5)
	row.Info:SetPoint("TOPLEFT", icon and 44 or 8, -21)
	row.Giver:SetPoint("TOPLEFT", icon and 44 or 8, -35)
	row.Title:SetText(value.title)
	row.Title:SetFontObject((value.heading or value.boss) and "GameFontNormal" or "GameFontHighlight")
	---@type table<integer, { r: number, g: number, b: number }>
	local qualityColors = rawget(_G, "ITEM_QUALITY_COLORS")
	local color = value.item and qualityColors and qualityColors[value.quality]
	if color then
		row.Title:SetTextColor(color.r, color.g, color.b)
	elseif value.boss then
		row.Title:SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
	else
		row.Title:SetTextColor(1, 1, 1)
	end
	row:EnableMouse(not value.heading)
	row:SetScript("OnEnter", function()
		if value.item then
			GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
			GameTooltip:SetItemByID(value.item)
			GameTooltip:Show()
		else
			ns.Overview.ShowTooltip(row, { value.title, value.info or "", value.giver or "", value.description or "" })
		end
	end)
	row.Info:SetText(value.info or "")
	row.Giver:SetText(value.giver or "")
	local point = value.entrance and Dungeons.Entrance(instance, source) or value.quest and value.quest.place
	MapTooltip(row.Map, function()
		return point
	end, row)
	row.Map:SetShown(point ~= nil)
	row.Map:SetEnabled(not ns.Setting("wanderer"))
	row.Map:SetScript("OnClick", function()
		if value.entrance then
			Dungeons.GoEntrance(instance, source)
		elseif value.quest then
			Dungeons.Go(value.quest.id)
		end
	end)
	row.Expand:Hide()
	row.Title:SetWidth(PAGE_W - 80)
	row.Info:SetWidth(PAGE_W - 80)
	row.Giver:SetWidth(PAGE_W - 80)
	ns.Art.SetSliceShown(row.Selected, false)
end

---@param item integer
---@return string?
local function ItemName(item)
	local name = C_Item.GetItemNameByID(item)
	if not name and not requestedItems[item] then
		requestedItems[item] = true
		C_Item.RequestLoadItemDataByID(item)
	end
	return name
end

local function PrepRows()
	if not page then
		return {}
	end
	local values, seen = {}, {}
	for _, entry in ipairs(page.prep) do
		if entry.quest then
			values[#values + 1] = {
				title = entry.quest.title,
				info = (entry.kind == "pre" and L.DUNGEON_PRE_ELSEWHERE or L.DUNGEON_OUTSIDE) .. L.SEPARATOR .. Status(
					entry.quest
				),
				giver = Giver(entry.quest),
				quest = entry.quest,
			}
		elseif entry.gate then
			local gate = entry.gate
			---@cast gate AGFEntranceGate
			local lines = {}
			if gate.level > 0 then
				lines[#lines + 1] = L.DUNGEON_ENTRY_LEVEL:format(gate.level)
			end
			if gate.items then
				local items = {}
				for _, item in ipairs(gate.items) do
					local name = ItemName(item)
					if name then
						items[#items + 1] = name
					end
				end
				if #items == #gate.items then
					lines[#lines + 1] = L.DUNGEON_REQUIRES_ITEM:format(table.concat(items, L.DUNGEON_OR))
				end
			end
			if gate.quest then
				local quest = ns.Data.quests[gate.quest]
				lines[#lines + 1] = L.WHY_COMPLETED:format(
					ns.State.QuestTitle(gate.quest) or (quest and quest.title) or L.WHY_EARLIER_QUEST
				)
			end
			if gate.conditional then
				lines[#lines + 1] = L.DUNGEON_GATE_UNKNOWN
			end
			local text = table.concat(lines, L.SEPARATOR)
			if text ~= "" and not seen[text] then
				seen[text] = true
				table.insert(values, 1, { title = L.DUNGEON_ENTRANCE_REQUIREMENTS, info = text, entrance = true })
			end
		end
	end
	return values
end

function SelectQuest(id)
	selectedQuest = id
	detailScroll:SetVerticalScroll(0)
	Draw()
end

local function DrawDetail()
	local quest = selectedQuest
		and Dungeons.Quest(ns.Data, ns.State.Player(), ns.State.Completed(), ns.State.Log(), selectedQuest)
	detail:SetShown(view == "quests" and quest ~= nil)
	if not quest then
		return
	end
	local cursor = 0
	local function Line(label, text)
		label:SetText(text)
		label:SetShown(text ~= "")
		if text ~= "" then
			label:ClearAllPoints()
			label:SetPoint("TOPLEFT", 0, -cursor)
			cursor = cursor + label:GetStringHeight() + 4
		end
	end
	Line(detailTitle, ns.State.QuestTitle(quest.id) or quest.title)
	local info = {}
	if quest.level and quest.level > 0 then
		info[#info + 1] = L.DUNGEON_QUEST_LEVEL:format(quest.level)
	end
	if quest.xp and quest.xp > 0 then
		info[#info + 1] = L.DUNGEON_XP:format(BreakUpLargeNumbers(quest.xp))
	end
	Line(detailInfo, table.concat(info, L.SEPARATOR))
	local objective = Dungeons.Objective(quest.id, source)
	if objective then
		cursor = cursor + 6
	end
	Line(detailObjectives, objective and L.DUNGEON_OBJECTIVES or "")
	Line(detailObjective, objective or "")
	cursor = cursor + 6
	local record = ns.Data.quests[quest.id]
	local start, finish = Place(record and record.start), Place(record and record.finish)
	Line(detailGiver, start ~= "" and L.DUNGEON_START:format(start) or "")
	Line(detailEnd, finish ~= "" and finish ~= start and L.DUNGEON_END:format(finish) or "")
	local items = source and source.rewards[quest.id] or {}
	detailDivider:SetShown(#items > 0)
	if #items > 0 then
		detailDivider:ClearAllPoints()
		detailDivider:SetPoint("TOPLEFT", 0, -cursor)
		cursor = cursor + 10
	end
	Line(detailRewards, #items > 0 and L.DUNGEON_REWARDS or "")
	for index, button in ipairs(rewards) do
		local item = items[index]
		local icon = item and ItemIcon(item.id)
		button:SetShown(icon ~= nil)
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", (index - 1) * 36, -cursor)
		if icon and item then
			button:SetNormalTexture(icon)
			button:SetScript("OnEnter", function()
				GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
				GameTooltip:SetItemByID(item.id)
				GameTooltip:Show()
			end)
		end
	end
	if #items > 0 then
		cursor = cursor + 38
	end
	local part, total
	for _, parent in ipairs(page and page.quests or {}) do
		local position, count = Dungeons.ChainPosition(ns.Data, parent.id, quest.id)
		if position and (not total or count > total) then
			part, total = position, count
		end
	end
	Line(detailChain, part and L.DUNGEON_PART:format(part, total) or "")
	detailBody:SetHeight(math.max(DETAIL_H, cursor))
	detailScroll.ScrollBar:SetShown(cursor > DETAIL_H)
	detail:SetScript("OnEnter", function()
		local lines = {}
		if objective then
			lines[#lines + 1] = objective
		end
		for _, line in ipairs(ns.Model.Why(ns.Data, ns.State.Player(), ns.State.Completed(), ns.State.Log(), quest.id)) do
			if not line.met then
				lines[#lines + 1] = line.text
			end
		end
		if #lines > 0 then
			ns.Overview.ShowTooltip(detail, lines)
		end
	end)
	MapTooltip(giver, function()
		return quest.place
	end, nil)
	giver:SetShown(quest.place ~= nil)
	giver:SetEnabled(not ns.Setting("wanderer"))
end

function Draw()
	if not page or not content:IsVisible() then
		return
	end
	local dungeon = page.dungeon
	local point = Dungeons.Entrance(dungeon.id, source)
	Window.SetEmpty(empty, nil)
	Window.SetRingIcon(dungeonIcon, journalIcon or "dungeon")
	title:SetText(ns.State.InstanceName(dungeon.id) or dungeon.name)
	location:SetText(
		point and L.DUNGEON_ENTRANCE_AT:format(ns.State.ZoneName(point.map) or "", point.x * 100, point.y * 100) or ""
	)
	local meta = {}
	if dungeon.minimum and dungeon.minimum > 0 then
		meta[#meta + 1] = L.DUNGEON_ENTRY_LEVEL:format(dungeon.minimum)
	end
	if page.xp > 0 then
		meta[#meta + 1] = L.DUNGEON_REMAINING_XP:format(BreakUpLargeNumbers(page.xp))
	end
	if dungeon.hostile then
		meta[#meta + 1] = L.DUNGEON_HOSTILE_ENTRANCE
	end
	summary:SetText(table.concat(meta, L.SEPARATOR))
	ns.ZoneIcon.SetBackdrop(
		header.Art,
		PAGE_W - 4,
		HEADER_H - 4,
		point and point.map,
		point and point.x,
		point and point.y,
		900
	)
	MapTooltip(entrance, function()
		return point
	end, nil)
	entrance:SetShown(point ~= nil)
	entrance:SetEnabled(point ~= nil and not ns.Setting("wanderer"))
	local key = "dungeon:" .. dungeon.id
	plan:SetChecked(Dungeons.Planned(dungeon.id))
	local offered = false
	for _, card in ipairs(ns.Route().journeys) do
		offered = offered or card.key == key
	end
	journey:SetShown(offered)
	SetList(list, catalog)
	if listSelection ~= dungeon.id then
		listSelection = dungeon.id
		for index, entry in ipairs(catalog) do
			if entry.id == dungeon.id then
				local y = (index - 1) * LIST_H
				local top = list.frame:GetVerticalScroll() or 0
				if y < top or y + LIST_H > top + list.height then
					list.frame:SetVerticalScroll(math.min(y, math.max(0, #catalog * LIST_H - list.height)))
				end
			end
		end
	end
	quests.frame:SetShown(view == "quests")
	other.frame:SetShown(view ~= "quests")
	other.rowHeight = (view == "prep" or view == "bosses") and ROW_H or 44
	subTabs[3]:SetText(L.DUNGEON_BOSSES_TAB)
	for index, key_ in ipairs({ "quests", "prep", "bosses", "loot" }) do
		local muted = (key_ == "bosses" and not bosses and not source and not ns.DungeonBosses[dungeon.id])
			or (key_ == "loot" and not source)
		subTabs[index]:SetTabSelected(key_ == view)
		subTabs[index].Text:ClearAllPoints()
		subTabs[index].Text:SetPoint("CENTER", 0, 0)
		if muted then
			subTabs[index]:SetNormalFontObject("GameFontDisableSmall")
		end
	end
	note:SetText(not sourceRead and L.DUNGEON_LOADING or "")
	if view == "quests" then
		SetList(quests, QuestRows())
		if #page.quests == 0 then
			Window.SetEmpty(
				empty,
				dungeon.excludedCharacter > 0 and L.DUNGEON_NO_CHARACTER_QUESTS
					or dungeon.excludedFaction > 0 and L.DUNGEON_NO_FACTION_QUESTS
					or L.DUNGEON_NO_QUESTS
			)
			note:SetText("")
		end
	elseif view == "prep" then
		local rows = PrepRows()
		SetList(other, rows)
		if #rows == 0 then
			Window.SetEmpty(empty, L.DUNGEON_NO_PREP)
		end
	else
		local rows = {}
		local known
		if view == "bosses" then
			known = Dungeons.Bosses(source, dungeon.id, bosses)
		else
			known = source and source.loot[dungeon.id]
		end
		if source and not known then
			known = {}
		end
		if view == "loot" and source then
			rows = Dungeons.LootRows(source, dungeon.id, Dungeons.Bosses(source, dungeon.id, bosses))
		else
			local loot = source and Dungeons.LootRows(source, dungeon.id, known or {}) or {}
			for _, entry in ipairs(known or {}) do
				local bossMeta = {
					entry.rank == 1 and L.DUNGEON_ELITE or entry.rank == 2 and L.DUNGEON_RARE_ELITE or L.DUNGEON_BOSS,
				}
				if entry.low and entry.low > 0 then
					local color = GetQuestDifficultyColor(entry.low)
					local level = entry.high
							and entry.high > entry.low
							and L.DUNGEON_ENEMY_LEVELS:format(entry.low, entry.high)
						or L.DUNGEON_LEVEL:format(entry.low)
					table.insert(
						bossMeta,
						1,
						("|cff%02x%02x%02x%s|r"):format(color.r * 255, color.g * 255, color.b * 255, level)
					)
				end
				local count, lootIndex = 0, nil
				for index, item in ipairs(loot) do
					if item.heading then
						if lootIndex then
							break
						end
						if item.bossID == entry.id and not entry.journal then
							lootIndex = index
						end
					elseif lootIndex then
						count = count + 1
					end
				end
				rows[#rows + 1] = {
					title = entry.name,
					boss = true,
					lootIndex = lootIndex,
					info = table.concat(bossMeta, L.SEPARATOR),
					description = entry.description,
					giver = count > 0 and L.DUNGEON_BOSS_LOOT:format(count) or L.DUNGEON_BOSS_LOOT_UNKNOWN,
				}
			end
		end
		SetList(other, rows)
		if not known then
			Window.SetEmpty(
				empty,
				sourceError and L.DUNGEON_SOURCE_FAILED or sourceRead and L.DUNGEON_NEEDS_QUESTIE or L.DUNGEON_LOADING
			)
			note:SetText("")
		elseif #rows == 0 then
			Window.SetEmpty(empty, view == "bosses" and L.DUNGEON_NO_BOSSES or L.DUNGEON_NO_RECORDS)
			note:SetText("")
		end
	end
	DrawDetail()
end

---@param work fun(yield: fun())
local function Run(work)
	generation = generation + 1
	local token, started = generation, 0
	local co = coroutine.create(function()
		work(function()
			if debugprofilestop() - started >= SLICE_MS then
				coroutine.yield()
			end
		end)
	end)
	local function Step()
		if token ~= generation or not content:IsVisible() then
			return
		end
		started = debugprofilestop()
		local ok, err = coroutine.resume(co)
		if not ok then
			sourceRead, sourceError = true, true
			note:SetText(L.DUNGEON_SOURCE_FAILED)
			geterrorhandler()(err)
		elseif coroutine.status(co) ~= "dead" then
			C_Timer.After(0, Step)
		end
	end
	C_Timer.After(0, Step)
end

function Refresh()
	if not content:IsVisible() then
		return
	end
	if sourceData ~= ns.Data then
		sourceData, source, sourceRead, sourceError = ns.Data, nil, false, false
	end
	Run(function(yield)
		local player = ns.State.Player()
		catalog = Dungeons.List(ns.Data, player, yield)
		local dungeon
		for _, entry in ipairs(catalog) do
			if entry.id == ns.WindowDB().dungeon then
				dungeon = entry
			end
		end
		if not dungeon then
			for _, entry in ipairs(catalog) do
				if entry.suitable then
					dungeon = entry
					break
				end
			end
		end
		dungeon = dungeon or catalog[1]
		if not dungeon then
			Window.SetEmpty(empty, L.DUNGEON_NO_RECORDS)
			return
		end
		ns.WindowDB().dungeon = dungeon.id
		page = Dungeons.Page(ns.Data, player, ns.State.Completed(), ns.State.Log(), dungeon, yield)
		local _
		bosses, _, journalIcon = Dungeons.Journal(dungeon.id, yield)
		local selected = selectedQuest and ns.Data.quests[selectedQuest]
		if #page.quests == 0 or (selectedQuest and (not selected or not Dungeons.ForCharacter(selected, player))) then
			selectedQuest = nil
		end
		selectedQuest = selectedQuest or dungeon.quests[1]
		Draw()
		if not sourceRead then
			source = Dungeons.Source(yield)
			sourceRead = true
			Draw()
		end
	end)
end

local function BuildDetail()
	detail = CreateFrame("Frame", nil, content, "InsetFrameTemplate") --[[@as Frame]]
	detail:SetPoint("TOPLEFT", RIGHT_X + QUEST_W + GAP, -BODY_Y)
	local width = PAGE_W - QUEST_W - GAP
	detail:SetSize(width, BODY_H)
	detail:EnableMouse(true)
	detail:SetScript("OnLeave", GameTooltip_Hide)
	detailScroll = CreateFrame("ScrollFrame", nil, detail, "ScrollFrameTemplate") --[[@as AGFScrollFrame]]
	detailScroll:SetPoint("TOPLEFT", 10, -10)
	detailScroll:SetSize(width - 32, DETAIL_H)
	detailScroll.ScrollBar:ClearAllPoints()
	detailScroll.ScrollBar:SetPoint("TOPLEFT", detailScroll, "TOPRIGHT", 3, 0)
	detailScroll.ScrollBar:SetPoint("BOTTOMLEFT", detailScroll, "BOTTOMRIGHT", 3, 0)
	detailBody = CreateFrame("Frame", nil, detailScroll)
	detailBody:SetSize(width - 32, DETAIL_H)
	detailScroll:SetScrollChild(detailBody)
	detailTitle = Text(detailBody, "", 0, 0, width - 32, "GameFontNormalLarge")
	detailInfo = Text(detailBody, "", 0, 0, width - 32)
	detailObjective = Text(detailBody, "", 0, 0, width - 32)
	detailObjective:SetSpacing(3)
	detailObjectives = Text(detailBody, "", 0, 0, width - 32, "GameFontNormal")
	detailGiver = Text(detailBody, "", 0, 0, width - 32)
	detailGiver:SetMaxLines(2)
	detailEnd = Text(detailBody, "", 0, 0, width - 32)
	detailEnd:SetMaxLines(2)
	detailDivider = detailBody:CreateTexture(nil, "ARTWORK")
	ns.Art.Fit(detailDivider, "UI-Journeys-Renown-divider", width - 32, 6)
	detailRewards = Text(detailBody, "", 0, 0, width - 32, "GameFontNormal")
	detailChain = Text(detailBody, "", 0, 0, width - 32, "GameFontDisableSmall")
	giver = Button(detail, L.DUNGEON_SHOW_GIVER, 10, BODY_H - 32, width - 20, function()
		if selectedQuest then
			Dungeons.Go(selectedQuest)
		end
	end)
	MapTooltip(giver)
	for index = 1, 6 do
		local button = CreateFrame("Button", nil, detailBody)
		button:SetSize(32, 32)
		button:SetScript("OnLeave", GameTooltip_Hide)
		rewards[index] = button
	end
end

---@param parent Frame
local function BuildContents(parent)
	content = parent
	content:SetScript("OnHide", function()
		generation = generation + 1
	end)
	local body = CreateFrame("Frame", nil, content, "InsetFrameTemplate") --[[@as Frame]]
	body:SetPoint("TOPLEFT", RIGHT_X - 4, -(BODY_Y - 4))
	body:SetSize(PAGE_W + 8, BODY_H + 8)
	body:SetFrameLevel(content:GetFrameLevel())
	empty = Window.CreateEmpty(body, "UI-EJ-Classic")
	empty.Art:ClearAllPoints()
	empty.Art:SetPoint("TOPLEFT", 4, -4)
	empty.Art:SetSize(PAGE_W, BODY_H)
	ns.Art.Cover(empty.Art, "UI-EJ-Classic", PAGE_W, BODY_H)
	empty.Text:SetWidth(PAGE_W - 60)
	Window.SetEmpty(empty, nil)
	local heading = Window.Heading(content, L.TAB_DUNGEONS)
	heading:SetPoint("TOPLEFT", LEFT + 8, -TOP)
	list = List(content, LEFT, TOP + 22, LIST_W, 338, LIST_H, function(row, value)
		row.Title:SetText(ns.State.InstanceName(value.id) or value.name)
		local range = Range(value --[[@as AGFDungeon]])
		row.Info:SetText(value.hostile and L.DUNGEON_HOSTILE_LEVELS:format(range) or range)
		row.Giver:SetText("")
		row.Title:SetFontObject("GameFontHighlight")
		if value.low then
			local player = ns.State.Player()
			local level = math.max(value.low, math.min(player.level, value.high))
			local color = GetQuestDifficultyColor(level)
			if value.hostile then
				row.Info:SetTextColor(0.5, 0.5, 0.5)
			else
				row.Info:SetTextColor(color.r, color.g, color.b)
			end
		end
		row:SetScript("OnEnter", function()
			ns.Overview.ShowTooltip(row, {
				row.Title:GetText(),
				Range(value --[[@as AGFDungeon]]),
				value.hostile and L.DUNGEON_HOSTILE_ENTRANCE or L.DUNGEON_LEVEL_TOOLTIP,
			})
		end)
		row.Map:Hide()
		row.Expand:Hide()
		ns.Art.SetSliceShown(row.Selected, value.id == ns.WindowDB().dungeon)
	end, function(value)
		ns.WindowDB().dungeon, selectedQuest, expanded = value.id, nil, {}
		quests.frame:SetVerticalScroll(0)
		other.frame:SetVerticalScroll(0)
		Refresh()
	end)
	header = Window.CreateCard(content, true)
	Window.SizeCard(header, PAGE_W, HEADER_H, 0.8)
	header:SetPoint("TOPLEFT", RIGHT_X, -TOP)
	header.Highlight:Hide()
	local inner = CreateFrame("Frame", nil, header)
	inner:SetAllPoints()
	inner:SetFrameLevel(header:GetFrameLevel() + 5)
	dungeonIcon = Window.CreateRingIcon(inner, 40)
	dungeonIcon:SetPoint("TOPLEFT", 12, -12)
	title = Text(inner, "", 62, 12, PAGE_W - 76, "GameFontNormalLarge")
	title:SetWordWrap(false)
	location = Text(inner, "", 62, 35, PAGE_W - 76)
	location:SetWordWrap(false)
	summary = Text(inner, "", 62, 51, PAGE_W - 76)
	plan = CreateFrame("CheckButton", nil, inner, "UICheckButtonTemplate") --[[@as AGFDungeonPlan]]
	plan:SetPoint("TOPLEFT", 10, -68)
	plan:SetSize(24, 24)
	plan:SetHitRectInsets(0, -100, 0, 0)
	plan.Text:SetText(L.DUNGEON_PLAN)
	plan.Text:SetFontObject("GameFontNormal")
	plan:SetScript("OnClick", function()
		if page then
			Dungeons.SetPlanned(page.dungeon.id, not Dungeons.Planned(page.dungeon.id))
		end
	end)
	entrance = Button(inner, L.GO_TO_ENTRANCE, PAGE_W - 136, 69, 124, function()
		if page then
			Dungeons.GoEntrance(page.dungeon.id, source)
		end
	end)
	MapTooltip(entrance)
	journey = Button(inner, L.DUNGEON_START_JOURNEY, 144, 69, 124, function()
		if page then
			ns.Choose("dungeon:" .. page.dungeon.id, true)
		end
	end)
	for index, label in ipairs({ L.DUNGEON_QUESTS_TAB, L.DUNGEON_PREP_TAB, L.DUNGEON_BOSSES_TAB, L.DUNGEON_LOOT_TAB }) do
		local key = ({ "quests", "prep", "bosses", "loot" })[index]
		local tab = CreateFrame("Button", nil, content, "TabSystemTopButtonTemplate") --[[@as AGFTopTab]]
		tab:SetText(label)
		tab:SetSize(78, 32)
		tab:HandleRotation()
		tab:SetPoint("BOTTOMLEFT", body, "TOPLEFT", 8 + (index - 1) * 82, 0)
		tab:SetScript("OnEnter", function()
			if (key == "bosses" and not bosses and not source) or (key == "loot" and not source) then
				ns.Overview.ShowTooltip(tab, {
					sourceError and L.DUNGEON_SOURCE_FAILED
						or sourceRead and L.DUNGEON_NEEDS_QUESTIE
						or L.DUNGEON_LOADING,
				})
			end
		end)
		tab:SetScript("OnLeave", GameTooltip_Hide)
		tab:SetScript("OnClick", function()
			view = key
			other.frame:SetVerticalScroll(0)
			Draw()
		end)
		subTabs[index] = tab
	end
	local mapsButton = CreateFrame("Button", nil, content, "TabSystemTopButtonTemplate") --[[@as AGFTopTab]]
	mapsButton:SetText(L.DUNGEON_MAPS_TAB)
	mapsButton:SetSize(78, 32)
	mapsButton:HandleRotation()
	mapsButton:SetPoint("BOTTOMLEFT", body, "TOPLEFT", 8 + 4 * 82, 0)
	mapsButton:SetScript("OnClick", function()
		if page then
			Window.OpenDungeonMaps(page.dungeon.id, content)
		end
	end)
	note = Text(content, "", RIGHT_X + 8, BODY_Y + BODY_H + 2, PAGE_W - 16, "GameFontDisableSmall")
	quests = List(content, RIGHT_X, BODY_Y, QUEST_W, BODY_H, 38, PaintQuest, function(value)
		SelectQuest(value.quest.id)
	end)
	other = List(content, RIGHT_X, BODY_Y, PAGE_W - 12, BODY_H, 36, PaintOther, function(value)
		if value.item then
			GameTooltip:SetOwner(other.frame, "ANCHOR_RIGHT")
			GameTooltip:SetItemByID(value.item)
			GameTooltip:Show()
		elseif value.boss and value.lootIndex then
			view = "loot"
			Draw()
			other.frame:SetVerticalScroll(
				math.min(
					(value.lootIndex - 1) * other.rowHeight,
					math.max(0, #other.values * other.rowHeight - other.height)
				)
			)
		elseif value.quest then
			view = "quests"
			SelectQuest(value.quest.id)
		end
	end)
	other.frame:Hide()
	BuildDetail()
end

---@param parent Frame
local function Build(parent)
	content = parent
	local built = false
	parent:SetScript("OnShow", function()
		if not built then
			built = true
			BuildContents(parent)
		end
	end)
end

---@param instance integer
function Window.OpenDungeon(instance)
	ns.WindowDB().dungeon, selectedQuest = instance, nil
	ns.OpenWindow()
	for index, tab in ipairs(Window.Tabs()) do
		if tab.key == "dungeons" then
			Window.Select(index)
			return
		end
	end
end

Window.AddTab({ key = "dungeons", label = L.TAB_DUNGEONS, Build = Build, Refresh = Refresh })
