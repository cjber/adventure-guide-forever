---@type string, AGFNamespace
local _, ns = ...

-- Forever 70009 can assert in Blizzard_Menu.AcquireMenu. Keep guide menus in our own frames.
---@alias AGFMenuEntryKind "root"|"button"|"title"|"divider"|"checkbox"

---@class AGFMenuDescription
---@field kind AGFMenuEntryKind
---@field text? string
---@field entries AGFMenuDescription[]
---@field onClick? fun()
---@field isSelected? fun(): boolean
---@field isEnabled? boolean|fun(): boolean
---@field tooltip? fun(tooltip: GameTooltip)
---@field parent? AGFMenuDescription
---@field back? AGFMenuDescription
local Description = {}
Description.__index = Description

---@param kind AGFMenuEntryKind
---@param text? string
---@return AGFMenuDescription
local function New(kind, text)
	return setmetatable({ kind = kind, text = text, entries = {} }, Description)
end

---@param text string
---@param action? fun()
---@return AGFMenuDescription
function Description:CreateButton(text, action)
	local entry = New("button", text)
	entry.onClick, entry.parent = action, self
	self.entries[#self.entries + 1] = entry
	return entry
end

function Description:CreateTitle(text)
	local entry = self:CreateButton(text)
	entry.kind = "title"
	return entry
end

function Description:CreateDivider()
	local entry = self:CreateButton("")
	entry.kind, entry.text = "divider", nil
	return entry
end

function Description:CreateCheckbox(text, selected, action)
	local entry = self:CreateButton(text, action)
	entry.kind, entry.isSelected = "checkbox", selected
	return entry
end

function Description:SetEnabled(enabled)
	self.isEnabled = enabled
end

function Description:IsEnabled()
	if type(self.isEnabled) == "function" then
		return self.isEnabled()
	end
	return self.isEnabled ~= false
end

function Description:SetTooltip(tooltip)
	self.tooltip = tooltip
end

-- The popup is as wide as its longest entry: a fixed row width cut titles such as a step's "Complete objectives ·
-- ..." with no way to read them. The body width is capped so one very long line cannot run off the screen; a row cut
-- at the cap carries its whole text in a tooltip, unless the entry already has one of its own.
local BODY_MIN, FRAME_PAD, ROW_INSET, TEXT_PADDING, BODY_MAX = 296, 24, 12, 20, 600

---@class AGFContextPopup : Frame
---@field rows Button[]
---@field owner? Region
---@field body Frame
---@field scroll AGFScrollFrame
---@type AGFContextPopup?
local popup
local Draw
---@type table<Frame, boolean>
local watchedOwners = setmetatable({}, { __mode = "k" })

---@param owner Frame
local function OwnerHidden(owner)
	if popup and popup.owner == owner then
		popup:Hide()
	end
end

---@return AGFContextPopup
local function Ensure()
	if popup then
		return popup
	end
	popup = CreateFrame("Frame", "AdventureGuideForeverContextMenu", UIParent) --[[@as AGFContextPopup]]
	popup.rows = {}
	popup:SetFrameStrata("FULLSCREEN_DIALOG")
	popup:SetClampedToScreen(true)
	popup:EnableMouse(true)
	local background = popup:CreateTexture(nil, "BACKGROUND")
	background:SetAllPoints()
	background:SetColorTexture(0.04, 0.03, 0.02, 1)
	local scroll = CreateFrame("ScrollFrame", nil, popup, "ScrollFrameTemplate") --[[@as AGFScrollFrame]]
	scroll:SetPoint("TOPLEFT", 0, -4)
	scroll:SetPoint("BOTTOMRIGHT", -24, 4)
	local body = CreateFrame("Frame", nil, scroll)
	body:SetWidth(296)
	scroll:SetScrollChild(body)
	popup.body, popup.scroll = body, scroll
	popup:SetScript("OnShow", function(self)
		self:RegisterEvent("GLOBAL_MOUSE_DOWN")
	end)
	popup:SetScript("OnHide", function(self)
		if self:IsShown() then
			self:Hide()
		end
		self:UnregisterEvent("GLOBAL_MOUSE_DOWN")
		self.owner = nil
		GameTooltip_Hide()
	end)
	popup:SetScript("OnEvent", function(self)
		if not self:IsMouseOver() and not (self.owner and self.owner:IsMouseOver()) then
			self:Hide()
		end
	end)
	popup:Hide()
	table.insert(UISpecialFrames, "AdventureGuideForeverContextMenu")
	return popup
end

---@param root AGFMenuDescription
function Draw(root)
	local frame = Ensure()
	local entries = {}
	if root.parent then
		local back = New("button", ns.L.MENU_BACK)
		back.back = root.parent
		entries[1] = back
	end
	for _, entry in ipairs(root.entries) do
		entries[#entries + 1] = entry
	end
	local y, bodyWidth = 6, BODY_MIN
	for index, entry in ipairs(entries) do
		local row = frame.rows[index]
		if not row then
			row = CreateFrame("Button", nil, frame.body, "UIPanelButtonTemplate") --[[@as Button]]
			frame.rows[index] = row
		end
		local height = entry.kind == "divider" and 8 or 26
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 6, -y)
		local selected = entry.isSelected and entry.isSelected()
		local label = entry.text or ""
		if entry.kind == "checkbox" then
			label = (selected and ns.L.MENU_CHECKED or ns.L.MENU_UNCHECKED):format(label)
		elseif #entry.entries > 0 then
			label = ns.L.MENU_SUBMENU:format(label)
		end
		row:SetText(label)
		local width = math.min(math.max(BODY_MIN - ROW_INSET, row:GetTextWidth() + TEXT_PADDING), BODY_MAX - ROW_INSET)
		row:SetSize(width, height)
		bodyWidth = math.max(bodyWidth, width + ROW_INSET)
		-- A row cut at the cap cannot show its whole line, so its tooltip does.
		local truncated = entry.tooltip == nil and row:GetTextWidth() > width - TEXT_PADDING
		row:SetEnabled(entry.kind ~= "title" and entry.kind ~= "divider" and entry:IsEnabled())
		row:SetScript("OnClick", function()
			if entry.back then
				Draw(entry.back)
			elseif #entry.entries > 0 then
				Draw(entry)
			else
				frame:Hide()
				if entry.onClick then
					entry.onClick()
				end
			end
		end)
		row:SetScript("OnEnter", function(self)
			if entry.tooltip then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				entry.tooltip(GameTooltip)
				GameTooltip:Show()
			elseif truncated then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				GameTooltip_SetTitle(GameTooltip, label)
				GameTooltip:Show()
			end
		end)
		row:SetScript("OnLeave", GameTooltip_Hide)
		row:SetShown(entry.kind ~= "divider")
		y = y + height
	end
	for index = #entries + 1, #frame.rows do
		frame.rows[index]:Hide()
	end
	frame.body:SetWidth(bodyWidth)
	frame.body:SetHeight(y + 6)
	frame:SetSize(bodyWidth + FRAME_PAD, math.min(y + 14, 420))
	frame.scroll:SetVerticalScroll(0)
end

---@param owner Region
---@param generator fun(owner: Region, root: AGFMenuDescription)
---@return AGFMenuDescription
function ns.ContextMenu(owner, generator)
	local root = New("root")
	generator(owner, root)
	local frame = Ensure()
	frame:Hide()
	frame.owner = owner
	-- Card owners can be inside a ScrollFrame; parenting to them clips the popup's rows.
	local ownerFrame = owner --[[@as Frame]]
	if ownerFrame.HookScript and not watchedOwners[ownerFrame] then
		ownerFrame:HookScript("OnHide", OwnerHidden)
		watchedOwners[ownerFrame] = true
	end
	frame:ClearAllPoints()
	frame:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -2)
	Draw(root)
	frame:Show()
	return root
end
