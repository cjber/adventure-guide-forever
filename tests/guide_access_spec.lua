local harness = dofile("tests/harness.lua")
local action = "ADVENTUREGUIDEFOREVER_WINDOW"
local function Verify(options)
	local h = harness.load(options)
	h.G.SlashCmdList.ADVENTUREGUIDEFOREVER("")
	h.G.AdventureGuideForever_OnAddonCompartmentClick()
	h.flush()
	assert(h.ns.PanelShown(), "guide opens on the map")
	assert(h.G.AdventureGuideForeverWindow == nil, "no standalone window")
	assert(h.ns.OpenWindow == nil, "no standalone entry point")
	assert(h.G.AdventureGuideForever_ToggleWindow == nil, "no window binding action")
	assert(#h.errors == 0, table.concat(h.errors, "\n"))
	return h
end
local h = Verify({ bindings = { ["SHIFT-J"] = action, ["CTRL-J"] = "TOGGLEQUESTLOG" } })
assert(h.bindings["SHIFT-J"] == nil, "old window key cleared")
assert(h.bindings["CTRL-J"] == "TOGGLEQUESTLOG", "other key retained")
assert(#h.savedBindings == 1, "changed bindings saved once")
local other = Verify({ bindings = { ["SHIFT-J"] = "TOGGLEQUESTLOG" } })
assert(other.bindings["SHIFT-J"] == "TOGGLEQUESTLOG", "player's Shift-J retained")
assert(#other.savedBindings == 0, "unchanged bindings not saved")
local combat = harness.load({
	setup = function(client)
		client.combat = true
	end,
	bindings = { ["SHIFT-J"] = action },
})
assert(combat.bindings["SHIFT-J"] == action, "cleanup waits for combat")
combat.combat = false
combat.fire("PLAYER_REGEN_ENABLED")
assert(combat.bindings["SHIFT-J"] == nil, "cleanup after combat")
assert(#combat.errors == 0, table.concat(combat.errors, "\n"))
print("guide_access_spec: passed")
