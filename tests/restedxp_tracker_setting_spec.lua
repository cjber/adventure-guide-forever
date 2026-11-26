local h = dofile("tests/harness.lua").load({ spf = "v1", db = { autoStart = false, showMapPins = true } })
local ns, G = h.ns, h.G
local key = "restedxpShowTracker"
local v2, icon, item, target, canvas
local fire = h.fire
h.fire = function(event, addon)
	if event == "ADDON_LOADED" and addon == "RXPGuides" then
		local engine = G.RXP
		v2 = G.CreateFrame("Frame", nil, G.UIParent)
		icon = G.CreateFrame("Button", nil, G.UIParent)
		item = G.CreateFrame("Frame", nil, G.UIParent)
		target = G.CreateFrame("Frame", nil, G.UIParent)
		canvas = G.CreateFrame("Frame", nil, G.UIParent)
		engine.v2.state = { guideWindow = { frame = v2 } }
		engine.v2.UpdateGuideWindow = function() end
		engine.activeItemFrame, engine.targeting = item, { activeTargetFrame = target }
		G.LibDBIcon10_RXPGuides = icon
		for _, frame in ipairs({ engine.RXPFrame, v2 }) do
			frame.SetClampedToScreen = function(self, clamped)
				self.clamped = clamped
			end
			frame:SetAlpha(0.8)
			frame:SetPoint("CENTER", G.UIParent, "CENTER", 12, 18)
			frame:SetClampedToScreen(true)
			frame.savePosition = true
		end
	end
	fire(event, addon)
end
local engine = dofile("tests/rxp_fixture.lua")(h, 1)
h.fire = fire
local main, arrow = engine.RXPFrame, engine.arrowFrame
local guide = assert(ns.RestedXP.Journey())
ns.Choose(guide.key, true)
ns.RXPActions.Shown = function()
	return true
end
G.WorldMapFrame.GetCanvas = function()
	return canvas
end
local line = G.CreateFrame("Frame", nil, canvas)
line.lineData = { element = { step = engine.currentGuide.steps[2] } }
line:EnableMouse(true)
engine.UpdateMap()
h.flush()
assert(main:GetAlpha() == 0 and v2:GetAlpha() == 0, "the tracker is suppressed by default")

local function Restored(frame, x)
	local point, parent, relative, offsetX, offsetY = frame:GetPoint()
	assert(frame:GetAlpha() == 0.8, "the RestedXP guide window is visible")
	assert(point == "CENTER" and parent == G.UIParent and relative == "CENTER" and offsetX == x and offsetY == 18)
	assert(frame:IsClampedToScreen() and frame.savePosition and not frame:GetDontSavePosition())
end

ns.SetSetting(key, true)
h.flush()
Restored(main, 12)
Restored(v2, 12)
assert(ns.RestedXP.Active() and ns.Setting("restedxpGuide"), "the integration stays active")
assert(ns.Route().journey == guide.key and ns.Route().steps[1].rxpIndex == 2 and ns.Guidance.Owns())
assert(icon:GetAlpha() == 0 and arrow:GetAlpha() == 0, "minimap button and redundant arrow remain suppressed")
assert(line:GetAlpha() == 0 and not line:IsMouseEnabled(), "RestedXP map lines remain suppressed")
assert(not item:IsShown() and not target:IsShown(), "AGF continues to own the displayed action controls")

engine.v2.UpdateGuideWindow()
h.flush()
Restored(v2, 12)
engine.SetStep(3)
engine.RXPFrame.activeSteps = { engine.currentGuide.steps[3] }
engine.currentGuide.steps[3].active = true
engine.arrowFrame.element = engine.currentGuide.steps[3].elements[1]
engine.UpdateMap()
h.flush()
assert(ns.Route().steps[1].rxpIndex == 3, "Adventure Guide follows RestedXP progress while both trackers show")

local function Entry(root, text)
	for _, entry in ipairs(root.entries) do
		if entry.text == text then
			return entry
		end
	end
	error("missing menu entry " .. text)
end
local function TrackerCheckbox(root)
	local entry = Entry(Entry(root, ns.L.RXP_TITLE), ns.L.SETTING_RXP_SHOW_TRACKER)
	assert(entry.kind == "checkbox" and entry.isSelected())
	return entry
end
local function Menu(generator)
	G.ForeverCore.ContextMenu(G.UIParent, generator)
	return h.menu
end
TrackerCheckbox(Menu(ns.Menu.Settings))
ns.Menu.Journey(G.UIParent, guide)
TrackerCheckbox(h.menu)
local checkbox = TrackerCheckbox(Menu(function(_, root)
	ns.Menu.Step(root, ns.Route().steps[1])
end))

v2:SetPoint("CENTER", G.UIParent, "CENTER", 24, 18)
h.combat = true
checkbox.onClick()
h.flush()
Restored(v2, 24)
h.combat = false
h.fire("PLAYER_REGEN_ENABLED")
h.flush()
assert(main:GetAlpha() == 0 and v2:GetAlpha() == 0 and not checkbox.isSelected())

local setting
for _, candidate in ipairs(h.addonSettings) do
	if candidate.key == key then
		setting = candidate
	end
end
assert(ns.DEFAULTS[key] == false, "new and existing saves start with the original suppression behaviour")
assert(setting, "the AddOns settings page registers the same setting"):SetValue(true)
h.flush()
Restored(main, 12)
Restored(v2, 24)
assert(checkbox.isSelected(), "the settings row and menu share the saved value")
assert(#h.errors == 0, table.concat(h.errors, "\n"))
print("restedxp_tracker_setting_spec: passed")
