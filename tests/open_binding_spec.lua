-- Run from the repository root: luajit tests/open_binding_spec.lua
-- Alt-G opens the guide through the hidden button Bindings.xml clicks; no minimap button is drawn, and the saved
-- keys of the retired micro menu button, minimap button and Forever addons page suggestions are cleared on load.
local harness = dofile("tests/harness.lua")
local h = harness.load()

-- The open button keeps the old minimap button's name so saved key bindings still reach it, but nothing draws it.
local button = assert(h.G.AdventureGuideForeverMinimapButton, "no open button for the key binding")
assert(not button.parent, "the open button is parented to a visible frame")
assert(h.ns.openButton == button, "the namespace does not point at it")

local opens = 0
h.ns.OpenPanel = function()
	opens = opens + 1
end
h.call(button.scripts.OnClick, button, "LeftButton")
assert(opens == 1, "a click did not open the guide")

local old = harness.load({
	db = {
		microButton = false,
		microButtonPlacement = "afterCollections",
		replaceMicroButton = true,
		minimapButtonHidden = true,
		minimapButtonAngle = 225,
		suggestCompanions = false,
		suggestFamily = false,
		familyDismissed = {},
	},
})
local saved = old.G.AdventureGuideForeverDB
for _, key in ipairs({
	"microButton",
	"microButtonPlacement",
	"replaceMicroButton",
	"minimapButtonHidden",
	"minimapButtonAngle",
	"suggestCompanions",
	"suggestFamily",
	"familyDismissed",
}) do
	assert(saved[key] == nil, "the retired setting stayed: " .. key)
end

assert(#h.errors == 0, table.concat(h.errors, "\n"))
assert(#old.errors == 0, table.concat(old.errors, "\n"))
print("open binding: ok")
