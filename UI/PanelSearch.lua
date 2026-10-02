---@type string, AGFNamespace
local _, ns = ...
local L, Art = ns.L, ns.Art
---@class AGFPanelSearch
local Search = {}
ns.PanelSearch = Search

-- The search (docs/design.md §2.4): 3 characters or more put up to 10 quests in place of the cards; a locked one lists
-- why, unmet lines first, up to 6 (its tooltip has them all).
local SEARCH_MIN, SEARCH_ROWS, WHY_LINES, RESULT_HEIGHT, WHY_HEIGHT = 3, 10, 6, 24, 14
local ROW_GAP = 2

---@type AGFSearchRow[]
local results = {}

-- One search result: the quest and where it starts, and for a locked one a lock and why (docs/design.md §2.4). One
-- open now joins the route with a shift-click, and wears the tradeskill favourite's star while it does (§2.18); an
-- orange or red one, which no route takes, does not (`open` false).
---@class AGFSearchRow : Frame
---@field Lock Texture
---@field Star Texture
---@field id? integer
---@field open? boolean
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
	row.Star = row:CreateTexture(nil, "ARTWORK")
	Art.Fit(row.Star, "tradeskills-star", 14, 14)
	row.Star:SetPoint("TOPRIGHT", -4, -5)
	row.Zone = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.Zone:SetPoint("TOPRIGHT", -22, -6)
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
		if self.open and self.id then
			GameTooltip_AddInstructionLine(GameTooltip, ns.Pinned({ self.id }) and L.SHIFT_REMOVE or L.SHIFT_ADD)
		end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", ns.Overview.RowLeave)
	row:SetScript("OnMouseUp", function(self, mouseButton)
		if mouseButton == "LeftButton" and IsShiftKeyDown() and self.open and self.id then
			ns.TogglePinned({ self.id })
			GameTooltip_Hide()
		end
	end)
	return row
end

---@param parent Frame
function Search.Build(parent)
	for index = 1, SEARCH_ROWS do
		results[index] = CreateResult(parent)
	end
end

---@param text string
---@return string?
function Search.Query(text)
	local query = strtrim(text)
	-- Characters, not bytes: a character is one byte that doesn't continue a UTF-8 sequence.
	local _, characters = query:gsub("[^\128-\191]", "")
	-- Not before completion data loads: every chain quest would read as locked.
	return characters >= SEARCH_MIN and ns.State.Ready() and query or nil
end

-- The client's title, asked for once when it has none cached; the search redraws as titles arrive (Attach).
---@type table<integer, boolean>
local requested = {}
---@param questID integer
---@return boolean
function Search.Requested(questID)
	return requested[questID] == true
end

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

-- One result from `top` down. A quest the player can take now is a plain row, starred once added to the route; a locked
-- one gets the lock and its lines, unmet first. No ring and no Go: the search explains, and adds with a shift-click.
---@param row AGFSearchRow
---@param id integer
---@param top number
---@return number top below it
local function RefreshResult(row, id, top)
	local state, data = ns.State, ns.Data
	local names = {
		title = QuestTitle,
		race = state.RaceName,
		class = state.ClassName,
		skill = state.SkillName,
		faction = state.FactionName,
		standing = state.StandingName,
	}
	local player = state.Player()
	local why = ns.Model.Why(data, player, state.Completed(), state.Log(), id, names)
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
	row.why, row.id = shown, id
	row.open = shown[1] == nil and not ns.Model.Hard(data.quests[id], player)
	row.Star:SetShown(row.open and ns.Pinned({ id }))
	local quest = data.quests[id]
	local map = quest.zone or (quest.start and quest.start.map)
	row.Title:SetText(QuestTitle(id) or quest.title)
	row.Zone:SetText(map and state.ZoneName(map, data) or "")
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
function Search.Layout(query)
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
