---@type string, AGFNamespace
local _, ns = ...
local L = ns.L
local Window, Overview = ns.Window, ns.Overview

-- The window's Completion tab (docs/design.md §2.19): Legacy Forever's progress where the player is and where the route
-- goes next (Providers.lua; at most four zones). The zone shown is featured over its map with each category Legacy
-- counts, and its next three unfinished objectives on the right; the other zones run across under the divider, a
-- click featuring one. What Legacy counts is completion, never a quest the player can take now. Without a Legacy
-- Forever that has the API the tab stays, greyed, and says what to install.

local FEATURED_WIDTH, FEATURED_HEIGHT, FEATURED_SPAN, RING = 440, 178, 900, 44
local CATEGORY_TOP, CATEGORY_PITCH, CATEGORY_COLUMNS = 72, 16, 2
local TARGET_ROWS, TARGET_HEIGHT, TARGET_PITCH, HEAD = 3, 44, 49, 18
local COLUMNS, GRID_GAP, GRID_SPAN, GRID_RING, GRID_PAD = 4, 10, 900, 30, 14
local BAR_GAP = 8
local LEGACY_ICON = "Legacy-Rewards-Tracker-Icon"
local DONE_MARK = "|A:UI-QuestTracker-Tracker-Check:12:12|a"
-- Legacy's categories in its own order, and each target kind's mark.
local CATEGORIES = { "areas", "taxis", "dungeons", "raids", "legacy", "reputations", "quests" }
local TARGET_ICONS = {
	explore = "poi-town",
	instance = "Dungeon",
	kill = "questobjective",
	quest = "QuestNormal",
	reputation = "Legacy-Tree-Frame-Points-icon",
}

local LEFT, TOP = Window.LEFT, Window.TOP
local WIDTH = Window.INSET_WIDTH - LEFT - Window.RIGHT
local GRID_TOP = TOP + FEATURED_HEIGHT + Window.DIVIDER_SPAN
local GRID_WIDTH = (WIDTH - (COLUMNS - 1) * GRID_GAP) / COLUMNS
local GRID_HEIGHT = Window.INSET_HEIGHT - 12 - GRID_TOP
local SIDE_LEFT = LEFT + FEATURED_WIDTH + 12
local SIDE_WIDTH = WIDTH - FEATURED_WIDTH - 12
local CATEGORY_WIDTH = (FEATURED_WIDTH - 36) / CATEGORY_COLUMNS

---@class AGFCompletionCard : AGFWindowCard
---@field Icon AGFRingIcon
---@field Title FontString
---@field Reason FontString
---@field Categories FontString[]
---@field Bar AGFProgressBar
---@field Foot FontString
---@field zone? AGFCompletionZone

---@class AGFTargetRow : AGFWindowIconRow
---@field zone? AGFCompletionZone
---@field target? LFTarget

---@type AGFCompletionCard
local featured
---@type AGFCompletionCard[]
local grid = {}
---@type AGFTargetRow[]
local targets = {}
---@type FontString
local heading
---@type FontString
local noTargets
---@type Texture
local divider
---@type AGFWindowEmpty
local empty
-- The zone featured: the player's own until another card is clicked.
---@type integer?
local picked

-- The line the tab gives while Legacy Forever is missing or too old to ask.
---@return string?
local function Muted()
	local state = ns.Providers.LegacyState()
	if state == "missing" then
		return ns.Companions.Hint("LegacyForever") or L.LEGACY_ABSENT
	elseif state == "outdated" then
		return L.LEGACY_OUTDATED
	end
end

-- "3/5", or with what Legacy can't check yet: "3/5 · 2 not known yet", or only that when it knows none of them, never
-- "0/0". Pending is never counted done.
---@param counts LFCounts
---@return string
local function CountLine(counts)
	local unknown = counts.pending > 0 and L.COMPLETION_NOT_KNOWN:format(counts.pending) or nil
	if counts.total == 0 and unknown then
		return unknown
	end
	local line = L.COMPLETION_COUNTS:format(counts.done, counts.total)
	return unknown and line .. L.SEPARATOR .. unknown or line
end

-- Legacy Forever's hint (its PENDING_HINTS) for a category's unchecked items, by the category they all belong to.
local NOT_KNOWN_HINTED = { taxis = L.COMPLETION_NOT_KNOWN_TAXIS, quests = L.COMPLETION_NOT_KNOWN_QUESTS }

-- "2 not known yet", with how to check them when they are all one category's: a fresh character's flight paths.
---@param summary LFZoneSummary
---@return string
local function NotKnownLine(summary)
	for _, category in ipairs(summary.categories) do
		if category.pending == summary.pending then
			return (NOT_KNOWN_HINTED[category.key] or L.COMPLETION_NOT_KNOWN):format(summary.pending)
		elseif category.pending > 0 then
			break
		end
	end
	return L.COMPLETION_NOT_KNOWN:format(summary.pending)
end

-- The zone's line under its name: why Legacy has no counts for it, else what is still waiting on data.
---@param zone AGFCompletionZone
---@return string
local function ZoneLine(zone)
	local summary = zone.summary
	if not summary then
		return zone.error == "loading" and L.COMPLETION_LOADING or L.COMPLETION_UNAVAILABLE
	elseif #summary.categories == 0 then
		return L.COMPLETION_EMPTY
	elseif summary.questsStatus == "loading" then
		return L.COMPLETION_LOADING
	end
	return summary.pending > 0 and NotKnownLine(summary) or ""
end

---@param parent Frame
---@param isFeatured boolean
---@return AGFCompletionCard
local function CreateCard(parent, isFeatured)
	local card = Window.CreateCard(parent, true) --[[@as AGFCompletionCard]]
	local width, height = isFeatured and FEATURED_WIDTH or GRID_WIDTH, isFeatured and FEATURED_HEIGHT or GRID_HEIGHT
	Window.SizeCard(card, width, height, 0.75)
	local content = CreateFrame("Frame", nil, card)
	content:SetAllPoints()
	content:SetFrameLevel(card:GetFrameLevel() + 5)
	local ring = isFeatured and RING or GRID_RING
	local pad = isFeatured and 18 or GRID_PAD
	card.Icon = Window.CreateRingIcon(content, ring)
	card.Icon:SetPoint("TOPLEFT", pad, -pad)
	Window.SetRingIcon(card.Icon, LEGACY_ICON)
	card.Title = content:CreateFontString(nil, "ARTWORK", isFeatured and "GameFontNormalHuge" or "GameFontNormal")
	card.Reason =
		content:CreateFontString(nil, "ARTWORK", isFeatured and "GameFontHighlight" or "GameFontHighlightSmall")
	card.Bar = Overview.CreateBar(content)
	card.Foot = content:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
	card.Foot:SetWordWrap(false)
	card.Categories = {}
	if isFeatured then
		local left = pad + ring + 14
		card.Title:SetPoint("TOPLEFT", left, -16)
		card.Title:SetPoint("RIGHT", -16, 0)
		card.Reason:SetPoint("TOPLEFT", left, -42)
		card.Reason:SetPoint("RIGHT", -16, 0)
		for index = 1, #CATEGORIES do
			local text = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
			local column, row = (index - 1) % CATEGORY_COLUMNS, math.floor((index - 1) / CATEGORY_COLUMNS)
			text:SetPoint("TOPLEFT", pad + column * CATEGORY_WIDTH, -(CATEGORY_TOP + row * CATEGORY_PITCH))
			text:SetWidth(CATEGORY_WIDTH - 6)
			text:SetJustifyH("LEFT")
			text:SetWordWrap(false)
			card.Categories[index] = text
		end
		card.Foot:SetPoint("TOPRIGHT", -18, -(FEATURED_HEIGHT - 41))
		card.Foot:SetJustifyH("RIGHT")
		card.Highlight:Hide()
	else
		card.Title:SetPoint("LEFT", card.Icon, "RIGHT", 10, 0)
		card.Title:SetWidth(GRID_WIDTH - GRID_PAD * 2 - ring - 10)
		card.Title:SetMaxLines(2)
		card.Title:SetWordWrap(true)
		card.Reason:SetPoint("TOPLEFT", GRID_PAD, -60)
		card.Reason:SetWidth(GRID_WIDTH - 2 * GRID_PAD)
		card.Reason:SetWordWrap(true)
		card.Reason:SetMaxLines(3)
		card.Foot:SetPoint("TOPRIGHT", -GRID_PAD, -(GRID_HEIGHT - GRID_PAD - 10))
		card.Foot:SetJustifyH("RIGHT")
		card:SetScript("OnClick", function(self)
			if self.zone then
				picked = self.zone.map
				Window.Refresh()
			end
		end)
	end
	for _, text in ipairs({ card.Title, card.Reason }) do
		text:SetJustifyH("LEFT")
	end
	return card
end

-- The zone's map, name, line and overall bar; the featured card adds a line a category.
---@param card AGFCompletionCard
---@param zone AGFCompletionZone
---@param isFeatured boolean
local function RefreshCard(card, zone, isFeatured)
	card.zone = zone
	local width, height = card:GetSize(true)
	ns.ZoneIcon.SetBackdrop(
		card.Art --[[@as AGFZoneBackdrop]],
		width - 4,
		height - 4,
		zone.map,
		0.5,
		0.5,
		isFeatured and FEATURED_SPAN or GRID_SPAN
	)
	card.Title:SetText(zone.name)
	card.Reason:SetText(ZoneLine(zone))
	local summary = zone.summary
	local counted = summary ~= nil and summary.total > 0
	card.Foot:SetShown(counted)
	if summary and counted then
		card.Foot:SetText(L.COMPLETION_COUNTS:format(summary.done, summary.total))
		local pad = isFeatured and 18 or GRID_PAD
		local cardWidth = isFeatured and FEATURED_WIDTH or GRID_WIDTH
		local top = isFeatured and FEATURED_HEIGHT - 38 or GRID_HEIGHT - GRID_PAD - 8
		local room = cardWidth - 2 * pad - card.Foot:GetUnboundedStringWidth() - BAR_GAP
		Overview.SetBar(card.Bar, pad, top, room, summary.done / summary.total)
	else
		card.Bar:Hide()
	end
	local byKey = {}
	for _, category in ipairs(summary and summary.categories or {}) do
		byKey[category.key] = category
	end
	local shown = 0
	for _, key in ipairs(CATEGORIES) do
		local category = byKey[key]
		if category and card.Categories[shown + 1] then
			shown = shown + 1
			local label = L["COMPLETION_CATEGORY_" .. key:upper()]
			local line = label .. "  " .. CountLine(category)
			if category.scope == "account" then
				line = line .. L.SEPARATOR .. L.COMPLETION_ACCOUNT
			end
			if category.complete then
				line = line .. " " .. DONE_MARK
			end
			card.Categories[shown]:SetText(line)
			card.Categories[shown]:Show()
		end
	end
	for index = shown + 1, #card.Categories do
		card.Categories[index]:Hide()
	end
end

---@param parent Frame
---@return AGFTargetRow
local function CreateTarget(parent)
	local row = Window.CreateIconRow(parent, TARGET_HEIGHT) --[[@as AGFTargetRow]]
	row:SetWidth(SIDE_WIDTH)
	-- Legacy checks the objective is still unfinished and placed, then sets the waypoint its own way.
	row:SetScript("OnClick", function(self)
		if self.zone and self.target and self.target.place then
			ns.Providers.NavigateCompletion(self.zone.map, self.target.key)
		end
	end)
	row:SetScript("OnEnter", function(self)
		local target = self.target
		if not target then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip_SetTitle(GameTooltip, target.text)
		if not target.place then
			GameTooltip_AddNormalLine(GameTooltip, L.COMPLETION_NO_LOCATION)
		elseif not ns.Setting("wanderer") then
			GameTooltip_AddInstructionLine(GameTooltip, L.COMPLETION_GO)
		end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	return row
end

---@param content Frame
local function Build(content)
	empty = Window.CreateEmpty(content, "Legacy-Tree-Frame-background")
	featured = CreateCard(content, true)
	featured:SetPoint("TOPLEFT", LEFT, -TOP)
	heading = Window.Heading(content, L.NEXT_STEPS)
	heading:SetPoint("TOPLEFT", SIDE_LEFT + 2, -TOP)
	for index = 1, TARGET_ROWS do
		local row = CreateTarget(content)
		row:SetPoint("TOPLEFT", SIDE_LEFT, -(TOP + HEAD + (index - 1) * TARGET_PITCH))
		targets[index] = row
	end
	noTargets = content:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	noTargets:SetPoint("TOPLEFT", SIDE_LEFT + 4, -(TOP + HEAD + 8))
	noTargets:SetWidth(SIDE_WIDTH - 8)
	noTargets:SetJustifyH("LEFT")
	divider = Window.CreateDivider(content, TOP + FEATURED_HEIGHT)
	for index = 1, COLUMNS - 1 do
		local card = CreateCard(content, false)
		card:SetPoint("TOPLEFT", LEFT + (index - 1) * (GRID_WIDTH + GRID_GAP), -GRID_TOP)
		grid[index] = card
	end
end

---@param zone AGFCompletionZone
local function RefreshTargets(zone)
	local list = zone.targets
	noTargets:SetShown(#list == 0)
	noTargets:SetText(zone.summary and L.COMPLETION_EMPTY or ZoneLine(zone))
	for index, row in ipairs(targets) do
		local target = list[index]
		row.zone, row.target = zone, target
		row:SetShown(target ~= nil)
		if target then
			Window.SetRingIcon(row.Icon, TARGET_ICONS[target.kind] or "questobjective")
			row.Title:SetText(target.text)
			local parts = {}
			if target.quantity and target.required then
				parts[1] = L.COMPLETION_COUNTS:format(target.quantity, target.required)
			end
			parts[#parts + 1] = not target.place and L.COMPLETION_NO_LOCATION or nil
			row.Detail:SetText(table.concat(parts, L.SEPARATOR))
		end
	end
end

local function Refresh()
	local muted = Muted()
	local zones = muted == nil and ns.Providers.Completion().zones or {}
	local line = muted or (#zones == 0 and L.COMPLETION_EMPTY) or nil
	Window.SetEmpty(empty, line)
	local first
	for _, zone in ipairs(zones) do
		first = (first == nil or zone.map == picked) and zone or first
	end
	featured:SetShown(first ~= nil)
	heading:SetShown(first ~= nil)
	divider:SetShown(first ~= nil and #zones > 1)
	if not first then
		noTargets:Hide()
		for _, row in ipairs(targets) do
			row:Hide()
		end
	else
		RefreshCard(featured, first, true)
		RefreshTargets(first)
	end
	local index = 0
	for _, zone in ipairs(zones) do
		if zone ~= first and grid[index + 1] then
			index = index + 1
			grid[index]:Show()
			RefreshCard(grid[index], zone, false)
		end
	end
	for rest = index + 1, #grid do
		grid[rest]:Hide()
	end
end

Window.AddTab({ key = "completion", label = L.TAB_COMPLETION, Build = Build, Refresh = Refresh, Muted = Muted })
