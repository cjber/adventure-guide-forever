---@type string, AGFNamespace
local _, ns = ...

-- Forever 70009 can assert in Blizzard_Menu.AcquireMenu. Keep guide menus in our own frames.
---@class AGFMenuDescription
---@field kind string
---@field text? string
---@field entries AGFMenuDescription[]
---@field onClick? fun()
---@field isSelected? fun(): boolean
---@field isEnabled? boolean|fun(): boolean
---@field tooltip? fun(tooltip: GameTooltip)
---@field tag? string
---@field parent? AGFMenuDescription
---@field back? AGFMenuDescription
local Description = {}
Description.__index = Description

---@param kind string
---@param text? string
---@return AGFMenuDescription
local function New(kind, text)
	return setmetatable({ kind = kind, text = text, entries = {} }, Description)
end

function Description:SetTag(tag)
	self.tag = tag
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

---@class AGFContextPopup : Frame
---@field rows Button[]
---@field owner? Region
---@field body Frame
---@field scroll AGFScrollFrame
---@type AGFContextPopup?
local popup
local Draw

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
	local y = 6
	for index, entry in ipairs(entries) do
		local row = frame.rows[index]
		if not row then
			row = CreateFrame("Button", nil, frame.body, "UIPanelButtonTemplate") --[[@as Button]]
			frame.rows[index] = row
		end
		local height = entry.kind == "divider" and 8 or 26
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 6, -y)
		row:SetSize(284, height)
		local selected = entry.isSelected and entry.isSelected()
		local label = entry.text or ""
		if entry.kind == "checkbox" then
			label = (selected and ns.L.MENU_CHECKED or ns.L.MENU_UNCHECKED):format(label)
		elseif #entry.entries > 0 then
			label = ns.L.MENU_SUBMENU:format(label)
		end
		row:SetText(label)
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
			end
		end)
		row:SetScript("OnLeave", GameTooltip_Hide)
		row:SetShown(entry.kind ~= "divider")
		y = y + height
	end
	for index = #entries + 1, #frame.rows do
		frame.rows[index]:Hide()
	end
	frame.body:SetHeight(y + 6)
	frame:SetSize(320, math.min(y + 14, 420))
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
	frame:SetParent(owner:GetObjectType() == "Texture" and UIParent or owner --[[@as Frame]])
	frame:ClearAllPoints()
	frame:SetPoint("TOPRIGHT", owner, "BOTTOMRIGHT", 0, -2)
	Draw(root)
	frame:Show()
	return root
end
