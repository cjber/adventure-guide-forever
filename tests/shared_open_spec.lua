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
		return { SetEnabled = function() end, SetTooltip = function() end }
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
local title, combatLine
assert(openEntry.tooltip, "the named open entry has a tooltip")
openEntry.tooltip({
	SetText = function(_, value)
		title = value
	end,
	AddLine = function(_, value)
		combatLine = value
	end,
})
assert(title == h.ns.L.CHOOSE_JOURNEY, "the tooltip names the action")
assert(combatLine == "Unavailable in combat", "the tooltip explains the combat restriction")
local before = #h.prints
local accepted, reason = openEntry.onClick()
assert(accepted == false and reason, "ForeverCore refuses the tracker request when combat starts")
assert(#h.prints == before + 1 and h.prints[#h.prints] == reason, "Core prints the refusal once")

h.combat = false
h.G.HideUIPanel(h.map)
h.flush()
assert(not h.map:IsShown(), "the world map starts closed")
h.ns.OpenPanel = nil
assert(core.Open(addon) == true, "the opener accepts a map request before the panel exists")
h.flush()
assert(h.map:IsShown(), "the world map opens without a panel opener")

assert(#h.errors == 0, table.concat(h.errors, "\n"))
print("shared_open_spec: ok")
