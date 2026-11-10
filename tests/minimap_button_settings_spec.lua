-- Run from the repository root: luajit tests/minimap_button_settings_spec.lua
-- The minimap button Core.lua creates, the Settings checkbox that hides it, and the one-time move of an old micro
-- menu button choice onto it (#416).
local harness = dofile("tests/harness.lua")
local h = harness.load()
local function setting(key)
	for _, item in ipairs(h.addonSettings) do
		if item.key == key then
			return item
		end
	end
	error("missing setting: " .. key)
end

assert(h.ns.Setting("minimapButtonHidden") == false)
assert(h.G.MicroMenu == nil, "the standalone micro menu lives on")
local button = assert(h.G.AdventureGuideForeverMinimapButton, "no minimap button")
assert(button.parent == h.G.Minimap, "the button is not parented to the Minimap")
assert(button:IsShown(), "the minimap button starts hidden")
assert(h.ns.minimapButton == button and button.minimapButtonSpec.host == h.ns, "the host does not point at it")

local spec = button.minimapButtonSpec
assert(spec.icon == h.ns.Icon and h.ns.Icon == "Interface\\Icons\\INV_Misc_Map_01", spec.icon)
assert(spec.title == h.ns.L.TITLE, spec.title)
assert(spec.binding == "Alt-G", spec.binding)
assert(spec.subtext == h.ns.L.MINIMAP_BUTTON_SUBTEXT, spec.subtext)
assert(spec.settings == h.G.AdventureGuideForeverDB, "the account saved table is not the button's settings")
assert(h.G.AdventureGuideForeverDB.minimapButtonAngle == 225, "the default angle was not saved")

local opens = 0
h.ns.OpenPanel = function()
	opens = opens + 1
end
h.call(button.scripts.OnClick, button, "LeftButton")
assert(opens == 1, "a click did not open the guide")

-- The checkbox is the shown state; the saved key is the hide flag MinimapButton.Refresh reads.
setting("minimapButton"):SetValue(false)
assert(h.ns.Setting("minimapButtonHidden") == true, "unchecking did not write the hide flag")
assert(not button:IsShown(), "the button stayed on the rim")
setting("minimapButton"):SetValue(true)
assert(h.ns.Setting("minimapButtonHidden") == false, "checking did not clear the hide flag")
assert(button:IsShown(), "the button stayed hidden")

-- A player who turned the old micro menu button off gets a hidden minimap button, once.
local old = harness.load({ db = { microButton = false, microButtonPlacement = "afterCollections" } })
assert(old.ns.Setting("minimapButtonHidden") == true, "the old off choice was not moved across")
assert(old.G.AdventureGuideForeverDB.microButton == nil, "the old setting stayed")
assert(old.G.AdventureGuideForeverDB.microButtonPlacement == nil, "the old placement stayed")
assert(old.G.AdventureGuideForeverDB.replaceMicroButton == nil, "the old replace setting stayed")
assert(not old.G.AdventureGuideForeverMinimapButton:IsShown(), "the moved choice did not hide the button")

local on = harness.load({ db = { microButton = true } })
assert(on.ns.Setting("minimapButtonHidden") == false, "the old on choice hid the button")
assert(on.G.AdventureGuideForeverDB.microButton == nil, "the old on setting stayed")
assert(on.G.AdventureGuideForeverMinimapButton:IsShown(), "the old on choice hid the button")

-- Once moved, the old key is gone, so showing the new button later is not undone by a stale copy.
local moved = harness.load({ db = { microButton = false, minimapButtonHidden = false } })
assert(moved.ns.Setting("minimapButtonHidden") == false, "a newer choice lost to the old setting")
assert(moved.G.AdventureGuideForeverMinimapButton:IsShown(), "a newer choice left the button hidden")

assert(#h.errors == 0, table.concat(h.errors, "\n"))
assert(#old.errors == 0, table.concat(old.errors, "\n"))
assert(#on.errors == 0, table.concat(on.errors, "\n"))
assert(#moved.errors == 0, table.concat(moved.errors, "\n"))
print("minimap button settings: ok")
