---@type string, AGFNamespace
local _, ns = ...

local PIN_TEMPLATE = "AdventureGuideForeverPinTemplate"
local GIVER_TEMPLATE = "AdventureGuideForeverGiverPinTemplate"
-- Shortest Path's stop badge (Route.lua): 16px, hung 4 units past the ring's lower right.
local BADGE_SIZE, BADGE_OFFSET = 16, 4

---@class AGFPinsModule
local Pins = {}
ns.Pins = Pins

---@type table<string, AGFPinFrame>
local pinsByKey = {}

-- One switch over every mark AGF draws (design §2.6): nothing unless showMapPins is on, and nothing for a wanderer
-- (roadmap #24), who is told where and never shown.
-- While the guide is open the rings preview the route it shows whatever the switch says (F3): the chosen journey's,
-- else the first card's, which the guide draws on its own (docs/design.md §2.2). Either way they step aside while
-- Shortest Path guides, since it numbers its stops itself.
---@return boolean
local function RingsShown()
	local preview = ns.PanelShown ~= nil and ns.PanelShown()
	return (preview or ns.Setting("showMapPins")) and not ns.Integrations.Guiding() and not ns.Setting("wanderer")
end

-- Givers need both switches, and stay while Shortest Path guides: it draws no givers of its own.
---@return boolean
local function GiversShown()
	return ns.Setting("showMapPins") and ns.Setting("showQuestGivers") and not ns.Setting("wanderer")
end

---@param tooltip GameTooltip
local function AddClickLine(tooltip)
	local name = ns.Integrations.Provider()
	GameTooltip_AddInstructionLine(tooltip, name and ns.L.CLICK_TRAVEL:format(name) or ns.L.CLICK_WAYPOINT)
end

-- The map's own marks, inline: a hand-in's "?", a pickup's "!", and the quest log's group tag.
local HAND_IN_ICON = "|A:questturnin:14:14|a "
local PICK_UP_ICON = "|A:questnormal:14:14|a "
local GROUP_ICON = " |A:questlog-questtypeicon-group:12:12|a"
-- A town's quests listed in its tooltip; the rest are counted.
local HUB_QUEST_LINES = 8

-- A quest's line, coloured as the quest log colours its level: the map's mark, the title (with its level when
-- `levelled`) and the group tag. A quest the data lacks (Forever's own) is the player's level, titled by the client.
---@param tooltip GameTooltip
---@param id integer
---@param mark string
---@param levelled boolean
local function QuestLine(tooltip, id, mark, levelled)
	local quest = ns.Data.quests[id]
	local level = (not quest or quest.level == -1) and UnitLevel("player") or quest.level
	local title = ns.State.QuestTitle(id) or (quest and quest.title) or ""
	local color = GetQuestDifficultyColor(level)
	GameTooltip_AddColoredLine(
		tooltip,
		mark
			.. (levelled and ns.L.QUEST_LEVEL:format(level, title) or title)
			.. ((quest and (quest.elite or quest.dungeon or quest.raid)) and GROUP_ICON or ""),
		CreateColor(color.r, color.g, color.b)
	)
end

-- One line per quest at a town, under the NPC it is handed to or taken from, in the town's order (hand-ins first, then
-- by level, docs/plan.md §7.3).
---@param tooltip GameTooltip
---@param step AGFStep
local function TownQuests(tooltip, step)
	local handin, shown = {}, 0
	for _, id in ipairs(step.handins or {}) do
		handin[id] = true
	end
	for _, giver in ipairs(step.givers or {}) do
		local named = false
		for _, id in ipairs(step.quests) do
			local spot, quest = step.spots and step.spots[id], ns.Data.quests[id]
			if quest and spot and spot.name == giver then
				if shown == HUB_QUEST_LINES then
					GameTooltip_AddHighlightLine(tooltip, ns.L.HUB_MORE_QUESTS:format(#step.quests - shown))
					return
				end
				if not named then
					GameTooltip_AddNormalLine(tooltip, giver)
					named = true
				end
				shown = shown + 1
				QuestLine(tooltip, id, handin[id] and HAND_IN_ICON or PICK_UP_ICON, not handin[id])
			end
		end
	end
end

-- An area's quests, each with its open objectives done there as the quest log words them: the client's words, else
-- its count so far. An objective the client's count can't be matched to shows under its quest with no line.
---@param tooltip GameTooltip
---@param step AGFStep
local function AreaObjectives(tooltip, step)
	local last
	for _, objective in ipairs(step.objectives or {}) do
		if objective.id ~= last then
			QuestLine(tooltip, objective.id, "", false)
			last = objective.id
		end
		local line = objective.text and ns.L.OBJECTIVE_LINE:format(objective.text)
			or (objective.have and objective.need and ns.L.OBJECTIVE_COUNT:format(objective.have, objective.need))
		if line then
			GameTooltip_AddHighlightLine(tooltip, line)
		end
	end
end

-- A step's lines (docs/design.md §2.9), shared by its ring and its row in the guide: the title numbered as the route
-- numbers it, the chapter, the travel line when there is one, why it is on the route, a town's quests by NPC, and an
-- area's objectives.
---@param tooltip GameTooltip
---@param step AGFStep
---@param index number
---@param travel? string
function Pins.StepTooltip(tooltip, step, index, travel)
	GameTooltip_SetTitle(tooltip, ns.L.STEP_NUMBERED:format(index, step.title))
	if step.chapter then
		GameTooltip_AddNormalLine(tooltip, step.chapter)
	end
	if travel then
		GameTooltip_AddHighlightLine(tooltip, travel)
	end
	GameTooltip_AddHighlightLine(tooltip, step.reason)
	if step.kind == "town" then
		TownQuests(tooltip, step)
	end
	AreaObjectives(tooltip, step)
end

local provider = CreateFromMixins(MapCanvasDataProviderMixin) --[[@as AGFMapProvider]]

function provider:RemoveAllData()
	self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
	self:GetMap():RemoveAllPinsByTemplate(GIVER_TEMPLATE)
	pinsByKey = {}
end

-- Givers first, so the route's numbered pins draw above them. A giver whose quest is a stop drawn already is left
-- to that stop: our ring for the chosen journey, or Shortest Path's numbered stop for what the last Go handed it.
---@param map AGFWorldMapFrame
---@param mapID integer
local function AddGivers(map, mapID)
	if not GiversShown() or not ns.State.Ready() then
		return
	end
	local routed = {}
	for _, step in ipairs(RingsShown() and ns.Route().steps or ns.Integrations.Guided()) do
		for _, id in ipairs(step.quests) do
			routed[id] = true
		end
	end
	local givers = ns.Model.Givers(ns.Data, ns.State.Player(), ns.State.Completed(), ns.State.Log(), mapID)
	for _, giver in ipairs(givers) do
		local covered = false
		for _, id in ipairs(giver.quests) do
			covered = covered or routed[id] == true
		end
		if not covered then
			map:AcquirePin(GIVER_TEMPLATE, giver)
		end
	end
end

-- Only the steps that sit on the map currently shown: a continent view gets no pins, matching
-- how the route already only points at zone-level maps.
function provider:RefreshAllData()
	self:RemoveAllData()
	local mapID = self:GetMap():GetMapID()
	if not mapID then
		return
	end
	AddGivers(self:GetMap(), mapID)
	if not RingsShown() then
		return
	end
	-- A numbered pin at each step's point, but none for the area the player stands in: they are there (§4.2). An area
	-- draws nothing more: the game's own objective mark and its hover shape show where its objectives are.
	-- A place the route comes back to (a town's second lap) keeps one ring, numbered for its first visit, with a "+N"
	-- for the rest and every visit in its tooltip (docs/design.md §2.9).
	---@type table<string, AGFPinVisit[]>
	local places, order = {}, {}
	for index, step in ipairs(ns.Route().steps) do
		if step.map == mapID and not step.here then
			local place = step.key
			for _, other in ipairs(order) do
				local first = places[other][1].step
				if first.key == step.key or (first.x == step.x and first.y == step.y) then
					place = other
					break
				end
			end
			if not places[place] then
				places[place] = {}
				order[#order + 1] = place
			end
			table.insert(places[place], { step = step, index = index })
		end
	end
	for _, place in ipairs(order) do
		local visits = places[place]
		---@type AGFPinFrame
		local pin = self:GetMap():AcquirePin(PIN_TEMPLATE, visits[1].step, visits[1].index, visits)
		for _, visit in ipairs(visits) do
			pinsByKey[visit.step.key] = pin
		end
	end
end

---@class AGFPinVisit
---@field step AGFStep
---@field index number

-- The step's kind (a pickup, a hand-in, an objective...) as a small badge on the ring's lower right, as Shortest
-- Path badges its own stops; made on first use.
---@param pin AGFPinFrame
---@return Texture
local function Badge(pin)
	if not pin.Badge then
		pin.Badge = pin:CreateTexture(nil, "OVERLAY", nil, 1)
		pin.Badge:SetSize(BADGE_SIZE, BADGE_SIZE)
		pin.Badge:SetPoint("BOTTOMRIGHT", BADGE_OFFSET, -BADGE_OFFSET)
		-- The outlined numerals the stock stack counts use, which read over light map art as gold text does not.
		pin.More = pin:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
		pin.More:SetPoint("BOTTOMLEFT", pin, "TOPRIGHT", -7, -7)
	end
	return pin.Badge
end

---@class AGFPinFrame : AGFMapPinMixin
---@field Icon Texture
---@field Number Texture
---@field Glow Texture
---@field Badge? Texture
---@field More? FontString
---@field step? AGFStep
---@field index? number
---@field visits? AGFPinVisit[]
AdventureGuideForeverPinMixin = CreateFromMixins(MapCanvasPinMixin)

---@param step AGFStep
---@param index number
---@param visits? AGFPinVisit[]
function AdventureGuideForeverPinMixin:OnAcquired(step, index, visits)
	-- The stock user waypoint's level (WaypointLocationDataProvider), above every quest "!" and "?", the super-tracked
	-- one's included (Blizzard_WorldMap.lua:291-311); givers stay at AREA_POI, under both.
	self:UseFrameLevelType("PIN_FRAME_LEVEL_WAYPOINT_LOCATION")
	self.step, self.index, self.visits = step, index, visits
	self.Number:SetAtlas("services-number-" .. index)
	local badge = Badge(self)
	ns.Overview.SetVerbIcon(badge, step)
	local more = visits and #visits > 1 and #visits - 1 or 0
	self.More:SetShown(more > 0)
	if more > 0 then
		self.More:SetText(ns.L.STOP_MORE:format(more))
	end
	-- The badge hangs past the ring; the pin takes the clicks it gets.
	self:SetHitRectInsets(0, -BADGE_OFFSET, 0, -BADGE_OFFSET)
	self:SetPosition(step.x, step.y)
	self:SetScalingLimits(1, 1.0, 1.2)
	self:ApplyCurrentScale()
	-- Closing the map hides the pin without an OnMouseLeave.
	self:SetScript("OnHide", self.OnMouseLeave)
end

function AdventureGuideForeverPinMixin:OnMouseEnter()
	self.Glow:Show()
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if self.step and self.index then
		Pins.StepTooltip(GameTooltip, self.step, self.index, ns.Integrations.Travel(self.step))
		if self.visits and #self.visits > 1 then
			for _, visit in ipairs(self.visits) do
				GameTooltip_AddNormalLine(GameTooltip, ns.L.STOP_VISIT:format(visit.index, visit.step.title))
			end
		end
		AddClickLine(GameTooltip)
	end
	GameTooltip:Show()
end

function AdventureGuideForeverPinMixin:OnMouseLeave()
	self.Glow:Hide()
	if GameTooltip:GetOwner() == self then
		GameTooltip:Hide()
	end
end

function AdventureGuideForeverPinMixin:OnClick(button)
	if button == "LeftButton" and self.step then
		ns.StartRoute(self.step)
	end
end

---@class AGFGiverPinFrame : AGFMapPinMixin
---@field Icon Texture
---@field Glow Texture
---@field giver? AGFGiver
AdventureGuideForeverGiverPinMixin = CreateFromMixins(MapCanvasPinMixin)

---@param giver AGFGiver
function AdventureGuideForeverGiverPinMixin:OnAcquired(giver)
	self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
	self.giver = giver
	self:SetPosition(giver.x, giver.y)
	self:SetScalingLimits(1, 1.0, 1.2)
	self:ApplyCurrentScale()
	-- Closing the map hides the pin without an OnMouseLeave.
	self:SetScript("OnHide", self.OnMouseLeave)
end

-- The client's own title wins when the quest is cached; the level is the bundled one.
function AdventureGuideForeverGiverPinMixin:OnMouseEnter()
	local giver = self.giver
	if not giver then
		return
	end
	self.Glow:Show()
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	GameTooltip_SetTitle(GameTooltip, giver.title)
	for _, id in ipairs(giver.quests) do
		local quest = ns.Data.quests[id]
		local level = quest.level == -1 and UnitLevel("player") or quest.level
		local title = C_QuestLog.GetTitleForQuestID(id) or quest.title
		GameTooltip_AddNormalLine(GameTooltip, ns.L.QUEST_LEVEL:format(level, title))
	end
	AddClickLine(GameTooltip)
	if #giver.adds > 0 then
		GameTooltip_AddInstructionLine(GameTooltip, ns.Pinned(giver.adds) and ns.L.SHIFT_REMOVE or ns.L.SHIFT_ADD)
	end
	GameTooltip:Show()
end

function AdventureGuideForeverGiverPinMixin:OnMouseLeave()
	self.Glow:Hide()
	if GameTooltip:GetOwner() == self then
		GameTooltip:Hide()
	end
end

-- A shift-click adds the giver's quests to the route (docs/design.md §2.18), or takes them off: those not orange or
-- red, which no route takes.
function AdventureGuideForeverGiverPinMixin:OnClick(button)
	if button == "LeftButton" and self.giver and IsShiftKeyDown() then
		if #self.giver.adds > 0 then
			ns.TogglePinned(self.giver.adds)
		end
		GameTooltip:Hide()
	elseif button == "LeftButton" and self.giver then
		ns.Integrations.Navigate(self.giver)
	end
end

-- A short flash so a step clicked in the panel is easy to find on the map. A no-op when the
-- step's pin isn't on the map currently shown (e.g. the click just switched maps and the new
-- pins haven't been laid out yet).
---@param key string
function Pins.Ping(key)
	local pin = pinsByKey[key]
	if pin then
		UIFrameFlash(pin.Icon, 0.2, 0.2, 1.2, true)
	end
end

function Pins.Refresh()
	if WorldMapFrame:IsShown() then
		provider:RefreshAllData()
	end
end

local function Attach()
	local map = WorldMapFrame
	map:AddDataProvider(provider)
	ns.OnRouteChange(Pins.Refresh)
	map:HookScript("OnShow", Pins.Refresh)
end

EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", Attach)
