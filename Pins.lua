---@type string, AGFNamespace
local _, ns = ...

local PIN_TEMPLATE = "AdventureGuideForeverPinTemplate"
local GIVER_TEMPLATE = "AdventureGuideForeverGiverPinTemplate"

---@class AGFPinsModule
local Pins = {}
ns.Pins = Pins

---@type table<string, AGFPinFrame>
local pinsByKey = {}

---@return boolean
local function Active()
	return ns.Setting("showMapPins") and not ns.Integrations.Guiding()
end

---@param tooltip GameTooltip
local function AddClickLine(tooltip)
	local name = ns.Integrations.Provider()
	GameTooltip_AddInstructionLine(
		tooltip,
		name and ("Click to travel with %s"):format(name) or "Click to set a waypoint"
	)
end

---@param tooltip GameTooltip
---@param step AGFStep
---@param index number
local function AddPinTooltip(tooltip, step, index)
	GameTooltip_SetTitle(tooltip, ("%d. %s"):format(index, step.title))
	GameTooltip_AddHighlightLine(tooltip, step.detail)
	local travel = ns.Integrations.Travel(step)
	if travel then
		GameTooltip_AddHighlightLine(tooltip, travel)
	end
	GameTooltip_AddNormalLine(tooltip, step.reason)
	if step.pinned then
		GameTooltip_AddNormalLine(tooltip, "Pinned")
	end
	AddClickLine(tooltip)
end

local provider = CreateFromMixins(MapCanvasDataProviderMixin) --[[@as AGFMapProvider]]

function provider:RemoveAllData()
	self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
	self:GetMap():RemoveAllPinsByTemplate(GIVER_TEMPLATE)
	pinsByKey = {}
end

-- Givers first, so the route's numbered pins draw above them. A giver whose quest is already a route
-- step is left to that step's pin (ours, or Shortest Path's numbered stop).
---@param map AGFWorldMapFrame
---@param mapID integer
local function AddGivers(map, mapID)
	if not ns.Setting("showQuestGivers") or not ns.State.Ready() then
		return
	end
	local routed = {}
	for _, step in ipairs(ns.Route().steps) do
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
	if not Active() then
		return
	end
	for index, step in ipairs(ns.Route().steps) do
		if step.map == mapID then
			---@type AGFPinFrame
			local pin = self:GetMap():AcquirePin(PIN_TEMPLATE, step, index)
			pinsByKey[step.key] = pin
		end
	end
end

---@class AGFPinFrame : AGFMapPinMixin
---@field Icon Texture
---@field Number Texture
---@field Glow Texture
---@field step? AGFStep
---@field index? number
AdventureGuideForeverPinMixin = CreateFromMixins(MapCanvasPinMixin)

---@param step AGFStep
---@param index number
function AdventureGuideForeverPinMixin:OnAcquired(step, index)
	self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
	self.step, self.index = step, index
	self.Number:SetAtlas("services-number-" .. index)
	self:SetPosition(step.x, step.y)
	self:SetScalingLimits(1, 1.0, 1.2)
	self:ApplyCurrentScale()
end

function AdventureGuideForeverPinMixin:OnMouseEnter()
	self.Glow:Show()
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if self.step and self.index then
		AddPinTooltip(GameTooltip, self.step, self.index)
	end
	GameTooltip:Show()
end

function AdventureGuideForeverPinMixin:OnMouseLeave()
	self.Glow:Hide()
	GameTooltip:Hide()
end

function AdventureGuideForeverPinMixin:OnClick(button)
	if button == "LeftButton" and self.step then
		ns.Integrations.Navigate(self.step)
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
end

-- The client's own title and level win when the quest is cached, as in the guide's rows.
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
		GameTooltip_AddNormalLine(GameTooltip, ("[%d] %s"):format(level, title))
	end
	AddClickLine(GameTooltip)
	GameTooltip:Show()
end

function AdventureGuideForeverGiverPinMixin:OnMouseLeave()
	self.Glow:Hide()
	GameTooltip:Hide()
end

function AdventureGuideForeverGiverPinMixin:OnClick(button)
	if button == "LeftButton" and self.giver then
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
