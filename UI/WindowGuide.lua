---@type string, AGFNamespace
local _, ns = ...
local Window, L = ns.Window, ns.L
local PAGE_SIZE, ROW_HEIGHT, ROW_PITCH = 10, 32, 34

-- A zone catalogue, not a second eligibility policy: only the planner supplies actionable steps.
-- Questie prerequisites order the outline; no future quest is sent to navigation or tracking.
---@param data AGFData
---@param player AGFPlayer
---@param completed table<integer, boolean>
---@param journey AGFJourney
---@param steps AGFStep[]
---@return integer[]
function Window.GuideOutline(data, player, completed, journey, steps)
	local zone = journey.zone
	if not zone then
		return {}
	end
	local active = {}
	---@type table<integer, AGFQuest>
	local candidates = {}
	---@type integer[]
	local ids = {}
	for _, step in ipairs(steps) do
		for _, id in ipairs(step.quests) do
			active[id] = true
		end
	end
	---@param mask? integer
	---@param bit? integer
	local function Matches(mask, bit)
		return not mask or mask == 0 or (bit and math.floor(mask / bit) % 2 == 1)
	end
	for id, quest in pairs(data.quests) do
		if
			(quest.zone == zone or (quest.start and quest.start.map == zone))
			and (quest.side == 3 or quest.side == player.side)
			and Matches(quest.races, player.raceBit)
			and Matches(quest.classes, player.classBit)
			and not quest.repeatable
			and not quest.dungeon
			and not completed[id]
			and not active[id]
		then
			candidates[id] = quest
			ids[#ids + 1] = id
		end
	end
	-- Follow-ups to this lap first, then useful levels, then the rest of the zone.
	local follows, following = {}, {}
	local function FollowsRoute(id)
		if active[id] then
			return true
		end
		if follows[id] ~= nil then
			return follows[id]
		end
		if following[id] or not candidates[id] then
			return false
		end
		following[id] = true
		local quest = candidates[id]
		local result = false
		for _, requirements in ipairs({ quest.pre or {}, quest.preAny or {} }) do
			for _, before in ipairs(requirements) do
				if before > 0 and FollowsRoute(before) then
					result = true
				end
			end
		end
		following[id], follows[id] = nil, result
		return result
	end
	local function Rank(id)
		if FollowsRoute(id) then
			return 0
		end
		local level = candidates[id].level
		if level < 0 or (level >= player.level - 5 and level <= player.level) then
			return 1
		end
		return level > player.level and 2 or 3
	end
	table.sort(ids)
	local ranks = {}
	for _, id in ipairs(ids) do
		ranks[id] = Rank(id)
	end
	table.sort(ids, function(a, b)
		if ranks[a] ~= ranks[b] then
			return ranks[a] < ranks[b]
		end
		local left, right = candidates[a], candidates[b]
		local al, bl = left.level, right.level
		return al < bl or (al == bl and a < b)
	end)
	local ordered, visited = {}, {}
	local function Visit(id)
		if visited[id] or not candidates[id] then
			return
		end
		visited[id] = true
		local quest = candidates[id]
		for _, requirements in ipairs({ quest.pre or {}, quest.preAny or {} }) do
			for _, before in ipairs(requirements) do
				if before > 0 then
					Visit(before)
				end
			end
		end
		ordered[#ordered + 1] = id
	end
	for _, id in ipairs(ids) do
		Visit(id)
	end
	return ordered
end

---@class AGFGuideRow : AGFWindowRow, AGFStepHoverRow
---@field step? AGFStep
---@field index? integer
---@field questID? integer

---@type Frame?
local guide
---@type AGFWindowSectionHeader
local heading
---@type FontString
local count
---@type Button
local previous
---@type Button
local nextPage
---@type AGFGuideRow[]
local rows = {}
---@type AGFJourney?
local target
local page = 1
local Refresh

---@param row AGFGuideRow
local function RowEnter(row)
	if row.step and row.index then
		ns.Pins.Highlight(row.step, true)
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		local travel = row.index == 1 and ns.Integrations.Travel(row.step) or ns.Integrations.TravelLine(row.step)
		ns.Pins.StepTooltip(GameTooltip, row.step, row.index, travel)
		GameTooltip:Show()
	elseif row.questID then
		ns.Overview.ShowTooltip(row, {
			(ns.Pins.QuestLineText(row.questID)),
			L.GUIDE_OUTLINE_TOOLTIP,
		})
	end
end

---@param parent Frame
local function Build(parent)
	guide = CreateFrame("Frame", "AdventureGuideForeverFullGuide", parent)
	guide:SetAllPoints(parent)
	guide:SetFrameLevel(parent:GetFrameLevel() + 20)
	guide:EnableMouse(true)
	local background = guide:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0.025, 0.02, 0.015, 1)
	heading = Window.CreateSectionHeader(guide, "")
	heading:SetPoint("TOPLEFT", Window.LEFT, -14)
	heading:SetWidth(Window.INSET_WIDTH - 180)
	local back = CreateFrame("Button", nil, guide, "UIPanelButtonTemplate") --[[@as Button]]
	back:SetSize(112, 22)
	back:SetPoint("TOPRIGHT", -Window.RIGHT, -14)
	back:SetText(L.GUIDE_BACK)
	back:SetScript("OnClick", function()
		guide:Hide()
	end)
	for index = 1, PAGE_SIZE do
		local row = Window.CreateStepRow(guide, ROW_HEIGHT) --[[@as AGFGuideRow]]
		row:SetWidth(Window.INSET_WIDTH - Window.LEFT - Window.RIGHT)
		row:SetPoint("TOPLEFT", Window.LEFT, -42 - (index - 1) * ROW_PITCH)
		row:SetScript("OnEnter", RowEnter)
		row:SetScript("OnLeave", ns.Overview.RowLeave)
		row:SetScript("OnHide", ns.Overview.RowLeave)
		row:SetScript("OnClick", function(self)
			if self.step and not ns.ShowQuest(self.step) then
				ns.Overview.ShowOnMap(self.step)
			end
		end)
		rows[index] = row
	end
	previous, nextPage, count = Window.CreatePager(guide, function()
		page = math.max(1, page - 1)
		Refresh()
	end, function()
		page = page + 1
		Refresh()
	end)
	guide:HookScript("OnHide", function()
		GameTooltip_Hide()
	end)
	parent:HookScript("OnHide", function()
		guide:Hide()
	end)
	ns.OnRouteChange(function()
		if guide:IsVisible() then
			Refresh()
		end
	end)
end

Refresh = function()
	if not target then
		return
	end
	local route = ns.Route()
	local steps = {}
	if route.journey == target.key then
		steps = route.steps
	else
		for _, journey in ipairs(route.journeys) do
			if journey.key == target.key then
				steps = journey.steps
				break
			end
		end
	end
	local future = Window.GuideOutline(ns.Data, ns.State.Player(), ns.State.Completed(), target, steps)
	local total = #steps + #future
	local pages
	page, pages = Window.ClampPage(page, total, PAGE_SIZE)
	heading.Label:SetText(target.title)
	count:SetText(L.GUIDE_PAGE:format(page, pages, #steps, #future))
	previous:SetEnabled(page > 1)
	nextPage:SetEnabled(page < pages)
	for index, row in ipairs(rows) do
		local position = (page - 1) * PAGE_SIZE + index
		local step = steps[position]
		local id = future[position - #steps]
		row.step, row.index, row.questID = step, step and position or nil, id
		row:SetShown(step ~= nil or id ~= nil)
		row:SetEnabled(step ~= nil)
		row:SetMotionScriptsWhileDisabled(true)
		if step then
			Window.SetStepRow(row, position, step.title, step.detail, step)
			row.Number:Show()
			row.Ring:Show()
			row.Title:SetTextColor(1, 0.82, 0)
		elseif id then
			local title, color = ns.Pins.QuestLineText(id)
			Window.SetStepRow(row, 1, title, L.GUIDE_OUTLINE)
			ns.Art.SetSliceShown(row.Selected, false)
			row.Number:Hide()
			row.Ring:Hide()
			row.Title:SetTextColor(color.r, color.g, color.b)
		end
	end
end

---@param journey AGFJourney
---@param parent Frame
function Window.OpenGuide(journey, parent)
	if not guide then
		Build(parent)
	end
	target, page = journey, 1
	Refresh()
	assert(guide):Show()
end
