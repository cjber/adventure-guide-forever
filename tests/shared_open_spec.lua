-- #811: The tracker and other consumers can open the guide through ForeverCore.
local harness = dofile("tests/harness.lua")
local h = harness.load({ db = { autoStart = false } })
h.flush()

local addon = "AdventureGuideForever"
local core = h.G.ForeverCore
assert(core.Open(addon) == true, "ForeverCore accepts the guide's open request")
h.flush()
assert(h.ns.PanelShown(), "the guide opens after the map shows")

local target = { kind = "block", block = { id = "journey-complete" }, module = h.tracker }
local requestedAddon
h.tracker.trackerMenu(target, {
	Title = function() end,
	Open = function(_, _, name)
		requestedAddon = name
		return { SetEnabled = function() end }
	end,
})
assert(requestedAddon == addon, "the tracker gives ForeverCore the addon name")

h.tracker:OnBlockHeaderClick(target.block, "RightButton")
local openEntry
for _, entry in ipairs(h.menu.entries) do
	if entry.text == h.ns.L.CHOOSE_JOURNEY then
		openEntry = entry
	end
end
assert(openEntry and openEntry:IsEnabled(), "the tracker offers the guide outside combat")

h.combat = true
local before = #h.prints
local accepted, reason = openEntry.onClick()
assert(accepted == false and reason, "ForeverCore refuses the tracker request when combat starts")
assert(#h.prints == before + 1 and h.prints[#h.prints] == reason, "Core prints the refusal once")
assert(#h.errors == 0, table.concat(h.errors, "\n"))
print("shared_open_spec: ok")
