---@type string, AGFNamespace
local _, ns = ...
local L, Art = ns.L, ns.Art

--[[ The Adventure Guide window (docs/design.md §2.19): the guide on its own, away from the world map, built as the
     Encounter Journal is (Blizzard_EncounterJournal.xml:1333): PortraitFrameTemplate 800x496, an InsetFrameTemplate
     from (4, -60) to (-4, 5) with the tier art at (3, -1), and PanelTabButtonTemplate tabs from BOTTOMLEFT (11, 2).
     The Today strip (the asides) runs across the top of the inset on every tab; each tab draws below it. A tab is one
     Window.AddTab call from its own file. The window reads the same route, asides and choices as the map panel and
     redraws only while it shows. ]]

local Window = ns.Window

local NAME = "AdventureGuideForeverWindow"
local WIDTH, HEIGHT = Window.WIDTH, Window.HEIGHT
local INSET_TOP, INSET_BOTTOM = Window.INSET_TOP, Window.INSET_BOTTOM
-- The key the window offers once, when nothing else has it.
local KEY, BINDING = "SHIFT-J", "ADVENTUREGUIDEFOREVER_WINDOW"
-- SkillUp's answers, item data and the character's PvP rank progress.
local EVENTS = {
	"SKILL_LINES_CHANGED",
	"BAG_UPDATE_DELAYED",
	"NEW_RECIPE_LEARNED",
	"TRADE_SKILL_LIST_UPDATE",
	"ITEM_DATA_LOAD_RESULT",
	"PLAYER_PVP_RANK_CHANGED",
	"MAJOR_FACTION_RENOWN_LEVEL_CHANGED",
	"UPDATE_FACTION",
}

---@class AGFWindowTab
---@field key string
---@field label string
---@field Build fun(content: Frame)
---@field Refresh fun(content: Frame)
---@field Muted? fun(): string? the line the tab's tooltip gives while its label is greyed

---@type AGFWindowTab[]
local tabs = {}
---@type AGFWindowFrame?
local frame
---@type Frame[]
local contents = {}
local selected = 1

---@param tab AGFWindowTab
function Window.AddTab(tab)
	tabs[#tabs + 1] = tab
end

---@return AGFWindowTab[]
function Window.Tabs()
	return tabs
end

--[[ The frame ]]

---@class AGFWindowFrame : Frame
---@field PortraitContainer Frame
---@field CloseButton Button
---@field Tabs Button[]
---@field SetTitle fun(self: AGFWindowFrame, title: string)
---@field GetPortrait fun(self: AGFWindowFrame): Texture
---@field Inset Frame
---@field Subtitle FontString
---@field selectedTab? integer
---@field numTabs? integer

local Refresh

local function SavePosition()
	---@cast frame -?
	local point, _, relativePoint, x, y = frame:GetPoint(1)
	ns.WindowDB().position = { point = point, relativePoint = relativePoint, x = x, y = y }
end

local function RestorePosition()
	---@cast frame -?
	local position = ns.WindowDB().position
	frame:ClearAllPoints()
	if
		type(position) == "table"
		and type(position.point) == "string"
		and type(position.relativePoint) == "string"
		and type(position.x) == "number"
		and type(position.y) == "number"
	then
		frame:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	end
end

local floating
local pendingOpen = false
local modeEvents = CreateFrame("Frame")

local function ShowWindow()
	if floating then
		frame:Show()
	else
		ShowUIPanel(frame)
	end
end

local function HideWindow()
	if floating then
		frame:Hide()
	else
		HideUIPanel(frame)
	end
end

function Window.ApplyMode()
	if not frame then
		return
	end
	if InCombatLockdown() then
		modeEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	local nextFloating = ns.Setting("floatWindow")
	if floating == nextFloating then
		return
	end
	local shown = frame:IsShown()
	if shown then
		HideWindow()
	end
	floating = nextFloating
	-- Attributes belong to this addon frame; never register in Blizzard's shared UIPanelWindows table.
	frame:SetAttribute("UIPanelLayout-defined", true)
	frame:SetAttribute("UIPanelLayout-area", not floating and "doublewide" or nil)
	frame:SetAttribute("UIPanelLayout-pushable", 0)
	frame:SetAttribute("UIPanelLayout-whileDead", true)
	frame:SetMovable(floating)
	if floating then
		RestorePosition()
	else
		frame:ClearAllPoints()
		frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 16, -116)
	end
	if shown then
		ShowWindow()
	end
	EventRegistry:TriggerEvent("AdventureGuideForever.WindowLayoutChanged", frame)
end

modeEvents:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	Window.ApplyMode()
	if pendingOpen then
		pendingOpen = false
		ns.OpenWindow()
	end
end)

-- The tab's label grey, with its tooltip saying why, while the tab has nothing of its own to show; still clickable,
-- so its page can say the same.
---@param button Button
---@param tab AGFWindowTab
local function RefreshTabLabel(button, tab)
	local muted = tab.Muted and tab.Muted()
	button:SetNormalFontObject(muted and "GameFontDisableSmall" or "GameFontNormalSmall")
end

---@param index integer
function Window.Select(index)
	if not (frame and tabs[index]) then
		return
	end
	selected = index
	ns.WindowDB().tab = tabs[index].key
	PanelTemplates_SetTab(frame, index)
	for position, content in ipairs(contents) do
		content:SetShown(position == index)
	end
	Refresh()
end

local function Build()
	frame = CreateFrame("Frame", NAME, UIParent, "PortraitFrameTemplate") --[[@as AGFWindowFrame]]
	frame:SetSize(WIDTH, HEIGHT)
	frame:SetTitle(ns.TITLE)
	frame:SetToplevel(true)
	frame:SetClampedToScreen(true)
	frame:SetDontSavePosition(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", function(self)
		if floating and not InCombatLockdown() then
			self:StartMoving()
		end
	end)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		if floating then
			SavePosition()
		end
	end)
	frame:Hide()
	Window.ApplyMode()
	frame.CloseButton:SetScript("OnClick", HideWindow)
	-- Escape closes it, as it does the game's own windows.
	table.insert(UISpecialFrames, NAME)
	-- The compass the panel's header and tab wear, on a dark disc in the portrait's ring.
	frame:GetPortrait():SetColorTexture(0.06, 0.05, 0.04, 1)
	local compass = frame.PortraitContainer:CreateTexture(nil, "OVERLAY", nil, 1)
	ns.Art.Fit(compass, "islands-queue-prop-compass", 54, 54)
	compass:SetPoint("CENTER", frame:GetPortrait(), "CENTER", 0, 2)
	frame.Subtitle = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	frame.Subtitle:SetPoint("TOPLEFT", 64, -34)
	frame.Subtitle:SetJustifyH("LEFT")
	local inset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate") --[[@as Frame]]
	inset:SetPoint("TOPLEFT", 4, -INSET_TOP)
	inset:SetPoint("BOTTOMRIGHT", -4, INSET_BOTTOM)
	frame.Inset = inset
	local art = inset:CreateTexture(nil, "BACKGROUND", nil, 1)
	art:SetPoint("TOPLEFT", 3, -1)
	art:SetPoint("BOTTOMRIGHT", -3, 1)
	Art.CoverFrame(inset, art, "UI-EJ-Classic", 6, 2)
	for index, tab in ipairs(tabs) do
		local content = CreateFrame("Frame", nil, frame)
		content:SetAllPoints(inset)
		content:Hide()
		contents[index] = content
		tab.Build(content)
		local button = CreateFrame("Button", NAME .. "Tab" .. index, frame, "PanelTabButtonTemplate")
		button:SetID(index)
		button:SetText(tab.label)
		button:SetScript("OnClick", function(self)
			PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
			Window.Select(self:GetID())
		end)
		button:HookScript("OnEnter", function(self)
			local line = tab.Muted and tab.Muted()
			if line then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip_SetTitle(GameTooltip, tab.label)
				GameTooltip_AddNormalLine(GameTooltip, line)
				GameTooltip:Show()
			end
		end)
		button:HookScript("OnLeave", GameTooltip_Hide)
		if index == 1 then
			button:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 11, 2)
		end
	end
	PanelTemplates_SetNumTabs(frame, #tabs)
	-- What SkillUp's answers follow (its own cache drops on the same events), listened to only while the window shows,
	-- and read a frame later so SkillUp has dropped its cache first; a burst of them redraws once.
	local queued = false
	frame:SetScript("OnEvent", function()
		if not queued then
			queued = true
			C_Timer.After(0, function()
				queued = false
				Refresh()
			end)
		end
	end)
	frame:SetScript("OnShow", function(self)
		for _, event in ipairs(EVENTS) do
			self:RegisterEvent(event)
		end
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
		ns.Moments.Opened()
		-- Legacy Forever is listened to only while the window shows (Providers.lua).
		ns.Providers.SetShown(true)
		Refresh()
	end)
	frame:SetScript("OnHide", function(self)
		ns.Overview.HideTooltipWithin(self)
		for _, event in ipairs(EVENTS) do
			self:UnregisterEvent(event)
		end
		ns.Providers.SetShown(false)
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
		if not (ns.PanelShown and ns.PanelShown()) then
			ns.Moments.Closed()
		end
	end)
	-- The same listeners as the panel's; each returns at once while the window is hidden.
	ns.OnRouteChange(Refresh)
	ns.Asides.OnChange(Refresh)
	ns.Moments.OnChange(Refresh)
	ns.Guidance.OnChange(Refresh)
	ns.Providers.OnChange(Refresh)
	local saved = ns.WindowDB().tab
	for index, tab in ipairs(tabs) do
		if tab.key == saved or saved == nil and tab.key == "next" then
			selected = index
		end
	end
	PanelTemplates_SetTab(frame, selected)
	contents[selected]:Show()
	EventRegistry:TriggerEvent("AdventureGuideForever.WindowCreated", frame)
end

function Refresh()
	if not (frame and frame:IsShown()) then
		return
	end
	local player = ns.State.Player()
	local zone = player.map and ns.State.ZoneName(player.map)
	frame.Subtitle:SetText(zone and L.OVERVIEW_WHERE:format(zone, player.level) or "")
	Window.RefreshToday(frame.Inset, tabs[selected].key ~= "next")
	for index, tab in ipairs(tabs) do
		RefreshTabLabel(frame.Tabs[index], tab)
	end
	tabs[selected].Refresh(contents[selected])
end
Window.Refresh = Refresh

---@return boolean
function ns.WindowShown()
	return frame ~= nil and frame:IsShown()
end

function ns.OpenWindow()
	if InCombatLockdown() then
		pendingOpen = true
		modeEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	if not frame then
		Build()
	end
	Window.ApplyMode()
	ShowWindow()
end

function ns.ToggleWindow()
	if frame and frame:IsShown() then
		HideWindow()
	else
		ns.OpenWindow()
	end
end

EventRegistry:RegisterCallback("AdventureGuideForever.EnsureWindow", function()
	if not frame and not InCombatLockdown() then
		Build()
	end
end, Window)

--[[ The key binding (Bindings.xml) ]]

BINDING_HEADER_ADVENTUREGUIDEFOREVER = ns.TITLE
BINDING_NAME_ADVENTUREGUIDEFOREVER_WINDOW = L.BINDING_TOGGLE_WINDOW

function AdventureGuideForever_ToggleWindow()
	ns.ToggleWindow()
end

-- Shift-J, once per account and only while no other action has it and the window has no key of its own: never over a
-- binding the player made. A login in combat waits for its end, since bindings can't change during it.
local offer = CreateFrame("Frame")
function Window.OfferKey()
	local saved = ns.WindowDB()
	if saved.keyOffered then
		return
	end
	if InCombatLockdown() then
		offer:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	offer:UnregisterEvent("PLAYER_REGEN_ENABLED")
	saved.keyOffered = true
	if GetBindingAction(KEY) ~= "" or GetBindingKey(BINDING) then
		return
	end
	if SetBinding(KEY, BINDING) then
		SaveBindings(GetCurrentBindingSet())
		ns.Print(L.BINDING_SET)
	end
end
offer:SetScript("OnEvent", Window.OfferKey)
EventUtil.ContinueAfterAllEvents(Window.OfferKey, "VARIABLES_LOADED", "PLAYER_LOGIN")
