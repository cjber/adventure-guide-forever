---@type string, AGFNamespace
local _, ns = ...

local provider = CreateFromMixins(MapCanvasDataProviderMixin) --[[@as AGFMapProvider]]
local host, view, button
local enteredWorld, variablesLoaded = false, false
local shownInstance

local function hide()
	if host then
		host:Hide()
		button:Hide()
	end
	shownInstance = nil
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
	local _, instanceType, _, _, _, _, _, instance = GetInstanceInfo()
	local current = C_Map.GetBestMapForUnit("player")
	local available = instanceType == "party" and current and WorldMapFrame:GetMapID() == current
	if not available then
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
		end)
	end
	shownInstance = instance
	view:SetMaps(maps)
	button:Show()
	host:Show()
	view:Show()
end

function provider:RefreshAllData()
	refresh()
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
	end)
end)
