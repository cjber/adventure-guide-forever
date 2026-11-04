-- Run from the repository root: luajit tests/upgrades_spec.lua
-- Reward upgrades (UI/Upgrades.lua, docs/design.md §2.28): a quest reward choice is an upgrade when the character can
-- use it, it is the armour type the class wears at its level, it has no primary stat the class never uses, and its
-- item level beats the weaker of the items in the slots it would take, with the game tutorial's weapon rules.
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local h = harness.load()
h.flush()
local Upgrades = h.ns.Upgrades

local function Item(equipLoc, level, extra)
	local item = { usable = true, equipLoc = equipLoc, level = level, classID = 4, subclassID = 0 }
	for key, value in pairs(extra or {}) do
		item[key] = value
	end
	return item
end

-- Every slot empty unless `worn` names it.
local function Worn(worn)
	local all = {}
	for slot = 1, 18 do
		all[slot] = worn and worn[slot] or false
	end
	return all
end

local SHAMAN = { class = "SHAMAN", level = 18, dualWield = false }
local LEATHER, MAIL = 2, 3

-- Item level against the worn item.
do
	local head = { [1] = { level = 15, equipLoc = "INVTYPE_HEAD" } }
	local helm = Item("INVTYPE_HEAD", 18, { subclassID = LEATHER })
	equal(Upgrades.IsUpgrade(helm, Worn(head), SHAMAN), true, "a higher item level is an upgrade")
	helm.level = 15
	equal(Upgrades.IsUpgrade(helm, Worn(head), SHAMAN), false, "the same item level is not")
	equal(Upgrades.IsUpgrade(helm, Worn(), SHAMAN), true, "anything beats an empty slot")
	helm.usable = false
	equal(Upgrades.IsUpgrade(helm, Worn(), SHAMAN), false, "an item the game shows red is not")
	equal(Upgrades.IsUpgrade(Item("", 30), Worn(), SHAMAN), false, "an item that is not worn is not")
	equal(Upgrades.IsUpgrade(Item("INVTYPE_BODY", 30), Worn(), SHAMAN), false, "a shirt is not")
end

-- Armour type: a shaman wears leather, then mail from 40; a cloak and a ring take any.
do
	local mail = Item("INVTYPE_CHEST", 20, { subclassID = MAIL })
	equal(Upgrades.IsUpgrade(mail, Worn(), SHAMAN), false, "mail before 40 is not a shaman's")
	local forty = { class = "SHAMAN", level = 40, dualWield = false }
	equal(Upgrades.IsUpgrade(mail, Worn(), forty), true, "mail at 40 is")
	equal(
		Upgrades.IsUpgrade(Item("INVTYPE_CHEST", 40, { subclassID = LEATHER }), Worn(), forty),
		false,
		"leather at 40 no longer is"
	)
	equal(
		Upgrades.IsUpgrade(Item("INVTYPE_CLOAK", 20, { subclassID = 1 }), Worn(), SHAMAN),
		true,
		"a cloth cloak is anyone's"
	)
	equal(Upgrades.IsUpgrade(Item("INVTYPE_FINGER", 20), Worn(), SHAMAN), true, "a ring has no armour type")
end

-- Primary stats: a mage has no use for strength, but stamina alone is judged on level.
do
	local mage = { class = "MAGE", level = 18, dualWield = false }
	local strength = Item("INVTYPE_FINGER", 20, { stats = { ITEM_MOD_STRENGTH_SHORT = 3 } })
	equal(Upgrades.IsUpgrade(strength, Worn(), mage), false, "strength only is not a mage's")
	strength.stats.ITEM_MOD_INTELLECT_SHORT = 2
	equal(Upgrades.IsUpgrade(strength, Worn(), mage), true, "with intellect too it is")
	local stamina = Item("INVTYPE_FINGER", 20, { stats = { ITEM_MOD_STAMINA_SHORT = 4 } })
	equal(Upgrades.IsUpgrade(stamina, Worn(), mage), true, "stamina alone is judged on level")
end

-- Two slots: the weaker worn item is the one to beat.
do
	local rings =
		{ [11] = { level = 25, equipLoc = "INVTYPE_FINGER" }, [12] = { level = 10, equipLoc = "INVTYPE_FINGER" } }
	equal(Upgrades.IsUpgrade(Item("INVTYPE_FINGER", 15), Worn(rings), SHAMAN), true, "beats the weaker ring")
	equal(Upgrades.IsUpgrade(Item("INVTYPE_FINGER", 10), Worn(rings), SHAMAN), false, "beats neither ring")
end

-- Weapons, by the game tutorial's rules: the same kind of main-hand weapon, no off hand behind a two-hander, and a
-- one-hander's off-hand slot only with dual wield.
do
	local weapon = { classID = 2, subclassID = 0 }
	local twoHander = { [16] = { level = 20, equipLoc = "INVTYPE_2HWEAPON" } }
	local oneHander = { [16] = { level = 20, equipLoc = "INVTYPE_WEAPON" } }
	equal(
		Upgrades.IsUpgrade(Item("INVTYPE_WEAPON", 25, weapon), Worn(twoHander), SHAMAN),
		false,
		"a one-hander is no upgrade over a two-hander"
	)
	equal(
		Upgrades.IsUpgrade(Item("INVTYPE_2HWEAPON", 25, weapon), Worn(oneHander), SHAMAN),
		false,
		"a two-hander is no upgrade over a one-hander"
	)
	equal(
		Upgrades.IsUpgrade(Item("INVTYPE_2HWEAPON", 25, weapon), Worn(twoHander), SHAMAN),
		true,
		"a better two-hander is"
	)
	equal(
		Upgrades.IsUpgrade(Item("INVTYPE_SHIELD", 25, { subclassID = 6 }), Worn(twoHander), SHAMAN),
		false,
		"no shield behind a two-hander"
	)
	equal(
		Upgrades.IsUpgrade(Item("INVTYPE_SHIELD", 25, { subclassID = 6 }), Worn(oneHander), SHAMAN),
		true,
		"a shield beside a one-hander"
	)
	-- The main hand is better than the reward: without dual wield the empty off hand doesn't count.
	local better = { [16] = { level = 30, equipLoc = "INVTYPE_WEAPON" } }
	local sword = Item("INVTYPE_WEAPON", 25, weapon)
	equal(Upgrades.IsUpgrade(sword, Worn(better), SHAMAN), false, "without dual wield only the main hand counts")
	local rogue = { class = "ROGUE", level = 18, dualWield = true }
	equal(Upgrades.IsUpgrade(sword, Worn(better), rogue), true, "with dual wield the empty off hand counts")
end

-- The client read: the choices the quest frame offers, against what the character wears; a choice still loading
-- holds the marks back until it arrives, and Pawn or the setting off marks nothing.
do
	local G = h.G
	local links = { "item:1", "item:2", "item:3" }
	local info = {
		["item:1"] = { 20, "INVTYPE_HEAD", 4, LEATHER },
		["item:2"] = { 20, "INVTYPE_HEAD", 4, MAIL },
		["item:3"] = { 12, "INVTYPE_HEAD", 4, LEATHER },
		[101] = { 15, "INVTYPE_HEAD", 4, LEATHER },
	}
	G.C_Item.GetItemInfo = function(item)
		local row = info[item]
		if row then
			return "Item", nil, 2, row[1], 1, "", "", 1, row[2], 0, 0, row[3], row[4]
		end
	end
	G.C_Item.GetItemStats = function()
		return {}
	end
	G.GetNumQuestChoices = function()
		return #links
	end
	G.GetQuestItemLink = function(_, index)
		return links[index]
	end
	G.GetQuestItemInfo = function()
		return "Item", 0, 1, 2, true, 1
	end
	G.GetQuestItemInfoLootType = function()
		return 0
	end
	G.GetInventoryItemID = function(_, slot)
		return slot == 1 and 101 or nil
	end
	G.CanDualWield = function()
		return false
	end
	local marked, pending = Upgrades.Marked()
	equal(marked[1], true, "the better leather helm is marked")
	equal(marked[2], nil, "the mail helm is not a level 18 shaman's")
	equal(marked[3], nil, "the weaker helm is not")
	equal(pending, false, "nothing is loading")
	info["item:3"] = nil
	marked, pending = Upgrades.Marked()
	equal(pending, true, "a choice still loading says so")
	equal(marked[1], true, "and the rest are still read")
	info[101] = nil
	marked, pending = Upgrades.Marked()
	equal(next(marked), nil, "a worn item still loading marks nothing")
	equal(pending, true, "and waits")
	equal(h.ns.DEFAULTS.markUpgrades, true, "on by default")
end

print(("upgrades_spec: %d checks passed"):format(checks))
