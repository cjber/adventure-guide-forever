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
assert(h.G.AdventureGuideForever.API.ResumeRestedXP(), "the companion can request the active guide")
h.flush()
assert(ns.Route().journey == nextGuide.key and ns.Guidance.Owns(), "resume selects and navigates the active RXP guide")
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
for _, frame in ipairs({ item, target }) do
	assert(frame:GetAlpha() == 0.8, "RXP item and target controls retain their visibility")
	local point, _, _, x, y = frame:GetPoint()
	assert(point == "CENTER" and x == 12 and y == 18, "RXP action controls retain their anchors")
end
assert(icon:GetAlpha() == 0, "the redundant RXP minimap button stays suppressed")
item:Hide()
target:Hide()
er.UpdateMap()
extras.flush()
assert(not item:IsShown() and not target:IsShown(), "integration respects controls hidden by RestedXP")
extras.ns.SetSetting("restedxpGuide", false)
extras.flush()
for _, frame in ipairs({ item, target, icon }) do
	assert(frame:GetAlpha() == 0.8, "turning off integration restores auxiliary UI")
	local point, _, _, x, y = frame:GetPoint()
	assert(point == "CENTER" and x == 12 and y == 18, "auxiliary anchors are restored")
end
print("restedxp_mode_spec: action controls remain available and the minimap button restores")

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
-- RXP's explicit .ingamewaypoint instruction can replace the native user waypoint.
for _, integrated in ipairs({ true, false }) do
	local native = harness.load({ db = { autoStart = false } })
	local nativeEngine = dofile("tests/rxp_fixture.lua")(native)
	native.ns.SetSetting("restedxpGuide", integrated)
	native.flush()
	local destination = { map = 1413, x = 0.5, y = 0.4, title = "Guide destination" }
	assert(native.ns.Guidance.Navigate(destination), "Go can set a native waypoint with RXP installed")
	assert(native.ns.Guidance.Owns(), "Go owns its newly set waypoint")
	local replacement = native.G.UiMapPoint.CreateFromCoordinates(1413, 0.3, 0.6)
	native.G.C_Map.SetUserWaypoint(replacement)
	local sets, clears = native.counts.SetUserWaypoint, native.counts.ClearUserWaypoint
	native.fire("USER_WAYPOINT_UPDATED")
	nativeEngine.UpdateMap()
	native.flush()
	assert(not native.ns.Guidance.Owns(), "a waypoint moved by RXP is no longer owned by the guide")
	assert(native.ns.Prefs().waypoint == nil, "the replaced waypoint is forgotten")
	native.ns.Stop()
	native.flush()
	assert(native.G.C_Map.GetUserWaypoint() == replacement, "Stop preserves RXP's replacement waypoint")
	assert(native.counts.SetUserWaypoint == sets, "refresh does not fight a replacement waypoint")
	assert(native.counts.ClearUserWaypoint == clears, "Stop does not clear another addon's waypoint")
	assert(#native.errors == 0, table.concat(native.errors, "\n"))
end

-- Native Unfocus leaves the pin in place but ends navigation to it.
for _, integrated in ipairs({ true, false }) do
	local native = harness.load({ db = { autoStart = false } })
	dofile("tests/rxp_fixture.lua")(native)
	native.ns.SetSetting("restedxpGuide", integrated)
	native.flush()
	assert(native.ns.Guidance.Navigate({ map = 1413, x = 0.5, y = 0.4, title = "Guide destination" }))
	local point = native.G.C_Map.GetUserWaypoint()
	native.G.C_SuperTrack.SetSuperTrackedUserWaypoint(false)
	native.G.C_SuperTrack.SetSuperTrackedQuestID(845)
	native.fire("SUPER_TRACKING_CHANGED")
	native.flush()
	assert(not native.ns.Guidance.Owns(), "unfocused waypoint no longer counts as running guidance")
	assert(native.ns.Prefs().waypoint == nil, "unfocused waypoint ownership is forgotten")
	local sets, clears = native.counts.SetUserWaypoint, native.counts.ClearUserWaypoint
	native.ns.Stop()
	native.flush()
	assert(native.G.C_Map.GetUserWaypoint() == point, "Stop preserves the pin the player unfocused")
	assert(native.G.C_SuperTrack.GetSuperTrackedQuestID() == 845, "Stop preserves the replacement quest focus")
	assert(not native.G.C_SuperTrack.IsSuperTrackingUserWaypoint(), "refresh never takes focus back")
	assert(native.counts.SetUserWaypoint == sets and native.counts.ClearUserWaypoint == clears)
	assert(#native.errors == 0, table.concat(native.errors, "\n"))
end

-- Automatic objective highlighting must retain navigation, whether the client
-- changes waypoint focus as a side effect of selecting a quest or not.
for _, exclusive in ipairs({ true, false }) do
	local native = harness.load({ db = { autoStart = false, followQuest = true } })
	local prefs = native.ns.Prefs()
	local step = {
		key = "area:845",
		title = "Quest objectives",
		map = 1413,
		x = 0.5,
		y = 0.4,
		here = true,
		objectives = { { id = 845 } },
		quests = { 845 },
		handins = {},
	}
	local route = native.ns.Route()
	route.chosen, route.steps = true, { step }
	native.ns.Snapshot().log[845] = { complete = false }
	local selectQuest = native.G.C_SuperTrack.SetSuperTrackedQuestID
	native.G.C_SuperTrack.SetSuperTrackedQuestID = function(id)
		selectQuest(id)
		if exclusive then
			native.G.C_SuperTrack.SetSuperTrackedUserWaypoint(false)
		end
	end
	assert(native.ns.Guidance.Navigate(step))
	native.ns.Focus.Sync()
	assert(prefs.focus == 845, "arrival selects the quest for objective highlighting")
	assert(native.G.C_SuperTrack.IsSuperTrackingUserWaypoint(), "own quest focus preserves waypoint navigation")
	assert(native.ns.Guidance.Owns(), "own quest focus does not discard the route's waypoint")
	step.here = false
	native.ns.Focus.Sync()
	assert(prefs.focus == nil, "leaving the objective clears the guide's quest highlight")
	assert(native.G.C_SuperTrack.IsSuperTrackingUserWaypoint(), "clearing own quest focus preserves navigation")
	assert(native.ns.Guidance.Owns(), "waypoint ownership survives leaving an objective")
	local point = native.G.C_Map.GetUserWaypoint()
	native.G.C_SuperTrack.SetSuperTrackedUserWaypoint(false)
	step.here = true
	native.ns.Focus.Sync()
	assert(
		not native.G.C_SuperTrack.IsSuperTrackingUserWaypoint(),
		"objective highlighting never refocuses an unfocused pin"
	)
	assert(native.G.C_Map.GetUserWaypoint() == point, "objective highlighting leaves the pin in place")
	assert(#native.errors == 0, table.concat(native.errors, "\n"))
end

for _, hidden in ipairs({ true, false }) do
	local native = harness.load({ db = { autoStart = false } })
	local nativeEngine = dofile("tests/rxp_fixture.lua")(native)
	native.ns.SetSetting("restedxpGuide", false)
	native.flush()
	local arrow = nativeEngine.arrowFrame
	nativeEngine.settings.profile.disableArrow = hidden
	arrow:SetAlpha(0.65)
	arrow:SetPoint("CENTER", native.G.UIParent, "CENTER", 24, 36)
	arrow:SetShown(not hidden)
	native.ns.SetSetting("restedxpGuide", true)
	native.flush()
	assert(arrow:GetAlpha() == 0.65, "RXP's arrow points the way to the guide's step")
	assert(arrow:IsShown() == not hidden, "the guide keeps RXP's own arrow preference")
	local point, _, _, x, y = arrow:GetPoint()
	assert(point == "CENTER" and x == 24 and y == 36, "RXP's arrow stays where the player put it")
	-- Another journey chosen: RXP's arrow would point away from the route being followed.
	native.ns.Choose("quest:845")
	native.flush()
	assert(arrow:GetAlpha() == 0, "another chosen journey hides RXP's arrow")
	native.ns.Choose(assert(native.ns.RestedXP.Journey()).key)
	native.flush()
	assert(arrow:GetAlpha() == 0.65, "choosing the guide again brings RXP's arrow back")
	native.ns.Choose("quest:845")
	native.flush()
	native.ns.SetSetting("restedxpGuide", false)
	native.flush()
	assert(arrow:GetAlpha() == 0.65, "returning to RXP restores its arrow alpha")
	assert(arrow:IsShown() == not hidden, "returning to RXP preserves the player's hidden-arrow choice")
	assert(nativeEngine.settings.profile.disableArrow == hidden, "integration never writes RXP's arrow preference")
	point, _, _, x, y = arrow:GetPoint()
	assert(point == "CENTER" and x == 24 and y == 36, "returning to RXP restores its arrow position")
	assert(#native.errors == 0, table.concat(native.errors, "\n"))
end
print("restedxp_mode_spec: map suppression, native waypoint ownership and arrow preferences passed")

-- Skip for now, from the step menu, on every step it offers: the current step, one still ahead, and in combat.
local skipping = harness.load({ spf = "v1", db = { autoStart = false } })
local se = dofile("tests/rxp_fixture.lua")(skipping, 3)
local function Key(index)
	return assert(skipping.ns.RestedXP.Journey()).key .. ":step:" .. index
end
local function Shown(index)
	for _, row in ipairs(skipping.ns.RestedXP.Snapshot().steps) do
		if row.index == index then
			return true
		end
	end
	return false
end
assert(Shown(4), "the guide previews the steps ahead")
skipping.ns.Skip(Key(4), "Continue the journey 2")
skipping.flush()
assert(se.currentGuide.steps[4].completed, "a step ahead is skipped the way RXP skips its own")
assert(se.GetGuideProgress() == 2 and not Shown(4), "skipping a step ahead leaves the current step and drops the row")
skipping.combat = true
skipping.ns.Skip(Key(2), "Speak with the quartermaster")
skipping.flush()
assert(se.GetGuideProgress() == 2, "RXP's step waits for combat's end")
skipping.combat = false
skipping.fire("PLAYER_REGEN_ENABLED")
skipping.flush()
assert(se.GetGuideProgress() == 3, "a skip asked for in combat is made once it ends")
assert(not skipping.ns.Prefs().skipped[Key(2)], "a guide step is skipped in RXP, never as a local skip")
assert(#skipping.errors == 0, table.concat(skipping.errors, "\n"))
print("restedxp_mode_spec: Skip for now on current, upcoming and in-combat steps passed")
