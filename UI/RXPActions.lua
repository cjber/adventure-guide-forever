---@type string, AGFNamespace
local _, ns = ...

--[[ Native-styled replacements for RestedXP's item and target windows while AGF steers its guide (#334). The buttons
     are secure: an item button uses the client's own item action, and a target button is a /cleartarget + /targetexact
     macro. Their frames are built, shown, hidden, moved and given attributes only out of combat; mid-fight only count,
     cooldown, range tint, glow and icon follow the client, and a change seen during a fight waits for
     PLAYER_REGEN_ENABLED. RestedXP's own windows are hidden while these are shown and restored otherwise, by
     Integrations/RestedXP.lua. ]]

local ActionButton = ns.ActionButton
local ITEM_SIZE = ActionButton.ITEM_SIZE
local GAP = 2
local ROW_GAP = 4
local POLL_INTERVAL = 0.2
local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

---@class AGFRXPActionsModule
local Actions = {}
ns.RXPActions = Actions

---@type Frame?
local root
---@type AGFActionButton[]
local itemButtons = {}
---@type AGFActionButton[]
local targetButtons = {}
local appliedHeight = 0
local pollElapsed = 0
local polling = false
local lastShown = false

---@param button AGFActionButton
local function ShowItemTooltip(button)
	if not button.itemId then
		return
	end
	GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
	GameTooltip:SetItemByID(button.itemId)
	GameTooltip:Show()
end

---@param index integer
---@return AGFActionButton
local function ItemButton(index)
	local button = itemButtons[index]
	if button then
		return button
	end
	local name = "AdventureGuideForeverItem" .. index
	button = CreateFrame("Button", name, root, "SecureActionButtonTemplate") --[[@as AGFActionButton]]
	ActionButton.Chrome(button)
	button:SetScript("OnEnter", ShowItemTooltip)
	itemButtons[index] = button
	return button
end

---@param index integer
---@return AGFActionButton
local function TargetButton(index)
	local button = targetButtons[index]
	if button then
		return button
	end
	local name = "AdventureGuideForeverTarget" .. index
	button = ActionButton.Create(assert(root), name)
	targetButtons[index] = button
	return button
end

---@param button AGFActionButton
---@param count integer
local function SetCount(button, count)
	if count > 1 then
		button.Count:SetText(tostring(count))
		button.Count:Show()
	else
		button.Count:Hide()
	end
end

---@param button AGFActionButton
---@param itemID integer
local function SetItem(button, itemID)
	button.itemId = itemID
	button.targetName = nil
	button:SetAttribute("type1", "item")
	button:SetAttribute("item", "item:" .. itemID)

	local icon = C_Item.GetItemIconByID(itemID)
	ns.Art.Icon(button.Icon, icon or QUESTION_ICON, ITEM_SIZE)
	button.Icon:SetVertexColor(1, 1, 1)
end

---@param button AGFActionButton
---@param itemID integer
local function UpdateItemState(button, itemID)
	local count = C_Item.GetItemCount(itemID)
	SetCount(button, count)

	-- Start from the item's own colours, so a cleared cooldown or range leaves no tint behind.
	button.Icon:SetVertexColor(1, 1, 1)
	local start, duration, enable = C_Item.GetItemCooldown(itemID)
	if start and duration and duration > 0 then
		button.Cooldown:SetCooldown(start, duration)
		local tint = (enable == 0 or enable == false) and 0.4 or 1
		button.Icon:SetVertexColor(tint, tint, tint)
	else
		button.Cooldown:Clear()
	end

	local inRange = C_Item.IsItemInRange(itemID, "target")
	if inRange == false then
		button.Range:SetVertexColor(1, 0.1, 0.1)
		button.Range:Show()
		button.Icon:SetVertexColor(1, 0.1, 0.1)
	else
		button.Range:Hide()
	end
end

-- The client re-reads an item's range as the player moves only when something asks it to, so a shown item button polls:
-- four cheap reads a second, non-secure visuals only, and nothing while the rows are hidden or the step has no item.
---@param _ Frame
---@param elapsed number
local function PollItemState(_, elapsed)
	if not root or not root:IsShown() then
		pollElapsed = 0
		return
	end
	pollElapsed = pollElapsed + elapsed
	if pollElapsed < POLL_INTERVAL then
		return
	end
	pollElapsed = 0
	for _, button in ipairs(itemButtons) do
		if button:IsShown() and button.itemId then
			UpdateItemState(button, button.itemId)
		end
	end
end

---@param step AGFRXPDisplayStep?
---@return AGFRXPItem[]
local function UsableItems(step)
	local items = {}
	for _, item in ipairs(step and step.items or {}) do
		local count = C_Item.GetItemCount(item.id)
		local usable = C_Item.IsUsableItem(item.id)
		if count > 0 and usable ~= false then
			items[#items + 1] = item
		end
	end
	return items
end

---@return AGFRXPDisplayStep?
local function CurrentStep()
	local snapshot = ns.RestedXP.Snapshot()
	for _, step in ipairs(snapshot.steps or {}) do
		if not step.preview and not step.sticky then
			return step
		end
	end
	for _, step in ipairs(snapshot.steps or {}) do
		if not step.preview then
			return step
		end
	end
end

-- The AGF section only supplies a screen position: root's parent and its one anchor are UIParent, so no secure child
-- makes Blizzard's tracker, which lays the section out, protected. Everything that moves or shows the rows happens out
-- of combat.
---@param module AGFTrackerModule
---@return boolean
local function ModuleVisible(module)
	return module:IsVisible() and not module.isCollapsed
end

-- The section's height without the action rows' own reservation, which they hang below.
---@param module AGFTrackerModule
---@return number
local function BaseHeight(module)
	local reserved = module.rxpActionsReserved or 0
	if (module.contentsHeight or 0) < reserved then
		reserved = 0
	end
	return math.max(0, (module.contentsHeight or 0) - reserved)
end

---@param module AGFTrackerModule
local function Anchor(module)
	if InCombatLockdown() or not root then
		return
	end
	local left, top = module:GetLeft(), module:GetTop()
	if not left or not top then
		root:Hide()
		return
	end
	local scale = module:GetEffectiveScale() / UIParent:GetEffectiveScale()
	root:SetFrameStrata(module:GetFrameStrata())
	root:SetFrameLevel(module:GetFrameLevel() + 5)
	root:ClearAllPoints()
	root:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left * scale, (top - BaseHeight(module)) * scale - ROW_GAP)
end

local function Clear()
	if InCombatLockdown() then
		return
	end
	if root then
		root:Hide()
	end
	if appliedHeight ~= 0 then
		appliedHeight = 0
		local module = ns.TrackerModule()
		if module then
			module:MarkDirty()
		end
	end
end

-- Whether AGF's own action rows are the thing on screen right now; RestedXP's native windows follow this.
---@return boolean
function Actions.Shown()
	return root ~= nil and root:IsShown()
end

-- Hidden for any reason (the tracker setting, a collapsed section, a step without actions): RestedXP's own item and
-- target windows come back, so a changed state asks the integration to reconcile them.
local function NotifyShown()
	local shown = Actions.Shown()
	if shown ~= lastShown then
		lastShown = shown
		ns.RestedXP.Refresh()
	end
end

local function Apply()
	if InCombatLockdown() then
		return
	end
	local module = ns.TrackerModule()
	if not module then
		return
	end
	if not ns.Setting("showTracker") then
		Clear()
		return
	end
	local step = CurrentStep()
	local items = UsableItems(step)
	local targets = step and step.targets or {}
	if #items == 0 and #targets == 0 then
		Clear()
		return
	end
	if not root then
		root = CreateFrame("Frame", "AdventureGuideForeverRXPActions", UIParent)
		root:SetSize(1, 1)
		root:Hide()
	end

	local current = ns.Readable(UnitName("target"))
	for index, item in ipairs(items) do
		local button = ItemButton(index)
		SetItem(button, item.id)
		UpdateItemState(button, item.id)
		ActionButton.SetKeybind(button, "AdventureGuideForeverItem" .. index)
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", root, "TOPLEFT", (index - 1) * (ITEM_SIZE + GAP), 0)
		button:Show()
	end
	for index = #items + 1, #itemButtons do
		itemButtons[index]:Hide()
	end
	for index, target in ipairs(targets) do
		local button = TargetButton(index)
		ActionButton.SetTarget(button, target, current)
		ActionButton.SetKeybind(button, "AdventureGuideForeverTarget" .. index)
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", root, "TOPLEFT", (index - 1) * (ITEM_SIZE + GAP), -ITEM_SIZE - ROW_GAP)
		button:Show()
	end
	for index = #targets + 1, #targetButtons do
		targetButtons[index]:Hide()
	end

	local rows = (#items > 0 and 1 or 0) + (#targets > 0 and 1 or 0)
	local width = math.max(#items, #targets) * (ITEM_SIZE + GAP) - GAP
	local height = rows * ITEM_SIZE + (rows - 1) * ROW_GAP
	root:SetSize(math.max(1, width), math.max(1, height))
	if ModuleVisible(module) then
		root:Show()
	else
		root:Hide()
	end
	local wantPoll = #items > 0
	if wantPoll ~= polling then
		polling = wantPoll
		pollElapsed = 0
		root:SetScript("OnUpdate", wantPoll and PollItemState or nil)
	end
	if height ~= appliedHeight then
		appliedHeight = height
		module:MarkDirty()
	end
	Anchor(module)
end

-- Called after the tracker section lays its own blocks out: reserve the action rows below them. The reservation is
-- kept separately so a repeated layout (the specs call LayoutContents directly) never adds it twice.
---@param module AGFTrackerModule
function Actions.Reserve(module)
	if not root then
		return
	end
	local visible = ModuleVisible(module)
	if not InCombatLockdown() then
		if not visible then
			root:Hide()
		elseif appliedHeight > 0 and not root:IsShown() then
			root:Show()
		end
	end
	NotifyShown()
	local shown = visible and root:IsShown() and ns.Setting("showTracker")
	local height = shown and root:GetHeight() or 0
	local reserved = module.rxpActionsReserved or 0
	if (module.contentsHeight or 0) < reserved then
		reserved = 0
	end
	local base = (module.contentsHeight or 0) - reserved
	if height <= 0 or base <= 0 then
		if reserved > 0 then
			module.contentsHeight = base
			module.rxpActionsReserved = nil
			if module.UpdateHeight then
				module:UpdateHeight()
			end
		end
		if not InCombatLockdown() then
			Anchor(module)
		end
		return
	end
	local extra = height + ROW_GAP
	module.contentsHeight = base + extra
	module.rxpActionsReserved = extra
	if module.UpdateHeight then
		module:UpdateHeight()
	end
	if not InCombatLockdown() then
		Anchor(module)
	end
end

-- The parts of a shown button that carry no secure state may follow the bags and the target mid-fight; attributes,
-- anchors and visibility wait for PLAYER_REGEN_ENABLED.
local function UpdateVisuals()
	if not root or not root:IsShown() then
		return
	end
	local current = ns.Readable(UnitName("target"))
	for _, button in ipairs(itemButtons) do
		if button:IsShown() and button.itemId then
			UpdateItemState(button, button.itemId)
		end
	end
	for _, button in ipairs(targetButtons) do
		if button:IsShown() and button.targetName then
			ActionButton.UpdateTargetVisual(button, current)
		end
	end
end

function Actions.Refresh()
	if InCombatLockdown() then
		return
	end
	if not (ns.RestedXP and ns.RestedXP.Active and ns.RestedXP.Active()) then
		Clear()
		NotifyShown()
		return
	end
	Apply()
	NotifyShown()
end

ns.RestedXP.OnChange(Actions.Refresh)

-- Events whose visible state may follow the client in combat without touching anything secure.
local VISUAL_EVENTS = {
	BAG_UPDATE_COOLDOWN = true,
	BAG_UPDATE_DELAYED = true,
	PLAYER_TARGET_CHANGED = true,
}

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_TARGET_CHANGED")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("BAG_UPDATE_COOLDOWN")
events:RegisterEvent("UPDATE_BINDINGS")
events:SetScript("OnEvent", function(_, event)
	if InCombatLockdown() and VISUAL_EVENTS[event] then
		UpdateVisuals()
		return
	end
	Actions.Refresh()
	-- A section that moved during the fight leaves the rows where they were; combat's end catches them up.
	if event == "PLAYER_REGEN_ENABLED" then
		local module = ns.TrackerModule()
		if module then
			Anchor(module)
		end
	end
end)
