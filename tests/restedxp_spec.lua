local harness = dofile("tests/harness.lua")
local startup = harness.load({
	db = { restedxpChoiceMade = true },
	spf = "v1",
	completed = { 844 },
	log = { { id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 } },
	setup = function(client)
		local root = client.G.CreateFrame("Frame", nil, client.G.UIParent)
		root.activeSteps = {}
		client.G.RXP = {
			RXPFrame = root,
			currentGuide = { empty = true },
			SetStep = function() end,
			GetGuideProgress = function()
				return 1
			end,
			settings = { profile = { showEnabled = true } },
		}
		client.fire("ADDON_LOADED", "RXPGuides")
	end,
})
-- Root handles whether AGF auto-starts when a guide source is active; the adapter only controls its own state.
assert(startup.ns.RestedXP.Active(), "the installed engine owns the initial source")
local h = harness.load({ db = { restedxpGuide = true, restedxpChoiceMade = true, autoStart = false } })
local ns, G = h.ns, h.G
local frame = G.CreateFrame("Frame", nil, G.UIParent)
frame:SetPoint("TOPLEFT", G.UIParent, "TOPLEFT", 25, -40)
frame:SetAlpha(0.7)
frame:Show()
frame.SetClampedToScreen = function(self, value)
	self.clamped = value
end
frame:SetClampedToScreen(true)
local child = G.CreateFrame("Frame", nil, frame)
child.SetClampedToScreen = frame.SetClampedToScreen
child:SetClampedToScreen(true)
local completed, stepIndex, loaded = 0, 2, nil
local step = {
	index = 2,
	active = true,
	title = "Current step",
	elements = {
		{ text = "Hidden", hidden = true },
		{
			text = "|cFF00FF00Collect apples|r: 3/10",
			OnComplete = function()
				completed = completed + 1
			end,
		},
		{ text = "Travel to town", textOnly = true, completed = true },
	},
}
local guide = { name = "Test guide", group = "Test group", steps = { { index = 1 }, step } }
for index = 3, 14 do
	guide.steps[index] = {
		index = index,
		title = "Future step " .. index,
		elements = { { text = "Future instruction " .. index, arrow = true, zone = 1413, x = index, y = 40 } },
	}
end
frame.activeSteps = { step }
frame.CurrentStepFrame = G.CreateFrame("Frame", nil, frame)
frame.CurrentStepFrame.UpdateText = function() end
local messages = {}
G.RXPCData = { stepSkip = {} }
G.RXP = {
	RXPFrame = frame,
	currentGuide = guide,
	GetGuideProgress = function()
		return stepIndex, "step-id"
	end,
	SetStep = function(index)
		stepIndex = index
	end,
	UpdateMap = function() end,
	settings = { profile = { showEnabled = true }, OpenSettings = function() end },
	RegisterMessage = function(receiver, name, callback)
		assert(receiver ~= G.RXP, "AGF must not overwrite RXP's handlers")
		messages[name] = callback
	end,
	guideList = { Test = { names_ = { { name = guide.name, group = guide.group } } } },
	GetGuideTable = function(group, name)
		if group == guide.group and name == guide.name then
			return guide
		end
	end,
	IsGuideActive = function()
		return true
	end,
	LoadGuideTable = function(_, group, name)
		loaded = group .. name
	end,
}
h.fire("ADDON_LOADED", "RXPGuides")
h.fire("PLAYER_ENTERING_WORLD")
h.flush()
-- RXP can load after AGF; the world event queues a fresh lookup and source switch.
ns.RestedXP.Refresh()
h.flush()
assert(messages.RXP_GUIDE_LOADED and messages.RXPGuidesV2_UpdateActiveSteps, "callbacks use the shared AceEvent bus")
assert(ns.RestedXP.Active(), "installed RXP is enabled by default")
assert(frame:IsShown() and frame:GetAlpha() == 0, "suppression preserves engine frame visibility")
assert(
	not frame:IsClampedToScreen() and not child:IsClampedToScreen(),
	"invisible native children cannot clamp onto the screen"
)
assert(
	frame.savePosition == false and frame:GetDontSavePosition(),
	"neither RXP nor the client may persist suppressed anchors"
)
local shown = ns.RestedXP.Snapshot()
assert(shown.index == 2 and shown.total == 14 and #shown.steps[1].lines == 2)
assert(shown.steps[1].lines[1].text == "Collect apples: 3/10")
assert(shown.steps[1].lines[1].elementIndex == 2, "hidden elements retain original indices")
assert(not shown.steps[1].lines[2].done, "text-only instructions are not completed objectives")
assert(shown.steps[1].lines[2].elementIndex == nil, "text instructions cannot be skipped as objectives")
assert(#shown.steps == 10, "the native guide preview is bounded to about ten rows")
assert(shown.steps[2].preview and shown.steps[2].index == 3, "future rows are read-only preview rows")
assert(shown.steps[2].map == 1413 and shown.steps[2].x == 0.03, "future preview rows expose known map coordinates")
step.elements[2].text = "Collect apples: 4/10"
frame.CurrentStepFrame.UpdateText()
h.flush()
assert(
	ns.RestedXP.Snapshot().steps[1].lines[1].text == "Collect apples: 4/10",
	"legacy progress refreshes without a quest event"
)
assert(ns.RestedXP.Skip(2, 2) and step.elements[2].skip and completed == 1)
assert(not ns.RestedXP.Skip(2, 3))
assert(ns.RestedXP.Skip(2) and stepIndex == 3, "skipping a main step advances the guide")
step.sticky = true
stepIndex = 2
assert(ns.RestedXP.Skip(2) and G.RXPCData.stepSkip[2] and stepIndex == 2, "skipping a sticky step keeps the main step")
assert(ns.RestedXP.Move(-1) and stepIndex == 1)
assert(ns.RestedXP.Select(guide.group, guide.name) and loaded == guide.group .. guide.name)
assert(not ns.RestedXP.Select("wrong", guide.name))
h.combat = true
assert(not ns.RestedXP.Move(1), "guide controls wait until combat ends")
ns.SetSetting("restedxpGuide", false)
h.flush()
assert(ns.RestedXP.Active(), "presentation waits until combat ends")
h.combat = false
h.fire("PLAYER_REGEN_ENABLED")
h.flush()
assert(not ns.RestedXP.Active() and frame:IsShown() and frame:GetAlpha() == 0.7)
assert(frame:IsClampedToScreen() and child:IsClampedToScreen(), "screen clamping is restored on all native descendants")
assert(frame.savePosition == nil and not frame:GetDontSavePosition(), "native position persistence is restored")
local point, parent, relative, px, py = frame:GetPoint(1)
assert(point == "TOPLEFT" and parent == G.UIParent and relative == "TOPLEFT" and px == 25 and py == -40)
assert(G.RXP.settings.profile.showEnabled, "restoring does not change the engine profile")
ns.SetSetting("restedxpGuide", true)
h.flush()
G.RXP.settings.profile.showEnabled = false
frame:Hide()
messages.RXPGuidesV2_GuideWindowRefresh("RXPGuidesV2_GuideWindowRefresh", "visibility", false)
h.flush()
assert(not ns.RestedXP.Active() and not frame:IsShown(), "a native RXP disable stays disabled")
assert(G.RXP.settings.profile.showEnabled == false, "restoration respects the player's new native settings")

-- Journey and SkipKey tests
-- Re-enable and reset state for Journey/SkipKey tests.
G.RXP.settings.profile.showEnabled = true
step.sticky = false
step.active = true
step.elements[2].skip = nil
step.elements[2].text = "|cFF00FF00Collect apples|r: 3/10"
stepIndex = 2
ns.SetSetting("restedxpGuide", true)
h.flush()
ns.RestedXP.Refresh()
h.flush()

-- Stable guide key encodes group and name with length prefixes.
local guideKey = "guide:10:Test group:10:Test guide"

-- Journey with no arrowFrame: all coordinates unknown, map=0.
assert(G.RXP.arrowFrame == nil, "arrowFrame absent in base engine setup")
local journey = ns.RestedXP.Journey()
assert(journey ~= nil, "Journey returns a journey when active with a loaded guide")
assert(journey.key == guideKey, "journey key is stable: length-prefixed group and name, not current step")
assert(journey.kind == "guide", "journey kind is guide")
assert(journey.section == "continue", "guide journey appears in the continue section")
assert(journey.title == guide.name, "journey title is the guide name")
assert(journey.map == 1413, "journey map follows the first known preview waypoint")
assert(#journey.steps == 10, "journey has the current step plus a bounded future preview")
local jstep = journey.steps[1]
assert(jstep.key == guideKey .. ":step:2", "step key is stable: guide key plus step index")
assert(jstep.kind == "guide", "guide instructions are not unshaped quest areas")
assert(jstep.rxpIndex == 2, "rxpIndex carries the RXP step index")
assert(jstep.rxpGuide == guide.name, "rxpGuide carries the guide name")
assert(jstep.map == 0 and jstep.x == 0 and jstep.y == 0, "unknown waypoint yields map=0 x=0 y=0")
assert(jstep.quests and #jstep.quests == 0, "step quests is an empty list for RXP steps")
assert(jstep.checklist and #jstep.checklist == 2, "checklist has one item per visible instruction")
assert(jstep.checklist[1].key == jstep.key .. ":elem:2", "checklist item key uses elementIndex when available")
assert(jstep.checklist[2].key == jstep.key .. ":line:2", "text-only instruction uses line index in key")
assert(not jstep.checklist[1].done, "non-completed instruction is not done")

-- Journey with a known arrowFrame element: coordinates appear in the matching non-sticky step.
G.RXP.arrowFrame = { element = { zone = 1413, x = 52.23, y = 31.01, arrow = true, step = step } }
G.RXP.activeWaypoints = { {} }
ns.RestedXP.Refresh()
h.flush()
local journey2 = ns.RestedXP.Journey()
assert(journey2 ~= nil, "Journey still returns a journey with arrowFrame set")
local jstep2 = journey2.steps[1]
assert(jstep2.map == 1413, "step map comes from arrowFrame element zone")
assert(math.abs(jstep2.x - 0.5223) < 0.0001, "arrowFrame x percentage converts to 0-1 fraction")
assert(math.abs(jstep2.y - 0.3101) < 0.0001, "arrowFrame y percentage converts to 0-1 fraction")
assert(journey2.map == 1413, "journey map comes from first step with a real waypoint")
assert(journey2.key == guideKey, "journey key is the same regardless of waypoint presence")

-- Completed, generated and invalid native targets cannot produce AGF pins or travel.
local arrow = G.RXP.arrowFrame.element
for _, change in ipairs({
	{ generated = 1 },
	{ completed = true, text = "Completed objective" },
	{ parent = { completed = true } },
	{ x = 101 },
	{ x = 0 / 0 },
}) do
	local previous = {}
	for key, value in pairs(change) do
		previous[key] = arrow[key]
		arrow[key] = value
	end
	ns.RestedXP.Refresh()
	h.flush()
	assert(ns.RestedXP.Journey().steps[1].map == 0, "an ineligible native waypoint remains unlocated")
	for key in pairs(change) do
		arrow[key] = previous[key]
	end
end
ns.RestedXP.Refresh()
h.flush()

-- Stable key is unchanged when the current step index advances.
stepIndex = 1
ns.RestedXP.Refresh()
h.flush()
local journey3 = ns.RestedXP.Journey()
assert(journey3 and journey3.key == guideKey, "journey key does not include the current step index")

-- Snapshot waypoint changes trigger OnChange callbacks.
local waypointChanges = 0
ns.RestedXP.OnChange(function()
	waypointChanges = waypointChanges + 1
end)
stepIndex = 2
G.RXP.arrowFrame.element.x = 60
ns.RestedXP.Refresh()
h.flush()
assert(waypointChanges > 0, "changing arrowFrame coordinates triggers snapshot callbacks")
local beforeChange = waypointChanges
G.RXP.arrowFrame.element.x = 60 -- same value: no new callback
ns.RestedXP.Refresh()
h.flush()
assert(waypointChanges == beforeChange, "identical coordinates do not trigger spurious callbacks")

-- SkipKey: exact match on both guide key and step key consumes the skip.
step.sticky = false
step.active = true
stepIndex = 2
ns.RestedXP.Refresh()
h.flush()
assert(ns.RestedXP.SkipKey(guideKey .. ":step:2"), "SkipKey accepts exact guide key and active step key")
assert(stepIndex == 3, "SkipKey delegates to Skip which advances a non-sticky step")

-- SkipKey rejects a checklist item key (non-exact suffix).
stepIndex = 2
step.active = true
assert(
	not ns.RestedXP.SkipKey(guideKey .. ":step:2:elem:2"),
	"SkipKey rejects a checklist item key with trailing suffix"
)

-- SkipKey rejects a key for a different guide.
assert(
	not ns.RestedXP.SkipKey("guide:8:NotThisGroup:10:Test guide:step:2"),
	"SkipKey rejects a key whose guide prefix does not match the current guide"
)

-- SkipKey rejects a step that is not in the guide.
assert(not ns.RestedXP.SkipKey(guideKey .. ":step:99"), "SkipKey rejects a step index not present in the guide")

-- SkipKey rejects when the guide source is inactive.
ns.SetSetting("restedxpGuide", false)
h.flush()
assert(ns.RestedXP.Journey() == nil, "Journey returns nil when the guide source is inactive")
assert(not ns.RestedXP.SkipKey(guideKey .. ":step:2"), "SkipKey returns false when the guide source is inactive")

assert(#h.errors == 0, table.concat(h.errors, "\n"))
print("restedxp_spec: engine controls, filtered elements, combat, restoration, Journey and SkipKey passed")
