---@type string, AGFNamespace
local _, ns = ...

-- Shared chrome for the tracker's secure item and target buttons (RXPActions.lua, NpcHighlight.lua): a square action
-- button whose icon sits in the game's own quest-item frame, and the one-click /cleartarget + /targetexact target
-- action. Buttons are made and given attributes out of combat only.

local ITEM_SIZE = 26
local FRAME_SIZE = 42
local TARGET_ICON = { target = 2056011, mob = 135274, unitscan = 135274 }
local HIGHLIGHT = "Interface\\Buttons\\ButtonHilight-Square"

---@class AGFActionButton : Button
---@field Icon Texture
---@field Glow Texture
---@field Count FontString
---@field Range FontString
---@field Binding FontString
---@field Cooldown Cooldown
---@field itemId? integer
---@field targetName? string
---@field targetKind? string

---@class AGFActionButtonModule
local ActionButton = {}
ns.ActionButton = ActionButton
ActionButton.ITEM_SIZE = ITEM_SIZE
ActionButton.FRAME_SIZE = FRAME_SIZE

---@param button AGFActionButton
---@param name string
function ActionButton.SetKeybind(button, name)
	local key = GetBindingKey("CLICK " .. name .. ":LeftButton")
	button.Binding:SetText(key or "")
	button.Binding:SetShown(key ~= nil and key ~= "")
end

---@param button AGFActionButton
function ActionButton.ShowTargetTooltip(button)
	if not button.targetName then
		return
	end
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	local friendly = button.targetKind == "target"
	GameTooltip:SetText(button.targetName, friendly and 0 or 1, friendly and 1 or 0, 0)
	GameTooltip:Show()
end

---@param button AGFActionButton
function ActionButton.Chrome(button)
	button:SetSize(ITEM_SIZE, ITEM_SIZE)
	button:RegisterForClicks("AnyUp")
	button:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	local border = button:CreateTexture(nil, "BACKGROUND")
	ns.Art.Fit(border, "UI-QuestTrackerButton-QuestItem-Frame", FRAME_SIZE, FRAME_SIZE)
	border:SetPoint("CENTER")

	local glow = button:CreateTexture(nil, "BACKGROUND", nil, 1)
	ns.Art.Fit(glow, "UI-QuestTrackerButton-QuestItem-Frame-Glow", FRAME_SIZE, FRAME_SIZE)
	glow:SetPoint("CENTER")
	glow:Hide()
	button.Glow = glow

	local icon = button:CreateTexture(nil, "BORDER")
	icon:SetSize(ITEM_SIZE, ITEM_SIZE)
	icon:SetPoint("CENTER")
	button.Icon = icon

	local highlight = button:CreateTexture(nil, "HIGHLIGHT")
	ns.Art.Icon(highlight, HIGHLIGHT, ITEM_SIZE)
	highlight:SetPoint("CENTER")
	highlight:SetBlendMode("ADD")

	local count = button:CreateFontString(nil, "ARTWORK", "NumberFontNormal")
	count:SetPoint("BOTTOMRIGHT", -3, 2)
	count:Hide()
	button.Count = count

	local range = button:CreateFontString(nil, "ARTWORK", "NumberFontNormalSmallGray")
	range:SetPoint("TOPRIGHT", 16, -2)
	range:SetSize(29, 10)
	range:SetText(RANGE_INDICATOR)
	range:Hide()
	button.Range = range

	local binding = button:CreateFontString(nil, "ARTWORK", "NumberFontNormalSmallGray")
	binding:SetPoint("TOPLEFT", -2, -1)
	binding:Hide()
	button.Binding = binding

	local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate") --[[@as Cooldown]]
	cooldown:SetAllPoints()
	cooldown:Hide()
	button.Cooldown = cooldown
end

-- A secure target button: one click clears the target, selects the named unit exactly, and lets the caller mark it.
---@param parent Frame
---@param name string
---@return AGFActionButton
function ActionButton.Create(parent, name)
	local button = CreateFrame("Button", name, parent, "SecureActionButtonTemplate") --[[@as AGFActionButton]]
	ActionButton.Chrome(button)
	button:SetScript("OnEnter", ActionButton.ShowTargetTooltip)
	return button
end

-- Only the icon and the glow, the parts a fight may touch: the button's macro and name stay as they were.
---@param button AGFActionButton
---@param current? string
function ActionButton.UpdateTargetVisual(button, current)
	if button.targetName == current then
		SetPortraitTexture(button.Icon, "target")
	else
		ns.Art.Icon(button.Icon, TARGET_ICON[button.targetKind] or TARGET_ICON.mob, ITEM_SIZE)
	end
	button.Icon:SetVertexColor(1, 1, 1)
	button.Glow:SetShown(button.targetName == current)
end

---@param button AGFActionButton
---@param target AGFRXPTarget
---@param current? string
function ActionButton.SetTarget(button, target, current)
	button.itemId = nil
	button.targetName = target.name
	button.targetKind = target.kind
	button:SetAttribute("type1", "macro")
	button:SetAttribute("macrotext", "/cleartarget\n/targetexact " .. target.name)
	ActionButton.UpdateTargetVisual(button, current)
end
