---@type string, AGFNamespace
local _, ns = ...

local PIN_TEMPLATE = "AdventureGuideForeverDungeonPinTemplate"
local provider = CreateFromMixins(MapCanvasDataProviderMixin) --[[@as AGFMapProvider]]
local host, view, button
local enteredWorld, variablesLoaded = false, false
local shownInstance, pinnedInstance, pinnedMap

local function hide()
	if host then
		host:Hide()
		button:Hide()
	end
	shownInstance = nil
end

-- The instance the player stands in, while the map shows the zone it is in: the interior that opens by itself.
---@return integer?
local function InsideInstance()
	local _, instanceType, _, _, _, _, _, instance = GetInstanceInfo()
	local current = C_Map.GetBestMapForUnit("player")
	if instanceType == "party" and current and WorldMapFrame:GetMapID() == current then
		return instance
	end
end

local function refresh()
	if not enteredWorld or not variablesLoaded or not WorldMapFrame:IsShown() then
		return
	end
	-- The overlay owns its frames; never create UI while the native map is locked.
	if InCombatLockdown() then
		hide()
		return
	end
	local instance = InsideInstance()
	if not instance and pinnedInstance and WorldMapFrame:GetMapID() == pinnedMap then
		instance = pinnedInstance
	elseif not instance then
		pinnedInstance, pinnedMap = nil, nil
	end
	if not instance then
		hide()
		return
	end
	if shownInstance == instance then
		return
	end
	local maps = ns.Window.DungeonMaps(instance)
	if #maps == 0 then
		hide()
		return
	end
	if not host then
		local canvas = WorldMapFrame.ScrollContainer
		host = CreateFrame("Frame", "AdventureGuideForeverWorldDungeonMap", canvas)
		host:SetAllPoints(canvas)
		host:SetFrameLevel(canvas:GetFrameLevel() + 100)
		host:EnableMouse(true)
		local background = host:CreateTexture(nil, "BACKGROUND")
		background:SetAllPoints()
		background:SetColorTexture(0.04, 0.035, 0.025, 1)
		view = ns.Window.CreateDungeonMapView(host)
		view.back:SetText(ns.L.DUNGEON_MAP_WORLD_BACK)
		button = CreateFrame("Button", nil, canvas, "UIPanelButtonTemplate")
		button:SetSize(118, 24)
		button:SetPoint("BOTTOMLEFT", 12, 12)
		button:SetFrameLevel(host:GetFrameLevel() + 1)
		button:SetText(ns.L.DUNGEON_MAPS_TAB)
		button:SetScript("OnClick", function()
			if not InCombatLockdown() then
				host:Show()
				view:Show()
			end
		end)
		view.panel:HookScript("OnHide", function()
			host:Hide()
			pinnedInstance, pinnedMap = nil, nil
		end)
	end
	shownInstance = instance
	view:SetInstance(instance)
	button:Show()
	host:Show()
	view:Show()
end

-- A click on an instance's entrance pin: the interior opens on the map until Back to map, even from outside.
---@param instance integer
local function Open(instance)
	if InCombatLockdown() then
		return
	end
	local point = ns.Dungeons.Entrance(instance)
	pinnedInstance, pinnedMap = instance, point and point.map or WorldMapFrame:GetMapID()
	refresh()
end

---@class AGFDungeonPinFrame : AGFMapPinMixin
---@field Icon Texture
---@field Glow Texture
---@field instance integer
AdventureGuideForeverDungeonPinMixin = CreateFromMixins(MapCanvasPinMixin)

-- The pin sits on the instance's own entrance, on the world map, for every dungeon the guide offers: the interior map
-- of an instance the player can walk into, opened without going there first.
---@param instance integer
---@param x number
---@param y number
function AdventureGuideForeverDungeonPinMixin:OnAcquired(instance, x, y)
	self:UseFrameLevelType("PIN_FRAME_LEVEL_AREA_POI")
	self.instance = instance
	self:SetPosition(x, y)
	self:SetScalingLimits(1, 1.0, 1.2)
	self:ApplyCurrentScale()
	-- Closing the map hides the pin without an OnMouseLeave.
	self:SetScript("OnHide", self.OnMouseLeave)
end

function AdventureGuideForeverDungeonPinMixin:OnMouseEnter()
	self.Glow:Show()
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
	local instance = self.instance
	local name = ns.State.InstanceName(instance) or (ns.Data.instances[instance] and ns.Data.instances[instance].name)
	GameTooltip_SetTitle(GameTooltip, name)
	GameTooltip_AddInstructionLine(GameTooltip, ns.L.DUNGEON_MAP_OPEN:format(name))
	GameTooltip:Show()
end

function AdventureGuideForeverDungeonPinMixin:OnMouseLeave()
	self.Glow:Hide()
	if GameTooltip:GetOwner() == self then
		GameTooltip:Hide()
	end
end

function AdventureGuideForeverDungeonPinMixin:OnClick(clicked)
	if clicked == "LeftButton" and self.instance then
		Open(self.instance)
	end
end

function provider:RemoveAllData()
	self:GetMap():RemoveAllPinsByTemplate(PIN_TEMPLATE)
end

function provider:RefreshAllData()
	local map = self:GetMap()
	map:RemoveAllPinsByTemplate(PIN_TEMPLATE)
	refresh()
	-- The interior covers the canvas, and it draws its own pins: none of these belong over or under it.
	if shownInstance or InCombatLockdown() or not enteredWorld or not variablesLoaded then
		return
	end
	local mapID = map:GetMapID()
	if not mapID then
		return
	end
	local inside = InsideInstance()
	for _, journey in ipairs(ns.Route().journeys) do
		local instance = journey.kind == "dungeon" and journey.instance
		if instance and instance ~= inside then
			local point = ns.Dungeons.Entrance(instance)
			if point and point.map == mapID and #ns.Window.DungeonMaps(instance) > 0 then
				map:AcquirePin(PIN_TEMPLATE, instance, point.x, point.y)
			end
		end
	end
end

local events = CreateFrame("Frame")
for _, event in ipairs({
	"PLAYER_ENTERING_WORLD",
	"VARIABLES_LOADED",
	"ZONE_CHANGED_NEW_AREA",
	"PLAYER_REGEN_DISABLED",
	"PLAYER_REGEN_ENABLED",
}) do
	events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event)
	enteredWorld = enteredWorld or event == "PLAYER_ENTERING_WORLD"
	variablesLoaded = variablesLoaded or event == "VARIABLES_LOADED"
	C_Timer.After(0, refresh)
end)
EventUtil.ContinueOnAddOnLoaded("Blizzard_WorldMap", function()
	WorldMapFrame:AddDataProvider(provider)
	WorldMapFrame:HookScript("OnHide", function()
		shownInstance = nil
		pinnedInstance, pinnedMap = nil, nil
	end)
end)
