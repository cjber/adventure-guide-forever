local harness = dofile("tests/harness.lua")
local h = harness.load({
	spf = "v1",
	completed = { 844 },
	log = { { id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 } },
})
h.flush()
local ns = h.ns
local chosen = ns.Prefs().journey
local before = #ns.Route().journeys
local engine = dofile("tests/rxp_fixture.lua")(h)
local guide = assert(ns.RestedXP.Journey())
assert(#ns.Route().journeys == before + 1, "the guide joins existing journey choices")
assert(ns.Prefs().journey == chosen, "adding a guide preserves the selected journey")
ns.Choose(guide.key, true)
h.flush()
assert(ns.Route().chosen and ns.Route().journey == guide.key, "the guide uses the ordinary journey selection")
assert(h.spf.NavigateRoute > 0, "SPF receives the guide target")
assert(ns.Route().steps[1].rxpIndex == 2, "the current step leads ongoing objectives")
local sent = h.spf.NavigateRoute
engine.arrowFrame.element.x = 54
engine.UpdateMap()
h.flush()
assert(h.spf.NavigateRoute > sent, "engine waypoint changes update the existing journey")
engine.arrowFrame.element = nil
engine.UpdateMap()
h.flush()
assert(not ns.Guidance.Owns(), "unlocated guide instructions cannot keep a stale route")
engine.arrowFrame.element = { zone = 1413, x = 55, y = 31, arrow = true, step = engine.currentGuide.steps[2] }
engine.UpdateMap()
h.flush()
assert(ns.Guidance.Owns(), "the chosen guide resumes when RXP supplies a destination")
-- A failed native skip in combat must not become a local AGF skip.
local currentKey = ns.Route().steps[1].key
h.combat = true
ns.Skip(currentKey, ns.Route().steps[1].title)
assert(not ns.Prefs().skipped[currentKey], "a combat-blocked RXP skip cannot hide its AGF step")
h.combat = false
-- A native chapter change keeps the chosen guide and hands SPF the new target once.
local firstGuideKey = guide.key
engine.currentGuide.name = "Example: Next chapter"
engine.currentGuide.steps[2].title = "Meet the next quartermaster"
engine.arrowFrame.element.x = 57
engine.UpdateMap()
h.flush()
local nextGuide = assert(ns.RestedXP.Journey())
assert(
	nextGuide.key ~= firstGuideKey and ns.Prefs().journey == nextGuide.key,
	"chapter changes keep the guide selected"
)
assert(ns.Prefs().guided == nextGuide.key and ns.Guidance.Owns(), "chapter changes retain native progress ownership")

-- Engine changes in combat wait, then update the current travel target on combat exit.
local beforeCombat = h.spf.NavigateRoute
h.combat = true
engine.arrowFrame.element.x = 59
engine.UpdateMap()
h.flush()
assert(h.spf.NavigateRoute == beforeCombat, "combat never starts a replacement journey")
h.combat = false
h.fire("PLAYER_REGEN_ENABLED")
h.flush()
assert(
	h.spf.NavigateRoute > beforeCombat and ns.Route().steps[1].x == 0.59,
	"combat exit applies the latest engine target"
)

ns.Stop()
h.flush()
ns.Invalidate()
h.flush()
assert(not ns.Guidance.Owns(), "Stop stays stopped across guide refreshes")
ns.Choose(chosen, true)
h.flush()
assert(ns.Route().journey == chosen, "other journeys remain selectable alongside the guide")
assert(#h.errors == 0, table.concat(h.errors, "\n"))

-- Reload while the native step has no waypoint must wait without sending invalid routes.
local group, name = "Example guides", "Example: The Barrens"
local key = "guide:" .. #group .. ":" .. group .. ":" .. #name .. ":" .. name
local restored = harness.load({
	spf = "ended",
	db = { autoStart = false },
	charDB = { journey = key, guided = key },
	setup = function(client)
		local rxp = dofile("tests/rxp_fixture.lua")(client)
		rxp.arrowFrame.element = nil
		client.spfDeclines = true
	end,
})
for _ = 1, 3 do
	restored.ns.Invalidate()
	restored.flush()
end
assert(restored.spf.NavigateRoute == 0, "restoring unlocated instructions never sends an invalid route")
assert(restored.ns.Prefs().guided == key, "reload retains guide progress while waiting for coordinates")
restored.spfDeclines = false
local rxp = restored.G.RXP
rxp.arrowFrame.element = { zone = 1413, x = 55, y = 31, arrow = true, step = rxp.currentGuide.steps[2] }
rxp.UpdateMap()
restored.flush()
assert(restored.ns.Guidance.Owns(), "restored guide resumes when the engine supplies its target")
assert(#restored.errors == 0, table.concat(restored.errors, "\n"))

print("restedxp_mode_spec: shared journeys, travel and Stop passed")

local walking = harness.load({ spf = "v1", db = { autoStart = false } })
dofile("tests/rxp_fixture.lua")(walking)
local movementGuide = assert(walking.ns.RestedXP.Journey())
local movementStep = movementGuide.steps[1]
assert(
	pcall(
		walking.ns.Model.Here,
		walking.ns.Data,
		{ map = movementStep.map, x = movementStep.x, y = movementStep.y },
		movementGuide.steps
	),
	"movement accepts guide steps without treating them as quest areas"
)

local catalogue = harness.load({ spf = "v1", player = { level = 22 }, db = { autoStart = false } })
local catalogueEngine = dofile("tests/rxp_fixture.lua")(catalogue)
local installed = {
	{ group = "Purchased guides", name = "01-06 Starting zone", steps = {} },
	{ group = "Purchased guides", name = "20-23 Current chapter", steps = {} },
	{ group = "Purchased guides", name = "23-26 Next chapter", steps = {} },
}
catalogueEngine.currentGuide, catalogueEngine.RXPFrame.activeSteps = nil, {}
catalogueEngine.guideList = { Purchased = { names_ = installed } }
catalogueEngine.GetGuideTable = function(guideGroup, guideName)
	for _, entry in ipairs(installed) do
		if entry.group == guideGroup and entry.name == guideName then
			return entry
		end
	end
end
local selected
catalogueEngine.LoadGuideTable = function(_, _guideGroup, guideName)
	selected = guideName
end
catalogueEngine.UpdateMap()
catalogue.flush()
local choices = catalogue.ns.RestedXP.Cards()
assert(#choices == 2, "past guide chapters do not crowd out suitable guides")
assert(choices[1].title == "20-23 Current chapter", "the player's current level sorts first")
assert(selected == "20-23 Current chapter", "one suitable chapter is selected automatically")
local routeCards = catalogue.ns.Route().journeys
assert(
	routeCards[1].key == choices[1].key and routeCards[1].section == "continue",
	"available guides use ordinary Continue cards"
)

local declined = harness.load({ spf = "v1", player = { level = 22 }, db = { autoStart = false } })
local dr = dofile("tests/rxp_fixture.lua")(declined)
dr.currentGuide, dr.RXPFrame.activeSteps = nil, {}
dr.guideList, dr.GetGuideTable = catalogueEngine.guideList, catalogueEngine.GetGuideTable
local unwanted
dr.LoadGuideTable = function(_, _, guideName)
	unwanted = guideName
end
declined.ns.Prefs().notInterested[choices[1].key] = "20-23 Current chapter"
dr.UpdateMap()
declined.flush()
assert(not unwanted, "auto selection respects dismissed guide cards")
catalogue.player.level = 23
local boundary = catalogue.ns.RestedXP.Cards()
assert(boundary[1].title == "23-26 Next chapter", "finished chapters do not lead at the shared level boundary")

local quest = harness.load({
	spf = "v1",
	log = {
		{
			id = 845,
			title = "The Zhevra",
			level = 13,
			complete = false,
			objectives = {
				{ type = "item", done = false, have = 0, need = 4, text = "Hooves: 0/4" },
			},
		},
	},
})
local qr = dofile("tests/rxp_fixture.lua")(quest)
qr.currentGuide.steps[2].elements[1].questId = 845
qr.currentGuide.steps[2].elements[1].tag = "complete"
qr.UpdateMap()
quest.flush()
local linked = assert(quest.ns.RestedXP.Journey()).steps[1]
assert(linked.quests[1] == 845, "RXP objectives retain their real quest ID")
assert(#linked.shapes > 0 and #linked.objectives > 0, "quest areas use the existing planner's live objective nodes")
assert(
	quest.ns.Model.Here(quest.ns.Data, linked.shapes[1], { linked }) == 1,
	"guide objectives keep existing area arrival behavior"
)
linked.preview = true
assert(
	quest.ns.Model.Here(quest.ns.Data, linked.shapes[1], { linked }) == nil,
	"future guide areas cannot count as arrival"
)
linked.preview = false
qr.currentGuide.steps[2].elements[2].questId = 845
qr.UpdateMap()
quest.flush()
local logReads, originalLog = 0, quest.ns.State.Log
quest.ns.State.Log = function()
	logReads = logReads + 1
	return originalLog()
end
local once = quest.ns.RestedXP.Journey()
quest.ns.RestedXP.Cards(once)
assert(logReads == 1, "guide cards reuse one journey and one quest log snapshot")
quest.ns.State.Log = originalLog
print("restedxp_mode_spec: guide cards, auto selection and quest areas passed")

local extras = harness.load({ spf = "v1", db = { autoStart = false } })
local er = dofile("tests/rxp_fixture.lua")(extras)
local item = extras.G.CreateFrame("Frame", nil, extras.G.UIParent)
local target = extras.G.CreateFrame("Frame", nil, extras.G.UIParent)
local icon = extras.G.CreateFrame("Button", nil, extras.G.UIParent)
for _, frame in ipairs({ item, target, icon }) do
	frame:SetPoint("CENTER", extras.G.UIParent, "CENTER", 12, 18)
	frame:SetAlpha(0.8)
end
er.activeItemFrame, er.targeting = item, { activeTargetFrame = target }
extras.G.LibDBIcon10_RXPGuides = icon
er.UpdateMap()
extras.flush()
for _, frame in ipairs({ item, target, icon }) do
	assert(frame:GetAlpha() == 0, "RXP auxiliary UI is suppressed by default")
end
extras.ns.SetSetting("restedxpGuide", false)
extras.flush()
for _, frame in ipairs({ item, target, icon }) do
	assert(frame:GetAlpha() == 0.8, "turning off integration restores auxiliary UI")
	local point, _, _, x, y = frame:GetPoint()
	assert(point == "CENTER" and x == 12 and y == 18, "auxiliary anchors are restored")
end
print("restedxp_mode_spec: auxiliary UI suppression and restoration passed")

local maps = harness.load({ spf = "v1", db = { autoStart = false } })
local mr = dofile("tests/rxp_fixture.lua")(maps)
local canvas = maps.G.CreateFrame("Frame", nil, maps.G.UIParent)
maps.G.WorldMapFrame.GetCanvas = function()
	return canvas
end
local ownLine = maps.G.CreateFrame("Frame", nil, canvas)
ownLine.lineData = { element = { step = mr.currentGuide.steps[2] } }
ownLine:SetAlpha(0.7)
ownLine:EnableMouse(true)
local otherLine = maps.G.CreateFrame("Frame", nil, canvas)
otherLine.lineData = { element = { step = { index = 2 } } }
otherLine:SetAlpha(0.6)
local removedWorld, removedMini, addedMini
maps.G.LibStub = {
	GetLibrary = function()
		return {
			RemoveAllWorldMapIcons = function(_, owner)
				removedWorld = owner
			end,
			RemoveAllMinimapIcons = function(_, owner)
				removedMini = owner
			end,
			AddMinimapIconMap = function(_, owner, iconFrame, map, x, y)
				addedMini = { owner = owner, icon = iconFrame, map = map, x = x, y = y }
			end,
		}
	end,
}
local waypoint = mr.activeWaypoints[1]
mr.UpdateMap()
maps.flush()
assert(removedWorld == mr and removedMini == mr, "map suppression removes only RXP-owned markers")
assert(ownLine:GetAlpha() == 0 and otherLine:GetAlpha() == 0.6, "only verified RXP guide lines are suppressed")
assert(not ownLine:IsMouseEnabled(), "suppressed RXP lines cannot intercept map clicks")
assert(mr.activeWaypoints[1] == waypoint, "map suppression preserves the navigation engine's waypoints")
maps.ns.Pins.Refresh()
maps.ns.SetSetting("showMapPins", true)
maps.ns.Pins.Refresh()
assert(addedMini and addedMini.map == 1413, "AGF registers the guide destination on the minimap")
maps.ns.SetSetting("restedxpGuide", false)
maps.flush()
assert(ownLine:IsMouseEnabled(), "native line mouse input is restored")
assert(ownLine:GetAlpha() == 0.7, "turning off integration restores native line presentation")
print("restedxp_mode_spec: native map suppression preserves ownership and waypoints")
