---@type string, AGFNamespace
local _, ns = ...
local L = ns.L

--[[ The Adventure Guide window (docs/design.md §2.19): the guide on its own, away from the world map, built as the
     Encounter Journal is (Blizzard_EncounterJournal.xml:1333): PortraitFrameTemplate 800x496, an InsetFrameTemplate
     from (4, -60) to (-4, 5) with the tier art at (3, -1), and PanelTabButtonTemplate tabs from BOTTOMLEFT (11, 2).
     The Today strip (the asides) runs across the top of the inset on every tab; each tab draws below it. A tab is one
     Window.AddTab call from its own file. The window reads the same route, asides and choices as the map panel and
     redraws only while it shows. ]]

---@class AGFWindow
local Window = {}
ns.Window = Window

local NAME = "AdventureGuideForeverWindow"
local WIDTH, HEIGHT = 800, 496
local INSET_TOP, INSET_BOTTOM = 60, 5
-- The tier art's dark right strip, where the Encounter Journal keeps its scroll bar, stays clear.
local RIGHT = 30
-- The Today strip: up to four asides across the art's top band, a ringed icon and its line.
local TODAY_MAX, TODAY_TOP, TODAY_LEFT, TODAY_RING = 4, 4, 18, 26
-- Where a tab's content starts in the inset, under the Today strip.
Window.TOP, Window.LEFT, Window.RIGHT = 50, 14, RIGHT
Window.INSET_WIDTH, Window.INSET_HEIGHT = WIDTH - 8, HEIGHT - INSET_TOP - INSET_BOTTOM
-- The key the window offers once, when nothing else has it.
local KEY, BINDING = "SHIFT-J", "ADVENTUREGUIDEFOREVER_WINDOW"
-- The Encounter Journal's dungeon button (UI-EJ-DungeonButton-Up, file 522972): pixels 1,439 to 175,535 of the 512 x
-- 1024 sheet, its rim 8 pixels wide, sliced into nine pieces so the rim keeps its width on any card.
local EJ_FILE, EJ_SHEET_W, EJ_SHEET_H = 522972, 512, 1024
local EJ_LEFT, EJ_TOP, EJ_RIGHT, EJ_BOTTOM, EJ_RIM = 1, 439, 175, 535, 8
-- The Suggested Content icon recipe: the icon cut to a circle on a dark disc inside the Adventure Guide's ring; an
-- atlas icon is inset so its own margin doesn't show.
local RING_SCALE, ATLAS_INSET = 1.4, 0.16
-- The events SkillUp Forever rebuilds its answers on, and an item's name or icon arriving.
local EVENTS = {
	"SKILL_LINES_CHANGED",
	"BAG_UPDATE_DELAYED",
	"NEW_RECIPE_LEARNED",
	"TRADE_SKILL_LIST_UPDATE",
	"ITEM_DATA_LOAD_RESULT",
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
---@type AGFTodayChip[]
local chips = {}
local selected = 1

---@param tab AGFWindowTab
function Window.AddTab(tab)
	tabs[#tabs + 1] = tab
end

---@return AGFWindowTab[]
function Window.Tabs()
	return tabs
end

--[[ Shared pieces the tabs draw with ]]

---@class AGFRingIcon : Frame
---@field Disc Texture
---@field Icon Texture
---@field Ring Texture
---@field Mask MaskTexture
---@field size number

---@param parent Frame
---@param size number
---@return AGFRingIcon
function Window.CreateRingIcon(parent, size)
	local ring = CreateFrame("Frame", nil, parent) --[[@as AGFRingIcon]]
	ring:SetSize(size, size)
	ring.size = size
	ring.Mask = ring:CreateMaskTexture()
	ring.Mask:SetAtlas("CircleMaskScalable")
	ring.Mask:SetAllPoints()
	ring.Disc = ring:CreateTexture(nil, "BACKGROUND")
	ring.Disc:SetColorTexture(0.05, 0.04, 0.03, 1)
	ring.Disc:SetAllPoints()
	ring.Disc:AddMaskTexture(ring.Mask)
	ring.Icon = ring:CreateTexture(nil, "ARTWORK")
	ring.Icon:AddMaskTexture(ring.Mask)
	ring.Ring = ring:CreateTexture(nil, "OVERLAY")
	ring.Ring:SetAtlas("adventureguide-ring")
	ring.Ring:SetSize(size * RING_SCALE, size * RING_SCALE)
	ring.Ring:SetPoint("CENTER")
	return ring
end

-- An atlas (inset) or a file icon (whole) in the ring.
---@param ring AGFRingIcon
---@param icon string|integer
function Window.SetRingIcon(ring, icon)
	ring.Icon:ClearAllPoints()
	if type(icon) == "number" then
		ring.Icon:SetTexture(icon)
		ring.Icon:SetAllPoints()
	else
		---@cast icon string
		local inset = ring.size * ATLAS_INSET
		ring.Icon:SetAtlas(icon)
		ring.Icon:SetPoint("TOPLEFT", inset, -inset)
		ring.Icon:SetPoint("BOTTOMRIGHT", -inset, inset)
	end
end

---@class AGFWindowCard : Button
---@field Fill Texture
---@field Art? AGFZoneBackdrop
---@field Picture Texture a still picture in place of the zone art (a profession's)
---@field Shade Texture
---@field Fade Texture
---@field Rim Texture[] the nine pieces of the rim, row by row

-- A card on the tier art: black under the zone's map (or a picture), the map dimmed and faded to the left so text
-- reads over it, in the Encounter Journal's dungeon-button rim.
---@param parent Frame
---@param zoneArt boolean
---@return AGFWindowCard
function Window.CreateCard(parent, zoneArt)
	local card = CreateFrame("Button", nil, parent) --[[@as AGFWindowCard]]
	card.Fill = card:CreateTexture(nil, "BACKGROUND")
	card.Fill:SetColorTexture(0, 0, 0, 1)
	card.Fill:SetPoint("TOPLEFT", 2, -2)
	card.Fill:SetPoint("BOTTOMRIGHT", -2, 2)
	card.Picture = card:CreateTexture(nil, "BACKGROUND", nil, 1)
	card.Picture:SetAllPoints(card.Fill)
	card.Picture:Hide()
	if zoneArt then
		card.Art = ns.ZoneIcon.CreateBackdrop(card)
		card.Art:SetPoint("TOPLEFT", 2, -2)
	end
	-- Over the art, whichever frame level the client gives it.
	local cover = CreateFrame("Frame", nil, card)
	cover:SetAllPoints()
	cover:SetFrameLevel(card:GetFrameLevel() + 3)
	card.Shade = cover:CreateTexture(nil, "BACKGROUND")
	card.Shade:SetColorTexture(0, 0, 0, 0.5)
	card.Shade:SetAllPoints(card.Fill)
	card.Fade = cover:CreateTexture(nil, "BACKGROUND", nil, 1)
	card.Fade:SetColorTexture(1, 1, 1, 1)
	card.Fade:SetGradient("HORIZONTAL", CreateColor(0, 0, 0, 0.6), CreateColor(0, 0, 0, 0))
	card.Fade:SetPoint("TOPLEFT", card.Fill)
	card.Fade:SetPoint("BOTTOMLEFT", card.Fill)
	local x = { EJ_LEFT, EJ_LEFT + EJ_RIM, EJ_RIGHT - EJ_RIM, EJ_RIGHT }
	local y = { EJ_TOP, EJ_TOP + EJ_RIM, EJ_BOTTOM - EJ_RIM, EJ_BOTTOM }
	card.Rim = {}
	for row = 1, 3 do
		for column = 1, 3 do
			local piece = cover:CreateTexture(nil, "BORDER")
			piece:SetTexture(EJ_FILE)
			piece:SetTexCoord(
				x[column] / EJ_SHEET_W,
				x[column + 1] / EJ_SHEET_W,
				y[row] / EJ_SHEET_H,
				y[row + 1] / EJ_SHEET_H
			)
			card.Rim[#card.Rim + 1] = piece
		end
	end
	card:SetHighlightAtlas("PetList-ButtonHighlight", "ADD")
	return card
end

-- Sizes a card: `width` by `height`, its rim placed piece by piece, the fade over `fade` of its width.
---@param card AGFWindowCard
---@param width number
---@param height number
---@param fade number
function Window.SizeCard(card, width, height, fade)
	card:SetSize(width, height)
	card.Fade:SetWidth((width - 4) * fade)
	for row = 1, 3 do
		for column = 1, 3 do
			local piece = card.Rim[(row - 1) * 3 + column]
			piece:ClearAllPoints()
			local w = column == 2 and width - 2 * EJ_RIM or EJ_RIM
			local h = row == 2 and height - 2 * EJ_RIM or EJ_RIM
			local x = column == 1 and 0 or column == 2 and EJ_RIM or width - EJ_RIM
			local y = row == 1 and 0 or row == 2 and EJ_RIM or height - EJ_RIM
			piece:SetSize(w, h)
			piece:SetPoint("TOPLEFT", x, -y)
		end
	end
end

---@class AGFWindowRow : Button
---@field Selected Texture
---@field Ring Texture
---@field Number Texture
---@field Title FontString
---@field Detail FontString

-- A numbered step on the right of a card: the route rows' art (Panel.lua), the ring and number at 26.
---@param parent Frame
---@param height number
---@return AGFWindowRow
function Window.CreateStepRow(parent, height)
	local row = CreateFrame("Button", nil, parent) --[[@as AGFWindowRow]]
	row:SetHeight(height)
	local background = row:CreateTexture(nil, "BACKGROUND")
	background:SetAtlas("PetList-ButtonBackground")
	background:SetAllPoints()
	row:SetHighlightAtlas("PetList-ButtonHighlight")
	row.Selected = row:CreateTexture(nil, "OVERLAY")
	row.Selected:SetAtlas("PetList-ButtonSelect")
	row.Selected:SetAllPoints()
	row.Ring = row:CreateTexture(nil, "ARTWORK")
	row.Ring:SetAtlas("adventureguide-ring")
	row.Ring:SetSize(26, 26)
	row.Ring:SetPoint("LEFT", 6, 0)
	row.Number = row:CreateTexture(nil, "OVERLAY")
	row.Number:SetSize(22, 25)
	row.Number:SetPoint("CENTER", row.Ring, "CENTER", 0, 0)
	row.Title = row:CreateFontString(nil, "ARTWORK", "GameFontNormalMed3")
	row.Title:SetPoint("BOTTOMLEFT", row, "LEFT", 40, 1)
	row.Title:SetPoint("RIGHT", -8, 0)
	row.Detail = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
	row.Detail:SetPoint("TOPLEFT", row, "LEFT", 40, -3)
	row.Detail:SetPoint("RIGHT", -8, 0)
	row.Detail:SetTextColor(0.8, 0.8, 0.8)
	for _, text in ipairs({ row.Title, row.Detail }) do
		text:SetJustifyH("LEFT")
		text:SetWordWrap(false)
	end
	return row
end

---@param row AGFWindowRow
---@param index integer
---@param title string
---@param detail? string
function Window.SetStepRow(row, index, title, detail)
	row.Number:SetAtlas("services-number-" .. index)
	row.Title:SetText(title)
	row.Detail:SetText(detail or "")
	row.Selected:SetShown(index == 1)
end

-- A tab's heading over a column: "Next steps", "Reagents".
---@param parent Frame
---@param text string
---@return FontString
function Window.Heading(parent, text)
	local heading = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	heading:SetJustifyH("LEFT")
	heading:SetText(text)
	return heading
end

--[[ The Today strip ]]

---@class AGFTodayChip : Button
---@field Icon AGFRingIcon
---@field Text FontString
---@field aside? AGFAside

---@param parent Frame
---@param width number
---@return AGFTodayChip
local function CreateChip(parent, width)
	local chip = CreateFrame("Button", nil, parent) --[[@as AGFTodayChip]]
	chip:SetSize(width, 36)
	chip.Icon = Window.CreateRingIcon(chip, TODAY_RING)
	chip.Icon:SetPoint("LEFT", 0, 0)
	chip.Text = chip:CreateFontString(nil, "ARTWORK", "GameFontNormal")
	chip.Text:SetPoint("LEFT", chip.Icon, "RIGHT", 8, 0)
	chip.Text:SetWidth(width - TODAY_RING - 14)
	chip.Text:SetJustifyH("LEFT")
	chip.Text:SetWordWrap(true)
	chip.Text:SetMaxLines(2)
	chip:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	chip:SetScript("OnClick", function(self, mouseButton)
		local aside = self.aside
		if aside and mouseButton == "RightButton" then
			ns.Asides.Open(self, "MENU_ADVENTURE_GUIDE_FOREVER_ASIDE", aside)
		elseif aside then
			ns.Asides.Go(aside)
		end
	end)
	-- As the panel's aside line: its whole line, and where a click goes when it goes anywhere.
	chip:SetScript("OnEnter", function(self)
		local aside = self.aside
		if not aside then
			return
		end
		local provider = ns.Integrations.Provider()
		local lines = { aside.text }
		lines[2] = aside.place
				and not ns.Setting("wanderer")
				and (provider and L.CLICK_TRAVEL:format(provider) or L.CLICK_WAYPOINT)
			or nil
		ns.Overview.ShowTooltip(self, lines)
	end)
	chip:SetScript("OnLeave", GameTooltip_Hide)
	return chip
end

---@param inset Frame
local function RefreshToday(inset)
	local asides = ns.Asides.All()
	local width = (Window.INSET_WIDTH - TODAY_LEFT - RIGHT) / TODAY_MAX
	for index = 1, TODAY_MAX do
		local aside = asides[index]
		local chip = chips[index]
		if aside and not chip then
			chip = CreateChip(inset, width)
			chip:SetPoint("TOPLEFT", TODAY_LEFT + (index - 1) * width, -TODAY_TOP)
			chips[index] = chip
		end
		if chip then
			chip.aside = aside
			chip:SetShown(aside ~= nil)
			if aside then
				Window.SetRingIcon(chip.Icon, aside.texture or aside.icon)
				chip.Text:SetText(aside.text)
			end
		end
	end
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
	if type(position) == "table" and type(position.point) == "string" then
		frame:SetPoint(position.point, UIParent, position.relativePoint, position.x, position.y)
	else
		frame:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
	end
end

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
	frame:SetMovable(true)
	frame:SetClampedToScreen(true)
	frame:SetDontSavePosition(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)
	frame:Hide()
	RestorePosition()
	-- Escape closes it, as it does the game's own windows.
	table.insert(UISpecialFrames, NAME)
	-- The compass the panel's header and tab wear, on a dark disc in the portrait's ring.
	frame:GetPortrait():SetColorTexture(0.06, 0.05, 0.04, 1)
	local compass = frame.PortraitContainer:CreateTexture(nil, "OVERLAY", nil, 1)
	compass:SetAtlas("islands-queue-prop-compass")
	compass:SetSize(54, 54)
	compass:SetPoint("CENTER", frame:GetPortrait(), "CENTER", 0, 2)
	frame.Subtitle = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	frame.Subtitle:SetPoint("TOPLEFT", 64, -34)
	frame.Subtitle:SetJustifyH("LEFT")
	local inset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate") --[[@as Frame]]
	inset:SetPoint("TOPLEFT", 4, -INSET_TOP)
	inset:SetPoint("BOTTOMRIGHT", -4, INSET_BOTTOM)
	frame.Inset = inset
	local art = inset:CreateTexture(nil, "BACKGROUND", nil, 1)
	art:SetAtlas("UI-EJ-Classic")
	art:SetPoint("TOPLEFT", 3, -1)
	art:SetPoint("BOTTOMRIGHT", -3, 1)
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
		Refresh()
	end)
	frame:SetScript("OnHide", function(self)
		ns.Overview.HideTooltipWithin(self)
		for _, event in ipairs(EVENTS) do
			self:UnregisterEvent(event)
		end
		PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
		if not (ns.PanelShown and ns.PanelShown()) then
			ns.Moments.Closed()
		end
	end)
	-- The same listeners as the panel's; each returns at once while the window is hidden.
	ns.OnRouteChange(Refresh)
	ns.Asides.OnChange(Refresh)
	ns.Moments.OnChange(Refresh)
	ns.Integrations.OnGuidanceChange(Refresh)
	local saved = ns.WindowDB().tab
	for index, tab in ipairs(tabs) do
		if tab.key == saved then
			selected = index
		end
	end
	PanelTemplates_SetTab(frame, selected)
	contents[selected]:Show()
end

function Refresh()
	if not (frame and frame:IsShown()) then
		return
	end
	local player = ns.State.Player()
	local zone = player.map and (ns.State.MapName(player.map) or (ns.Data.zones[player.map] or {}).name)
	frame.Subtitle:SetText(zone and L.OVERVIEW_WHERE:format(zone, player.level) or "")
	RefreshToday(frame.Inset)
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
	if not frame then
		Build()
	end
	---@cast frame -?
	frame:Show()
end

function ns.ToggleWindow()
	if frame and frame:IsShown() then
		frame:Hide()
	else
		ns.OpenWindow()
	end
end

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
