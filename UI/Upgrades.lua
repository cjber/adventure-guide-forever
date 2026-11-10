---@type string, AGFNamespace
local _, ns = ...

if ns.broken then
	return
end

--[[ Reward upgrades (docs/design.md §2.28). When a quest giver's window lists rewards to choose from, the game's own
     green upgrade arrow (the bags' `bags-greenarrow`) marks each choice that beats what the character wears in its
     slot: an item the character can use, of the armour type its class wears at its level, with no primary stat the
     class never uses, and a higher item level than the weaker of the items in the slots it would take. The weapon
     rules are the game's own tutorial's (Blizzard_TutorialServices.lua): a main-hand weapon only for the same kind
     of weapon held now, and nothing for the off hand behind a two-handed one. No stat weights. Pawn marks the same
     rewards, so with Pawn loaded this marks nothing. Tweaks Forever's gold coin (the best-selling choice) sits on the
     icon's other corner. ]]

local Art = ns.Art

---@class AGFUpgrades
local Upgrades = {}
ns.Upgrades = Upgrades

local ARROW = "bags-greenarrow"
-- The bags draw the arrow at its atlas size on a 37 px item button; a reward icon is 39 px.
local ARROW_BOX = 16

local ARMOR = 4
local CLOTH, LEATHER, MAIL, PLATE = 1, 2, 3, 4
local MAIN_HAND, OFF_HAND = 16, 17

-- The armour a class wears in its armour slots, and the level it moves to the heavier type, as the class trainers
-- teach it.
local ARMOUR = {
	WARRIOR = { MAIL, 40, PLATE },
	PALADIN = { MAIL, 40, PLATE },
	HUNTER = { LEATHER, 40, MAIL },
	SHAMAN = { LEATHER, 40, MAIL },
	ROGUE = { LEATHER },
	DRUID = { LEATHER },
	MAGE = { CLOTH },
	PRIEST = { CLOTH },
	WARLOCK = { CLOTH },
}

local STRENGTH, AGILITY, INTELLECT = "ITEM_MOD_STRENGTH_SHORT", "ITEM_MOD_AGILITY_SHORT", "ITEM_MOD_INTELLECT_SHORT"
local PRIMARY = { STRENGTH, AGILITY, INTELLECT }
-- The primary stats each class uses in any of its roles. An item whose primary stats are all outside these is no
-- upgrade, whatever its level; stamina, spirit and items with no primary stat are judged on level alone.
local USES = {
	WARRIOR = { [STRENGTH] = true, [AGILITY] = true },
	PALADIN = { [STRENGTH] = true, [INTELLECT] = true },
	HUNTER = { [AGILITY] = true },
	ROGUE = { [AGILITY] = true },
	SHAMAN = { [STRENGTH] = true, [AGILITY] = true, [INTELLECT] = true },
	DRUID = { [STRENGTH] = true, [AGILITY] = true, [INTELLECT] = true },
	MAGE = { [INTELLECT] = true },
	PRIEST = { [INTELLECT] = true },
	WARLOCK = { [INTELLECT] = true },
}

-- The slots each equip location takes. A one-handed weapon's off-hand slot needs dual wield (Slots).
local SLOTS = {
	INVTYPE_HEAD = { 1 },
	INVTYPE_NECK = { 2 },
	INVTYPE_SHOULDER = { 3 },
	INVTYPE_CHEST = { 5 },
	INVTYPE_ROBE = { 5 },
	INVTYPE_WAIST = { 6 },
	INVTYPE_LEGS = { 7 },
	INVTYPE_FEET = { 8 },
	INVTYPE_WRIST = { 9 },
	INVTYPE_HAND = { 10 },
	INVTYPE_FINGER = { 11, 12 },
	INVTYPE_TRINKET = { 13, 14 },
	INVTYPE_CLOAK = { 15 },
	INVTYPE_2HWEAPON = { MAIN_HAND },
	INVTYPE_WEAPONMAINHAND = { MAIN_HAND },
	INVTYPE_WEAPON = { MAIN_HAND, OFF_HAND },
	INVTYPE_WEAPONOFFHAND = { OFF_HAND },
	INVTYPE_SHIELD = { OFF_HAND },
	INVTYPE_HOLDABLE = { OFF_HAND },
	INVTYPE_RANGED = { 18 },
	INVTYPE_RANGEDRIGHT = { 18 },
	INVTYPE_THROWN = { 18 },
	INVTYPE_RELIC = { 18 },
}

-- Armour slots, where the armour type counts; a cloak is cloth for every class.
local ARMOUR_SLOT = {
	INVTYPE_HEAD = true,
	INVTYPE_SHOULDER = true,
	INVTYPE_CHEST = true,
	INVTYPE_ROBE = true,
	INVTYPE_WAIST = true,
	INVTYPE_LEGS = true,
	INVTYPE_FEET = true,
	INVTYPE_WRIST = true,
	INVTYPE_HAND = true,
}

---@class AGFRewardItem
---@field usable boolean the game shows it as usable (not red) for this character
---@field equipLoc string its INVTYPE_ equip location, "" for an item that is not worn
---@field classID integer?
---@field subclassID integer?
---@field level integer its item level
---@field stats table<string, number>? its stats by ITEM_MOD_ key

---@class AGFWorn
---@field level integer the worn item's item level
---@field equipLoc string

---@class AGFUpgradePlayer
---@field class string the class token
---@field level integer
---@field dualWield boolean

-- A main-hand weapon's kind for the tutorial's rule: two-handed or not.
---@param equipLoc string
local function TwoHanded(equipLoc)
	return equipLoc == "INVTYPE_2HWEAPON"
end

-- The slots `item` would take for `player`, given what is worn (`worn[slot]`, false for an empty slot).
---@param item AGFRewardItem
---@param worn table<integer, AGFWorn|false>
---@param player AGFUpgradePlayer
---@return integer[]
local function Slots(item, worn, player)
	local held = worn[MAIN_HAND]
	local twoHandHeld = held and TwoHanded(held.equipLoc)
	local slots = {}
	for _, slot in ipairs(SLOTS[item.equipLoc] or {}) do
		local fits = true
		if slot == MAIN_HAND and held then
			fits = TwoHanded(item.equipLoc) == twoHandHeld
		elseif slot == OFF_HAND then
			fits = not twoHandHeld
				and (
					(item.equipLoc ~= "INVTYPE_WEAPON" and item.equipLoc ~= "INVTYPE_WEAPONOFFHAND")
					or player.dualWield
				)
		end
		if fits then
			slots[#slots + 1] = slot
		end
	end
	return slots
end

-- Whether `item` is an upgrade for `player` over what is worn: `worn` maps each equipment slot to its item, or false
-- when the slot is empty.
---@param item AGFRewardItem
---@param worn table<integer, AGFWorn|false>
---@param player AGFUpgradePlayer
---@return boolean
function Upgrades.IsUpgrade(item, worn, player)
	if not item.usable or not SLOTS[item.equipLoc] then
		return false
	end
	local armour = ARMOUR[player.class]
	if armour and item.classID == ARMOR and ARMOUR_SLOT[item.equipLoc] and item.subclassID ~= 0 then
		local wears = (armour[2] and player.level >= armour[2]) and armour[3] or armour[1]
		if item.subclassID ~= wears then
			return false
		end
	end
	local uses = USES[player.class]
	if uses and item.stats then
		local any, useful = false, false
		for _, stat in ipairs(PRIMARY) do
			if (item.stats[stat] or 0) > 0 then
				any, useful = true, useful or uses[stat] == true
			end
		end
		if any and not useful then
			return false
		end
	end
	local weakest
	for _, slot in ipairs(Slots(item, worn, player)) do
		local level = worn[slot] and worn[slot].level or 0
		weakest = weakest and math.min(weakest, level) or level
	end
	return weakest ~= nil and item.level > weakest
end

--[[ The quest frame ]]

-- An item's level, equip location, class and subclass from the client, or nil while it is not cached.
---@param item string|integer a link or an item ID
---@return integer?, string?, integer?, integer?
local function Info(item)
	local _, _, _, level, _, _, _, _, equipLoc, _, _, classID, subclassID = C_Item.GetItemInfo(item)
	if not level then
		return nil
	end
	return level, equipLoc or "", classID, subclassID
end

-- What the character wears, by slot (false for empty); nil while a worn item is not cached.
---@return table<integer, AGFWorn|false>?
local function Worn()
	local worn = {}
	for slot = 1, 18 do
		local id = GetInventoryItemID("player", slot)
		if id then
			local level, equipLoc = Info(id)
			if not level then
				return nil
			end
			worn[slot] = { level = level, equipLoc = equipLoc }
		else
			worn[slot] = false
		end
	end
	return worn
end

-- The `index`th reward choice as an AGFRewardItem; false for one that is not an item; nil while it is not cached.
---@param index integer
---@return AGFRewardItem|false|nil
local function Choice(index)
	if GetQuestItemInfoLootType and GetQuestItemInfoLootType("choice", index) ~= 0 then
		return false
	end
	local link = GetQuestItemLink("choice", index)
	if not link then
		return nil
	end
	local level, equipLoc, classID, subclassID = Info(link)
	if not level then
		return nil
	end
	local usable = select(5, GetQuestItemInfo("choice", index))
	return {
		usable = usable ~= false,
		equipLoc = equipLoc or "",
		classID = classID,
		subclassID = subclassID,
		level = level,
		stats = C_Item.GetItemStats and C_Item.GetItemStats(link) or nil,
	}
end

-- Which reward choices are upgrades, by choice index, and whether any item was still loading.
---@return table<integer, true>, boolean
function Upgrades.Marked()
	local marked, pending = {}, false
	local worn = Worn()
	if not worn then
		return marked, true
	end
	local player = {
		class = UnitClassBase("player"),
		level = UnitLevel("player"),
		dualWield = CanDualWield and CanDualWield() == true or false,
	}
	for index = 1, GetNumQuestChoices() do
		local item = Choice(index)
		if item == nil then
			pending = true
		elseif item and Upgrades.IsUpgrade(item, worn, player) then
			marked[index] = true
		end
	end
	return marked, pending
end

---@type table<AGFQuestRewardButton, Texture>
local arrows = {}
-- A quest giver's detail or reward panel is the quest display on screen; an item is still loading.
local showing, waiting = false, false

-- The quest frame's reward choice buttons in choice order. Read only: Blizzard lays out the choices in order, after
-- any fixed rewards, and marks each with type "choice".
---@return AGFQuestRewardButton[]
local function ChoiceButtons()
	local buttons = {}
	for _, button in ipairs(QuestInfoRewardsFrame and QuestInfoRewardsFrame.RewardButtons or {}) do
		if button:IsShown() and button.type == "choice" then
			buttons[#buttons + 1] = button
		end
	end
	return buttons
end

local function Update()
	waiting = false
	for _, arrow in pairs(arrows) do
		arrow:Hide()
	end
	if not (showing and ns.Setting("markUpgrades")) or C_AddOns.IsAddOnLoaded("Pawn") then
		return
	end
	local marked, pending = Upgrades.Marked()
	waiting = pending
	for index, button in ipairs(ChoiceButtons()) do
		if marked[index] then
			local arrow = arrows[button]
			if not arrow then
				-- On the button itself, so it scrolls and hides with it, above the icon as the bags draw it.
				arrow = button:CreateTexture(nil, "OVERLAY", nil, 2)
				Art.Fit(arrow, ARROW, ARROW_BOX, ARROW_BOX)
				arrow:SetPoint("TOPLEFT", button.Icon or button, "TOPLEFT", 0, 0)
				arrows[button] = arrow
			end
			arrow:Show()
		end
	end
end
Upgrades.Update = Update

-- Laid out after Blizzard's QuestInfo_Display: only a giver's detail and reward panels, whose rewards the Get-
-- QuestItem functions read; the quest log's display shares the rewards frame and reads other functions.
---@param template table?
local function Displayed(template)
	showing = (template == QUEST_TEMPLATE_DETAIL or template == QUEST_TEMPLATE_REWARD)
		and not (QuestInfoFrame and QuestInfoFrame.questLog)
	ns.core.SafeCall("quest rewards", Update)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
-- A choice's item arriving re-lays the rewards without QuestInfo_Display.
events:RegisterEvent("QUEST_ITEM_UPDATE")
events:RegisterEvent("QUEST_FINISHED")
events:SetScript("OnEvent", function(_, event)
	if event == "PLAYER_LOGIN" then
		if QuestInfo_Display then
			hooksecurefunc("QuestInfo_Display", Displayed)
		end
		return
	elseif event == "QUEST_FINISHED" then
		showing = false
	elseif not waiting then
		return
	end
	ns.core.SafeCall("quest rewards", Update)
end)
