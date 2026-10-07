local harness = dofile("tests/harness.lua")
local fixture = dofile("tests/rxp_fixture.lua")
local function fresh()
	local h = harness.load({ spf = "v1", db = { autoStart = false } })
	local rxp = fixture(h, nil, true)
	local popup = assert(h.G.AdventureGuideForeverGuideSetup)
	local rows = h.Find(function(frame)
		return frame:GetParent() == popup and frame.objectType == "Button"
	end)
	assert(#rows == 2, "setup has two direct choices")
	return h, rxp, popup, rows
end
local h, rxp, popup, rows = fresh()
assert(popup:IsShown() and not h.ns.RestedXP.Active(), "ask before taking over an installed guide")
assert(rxp.RXPFrame:GetAlpha() == 1, "native window stays visible while choice is pending")
h.Click(rows[1])
h.flush()
assert(not popup:IsShown() and h.ns.Setting("restedxpChoiceMade"), "choice is remembered and popup closes")
assert(h.ns.RestedXP.Active() and rxp.RXPFrame:GetAlpha() == 0, "guide choice activates the existing frontend")
h.ns.RestedXP.Refresh()
h.flush()
assert(not popup:IsShown(), "engine updates do not repeat setup")
h.ns.SetSetting("restedxpGuide", false)
h.flush()
assert(rxp.RXPFrame:GetAlpha() == 1, "settings restore the native display")
assert(h.G.AdventureGuideForever.API.RestedXPNativeUI(), "navigation addons see the native display choice")
local native, nativeRXP, nativePopup, nativeRows = fresh()
native.Click(nativeRows[2])
native.flush()
assert(not native.ns.RestedXP.Active() and nativeRXP.RXPFrame:GetAlpha() == 1, "native choice preserves RXP window")
assert(native.ns.Setting("restedxpChoiceMade") and not nativePopup:IsShown(), "native choice is remembered")
local cancelled, _, cancelledPopup = fresh()
cancelledPopup:Hide()
cancelled.flush()
assert(
	cancelled.ns.Setting("restedxpChoiceMade") and not cancelled.ns.Setting("restedxpGuide"),
	"dismissal keeps native UI without asking again"
)
local combat, _, combatPopup = fresh()
combat.SetCombat(true)
assert(
	not combatPopup:IsShown() and not combat.ns.Setting("restedxpChoiceMade"),
	"combat defers setup without making a choice"
)
combat.SetCombat(false)
combat.flush()
assert(combatPopup:IsShown(), "pending choice returns after combat")
local settings, _, settingsPopup = fresh()
settings.ns.SetSetting("restedxpGuide", true)
assert(not settingsPopup:IsShown(), "settings choice closes the pending setup immediately")
local startup = harness.load({ db = { restedxpGuide = true, restedxpChoiceMade = true }, spf = "v1" })
local engine = fixture(startup)
startup.ns.SetSetting("restedxpGuide", false)
startup.flush()
startup.ns.SetSetting("restedxpGuide", true)
assert(
	startup.G.AdventureGuideForever.API.RestedXPIntegrated() and not startup.ns.RestedXP.Active(),
	"navigation ownership is assigned before the deferred render"
)
engine.settings.profile.showEnabled = false
assert(not startup.G.AdventureGuideForever.API.RestedXPIntegrated(), "disabled RXP profiles release ownership")
for _, client in ipairs({ h, native, cancelled, combat, settings, startup }) do
	assert(#client.errors == 0, table.concat(client.errors, "\n"))
end
print("guide_setup_spec: first login, both choices, dismissal, settings and combat passed")
