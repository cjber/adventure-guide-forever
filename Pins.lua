---@type string, AGFNamespace
local _, ns = ...

local PIN_TEMPLATE = "AdventureGuideForeverPinTemplate"

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
---@param step AGFStep
---@param index number
local function AddPinTooltip(tooltip, step, index)
	GameTooltip_SetTitle(tooltip, ("%d. %s"):format(index, step.title))
	GameTooltip_AddNormalLine(tooltip, step.detail)
	if step.pinned then
		GameTooltip_AddInstructionLine(tooltip, "Pinned")
	end
end

local provider = CreateFromMixins(MapCanvasDataProviderMixin) --[[@as AGFMapProvider]]

function provider:RemoveAllData()
	self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
	pinsByKey = {}
end

-- Only the steps that sit on the map currently shown: a continent view gets no pins, matching
-- how the route already only points at zone-level maps.
function provider:RefreshAllData()
	self:RemoveAllData()
	if not Active() then
		return
	end
	local mapID = self:GetMap():GetMapID()
	if not mapID then
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
---@field Number FontString
---@field step? AGFStep
---@field index? number
AdventureGuideForeverPinMixin = CreateFromMixins(MapCanvasPinMixin)

---@param step AGFStep
---@param index number
function AdventureGuideForeverPinMixin:OnAcquired(step, index)
	self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
	self.step, self.index = step, index
	self.Number:SetText(tostring(index))
	self:SetPosition(step.x, step.y)
	self:SetScalingLimits(1, 1.0, 1.2)
	self:ApplyCurrentScale()
end

function AdventureGuideForeverPinMixin:OnMouseEnter()
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	if self.step and self.index then
		AddPinTooltip(GameTooltip, self.step, self.index)
	end
	GameTooltip:Show()
end

function AdventureGuideForeverPinMixin:OnMouseLeave()
	GameTooltip:Hide()
end

function AdventureGuideForeverPinMixin:OnClick(button)
	if button == "LeftButton" and self.step then
		ns.Integrations.Navigate(self.step)
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
