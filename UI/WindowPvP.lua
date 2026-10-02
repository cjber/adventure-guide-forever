---@type string, AGFNamespace
local _, ns = ...
local L = ns.L
local Window = ns.Window

-- The window's PvP tab (docs/design.md §2.19): the character's PvP rank over the battleground queue's own art, its rank
-- points toward the next rank and the next reward, as the character pane's rank tab reads them (PvP.lua), and on the
-- right every battleground open at the player's level with the nearest battlemaster of their side. No honour
-- conversion, match count or queue time: the client gives none of them.

local CARD_WIDTH, REWARD_RING = Window.Cards.width, 26
local ROWS, ROW_HEIGHT, ROW_PITCH, HEAD = 7, 44, 49, 18
-- The rank badges (Interface\PvPRankBadges): PvPRank01 to 14 by rank, then the Alliance and Horde crests.
local BADGE_FIRST, BADGE_ALLIANCE, BADGE_HORDE = 136766, 136781, 136782

local TOP = Window.TOP
local SIDE_LEFT = Window.Cards.sideLeft
local SIDE_WIDTH = Window.Cards.sideWidth

---@class AGFPvPCard : AGFWindowPictureCard
---@field Reward AGFRingIcon
---@field RewardText FontString

---@class AGFBattleRow : AGFWindowIconRow
---@field battle? AGFPvPBattle

---@type AGFPvPCard
local card
---@type AGFBattleRow[]
local rows = {}
---@type FontString
local heading
---@type FontString
local none
---@type AGFWindowEmpty
local empty

-- The line the tab gives while the client has neither rank nor battlegrounds to read.
---@return string?
local function Muted()
	local data = ns.PvP.Data()
	if not data.available and data.rank.state == "unavailable" then
		return L.PVP_UNAVAILABLE
	end
end

---@param parent Frame
---@return AGFBattleRow
local function CreateRow(parent)
	local row = Window.CreateIconRow(parent, ROW_HEIGHT) --[[@as AGFBattleRow]]
	row:SetWidth(SIDE_WIDTH)
	Window.SetRingIcon(row.Icon, "battlemaster")
	-- The battlemaster as a waypoint, through Shortest Path when it's loaded; one the data has no place for says so.
	row:SetScript("OnClick", function(self)
		if self.battle and self.battle.place and not ns.Setting("wanderer") then
			ns.PvP.Go(self.battle.id)
		end
	end)
	row:SetScript("OnEnter", function(self)
		local battle = self.battle
		if not battle then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, battle.name)
		GameTooltip_AddNormalLine(GameTooltip, L.PVP_BATTLEGROUND_LEVEL:format(battle.level))
		if not battle.place then
			GameTooltip_AddNormalLine(GameTooltip, L.PVP_NO_BATTLEMASTER)
		elseif not ns.Setting("wanderer") then
			GameTooltip_AddInstructionLine(GameTooltip, L.PVP_GO_BATTLEMASTER)
		end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	return row
end

---@param content Frame
local function Build(content)
	empty = Window.CreateEmpty(content, "pvpqueue-background-casual")
	local picture, inner = Window.CreatePictureCard(content)
	card = picture --[[@as AGFPvPCard]]
	card.Reward = Window.CreateRingIcon(inner, REWARD_RING)
	card.Reward:SetPoint("TOPLEFT", 22, -100)
	card.RewardText = inner:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	card.RewardText:SetPoint("LEFT", card.Reward, "RIGHT", 12, 0)
	card.RewardText:SetWidth(CARD_WIDTH - 22 - REWARD_RING - 12 - 18)
	card.RewardText:SetJustifyH("LEFT")
	card.RewardText:SetWordWrap(true)
	card.RewardText:SetMaxLines(2)

	heading = Window.Heading(content, L.MENU_BATTLEGROUNDS)
	heading:SetPoint("TOPLEFT", SIDE_LEFT + 2, -TOP)
	for index = 1, ROWS do
		local row = CreateRow(content)
		row:SetPoint("TOPLEFT", SIDE_LEFT, -(TOP + HEAD + (index - 1) * ROW_PITCH))
		rows[index] = row
	end
	none = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	none:SetPoint("TOPLEFT", SIDE_LEFT + 4, -(TOP + HEAD + 8))
	none:SetWidth(SIDE_WIDTH - 8)
	none:SetJustifyH("LEFT")
	none:SetText(L.PVP_NO_BATTLEGROUNDS)
end

-- The rank's badge, title, line and bar: a rank with its points toward the next, the highest with none to earn.
---@param rank AGFPvPRank
local function RefreshRank(rank)
	local side = ns.State.Player().side
	local ranked = (rank.state == "ranked" or rank.state == "capped") and rank.level ~= nil and rank.level > 0
	Window.SetPicture(card, side == 1 and "pvpqueue-background-casual-alliance" or "pvpqueue-background-casual-horde")
	Window.SetRingIcon(
		card.Icon,
		ranked and BADGE_FIRST + rank.level - 1 or (side == 1 and BADGE_ALLIANCE or BADGE_HORDE)
	)
	if ranked then
		card.Title:SetText(L.PVP_RANK:format(rank.level))
	else
		local title = rank.state == "unranked" and L.PVP_UNRANKED or L.TAB_PVP
		card.Title:SetText(title)
	end
	local range = (rank.state == "capped" and L.PVP_CAPPED) or (rank.state == "unavailable" and L.PVP_UNAVAILABLE) or ""
	card.Range:SetText(range)
	local earned, threshold = rank.earned, rank.threshold
	local points = rank.state ~= "capped" and earned ~= nil and threshold ~= nil and threshold > 0
	card.BarLabel:SetShown(points)
	if points then
		---@cast earned -?
		---@cast threshold -?
		card.BarLabel:SetText(L.PVP_RANK_POINTS:format(earned, threshold))
		Window.SetPictureProgress(card, earned / threshold)
	else
		card.Bar:Hide()
	end
	local reward = rank.reward
	card.Reward:SetShown(reward ~= nil)
	card.RewardText:SetShown(reward ~= nil)
	if reward then
		Window.SetRingIcon(card.Reward, reward.icon or "battlemaster")
		card.RewardText:SetText(L.PVP_NEXT_REWARD:format(reward.level, reward.text))
	end
end

---@param battles AGFPvPBattle[]
local function RefreshBattles(battles)
	none:SetShown(#battles == 0)
	for index, row in ipairs(rows) do
		local battle = battles[index]
		row.battle = battle
		row:SetShown(battle ~= nil)
		if battle then
			row.Title:SetText(battle.name)
			local detail = L.PVP_BATTLEGROUND_LEVEL:format(battle.level)
			row.Detail:SetText(battle.place and detail or detail .. L.SEPARATOR .. L.PVP_NO_BATTLEMASTER)
		end
	end
end

local function Refresh()
	local muted = Muted()
	Window.SetEmpty(empty, muted)
	card:SetShown(muted == nil)
	heading:SetShown(muted == nil)
	if muted then
		none:Hide()
		for _, row in ipairs(rows) do
			row:Hide()
		end
		return
	end
	local data = ns.PvP.Data()
	RefreshRank(data.rank)
	RefreshBattles(data.battlegrounds)
end

Window.AddTab({ key = "pvp", label = L.TAB_PVP, Build = Build, Refresh = Refresh, Muted = Muted })
