---@type string, AGFNamespace
local _, ns = ...
local L, Window, Dungeons = ns.L, ns.Window, ns.Dungeons

-- §2.21: the Dungeons tab as the Encounter Journal draws itself, since Blizzard's journal frames do not load on
-- this client. The select page is the journal's 174x96 tile grid under its Dungeons and Raids tabs; the instance
-- page is its two-pane encounter layout, with the boss list on the left and the detail pane on the right under the
-- journal's own side tabs. Work belongs to the visible page. Hiding it cancels its coroutine before any more source
-- reads or drawing.
--
-- Ported from Adventure Guide for Classic by FooxyTV (GPL-3.0), ui/InstanceSelect.lua, ui/Info.lua,
-- ui/EncounterFrame.lua, ui/Encounters.lua, ui/InfoTabs.lua, ui/InstanceOverview.lua, ui/Loot.lua, ui/NavBar.lua and
-- ui/widgets/. The frame numbers, anchors, texture coordinates, fonts and draw layers below are the reference's; the
-- data, the quest, prep, plan, map and guide features and the optional-source handling are this addon's.
-- The layout's own numbers and art crops, grouped so the drawing functions keep few upvalues (Lua 5.1 allows 60).
local C = {
	LEFT = Window.LEFT,
	RIGHT_PAD = 14,
	-- The journal's own sizes and art (Blizzard_EncounterJournal.xml: EncounterInstanceButtonTemplate,
	-- EncounterBossButtonTemplate, EncounterItemTemplate; InfoTabs.lua: the 63x57 side tab): a 174x96 instance tile,
	-- a 325x55 boss button, a 321x45 loot row with its 42x42 icon. A row is 2 units taller than the art it lays out.
	TILE_W = 174,
	TILE_H = 96,
	ICON = 28,
	GRID_COLUMNS = 4,
	GRID_W = 748,
	GRID_H = 379,
	GRID_X = 14,
	GRID_Y = 47,
	GRID_GAP = 15,
	BOSS_W = 325,
	BOSS_H = 55,
	BOSS_PORTRAIT_W = 128,
	BOSS_PORTRAIT_H = 64,
	LOOT_W = 321,
	LOOT_ICON = 45,
	LOOT_ROW = 47,
	ABILITY_H = 24,
	ROW_H = 38,
	SIDE_W = 63,
	SIDE_H = 57,
	SIDE_GAP = 2,
	-- The instance page: its `info` frame is the reference's 785x425, the inset's own size (792x431) less the
	-- shadows; the boss list is 338x382 at (25,1) and the side tabs hang from its top right at (-12,-35).
	INFO_W = 785,
	INFO_H = 425,
	PANE_X = 25,
	PANE_W = 338,
	PANE_Y = 1,
	-- The reference's 382 less room for the addon's entrance and summary lines under the instance title.
	PANE_H = 366,
	LIST_PAD = 10,
	SIDE_X = 12,
	SIDE_Y = 35,
	-- The reference's textures (ui/InstanceSelect.lua, ui/Info.lua, ui/InstanceOverview.lua, ui/Encounters.lua).
	SELECT_BG = "Interface/EncounterJournal/UI-EJ-Classic",
	JOURNAL_BG = "Interface/EncounterJournal/UI-EJ-JournalBG",
	JOURNAL_CROP = { 0, 0.766601562, 0, 0.830078125 },
	SHADOW_L = { 0, 0.755859375, 0.9599609375, 1 },
	SHADOW_R = { 0.755859375, 0, 0.9599609375, 1 },
	SHADOW_W = 386,
	SHADOW_H = 39,
	LOREBG = "Interface/EncounterJournal/UI-EJ-LOREBG-Default",
	LOREBG_CROP = { 0, 0.7617187, 0, 0.65625 },
	BOSS_DEFAULT = "Interface\\EncounterJournal\\UI-EJ-BOSS-Default",
	-- The tile's instance picture (the reference's `instance.thumbnail`): the whole button minus its ornate rim.
	THUMBNAIL_CROP = { 0, 0.68359375, 0, 0.7421875 },
	-- Interface\EncounterJournal\UI-EncounterJournalTextures (file 522972), cut at the journal's own texcoords.
	EJ_SHEET = 522972,
	CROPS = {
		dungeonUp = { 0.00195313, 0.34179688, 0.42871094, 0.52246094 },
		dungeonDown = { 0.00195313, 0.34179688, 0.33300781, 0.42675781 },
		dungeonHighlight = { 0.34570313, 0.68554688, 0.33300781, 0.42675781 },
		bossUp = { 0.00195313, 0.63671875, 0.21386719, 0.26757813 },
		bossDown = { 0.00195313, 0.63671875, 0.10253906, 0.15625000 },
		bossHighlight = { 0.00195313, 0.63671875, 0.15820313, 0.21191406 },
		loot = { 0.00195313, 0.62890625, 0.61816406, 0.66210938 },
		overviewTitleBG = { 0.34570313, 0.84570313, 0.42871094, 0.49121094 },
	},
}
C.BODY_H = C.PANE_H
C.BODY_Y = C.PANE_Y
C.RIGHT_X = C.PANE_X + C.PANE_W + 12
C.RIGHT_W = C.INFO_W - C.RIGHT_X - (C.SIDE_W + C.SIDE_X)
C.JOURNAL_LEFT = Window.INSET_WIDTH - 1 - C.INFO_W
-- The journal's hand-built side tabs: one 63x57 body per state and a 48x43 icon, per tab (InfoTabs.lua).
C.TAB_CROP = {
	up = { 0.25585938, 0.37890625, 0.90332031, 0.95898438 },
	down = { 0.12890625, 0.25195313, 0.90332031, 0.95898438 },
	highlight = { 0.00195313, 0.12500000, 0.90332031, 0.95898438 },
}
-- The tabs the instance page runs down its right edge: the view key, its label and its icon crops.
C.SIDE = {
	{
		key = "overview",
		label = L.DUNGEON_OVERVIEW_TAB,
		up = { 0.85546875, 0.94921875, 0.52441406, 0.56640625 },
		down = { 0.90234375, 0.99609375, 0.26953125, 0.31152344 },
	},
	{ key = "quests", label = L.DUNGEON_QUESTS_TAB, icon = "Interface\\GossipFrame\\AvailableQuestIcon" },
	{
		key = "prep",
		label = L.DUNGEON_PREP_TAB,
		up = { 0.90234375, 1, 0.662109375, 0.705078125 },
		down = { 0.8046875, 0.900390625, 0.662109375, 0.705078125 },
	},
	{
		key = "bosses",
		label = L.DUNGEON_BOSSES_TAB,
		up = { 0.904296875, 0.99609375, 0.70703125, 0.748046875 },
		down = { 0.806640625, 0.8984375, 0.70703125, 0.748046875 },
	},
	{
		key = "loot",
		label = L.DUNGEON_LOOT_TAB,
		up = { 0.73046875, 0.82421875, 0.61816406, 0.66015625 },
		down = { 0.63281250, 0.72656250, 0.61816406, 0.66015625 },
	},
}
-- The instance page's tabs in the order they run down the right edge.
C.VIEWS = { "overview", "quests", "prep", "bosses", "loot" }

---@class AGFDungeonPlan : CheckButton
---@field Text FontString

-- All of the tab's frames and state, so the drawing functions hold one upvalue for it.
local ui = {
	catalog = {},
	rewards = {},
	sideTabs = {},
	selectTabs = {},
	expanded = {},
	sourceRead = false,
	sourceError = false,
	generation = 0,
	selecting = nil,
	kind = "dungeons",
	view = "quests",
	reading = false,
}

-- A view whose optional source has not answered yet is greyed but still clickable, so its page can say why.
---@param key string
local function Muted(key)
	return (key == "bosses" and not ui.bosses and not ui.source) or (key == "loot" and not ui.source)
end

local function SourceMessage()
	return ui.sourceError and L.DUNGEON_SOURCE_FAILED or ui.sourceRead and L.DUNGEON_NEEDS_QUESTIE or L.DUNGEON_LOADING
end

---@param texture Texture
---@param crop number[]
local function Sheet(texture, crop)
	texture:SetTexture(C.EJ_SHEET)
	texture:SetTexCoord(crop[1], crop[2], crop[3], crop[4])
end

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
---@param width number
---@param action fun()
---@param height? number
---@return Button
local function Button(parent, label, width, action, height)
	local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate") --[[@as Button]]
	button:SetSize(width, height or 22)
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

---@param id integer
---@return integer?
local function ItemIcon(id)
	local icon = C_Item.GetItemIconByID(id)
	if not icon then
		Dungeons.RequestItem(id)
	end
	return icon
end

---@param dungeon AGFDungeon
---@return string
local function Range(dungeon)
	if dungeon.low then
		return L.DUNGEON_QUEST_LEVELS:format(dungeon.low, dungeon.high)
	end
	return ""
end

local Refresh, Draw, SelectQuest

--[[ The instance select page ]]

---@param parent Frame
---@param width number
---@param rowHeight number
---@param click fun(value: table)
---@return AGFDungeonRow
local function CreateInstanceTile(parent, width, rowHeight, click)
	local row = CreateFrame("Button", nil, parent) --[[@as AGFDungeonRow]]
	row:SetSize(width, rowHeight - 2)
	-- The reference's `instance.thumbnail` shows through the ornate frame's centre; the addon has no per-instance
	-- splash, so the ground is the flat dark tile (ui/InstanceSelect.lua).
	row.bgImage = row:CreateTexture(nil, "BACKGROUND")
	row.bgImage:SetTexCoord(C.THUMBNAIL_CROP[1], C.THUMBNAIL_CROP[2], C.THUMBNAIL_CROP[3], C.THUMBNAIL_CROP[4])
	row.bgImage:SetAllPoints()
	row.Up = row:CreateTexture(nil, "BACKGROUND", nil, 1)
	Sheet(row.Up, C.CROPS.dungeonUp)
	row.Up:SetSize(C.TILE_W, C.TILE_H)
	row.Up:SetPoint("TOPLEFT")
	row.Down = row:CreateTexture(nil, "ARTWORK")
	Sheet(row.Down, C.CROPS.dungeonDown)
	row.Down:SetSize(C.TILE_W, C.TILE_H)
	row.Down:SetPoint("TOPLEFT")
	row.Down:Hide()
	row.Highlight = row:CreateTexture(nil, "HIGHLIGHT")
	Sheet(row.Highlight, C.CROPS.dungeonHighlight)
	row.Highlight:SetSize(C.TILE_W, C.TILE_H)
	row.Highlight:SetPoint("TOPLEFT")
	row.Title = row:CreateFontString(nil, "OVERLAY", "QuestTitleFontBlackShadow")
	row.Title:SetSize(150, 0)
	row.Title:SetPoint("TOP", 0, -15)
	row.Title:SetJustifyH("CENTER")
	row.Title:SetWordWrap(true)
	row.Range = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.Range:SetSize(100, 12)
	row.Range:SetPoint("BOTTOMLEFT", 7, 7)
	row.Range:SetJustifyH("LEFT")
	row:SetScript("OnClick", function()
		click(row.value)
	end)
	return row
end

---@param row AGFDungeonRow
---@param value table
local function PaintTile(row, value)
	row.Title:SetText(ns.State.InstanceName(value.id) or value.name)
	local range = Range(value --[[@as AGFDungeon]])
	local info = value.hostile and L.DUNGEON_HOSTILE_LEVELS:format(range) or range
	if value.raid then
		local size = L.DUNGEON_RAID_PLAYERS:format(value.players)
		info = info ~= "" and size .. L.SEPARATOR .. info or size
	end
	row.Range:SetText(info)
	if value.low then
		local player = ns.State.Player()
		local level = math.max(value.low, math.min(player.level, value.high))
		local color = GetQuestDifficultyColor(level)
		row.Range:SetTextColor(
			value.hostile and 0.5 or color.r,
			value.hostile and 0.5 or color.g,
			value.hostile and 0.5 or color.b
		)
	else
		row.Range:SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
	end
	-- The reference's `instance.thumbnail`, or a flat dark tile when the addon has no art for the instance.
	row.bgImage:SetTexture(nil)
	row.bgImage:SetColorTexture(0.1, 0.09, 0.08, 1)
	row.Up:Show()
	row.Down:SetShown(not ui.selecting and value.id == ns.WindowDB().dungeon)
	row:SetScript("OnEnter", function()
		ns.Overview.ShowTooltip(row, {
			row.Title:GetText(),
			info,
			value.hostile and L.DUNGEON_HOSTILE_ENTRANCE
				or (value.raid and L.DUNGEON_RAID_TOOLTIP or L.DUNGEON_LEVEL_TOOLTIP),
		})
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
end

--[[ The quest and prep rows: the journal's list row, with the chain's expand control and its Map control. ]]

---@param parent Frame
---@param width number
---@param rowHeight number
---@param click fun(value: table)
---@return AGFDungeonRow
local function CreateListRow(parent, width, rowHeight, click)
	local row = CreateFrame("Button", nil, parent) --[[@as AGFDungeonRow]]
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
	row.Map = Button(row, L.DUNGEON_MAP, 46, function()
		if row.value and row.value.quest then
			Dungeons.Go(row.value.quest.id)
		end
	end, 18)
	MapTooltip(row.Map)
	row.Expand = CreateFrame("Button", nil, row, "CollapseButtonTemplate") --[[@as AGFCollapseButton]]
	row.Expand:SetSize(20, 20)
	row.Expand:SetPoint("TOPLEFT", 3, -2)
	row.Expand:SetScript("OnClick", function()
		if row.value and row.value.quest then
			local id = row.value.quest.id
			ui.expanded[id] = not ui.expanded[id]
			Draw()
		end
	end)
	row:SetScript("OnClick", function()
		if row.value then
			click(row.value)
		end
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	return row
end

---@param row AGFDungeonRow
---@param value table
local function PaintQuest(row, value)
	local quest = value.quest
	local offset = value.chain and 34 or 24
	local width = row:GetWidth()
	row.Title:SetText((ns.State.QuestTitle(quest.id) or quest.title))
	row.Title:ClearAllPoints()
	row.Title:SetPoint("TOPLEFT", offset, -5)
	row.Title:SetWidth(width - offset - 74 - 16)
	row.Info:SetText(Dungeons.QuestStatus(quest))
	row.Info:ClearAllPoints()
	row.Info:SetPoint("TOPRIGHT", -8, -7)
	row.Info:SetWidth(74)
	row.Info:SetJustifyH("RIGHT")
	row.Giver:SetText(Dungeons.GiverText(quest))
	row.Giver:ClearAllPoints()
	row.Giver:SetPoint("TOPLEFT", offset, -21)
	row.Giver:SetWidth(width - offset - 8)
	row.Map:SetShown(value.chain and quest.place ~= nil)
	row.Map:ClearAllPoints()
	row.Map:SetPoint("TOPRIGHT", -4, -18)
	if value.chain and quest.place then
		row.Giver:SetWidth(width - 34 - 58)
	end
	MapTooltip(row.Map, function()
		return quest.place
	end, row)
	row.Map:SetEnabled(quest.place ~= nil and not ns.Setting("wanderer"))
	row.Expand:SetShown(not value.chain and #Dungeons.Chain(ns.Data, quest.id, function() end) > 1)
	row.Expand:UpdateCollapsedState(not ui.expanded[quest.id])
	row:SetScript("OnEnter", function()
		local lines = { row.Title:GetText(), Dungeons.QuestStatus(quest), Dungeons.GiverText(quest) }
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
	ns.Art.SetSliceShown(row.Selected, ui.selectedQuest == quest.id)
end

---@param row AGFDungeonRow
---@param value table
local function PaintPrep(row, value)
	local width = row:GetWidth()
	row.Title:SetText(value.title)
	row.Title:ClearAllPoints()
	row.Title:SetPoint("TOPLEFT", 8, -5)
	row.Title:SetWidth(width - 16)
	row.Info:SetText(value.info or "")
	row.Info:ClearAllPoints()
	row.Info:SetPoint("TOPLEFT", 8, -21)
	row.Info:SetWidth(width - 16)
	row.Info:SetJustifyH("LEFT")
	row.Giver:SetText(value.giver or "")
	row.Giver:ClearAllPoints()
	row.Giver:SetPoint("TOPLEFT", 8, -35)
	row.Giver:SetWidth(width - 16)
	row.Expand:Hide()
	local quest = value.quest
	local place = quest and quest.place
	row.Map:SetShown(place ~= nil)
	row.Map:ClearAllPoints()
	row.Map:SetPoint("TOPRIGHT", -4, -18)
	row.Map:SetEnabled(place ~= nil and not ns.Setting("wanderer"))
	MapTooltip(row.Map, function()
		return place
	end, row)
	row:SetScript("OnEnter", function()
		ns.Overview.ShowTooltip(row, { value.title, value.info or "", value.giver or "" })
	end)
	ns.Art.SetSliceShown(row.Selected, false)
end

--[[ The boss list: the journal's 325x55 button with its default portrait. ]]

---@param parent Frame
---@param width number
---@param rowHeight number
---@param click fun(value: table)
---@return AGFDungeonRow
local function CreateBossRow(parent, width, rowHeight, click)
	local row = CreateFrame("Button", nil, parent) --[[@as AGFDungeonRow]]
	row:SetSize(width, rowHeight - 2)
	row.Up = row:CreateTexture(nil, "BACKGROUND")
	Sheet(row.Up, C.CROPS.bossUp)
	row.Up:SetSize(C.BOSS_W, C.BOSS_H)
	row.Up:SetPoint("TOPLEFT")
	row.Down = row:CreateTexture(nil, "ARTWORK")
	Sheet(row.Down, C.CROPS.bossDown)
	row.Down:SetSize(C.BOSS_W, C.BOSS_H)
	row.Down:SetPoint("TOPLEFT")
	row.Down:Hide()
	row.Highlight = row:CreateTexture(nil, "HIGHLIGHT")
	Sheet(row.Highlight, C.CROPS.bossHighlight)
	row.Highlight:SetSize(C.BOSS_W, C.BOSS_H)
	row.Highlight:SetPoint("TOPLEFT")
	row.Portrait = row:CreateTexture(nil, "OVERLAY", nil, 6)
	row.Portrait:SetTexture(C.BOSS_DEFAULT)
	row.Portrait:SetSize(C.BOSS_PORTRAIT_W, C.BOSS_PORTRAIT_H)
	row.Portrait:SetPoint("TOPLEFT", -4, 13)
	row.Title = Text(row, "", 105, 3, 160, "GameFontNormalMed3")
	row.Title:SetWordWrap(false)
	row.Info = Text(row, "", 105, 21, C.BOSS_W - 120)
	row.Info:SetWordWrap(false)
	row.Giver = Text(row, "", 105, 35, C.BOSS_W - 120, "GameFontDisableSmall")
	row.Giver:SetWordWrap(false)
	row:SetScript("OnClick", function()
		click(row.value)
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	return row
end

---@param row AGFDungeonRow
---@param value table
local function PaintBoss(row, value)
	row.Up:Show()
	-- The reference's per-encounter portrait, read from the client journal by encounter name (ui/Encounters.lua sets
	-- `encounter.portrait`; the picture file id, or the creature display the client turns into a live portrait).
	local journal = ui.portraits and ui.portraits[value.title]
	local portrait = value.portrait or (journal and journal.portrait)
	local display = value.display or (journal and journal.display)
	if portrait then
		row.Portrait:SetTexture(portrait)
		row.Portrait:SetShown(true)
	elseif display and row.Portrait.SetPortraitTextureFromCreatureDisplayID then
		row.Portrait:SetPortraitTextureFromCreatureDisplayID(display)
		row.Portrait:SetShown(true)
	else
		row.Portrait:SetTexture(nil)
		row.Portrait:SetShown(false)
	end
	row.Title:SetText(value.title)
	row.Title:SetTextColor(0.87, 0.659, 0.463)
	row.Info:SetText(value.info or "")
	row.Giver:SetText(value.giver or "")
	row.Down:SetShown(ui.selectedBoss == value.id)
	row:SetScript("OnEnter", function()
		ns.Overview.ShowTooltip(row, { value.title, value.info or "", value.giver or "", value.description or "" })
	end)
end

--[[ The detail pane's rows: an ability as an icon and a name, a drop as the journal's 321x45 loot row. ]]

---@param parent Frame
---@param width number
---@param rowHeight number
---@param click fun(value: table)
---@return AGFDungeonRow
local function CreateAbilityRow(parent, width, rowHeight, click)
	local row = CreateFrame("Button", nil, parent) --[[@as AGFDungeonRow]]
	row:SetSize(width, rowHeight - 2)
	row.AbilityIcon = row:CreateTexture(nil, "ARTWORK", nil, 1)
	row.AbilityIcon:SetSize(18, 18)
	row.AbilityIcon:SetPoint("TOPLEFT", 2, -2)
	row.Title = Text(row, "", 26, 4, width - 40, "GameFontNormal")
	row.Title:SetWordWrap(false)
	row:SetScript("OnClick", function()
		click(row.value)
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	return row
end

---@param row AGFDungeonRow
---@param value table
local function PaintAbility(row, value)
	-- One spell: the client's icon and name, its own tooltip on hover. An id this build cannot resolve never reaches
	-- here (Dungeons.Abilities), so a row always has both.
	row.Title:SetText(value.title)
	row.Title:SetFontObject("GameFontHighlight")
	row.AbilityIcon:SetTexture(value.icon)
	row:SetScript("OnEnter", function()
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:SetSpellByID(value.ability)
		GameTooltip:Show()
	end)
end

---@param parent Frame
---@param width number
---@param rowHeight number
---@param click fun(value: table)
---@return AGFDungeonRow
local function CreateLootRow(parent, width, rowHeight, click)
	local row = CreateFrame("Button", nil, parent) --[[@as AGFDungeonRow]]
	row:SetSize(width, rowHeight - 2)
	row.LootFrame = row:CreateTexture(nil, "BORDER")
	Sheet(row.LootFrame, C.CROPS.loot)
	row.LootFrame:SetSize(C.LOOT_W, 45)
	row.LootFrame:SetPoint("TOPLEFT", 0, -2)
	row.LootFrame:Hide()
	row.ItemIcon = row:CreateTexture(nil, "ARTWORK", nil, 1)
	row.ItemIcon:SetSize(C.LOOT_ICON, C.LOOT_ICON)
	row.ItemIcon:SetPoint("TOPLEFT", 2, -4)
	row.ItemIcon:Hide()
	row.IconBorder = row:CreateTexture(nil, "OVERLAY")
	row.IconBorder:SetTexture("Interface\\Common\\WhiteIconFrame")
	row.IconBorder:SetSize(C.LOOT_ICON, C.LOOT_ICON)
	row.IconBorder:SetPoint("TOPLEFT", row.ItemIcon, "TOPLEFT")
	row.IconBorder:Hide()
	row.Header = Text(row, "", 5, 6, width - 12, "GameFontNormalLarge")
	row.Header:Hide()
	row.Title = Text(row, "", 54, 7, width - 150, "GameFontNormalMed3")
	row.Title:SetWordWrap(false)
	row.Info = Text(row, "", 54, 25, width - 70, "GameFontBlack")
	row.Info:SetWordWrap(false)
	row.Percent = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	row.Percent:SetPoint("TOPRIGHT", -8, -7)
	row.Percent:SetJustifyH("RIGHT")
	row.Percent:Hide()
	row:SetScript("OnClick", function()
		click(row.value)
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	return row
end

---@param row AGFDungeonRow
---@param value table
local function PaintLoot(row, value)
	if value.heading then
		-- A boss's or Trash's heading over its drops.
		row.Header:SetText(value.title)
		row.Header:Show()
		row.Info:SetFontObject("GameFontHighlightSmall")
		row.Info:SetText(value.info or "")
		row.Info:SetShown(value.info ~= nil and value.info ~= "")
		row.LootFrame:Hide()
		row.ItemIcon:Hide()
		row.IconBorder:Hide()
		row.Title:Hide()
		row.Percent:SetText("")
		row.Percent:Hide()
		row:SetScript("OnEnter", nil)
		return
	end
	local icon = ItemIcon(value.item)
	row.Header:Hide()
	row.LootFrame:Show()
	row.ItemIcon:SetShown(icon ~= nil)
	row.IconBorder:SetShown(icon ~= nil)
	if icon then
		row.ItemIcon:SetTexture(icon)
	end
	local color = ITEM_QUALITY_COLORS[value.quality] or ITEM_QUALITY_COLORS[1]
	row.Title:SetText(value.title)
	row.Title:SetTextColor(color.r, color.g, color.b)
	row.Title:Show()
	row.IconBorder:SetVertexColor(color.r, color.g, color.b)
	row.Info:SetFontObject("GameFontBlack")
	row.Info:SetText(value.info or "")
	row.Info:SetShown(true)
	if value.percent then
		-- The rate as a number, then the journal's own percent sign, as AtlasLoot's tooltip does.
		row.Percent:SetText(L.DUNGEON_DROP_RATE:format(value.percent) .. "%")
		row.Percent:Show()
	else
		row.Percent:SetText("")
		row.Percent:Hide()
	end
	row:SetScript("OnEnter", function()
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:SetItemByID(value.item)
		GameTooltip:Show()
	end)
end

--[[ The side tabs ]]

---@param parent Frame
---@param spec table
---@return AGFTopTab
local function CreateSideTab(parent, spec)
	local tab = CreateFrame("Button", nil, parent) --[[@as AGFTopTab]]
	tab:SetSize(C.SIDE_W, C.SIDE_H)
	tab.key = spec.key
	tab.Normal = tab:CreateTexture(nil, "BACKGROUND")
	Sheet(tab.Normal, C.TAB_CROP.up)
	tab.Normal:SetAllPoints()
	tab.Pushed = tab:CreateTexture(nil, "ARTWORK")
	Sheet(tab.Pushed, C.TAB_CROP.down)
	tab.Pushed:SetAllPoints()
	tab.Highlight = tab:CreateTexture(nil, "HIGHLIGHT")
	Sheet(tab.Highlight, C.TAB_CROP.highlight)
	tab.Highlight:SetAllPoints()
	tab.Icon = tab:CreateTexture(nil, "OVERLAY")
	tab.Icon:SetSize(48, 43)
	if spec.icon then
		tab.Icon:SetTexture(spec.icon)
		tab.Icon:SetSize(25, 25)
		tab.Icon:SetPoint("CENTER")
		tab.SelectedIcon = tab.Icon
	else
		tab.Icon:SetPoint("RIGHT", -6, 0)
		tab.Icon:SetTexCoord(spec.up[1], spec.up[2], spec.up[3], spec.up[4])
		tab.SelectedIcon = tab:CreateTexture(nil, "OVERLAY", nil, 1)
		tab.SelectedIcon:SetTexture(C.EJ_SHEET)
		tab.SelectedIcon:SetSize(48, 43)
		tab.SelectedIcon:SetPoint("CENTER")
		tab.SelectedIcon:SetTexCoord(spec.down[1], spec.down[2], spec.down[3], spec.down[4])
		tab.SelectedIcon:Hide()
	end
	-- The journal's tabs are icon-only; the label rides a hidden font string so the control still carries its name,
	-- and the tooltip says it.
	tab.Text = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	tab.Text:SetText(spec.label)
	tab.Text:Hide()
	tab:SetScript("OnEnter", function()
		if tab.muted then
			ns.Overview.ShowTooltip(tab, { SourceMessage() })
		else
			GameTooltip:SetOwner(tab, "ANCHOR_RIGHT")
			GameTooltip:SetText(spec.label)
			GameTooltip:Show()
		end
	end)
	tab:SetScript("OnLeave", GameTooltip_Hide)
	tab:SetScript("OnClick", function()
		ui.view = spec.key
		Draw()
	end)
	return tab
end

---@param tab AGFTopTab
---@param selected boolean
local function SelectSideTab(tab, selected)
	tab.SelectedIcon:SetShown(selected)
	if tab.SelectedIcon ~= tab.Icon then
		tab.Icon:SetShown(not selected)
	end
	tab:SetAlpha(tab.muted and 0.55 or 1)
end

--[[ The instance page's detail pane ]]

function SelectQuest(id)
	ui.selectedQuest = id
	ui.detailScroll:SetVerticalScroll(0)
	Draw()
end

local function DrawDetail()
	local quest = ui.selectedQuest
		and Dungeons.Quest(ns.Data, ns.State.Player(), ns.State.Completed(), ns.State.Log(), ui.selectedQuest)
	local detail = ui.detail
	detail:SetShown(ui.view == "quests" and quest ~= nil)
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
	Line(ui.detailTitle, ns.State.QuestTitle(quest.id) or quest.title)
	local info = {}
	if quest.level and quest.level > 0 then
		info[#info + 1] = L.DUNGEON_LEVEL:format(quest.level)
	end
	if quest.xp and quest.xp > 0 then
		info[#info + 1] = L.DUNGEON_XP:format(BreakUpLargeNumbers(quest.xp))
	end
	Line(ui.detailInfo, table.concat(info, L.SEPARATOR))
	local objective = Dungeons.Objective(quest.id, ui.source)
	if objective then
		cursor = cursor + 6
	end
	Line(ui.detailObjectives, objective and L.DUNGEON_OBJECTIVES or "")
	Line(ui.detailObjective, objective or "")
	cursor = cursor + 6
	local record = ns.Data.quests[quest.id]
	local start, finish = Dungeons.PlaceText(record and record.start), Dungeons.PlaceText(record and record.finish)
	Line(ui.detailGiver, start ~= "" and L.DUNGEON_START:format(start) or "")
	Line(ui.detailEnd, finish ~= "" and finish ~= start and L.DUNGEON_END:format(finish) or "")
	local items = ui.source and ui.source.rewards[quest.id] or {}
	ui.detailDivider:SetShown(#items > 0)
	if #items > 0 then
		ui.detailDivider:ClearAllPoints()
		ui.detailDivider:SetPoint("TOPLEFT", 0, -cursor)
		cursor = cursor + 10
	end
	Line(ui.detailRewards, #items > 0 and L.DUNGEON_REWARDS or "")
	for index, button in ipairs(ui.rewards) do
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
	for _, parent in ipairs(ui.page and ui.page.quests or {}) do
		local position, count = Dungeons.ChainPosition(ns.Data, parent.id, quest.id)
		if position and (not total or count > total) then
			part, total = position, count
		end
	end
	Line(ui.detailChain, part and L.DUNGEON_PART:format(part, total) or "")
	ui.detailBody:SetHeight(math.max(C.BODY_H - 52, cursor))
	ui.detailScroll.ScrollBar:SetShown(cursor > C.BODY_H - 52)
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
	MapTooltip(ui.giver, function()
		return quest.place
	end, nil)
	ui.giver:SetShown(quest.place ~= nil)
	ui.giver:SetEnabled(not ns.Setting("wanderer"))
end

-- The entrance requirements as the paper well Prep shows.
---@param each AGFDungeonPage
---@return string[]
local function GateLines(each)
	local lines = {}
	for _, entry in ipairs(each.prep) do
		if entry.gate then
			local text = Dungeons.GateText(entry.gate)
			if text ~= "" then
				lines[#lines + 1] = text
			end
		end
	end
	return lines
end

---@param shown boolean
local function ShowInstance(shown)
	ui.info:SetShown(shown)
end

---@param shown boolean
local function ShowSelect(shown)
	for _, tab in ipairs(ui.selectTabs) do
		tab:SetShown(shown)
	end
	ui.select:SetShown(shown)
	if not shown then
		return
	end
	local pageName = ui.kind == "dungeons" and L.DUNGEON_LIST_DUNGEONS or L.DUNGEON_RAIDS_TAB
	ui.selectTitle:SetText(pageName)
	PanelTemplates_SetTab(ui.content, ui.kind == "dungeons" and 1 or 2)
	local values = {}
	for _, entry in ipairs(ui.catalog) do
		if (ui.kind == "raids") == (entry.raid == true) then
			values[#values + 1] = entry
		end
	end
	Window.SetList(ui.grid, values)
	if #values == 0 then
		Window.SetEmpty(ui.empty, L.DUNGEON_NO_RECORDS)
	end
end

function Draw()
	if not ui.content:IsVisible() then
		return
	end
	if ui.selecting or not ui.page then
		Window.SetEmpty(ui.empty, nil)
		ShowInstance(false)
		ShowSelect(true)
		if ui.navBar then
			ui.navBar:SetCrumbs({})
		end
		return
	end
	local dungeon = ui.page.dungeon
	Window.SetEmpty(ui.empty, nil)
	ShowSelect(false)
	ShowInstance(true)
	local point = Dungeons.Entrance(dungeon.id)
	ui.instanceButton.icon:SetShown(ui.journalIcon ~= nil)
	if ui.journalIcon then
		ui.instanceButton.icon:SetTexture(ui.journalIcon)
		if not ui.instanceMask then
			local mask = ui.instanceButton:CreateMaskTexture()
			mask:SetAllPoints(ui.instanceButton.icon)
			mask:SetTexture(
				"Interface\\CharacterFrame\\TempPortraitAlphaMask",
				"CLAMPTOBLACKADDITIVE",
				"CLAMPTOBLACKADDITIVE"
			)
			ui.instanceButton.icon:AddMaskTexture(mask)
			ui.instanceMask = mask
		end
	end
	ui.title:SetText(ns.State.InstanceName(dungeon.id) or dungeon.name)
	ui.location:SetText(
		point and L.DUNGEON_ENTRANCE_AT:format(ns.State.ZoneName(point.map) or "", point.x * 100, point.y * 100) or ""
	)
	local meta = {}
	if dungeon.raid and dungeon.players then
		meta[#meta + 1] = L.DUNGEON_RAID_PLAYERS:format(dungeon.players)
	end
	if dungeon.minimum and dungeon.minimum > 0 then
		meta[#meta + 1] = L.WHY_LEVEL:format(dungeon.minimum)
	end
	if ui.page.xp > 0 then
		meta[#meta + 1] = L.DUNGEON_REMAINING_XP:format(BreakUpLargeNumbers(ui.page.xp))
	end
	if dungeon.hostile then
		meta[#meta + 1] = L.DUNGEON_HOSTILE_ENTRANCE
	end
	ui.summary:SetText(table.concat(meta, L.SEPARATOR))
	ui.note:SetText(ui.sourceError and L.DUNGEON_SOURCE_FAILED or (not ui.sourceRead and L.DUNGEON_LOADING) or "")
	ui.note:SetShown(ui.sourceError or not ui.sourceRead)
	ui.location:SetShown(point ~= nil and not ui.note:IsShown())
	MapTooltip(ui.entrance, function()
		return point
	end, nil)
	ui.entrance:SetShown(point ~= nil)
	ui.entrance:SetEnabled(point ~= nil and not ns.Setting("wanderer"))
	local key = "dungeon:" .. dungeon.id
	ui.plan:SetChecked(Dungeons.Planned(dungeon.id))
	local offered = false
	for _, card in ipairs(ns.Route().journeys) do
		offered = offered or card.key == key
	end
	ui.journey:SetShown(offered)
	-- The overview's lore art and the paper well under it.
	ui.overviewArt:SetShown(
		ns.ZoneIcon.SetBackdrop(
			ui.overviewArt,
			C.RIGHT_W - 4,
			C.BODY_H - 4,
			point and point.map,
			point and point.x,
			point and point.y,
			900
		)
	)
	ui.overviewTitle:SetText(ui.title:GetText())
	ui.overviewText:SetShown(#meta > 0)
	Window.SetPaperWell(ui.overviewText, { table.concat(meta, L.SEPARATOR) })
	local prep = GateLines(ui.page)
	ui.prepWell:SetShown(#prep > 0)
	ui.prepWell:SetHeight(math.max(30, 18 + 16 * #prep))
	Window.SetPaperWell(ui.prepWell, prep)
	-- The boss list every instance view runs on, then the abilities or the drops beside it.
	local bossKnown = Dungeons.Bosses(ui.source, dungeon.id, ui.bosses)
	local bossRows = Dungeons.BossRows(ui.source, dungeon.id, bossKnown)
	local selected
	for _, boss in ipairs(bossKnown) do
		if boss.id == ui.selectedBoss then
			selected = boss
		end
	end
	if not selected and ui.sourceRead then
		-- The list is still the client journal's until the optional source answers; picking its first boss then would
		-- hold the wrong encounter once the curated order arrives.
		ui.selectedBoss = bossKnown[1] and bossKnown[1].id
		selected = bossKnown[1]
	end
	if ui.view == "quests" then
		Window.SetList(ui.questList, Dungeons.QuestRows(ui.page, ui.expanded))
		if #ui.page.quests == 0 then
			Window.SetEmpty(
				ui.empty,
				dungeon.excludedCharacter > 0 and L.DUNGEON_NO_CHARACTER_QUESTS
					or dungeon.excludedFaction > 0 and L.DUNGEON_NO_FACTION_QUESTS
					or L.DUNGEON_NO_QUESTS
			)
			ui.note:Hide()
		end
	elseif ui.view == "prep" then
		local rows = {}
		for _, entry in ipairs(Dungeons.PrepRows(ui.page)) do
			if entry.quest then
				rows[#rows + 1] = entry
			end
		end
		Window.SetList(ui.prepList, rows)
		if #rows == 0 and #prep == 0 then
			Window.SetEmpty(ui.empty, L.DUNGEON_NO_PREP)
		end
	elseif ui.view == "bosses" then
		Window.SetList(ui.bossList, bossRows)
		ui.abilityHeader.Label:SetText(selected and selected.name or "")
		ui.abilityHeader:SetShown(selected ~= nil)
		Window.SetList(ui.abilityList, selected and Dungeons.AbilityRows(selected.journal and nil or selected.id) or {})
		if #bossKnown == 0 then
			Window.SetEmpty(ui.empty, Dungeons.NoBosses())
			ui.note:Hide()
		end
	elseif ui.view == "loot" then
		Window.SetList(ui.bossList, bossRows)
		local rows = ui.source and Dungeons.LootRows(ui.source, dungeon.id, bossKnown) or {}
		Window.SetList(ui.lootList, rows)
		if not ui.source then
			Window.SetEmpty(ui.empty, SourceMessage())
			ui.note:Hide()
		elseif #rows == 0 then
			Window.SetEmpty(ui.empty, L.DUNGEON_NO_RECORDS)
			ui.note:Hide()
		end
	else
		-- Overview: the boss list beside the lore art.
		Window.SetList(ui.bossList, bossRows)
		if #bossKnown == 0 and not ui.source then
			ui.note:Hide()
		end
	end
	for index, key_ in ipairs(C.VIEWS) do
		local tab = ui.sideTabs[index]
		tab.muted = Muted(key_)
		SelectSideTab(tab, key_ == ui.view)
	end
	ui.bossList.frame:SetShown(ui.view == "overview" or ui.view == "bosses" or ui.view == "loot")
	ui.questList.frame:SetShown(ui.view == "quests")
	ui.prepList.frame:SetShown(ui.view == "prep")
	ui.overview:SetShown(ui.view == "overview")
	ui.prepPane:SetShown(ui.view == "prep")
	ui.abilityHeader:SetShown(ui.view == "bosses")
	ui.abilityList.frame:SetShown(ui.view == "bosses")
	ui.lootList.frame:SetShown(ui.view == "loot")
	ui.right:Show()
	ui.mapsButton:SetEnabled(true)
	if ui.navBar then
		local crumbs = { { name = ui.title:GetText(), OnClick = function() end } }
		if ui.view == "bosses" and selected then
			crumbs[#crumbs + 1] = { name = selected.name, OnClick = function() end }
		end
		ui.navBar:SetCrumbs(crumbs)
	end
	DrawDetail()
end

-- A source read made without AtlasLoot's pages is not kept: read again when AtlasLoot or its pages load later, or when
-- the fight that held them back ends. The hidden tab reads on its next show.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("ADDON_LOADED")
watcher:SetScript("OnEvent", function(self, event, addon)
	if event == "PLAYER_REGEN_ENABLED" then
		self:UnregisterEvent(event)
	elseif ui.reading or not Dungeons.IsSourceAddon(addon) then
		return
	end
	ui.reading, ui.sourceRead = false, false
	if ui.content and ui.content:IsVisible() then
		Refresh()
	end
end)

---@param work fun(yield: fun())
local function Run(work)
	ui.generation = ui.generation + 1
	local token, started = ui.generation, 0
	local co = coroutine.create(function()
		work(function()
			if debugprofilestop() - started >= 1 then
				coroutine.yield()
			end
		end)
	end)
	local function Step()
		if token ~= ui.generation or not ui.content:IsVisible() then
			return
		end
		started = debugprofilestop()
		local ok, err = coroutine.resume(co)
		if not ok then
			ui.sourceRead, ui.sourceError = true, true
			ui.note:SetText(L.DUNGEON_SOURCE_FAILED)
			geterrorhandler()(err)
		elseif coroutine.status(co) ~= "dead" then
			C_Timer.After(0, Step)
		end
	end
	C_Timer.After(0, Step)
end

-- The NavBar's search (ui/NavBar.lua): the addon's instance catalogue and the open instance's quests, capped at the
-- reference's twenty rows.
---@param text string
---@return table[]
local function SearchJournal(text)
	local needle = text:lower()
	local rows = {}
	for _, entry in ipairs(ui.catalog) do
		local name = ns.State.InstanceName(entry.id) or entry.name
		if name and name:lower():find(needle, 1, true) then
			rows[#rows + 1] = {
				name = name,
				sub = entry.raid and L.DUNGEON_RAIDS_TAB or L.DUNGEON_LIST_DUNGEONS,
				OnClick = function()
					ns.WindowDB().dungeon, ui.selecting = entry.id, false
					ui.selectedQuest, ui.selectedBoss = nil, nil
					Refresh()
				end,
			}
		end
		if #rows >= 20 then
			return rows
		end
	end
	for _, quest in ipairs(ui.page and ui.page.quests or {}) do
		local title = ns.State.QuestTitle(quest.id) or quest.title
		if title and title:lower():find(needle, 1, true) then
			local id = quest.id
			rows[#rows + 1] = {
				name = title,
				sub = ui.title:GetText(),
				OnClick = function()
					ui.view, ui.selectedQuest = "quests", id
					Draw()
				end,
			}
		end
		if #rows >= 20 then
			return rows
		end
	end
	return rows
end

function Refresh()
	if ui.navBar then
		ui.navBar:SetHomeClick(function()
			ui.selecting = true
			Draw()
		end)
		ui.navBar:SetSearch(SearchJournal)
	end
	if ui.classicGuide then
		ui.classicGuide:SetShown(ns.Integrations.ClassicGuideAvailable())
	end
	if not ui.content:IsVisible() then
		return
	end
	if ui.selecting == nil then
		-- A remembered instance opens its page; a character who has chosen none lands on the tile grid, as the
		-- journal's own Dungeons tab does.
		ui.selecting = ns.WindowDB().dungeon == nil
	end
	ui.reading = false
	if ui.sourceData ~= ns.Data then
		ui.sourceData, ui.source, ui.sourceRead, ui.sourceError = ns.Data, nil, false, false
	end
	Run(function(yield)
		local player = ns.State.Player()
		ui.catalog = Dungeons.List(ns.Data, player, yield)
		local dungeon
		for _, entry in ipairs(ui.catalog) do
			if entry.id == ns.WindowDB().dungeon then
				dungeon = entry
			end
		end
		if not dungeon and not ui.selecting then
			for _, entry in ipairs(ui.catalog) do
				if entry.suitable then
					dungeon = entry
					break
				end
			end
		end
		dungeon = dungeon or ui.catalog[1]
		if dungeon then
			ns.WindowDB().dungeon = dungeon.id
			ui.page = Dungeons.Page(ns.Data, player, ns.State.Completed(), ns.State.Log(), dungeon, yield)
			ui.bosses, ui.journalIcon = Dungeons.Journal(dungeon.id, yield)
			ui.portraits = {}
			for _, boss in ipairs(ui.bosses or {}) do
				ui.portraits[boss.name] = boss
			end
			local selected = ui.selectedQuest and ns.Data.quests[ui.selectedQuest]
			if
				#ui.page.quests == 0
				or (ui.selectedQuest and (not selected or not Dungeons.ForCharacter(selected, player)))
			then
				ui.selectedQuest = nil
			end
			ui.selectedQuest = ui.selectedQuest or dungeon.quests[1]
		end
		Draw()
		if not ui.sourceRead then
			local deferred
			ui.reading = true
			ui.source, deferred = Dungeons.Source(yield)
			ui.reading, ui.sourceRead = false, true
			if deferred then
				watcher:RegisterEvent("PLAYER_REGEN_ENABLED")
			end
			Draw()
		end
	end)
end

local function BuildDetail()
	local right = ui.right
	local detail = CreateFrame("Frame", nil, right, "InsetFrameTemplate") --[[@as Frame]]
	ui.detail = detail
	detail:SetAllPoints()
	detail:EnableMouse(true)
	detail:SetScript("OnLeave", GameTooltip_Hide)
	local width = C.RIGHT_W
	local scroll = CreateFrame("ScrollFrame", nil, detail, "ScrollFrameTemplate") --[[@as AGFScrollFrame]]
	ui.detailScroll = scroll
	scroll:SetPoint("TOPLEFT", 10, -10)
	scroll:SetSize(width - 32, C.BODY_H - 52)
	scroll.ScrollBar:ClearAllPoints()
	scroll.ScrollBar:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 3, 0)
	scroll.ScrollBar:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 3, 0)
	local body = CreateFrame("Frame", nil, scroll)
	ui.detailBody = body
	body:SetSize(width - 32, C.BODY_H - 52)
	scroll:SetScrollChild(body)
	ui.detailTitle = Text(body, "", 0, 0, width - 32, "GameFontNormalLarge")
	ui.detailInfo = Text(body, "", 0, 0, width - 32)
	ui.detailObjective = Text(body, "", 0, 0, width - 32)
	ui.detailObjective:SetSpacing(3)
	ui.detailObjectives = Text(body, "", 0, 0, width - 32, "GameFontNormal")
	ui.detailObjectives:SetTextColor(Window.GOLD[1], Window.GOLD[2], Window.GOLD[3])
	ui.detailGiver = Text(body, "", 0, 0, width - 32)
	ui.detailGiver:SetMaxLines(2)
	ui.detailEnd = Text(body, "", 0, 0, width - 32)
	ui.detailEnd:SetMaxLines(2)
	ui.detailDivider = body:CreateTexture(nil, "ARTWORK")
	ns.Art.Fit(ui.detailDivider, "UI-Journeys-Renown-divider", width - 32, 6)
	ui.detailRewards = Text(body, "", 0, 0, width - 32, "GameFontNormal")
	ui.detailRewards:SetTextColor(Window.GOLD[1], Window.GOLD[2], Window.GOLD[3])
	ui.detailChain = Text(body, "", 0, 0, width - 32, "GameFontDisableSmall")
	local giver = Button(detail, L.DUNGEON_SHOW_GIVER, width - 20, function()
		if ui.selectedQuest then
			Dungeons.Go(ui.selectedQuest)
		end
	end)
	ui.giver = giver
	giver:SetPoint("BOTTOMLEFT", 10, 10)
	MapTooltip(giver)
	for index = 1, 6 do
		local button = CreateFrame("Button", nil, body)
		button:SetSize(32, 32)
		button:SetScript("OnLeave", GameTooltip_Hide)
		ui.rewards[index] = button
	end
end

---@param parent Frame
---@param frame AGFWindowFrame
local function BuildContents(parent, frame)
	ui.content = parent
	ui.frame = frame
	parent:SetScript("OnHide", function()
		ui.generation = ui.generation + 1
	end)
	-- The journal's Dungeons and Raids pair belongs to its window's own tab bar; this shared window's bar carries
	-- the addon's tabs, so the pair rides at the select page's top (ui/EncounterJournalTabs.lua).
	local first = CreateFrame("Button", nil, parent, "PanelTabButtonTemplate") --[[@as AGFTopTab]]
	first:SetText(L.DUNGEON_LIST_DUNGEONS)
	first:SetID(1)
	first:SetPoint("TOPLEFT", C.LEFT, -2)
	first:SetScript("OnClick", function()
		ui.kind, ui.selecting = "dungeons", true
		PanelTemplates_SetTab(parent, 1)
		Draw()
	end)
	local second = CreateFrame("Button", nil, parent, "PanelTabButtonTemplate") --[[@as AGFTopTab]]
	second:SetText(L.DUNGEON_RAIDS_TAB)
	second:SetID(2)
	second:SetScript("OnClick", function()
		ui.kind, ui.selecting = "raids", true
		PanelTemplates_SetTab(parent, 2)
		Draw()
	end)
	PanelTemplates_SetNumTabs(parent, 2)
	ui.selectTabs[1], ui.selectTabs[2] = first, second

	-- The instance select page (ui/InstanceSelect.lua): the journal's panel ground, its large title and the 174x96
	-- tile grid four across on its own scroll box.
	local select = CreateFrame("Frame", nil, parent)
	ui.select = select
	select:SetPoint("TOPLEFT", 0, -2)
	select:SetPoint("BOTTOMRIGHT", -3, 0)
	local bg = select:CreateTexture(nil, "BACKGROUND")
	bg:SetTexture(C.SELECT_BG)
	bg:SetAllPoints()
	bg:SetPoint("TOPLEFT", 3, -1)
	select.bg = bg
	local selectTitle = select:CreateFontString(nil, "BACKGROUND", "GameFontNormalLarge2")
	ui.selectTitle = selectTitle
	selectTitle:SetJustifyH("LEFT")
	selectTitle:SetPoint("TOPRIGHT", -C.GRID_X - 8, -15)
	ui.grid = Window.CreateList(select, C.GRID_X, C.GRID_Y, C.GRID_W, C.GRID_H, C.TILE_H, PaintTile, function(value)
		ns.WindowDB().dungeon, ui.selectedQuest, ui.selectedBoss, ui.expanded = value.id, nil, nil, {}
		ui.selecting = false
		ui.questList.frame:SetVerticalScroll(0)
		Refresh()
	end, CreateInstanceTile, nil, C.GRID_COLUMNS, C.GRID_GAP)
	ui.grid.scrollBar:ClearAllPoints()
	ui.grid.scrollBar:SetPoint("TOPLEFT", ui.grid.scrollBox, "TOPRIGHT", 12, -6)
	ui.grid.scrollBar:SetPoint("BOTTOMLEFT", ui.grid.scrollBox, "BOTTOMRIGHT", 12, 4)
	select:Hide()

	-- The instance and encounter page (ui/Info.lua, ui/EncounterFrame.lua): the journal's 785x425 parchment, its
	-- edge shadows, the instance portrait button and the instance title, over the two panes and the side tabs.
	local info = CreateFrame("Frame", nil, parent)
	ui.info = info
	info:SetSize(C.INFO_W, C.INFO_H)
	info:SetPoint("BOTTOMRIGHT", -1, 2)
	local jbg = info:CreateTexture(nil, "BACKGROUND")
	jbg:SetDrawLayer("BACKGROUND", 1)
	jbg:SetTexture(C.JOURNAL_BG)
	jbg:SetTexCoord(C.JOURNAL_CROP[1], C.JOURNAL_CROP[2], C.JOURNAL_CROP[3], C.JOURNAL_CROP[4])
	jbg:SetAllPoints()
	info.bg = jbg
	local leftShadow = info:CreateTexture(nil, "BACKGROUND", nil, 3)
	leftShadow:SetTexture(C.EJ_SHEET)
	leftShadow:SetTexCoord(C.SHADOW_L[1], C.SHADOW_L[2], C.SHADOW_L[3], C.SHADOW_L[4])
	leftShadow:SetSize(C.SHADOW_W, C.SHADOW_H)
	leftShadow:SetPoint("TOPLEFT", 0, -11)
	local rightShadow = info:CreateTexture(nil, "BACKGROUND", nil, 3)
	rightShadow:SetTexture(C.EJ_SHEET)
	rightShadow:SetTexCoord(C.SHADOW_R[1], C.SHADOW_R[2], C.SHADOW_R[3], C.SHADOW_R[4])
	rightShadow:SetSize(C.SHADOW_W, C.SHADOW_H)
	rightShadow:SetPoint("TOPRIGHT", 0, -11)
	local instanceButton = CreateFrame("Button", nil, info)
	ui.instanceButton = instanceButton
	instanceButton:SetMotionScriptsWhileDisabled(true)
	instanceButton:SetSize(64, 61)
	instanceButton:SetPoint("TOPLEFT", 0, -3)
	instanceButton.icon = instanceButton:CreateTexture(nil, "BACKGROUND", nil, 6)
	instanceButton.icon:SetSize(64, 64)
	instanceButton.icon:SetPoint("TOPLEFT", 6.5, -7)
	local border = instanceButton:CreateTexture()
	Sheet(border, { 0.50585938, 0.63085938, 0.02246094, 0.08203125 })
	instanceButton:SetNormalTexture(border)
	local borderHighlight = instanceButton:CreateTexture()
	Sheet(borderHighlight, { 0.50585938, 0.63085938, 0.02246094, 0.08203125 })
	instanceButton:SetHighlightTexture(borderHighlight, "ADD")
	local title = info:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	ui.title = title
	title:SetJustifyH("LEFT")
	title:SetSize(290, 12)
	title:SetPoint("TOPLEFT", 65, -20)
	title:SetTextColor(Window.TITLE_INK[1], Window.TITLE_INK[2], Window.TITLE_INK[3])
	title:SetWordWrap(false)
	local location = Text(info, "", 65, 34, 290)
	ui.location = location
	location:SetWordWrap(false)
	local summary = Text(info, "", 65, 46, 290)
	ui.summary = summary
	summary:SetWordWrap(false)
	local note = Text(info, "", 65, 34, 290, "GameFontDisableSmall")
	ui.note = note
	note:SetWordWrap(false)

	-- The action controls stay over the parchment's top right, where the reference keeps its difficulty dropdown.
	local back = Button(info, L.MENU_BACK, 52, function()
		ui.selecting = true
		Draw()
	end, 20)
	ui.back = back
	back:SetPoint("TOPRIGHT", -8, -4)
	local mapsButton = Button(info, L.DUNGEON_MAPS_TAB, 62, function()
		if ui.page then
			ui.mapsButton:SetEnabled(false)
			local mapView = Window.CreateDungeonMapView(parent)
			mapView.back:SetScript("OnClick", function()
				ui.mapsButton:SetEnabled(true)
				mapView:Hide()
			end)
			Window.OpenDungeonMaps(ui.page.dungeon.id, parent)
		end
	end, 20)
	ui.mapsButton = mapsButton
	mapsButton:SetPoint("TOPRIGHT", -66, -4)
	local classicGuide = Button(info, L.DUNGEON_CLASSIC_GUIDE, 168, function()
		ns.Integrations.OpenClassicGuide()
	end)
	ui.classicGuide = classicGuide
	classicGuide:SetPoint("TOPRIGHT", -136, -4)
	classicGuide:SetShown(ns.Integrations.ClassicGuideAvailable())
	classicGuide:SetScript("OnEnter", function()
		ns.Overview.ShowTooltip(classicGuide, { L.DUNGEON_CLASSIC_GUIDE_TOOLTIP })
	end)
	classicGuide:SetScript("OnLeave", GameTooltip_Hide)
	local journey = Button(info, L.DUNGEON_START_JOURNEY, 110, function()
		if ui.page then
			ns.Choose("dungeon:" .. ui.page.dungeon.id, true)
		end
	end)
	ui.journey = journey
	journey:SetPoint("TOPRIGHT", -8, -28)
	local entrance = Button(info, L.GO_TO_ENTRANCE, 108, function()
		if ui.page then
			Dungeons.GoEntrance(ui.page.dungeon.id)
		end
	end)
	ui.entrance = entrance
	entrance:SetPoint("TOPRIGHT", -124, -28)
	MapTooltip(entrance)
	local plan = CreateFrame("CheckButton", nil, info, "UICheckButtonTemplate") --[[@as AGFDungeonPlan]]
	ui.plan = plan
	plan:SetPoint("TOPRIGHT", -300, -28)
	plan:SetSize(24, 24)
	plan:SetHitRectInsets(0, -100, 0, 0)
	plan.Text:SetText(L.DUNGEON_PLAN)
	plan.Text:SetFontObject("GameFontNormal")
	plan:SetScript("OnClick", function()
		if ui.page then
			Dungeons.SetPlanned(ui.page.dungeon.id, not Dungeons.Planned(ui.page.dungeon.id))
		end
	end)

	-- The two panes: the boss list 338x382 at (25,1) on the left (ui/Encounters.lua), the detail pane on the right
	-- and the side tabs down the pane's right edge (ui/InfoTabs.lua).
	local paneTop = C.INFO_H - C.PANE_H - C.PANE_Y
	local listX, listW = C.PANE_X + C.LIST_PAD, C.PANE_W - C.LIST_PAD
	ui.bossList = Window.CreateList(info, listX, paneTop, listW, C.PANE_H, C.BOSS_H + 2, PaintBoss, function(value)
		ui.selectedBoss = value.id
		if ui.view == "loot" and value.lootIndex then
			Window.ScrollListTo(ui.lootList, value.lootIndex)
		end
		Draw()
	end, CreateBossRow)
	ui.bossList.scrollBar:ClearAllPoints()
	ui.bossList.scrollBar:SetPoint("TOPLEFT", ui.bossList.scrollBox, "TOPRIGHT", 5, -5)
	ui.bossList.scrollBar:SetPoint("BOTTOMLEFT", ui.bossList.scrollBox, "BOTTOMRIGHT", 5, 5)
	ui.questList = Window.CreateList(info, listX, paneTop, listW, C.PANE_H, C.ROW_H, PaintQuest, function(value)
		SelectQuest(value.quest.id)
	end, CreateListRow)
	ui.prepList = Window.CreateList(info, listX, paneTop, listW, C.PANE_H, C.ROW_H, PaintPrep, function(value)
		if value.quest then
			Dungeons.Go(value.quest.id)
		end
	end, CreateListRow)
	local right = CreateFrame("Frame", nil, info)
	ui.right = right
	right:SetPoint("TOPLEFT", C.RIGHT_X, -paneTop)
	right:SetSize(C.RIGHT_W, C.PANE_H)

	-- Overview (ui/InstanceOverview.lua): the instance title over the entrance zone's existing map art in the
	-- reference's lore area, the entry lines in its paper well, and the reference's Show Map button.
	local overview = CreateFrame("Frame", nil, right)
	ui.overview = overview
	overview:SetAllPoints()
	local art = ns.ZoneIcon.CreateBackdrop(overview)
	ui.overviewArt = art
	art:SetPoint("TOPLEFT", 2, -2)
	art:SetPoint("BOTTOMRIGHT", -2, 2)
	overview.titleBG = overview:CreateTexture(nil, "ARTWORK")
	overview.titleBG:SetTexture(C.EJ_SHEET)
	overview.titleBG:SetTexCoord(0.34570313, 0.84570313, 0.42871094, 0.49121094)
	overview.titleBG:SetSize(256, 64)
	overview.titleBG:SetPoint("TOP", 0, -24)
	overview.titleBG:SetAlpha(0.75)
	local overviewTitle = overview:CreateFontString(nil, "OVERLAY", Window.FONT_TITLE)
	ui.overviewTitle = overviewTitle
	overviewTitle:SetPoint("TOP", 0, -40)
	overviewTitle:SetWidth(C.RIGHT_W - 40)
	overviewTitle:SetJustifyH("CENTER")
	overviewTitle:SetTextColor(Window.TITLE_INK[1], Window.TITLE_INK[2], Window.TITLE_INK[3])
	ui.overviewText = Window.CreatePaperWell(overview)
	ui.overviewText:SetPoint("BOTTOMLEFT", 12, 44)
	ui.overviewText:SetPoint("BOTTOMRIGHT", -12, 44)
	ui.overviewText:SetHeight(72)
	local showMap = Button(overview, L.DUNGEON_MAPS_TAB, 82, function()
		if ui.page then
			Window.OpenDungeonMaps(ui.page.dungeon.id, parent)
		end
	end, 24)
	ui.showMap = showMap
	showMap:SetPoint("BOTTOMLEFT", 12, 12)

	local prepPane = CreateFrame("Frame", nil, right)
	ui.prepPane = prepPane
	prepPane:SetAllPoints()
	ui.prepWell = Window.CreatePaperWell(prepPane)
	ui.prepWell:SetPoint("TOPLEFT", 12, -12)
	ui.prepWell:SetPoint("TOPRIGHT", -12, -12)
	ui.prepWell:SetHeight(120)
	ui.abilityHeader = Window.CreateSectionHeader(right, "", nil)
	ui.abilityHeader:SetPoint("TOPLEFT", 0, 0)
	ui.abilityHeader:SetWidth(C.RIGHT_W)
	ui.abilityList = Window.CreateList(
		right,
		0,
		28,
		C.RIGHT_W,
		C.PANE_H - 28,
		C.ABILITY_H,
		PaintAbility,
		function() end,
		CreateAbilityRow
	)
	ui.lootList = Window.CreateList(
		right,
		0,
		0,
		C.RIGHT_W,
		C.PANE_H,
		C.LOOT_ROW,
		PaintLoot,
		function() end,
		CreateLootRow
	)
	-- The journal's side tabs run down the right edge from the pane's top.
	for index, spec in ipairs(C.SIDE) do
		local tab = CreateSideTab(info, spec)
		if index == 1 then
			tab:SetPoint("TOPLEFT", info, "TOPRIGHT", -C.SIDE_X - C.SIDE_W, -C.SIDE_Y)
		else
			tab:SetPoint("TOP", ui.sideTabs[index - 1], "BOTTOM", 0, -C.SIDE_GAP)
		end
		ui.sideTabs[index] = tab
	end
	local empty = Window.CreateEmpty(info, "UI-EJ-Classic")
	ui.empty = empty
	empty.Art:ClearAllPoints()
	empty.Art:SetPoint("TOPLEFT", C.PANE_X, -paneTop)
	empty.Art:SetSize(C.INFO_W - C.PANE_X - 8, C.PANE_H)
	ns.Art.Cover(empty.Art, "UI-EJ-Classic", C.INFO_W - C.PANE_X - 8, C.PANE_H)
	empty.Text:SetWidth(C.INFO_W - C.PANE_X - 80)
	Window.SetEmpty(empty, nil)
	info:Hide()
	BuildDetail()
end

---@param parent Frame
---@param frame AGFWindowFrame
local function Build(parent, frame)
	ui.content, ui.frame = parent, frame
	local built = false
	parent:SetScript("OnShow", function()
		if not built then
			built = true
			BuildContents(parent, frame)
		end
	end)
	ui.navBar = Window.CreateNavBar(frame)
end

---@param instance integer
function Window.OpenDungeon(instance)
	ns.WindowDB().dungeon, ui.selectedQuest, ui.selectedBoss = instance, nil, nil
	ui.selecting = false
	ns.OpenWindow()
	for index, tab in ipairs(Window.Tabs()) do
		if tab.key == "dungeons" then
			Window.Select(index)
			return
		end
	end
end

Window.AddTab({
	key = "dungeons",
	label = L.TAB_DUNGEONS,
	FullInset = true,
	Build = Build,
	Refresh = Refresh,
	OnSelect = function(selected)
		if ui.navBar then
			ui.navBar:SetShown(selected)
		end
	end,
})
