-- RestedXP's own item and target windows while AGF steers it (#334): native-styled secure items and /target buttons in
-- the AGF tracker section, built and changed only out of combat, and the native windows handed back on Stop.
local harness = dofile("tests/harness.lua")
local items = {
	[1234] = { name = "Runed Scroll", icon = 134400 },
	[5678] = { name = "Healing Potion", icon = 134400, quality = 2 },
	[9012] = { name = "Signal Flare", icon = 134400 },
}
local h = harness.load({
	spf = "v1",
	db = { autoStart = false },
	items = items,
	bags = { [1234] = 3, [5678] = 1, [9012] = 2 },
})
local ns = h.ns
local engine = dofile("tests/rxp_fixture.lua")(h)
h.bindings["ALT-1"] = "CLICK AdventureGuideForeverItem1:LeftButton"
h.bindings["ALT-2"] = "CLICK AdventureGuideForeverTarget1:LeftButton"
local targetName = "Quartermaster"
h.G.UnitName = function(unit)
	return unit == "target" and targetName or nil
end
local module = assert(ns.TrackerModule())
-- The section's laid-out screen position: the action rows copy it into their own UIParent anchor.
module.rect = { 40, 300, 240, 140 }

local current = engine.currentGuide.steps[2]
local function Aim(itemIDs, friendly, enemy)
	current.activeItems = itemIDs
	current.elements[1].targets = friendly
	current.elements[2].mobs = enemy
	ns.RestedXP.Refresh()
	h.flush()
end

Aim({ [1234] = true, [5678] = true }, { "Quartermaster" }, { "Plainstrider" })

local root = assert(h.G.AdventureGuideForeverRXPActions, "the action rows use the AGF tracker section")
assert(root:IsShown(), "the action rows show while AGF steers RestedXP")
assert(root:GetParent() == h.G.UIParent, "the action rows hang off UIParent, not the secure tracker section")

local scroll = assert(h.G.AdventureGuideForeverItem1)
local potion = assert(h.G.AdventureGuideForeverItem2)
assert(scroll:IsShown() and potion:IsShown(), "one item button per usable step item")
assert(scroll:GetAttribute("type1") == "item", "an item button uses the client's item action")
assert(scroll:GetAttribute("item") == "item:1234", "an item button carries its item ID")
assert(scroll.Count:GetText() == "3", "the item button shows how many the bags hold")
assert(scroll.Binding:GetText() == "ALT-1" and scroll.Binding:IsShown(), "the item button shows its key binding")
assert(potion.Count:IsShown() == false, "a single item shows no count, as the native button does")

local talk = assert(h.G.AdventureGuideForeverTarget1)
local kill = assert(h.G.AdventureGuideForeverTarget2)
assert(talk:IsShown() and kill:IsShown(), "one target button per step target")
assert(talk:GetAttribute("type1") == "macro", "a target button is a secure macro")
assert(talk:GetAttribute("macrotext") == "/cleartarget\n/targetexact Quartermaster", "a talk target names its NPC")
assert(kill:GetAttribute("macrotext") == "/cleartarget\n/targetexact Plainstrider", "a kill target names its creature")
assert(talk.Glow:IsShown() and not kill.Glow:IsShown(), "the current target is the one marked")
assert(talk.Icon.file == "portrait:target", "the current target shows its portrait")
assert(talk.Binding:GetText() == "ALT-2" and talk.Binding:IsShown(), "the target button shows its key binding")

h.tracker:LayoutContents()
local reserved = assert(module.rxpActionsReserved, "the section reserves room for the action rows")
assert(module.contentsHeight >= reserved, "the action rows are part of the section's height")
assert(root:GetNumPoints() == 1, "the action rows have exactly one anchor")
local point, relativeTo, relativePoint, x = root:GetPoint(1)
assert(
	point == "TOPLEFT" and relativeTo == h.G.UIParent and relativePoint == "BOTTOMLEFT",
	"the action rows anchor only to UIParent, never to the tracker section"
)
assert(x == module.rect[1], "the action rows take their x from the section's screen position")
assert(root:GetFrameStrata() == module:GetFrameStrata(), "the action rows sit at the section's frame strata")
assert(root:GetFrameLevel() == module:GetFrameLevel() + 5, "the action rows sit just above the section")

-- A guide change during combat waits: no secure frame is created, moved, shown or given a new attribute until
-- PLAYER_REGEN_ENABLED brings the rebuild.
local created = h.counts.CreateFrame
local rootPoint, rootParent = root:GetPoint(1)
local rootWidth, rootHeight = root:GetSize()
local rootLevel = root:GetFrameLevel()
local scrollPoint, scrollParent = scroll:GetPoint(1)
h.SetCombat(true)
ns.RXPActions.Refresh()
Aim({ [9012] = true }, { "New Quartermaster" }, {})
assert(h.counts.CreateFrame == created, "combat creates no secure action frame")
assert(scroll:GetAttribute("item") == "item:1234", "combat leaves the old item action in place")
assert(
	talk:GetAttribute("macrotext") == "/cleartarget\n/targetexact Quartermaster",
	"combat leaves the old target in place"
)
assert(root:IsShown(), "the actions already shown stay put through combat")
local combatPoint, combatParent = root:GetPoint(1)
assert(
	combatPoint == rootPoint and combatParent == rootParent,
	"combat leaves the action rows anchored where they were"
)
local width, height = root:GetSize()
assert(width == rootWidth and height == rootHeight, "combat leaves the action rows the same size")
assert(root:GetFrameLevel() == rootLevel, "combat leaves the action rows' level alone")
local itemPoint, itemParent = scroll:GetPoint(1)
assert(itemPoint == scrollPoint and itemParent == scrollParent, "combat leaves a shown button's anchor alone")
-- The non-secure parts do follow the bags mid-fight: the count changes, the secure item action does not.
h.bags[1234] = 5
h.fire("BAG_UPDATE_DELAYED")
assert(scroll.Count:GetText() == "5", "a bag change in combat updates the shown count only")
assert(scroll:GetAttribute("item") == "item:1234", "a bag change in combat leaves the item action in place")
-- The target's icon and glow are not secure either: the current target moves the mark without changing the macro.
targetName = "Plainstrider"
h.fire("PLAYER_TARGET_CHANGED")
assert(not talk.Glow:IsShown() and kill.Glow:IsShown(), "a target change in combat moves the glow only")
assert(
	talk:GetAttribute("macrotext") == "/cleartarget\n/targetexact Quartermaster",
	"a target change leaves the macro in place"
)
targetName = "Quartermaster"
h.fire("PLAYER_TARGET_CHANGED")
assert(talk.Glow:IsShown() and not kill.Glow:IsShown(), "the glow follows the current target back mid-fight")
h.SetCombat(false)
h.flush()
assert(scroll:GetAttribute("item") == "item:9012", "combat's end applies the step's new item")
assert(scroll.Count:GetText() == "2", "the new item's count is read when it applies")
assert(
	talk:GetAttribute("macrotext") == "/cleartarget\n/targetexact New Quartermaster",
	"combat's end applies the new target"
)
assert(not potion:IsShown(), "an item no longer in the step is hidden after combat")
assert(not kill:IsShown(), "a target no longer in the step is hidden after combat")

-- An item's icon starts from its own colours: a cleared range or cooldown leaves no old tint behind, and the range tint
-- wins when both apply.
local originalCooldown, originalRange = h.G.C_Item.GetItemCooldown, h.G.C_Item.IsItemInRange
h.G.C_Item.GetItemCooldown = function()
	return 0, 0, 1
end
h.G.C_Item.IsItemInRange = function()
	return false
end
ns.RXPActions.Refresh()
local r, g, b = unpack(scroll.Icon.vertexColor)
assert(r == 1 and g == 0.1 and b == 0.1, "an out-of-range item tints its icon red")
assert(scroll.Range:IsShown(), "the range marker shows out of range")
h.G.C_Item.IsItemInRange = function()
	return nil
end
ns.RXPActions.Refresh()
r, g, b = unpack(scroll.Icon.vertexColor)
assert(r == 1 and g == 1 and b == 1, "a cleared range restores the icon's own colours")
assert(not scroll.Range:IsShown(), "the range marker hides back in range")
h.G.C_Item.GetItemCooldown = function()
	return 0, 30, 0
end
ns.RXPActions.Refresh()
r, g, b = unpack(scroll.Icon.vertexColor)
assert(r == 0.4 and g == 0.4 and b == 0.4, "a disabled cooldown tints the icon after the reset")
h.G.C_Item.IsItemInRange = function()
	return false
end
ns.RXPActions.Refresh()
r, g, b = unpack(scroll.Icon.vertexColor)
assert(r == 1 and g == 0.1 and b == 0.1, "the range tint is applied after the cooldown tint")

-- The item range is re-read while the player moves: a throttled OnUpdate refresh of the shown item buttons only.
local polls = 0
h.G.C_Item.GetItemCooldown = function()
	return 0, 0, 1
end
h.G.C_Item.IsItemInRange = function()
	polls = polls + 1
	return false
end
ns.RXPActions.Refresh()
local update = assert(root:GetScript("OnUpdate"), "the shown item rows poll the item's range")
update(root, 1) -- clear any time the harness frames already added
polls = 0
update(root, 0.19)
assert(polls == 0, "the poll waits for its 0.2 s interval")
update(root, 0.01)
assert(polls == 1, "the poll reads the item's range once the interval passes")
r, g, b = unpack(scroll.Icon.vertexColor)
assert(
	r == 1 and g == 0.1 and b == 0.1 and scroll.Range:IsShown(),
	"a move out of range tints the icon without a bag event"
)
root:Hide()
update(root, 0.2)
assert(polls == 1, "the poll does nothing while the rows are hidden")
root:Show()
Aim({}, { "Quartermaster" }, {})
assert(root:IsShown(), "a target-only step still shows its target row")
assert(root:GetScript("OnUpdate") == nil, "the poll is off when the step has no item button")
Aim({ [9012] = true }, { "New Quartermaster" }, {})
assert(root:GetScript("OnUpdate"), "the poll returns with the item button")
h.G.C_Item.GetItemCooldown = originalCooldown
h.G.C_Item.IsItemInRange = originalRange
ns.RXPActions.Refresh()

-- AGF hides RXP's own windows only while it steers, and gives back what RXP itself was showing.
local itemFrame = h.G.CreateFrame("Frame", nil, h.G.UIParent)
local targetFrame = h.G.CreateFrame("Frame", nil, h.G.UIParent)
itemFrame:Show()
targetFrame:Show()
engine.activeItemFrame = itemFrame
engine.targeting = { activeTargetFrame = targetFrame }
ns.RestedXP.Refresh()
h.flush()
assert(not itemFrame:IsShown() and not targetFrame:IsShown(), "RXP's action windows stay hidden while AGF steers")
-- Turning the tracker setting off while the guide stays active hides AGF's rows and gives RXP its windows back; turning
-- it on again takes them away.
ns.SetSetting("showTracker", false)
h.flush()
assert(not root:IsShown(), "the tracker setting hides the AGF action rows")
assert(itemFrame:IsShown() and targetFrame:IsShown(), "the tracker setting gives RXP's action windows back")
ns.SetSetting("showTracker", true)
h.flush()
assert(root:IsShown(), "the tracker setting brings the AGF action rows back")
assert(not itemFrame:IsShown() and not targetFrame:IsShown(), "the AGF action rows hide RXP's windows again")
ns.SetSetting("restedxpGuide", false)
h.flush()
assert(itemFrame:IsShown() and targetFrame:IsShown(), "stopping AGF gives RXP's action windows back")
assert(not root:IsShown(), "the AGF action rows hide when AGF stops steering")
print("restedxp_actions_spec: native items, targets, combat queueing and the RXP handoff passed")

-- Not steering at all: the native windows are left alone and no replacement is built.
local idle = harness.load({ db = { restedxpGuide = false, restedxpChoiceMade = true } })
local idleEngine = dofile("tests/rxp_fixture.lua")(idle, nil, true)
local idleItem = idle.G.CreateFrame("Frame", nil, idle.G.UIParent)
local idleTarget = idle.G.CreateFrame("Frame", nil, idle.G.UIParent)
idleItem:Show()
idleTarget:Show()
idleEngine.activeItemFrame = idleItem
idleEngine.targeting = { activeTargetFrame = idleTarget }
idle.ns.RestedXP.Refresh()
idle.flush()
assert(not idle.ns.RestedXP.Active(), "the idle client is not steered")
assert(idleItem:IsShown() and idleTarget:IsShown(), "RXP's windows are left alone when AGF is not steering")
assert(idle.G.AdventureGuideForeverRXPActions == nil, "no replacement is built when AGF is not steering")
print("restedxp_actions_spec: idle RXP windows are untouched")
