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

assert(h.ns.Setting("microButton") == true)
assert(h.ns.Setting("replaceMicroButton") == true)
assert(h.ns.Setting("microButtonPlacement") == "beforeGameMenu")
local button = h.G.AdventureGuideForeverMicroButton
assert(button and button:IsShown())
assert(not h.G.AdventureGuideMicroButton:IsShown())

setting("microButton"):SetValue(false)
assert(not button:IsShown())
setting("microButton"):SetValue(true)
assert(button:IsShown())
setting("microButtonPlacement"):SetValue("afterCollections")
assert(h.ns.Setting("microButtonPlacement") == "afterCollections")

local opens = 0
h.ns.OpenPanel = function()
	opens = opens + 1
end
h.call(h.G.AdventureGuideMicroButton.scripts.OnClick, h.G.AdventureGuideMicroButton)
assert(opens == 1)
setting("replaceMicroButton"):SetValue(false)
assert(h.G.AdventureGuideMicroButton:IsShown())
h.call(h.G.AdventureGuideMicroButton.scripts.OnClick, h.G.AdventureGuideMicroButton)
assert(opens == 1)
local note
for _, row in ipairs(h.settings) do
	if row.kind == "element" and row.name == h.ns.L.MICRO_BUTTON_BINDING_NOTE then
		note = row
	end
end
assert(note, "the visible keybinding note is missing from the micro menu settings")
assert(note.template == "SettingsListElementTemplate")
assert(#h.errors == 0, table.concat(h.errors, "\n"))
print("micro button settings: ok")
