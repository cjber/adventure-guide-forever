-- Run from the repository root: luajit tests/quest_pins_spec.lua
-- The game's own quest pins and the guide's numbered stops (#468): while a stop is drawn on the world map, the game's
-- pin for each quest that stop marks is hidden, so the stop reads once. A stop the player stands in draws no marker,
-- so its pin stays; quests outside the journey keep theirs; a pin we did not hide is never shown by us; and a provider
-- refresh that re-shows a pin is followed in the same frame by hiding it again (#718).
local harness = dofile("tests/harness.lua")
local h = harness.load({ db = { autoStart = false } })
h.flush()

local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local ns = h.ns
local MAP, OTHER = 1413, 1414

-- The guide is open and previewing a journey, which is what draws its numbered stops on the map.
ns.PanelShown = function()
	return true
end

-- A route is a snapshot the planner replaces, never a table a caller edits: a new one is a new table, as Core commits
-- it, so the pin pass can tell its marked quests have moved by the table's identity alone.
local route
local function SetSteps(...)
	route = { steps = { ... }, journeys = {}, chosen = false }
end
ns.Route = function()
	return route
end

local function AddStep(fields)
	local step = { map = MAP, x = 0.4, y = 0.4, kind = "area", title = "Step", quests = {}, key = "area:1:1" }
	for key, value in pairs(fields) do
		step[key] = value
	end
	return step
end

local numbered = AddStep({ key = "area:101:1", quests = { 101, 201 }, rxpIndex = 1 })
local elsewhere = AddStep({ key = "area:301:1", map = OTHER, quests = { 301 } })
local here = AddStep({ key = "area:401:1", quests = { 401 }, here = true })
SetSteps(numbered, elsewhere, here)

-- The game's own pins, as its quest data provider would have acquired them: three the stops mark, one for a step on
-- another map, one no stop marks, and one another addon had already hidden.
local pin101 = h.AddQuestPin(101)
local pin201 = h.AddQuestPin(201)
local pin401 = h.AddQuestPin(401)
local pin301 = h.AddQuestPin(301)
local pin999 = h.AddQuestPin(999)
local foreign = h.AddQuestPin(500, false)

h.G.C_Map.OpenWorldMap()
h.flush()
h.map:SetMapID(MAP)
h.flush()
ns.Pins.Refresh()

equal(pin101:IsShown(), false, "a numbered stop hides its quest's game pin")
equal(pin201:IsShown(), false, "every quest at that stop is hidden")
equal(pin401:IsShown(), true, "a stop the player stands in draws no marker, so its pin stays")
equal(pin301:IsShown(), true, "a step on another map marks nothing here")
equal(pin999:IsShown(), true, "a quest outside the journey keeps its pin")
equal(foreign:IsShown(), false, "a pin hidden by someone else stays hidden")

-- #764: the setting keeps the game's own quest markers and areas beside the route's pins, on by default.
ns.SetSetting("hideQuestMarkers", false)
h.flush()
equal(pin101:IsShown(), true, "with the setting off, a numbered stop hides nothing")
equal(pin201:IsShown(), true, "every quest at it keeps its pin")
equal(pin301:IsShown(), true, "a step on another map still marks nothing here")
equal(foreign:IsShown(), false, "and a pin hidden by another addon stays hidden")
ns.SetSetting("hideQuestMarkers", true)
h.flush()
equal(pin101:IsShown(), false, "the setting on hides the stop's pins again")
equal(pin201:IsShown(), false, "every quest at it")

-- The rings go with the wanderer setting: the pins we hid come back, the one we did not hide stays as it was.
ns.SetSetting("wanderer", true)
ns.Pins.Refresh()
equal(pin101:IsShown(), true, "wanderer mode restores a hidden pin")
equal(pin201:IsShown(), true, "every pin we hid comes back")
equal(foreign:IsShown(), false, "and the pin we did not hide stays hidden")

-- The journey rings again: the same pins hide once more.
ns.SetSetting("wanderer", false)
ns.Pins.Refresh()
equal(pin101:IsShown(), false, "the stops hide their pins again")
equal(pin201:IsShown(), false, "all of them")

-- An empty route shows no numbered stops, so nothing is marked.
SetSteps()
ns.Pins.Refresh()
equal(pin101:IsShown(), true, "an empty route restores the pins")
equal(pin201:IsShown(), true, "both of them")
equal(foreign:IsShown(), false, "and still leaves the other addon's pin alone")

-- The addon's own handler for a quest event, drawing in the event's frame the way its map show callback and a route
-- commit do: it calls Pins.Refresh, and Draw runs the pass over the pins the provider has not replaced yet. Made before
-- the provider's frame, as the addon's frames are, so in one dispatch it draws before the provider's refresh.
local drawOnEvent = h.G.CreateFrame("Frame")
drawOnEvent:RegisterEvent("QUEST_POI_UPDATE")
drawOnEvent:SetScript("OnEvent", function()
	ns.Pins.Refresh()
end)

-- The provider's own frame, made after the addon's: on its events ours hears each one first and this frame, as the
-- provider registered in the map's OnShow, then re-acquires and re-shows every pin.
local provider = h.G.CreateFrame("Frame")
provider:RegisterEvent("QUEST_LOG_UPDATE")
provider:RegisterEvent("QUEST_POI_UPDATE")
provider:SetScript("OnEvent", function()
	for _, pin in ipairs({ pin101, pin201, pin301, pin401, pin999 }) do
		pin:Show()
	end
end)

-- Our frame's OnUpdate is the one the pass runs from: the map canvas's own host frame has the map as its parent.
local function PassFrame()
	local found
	for _, frame in ipairs(h.frames) do
		if frame.parent == nil and frame.scripts and frame.scripts.OnUpdate then
			assert(found == nil, "more than one parentless OnUpdate frame")
			found = frame
		end
	end
	return assert(found, "the pin pass frame")
end
local pass = PassFrame()

-- The pin pass's event frame: the provider's events, on a frame of its own, all in one handler.
local function PinEvents()
	for _, frame in ipairs(h.frames) do
		local events = frame.events
		if
			frame.parent == nil
			and frame.scripts
			and frame.scripts.OnEvent
			and events
			and events.QUEST_LOG_UPDATE
			and events.QUEST_WATCH_LIST_CHANGED
			and events.QUEST_POI_UPDATE
			and events.SUPER_TRACKING_CHANGED
			and events.CVAR_UPDATE
		then
			return frame
		end
	end
	error("the pin pass's event frame")
end

-- The provider registers its events in the map's OnShow, after this addon's frame, so in one dispatch our handler runs
-- first and its refresh re-shows every pin after it. The pass runs from our frame's OnUpdate, after every handler in
-- the frame and before it draws (#718): no timer, and no frame drawn with a stopped quest's pin.
SetSteps(numbered, elsewhere, here)
ns.Pins.Refresh()
h.flush()
h.fire("QUEST_LOG_UPDATE")
equal(pin101:IsShown(), true, "the provider's handler runs after ours and re-shows the pin")
h.frame() -- the frame's OnUpdate phase only: no timer runs
equal(pin101:IsShown(), false, "the pass hides it again in the same frame")
equal(pin201:IsShown(), false, "every mark of the stop")
equal(pin999:IsShown(), true, "a quest outside the journey keeps its pin")

-- The addon's own handler draws in that same frame, before the provider's refresh: Draw runs the pass over the pins
-- the provider has not replaced yet, and the provider re-acquires every one of them after it. The queued pass must
-- still run at the frame's end, or the pin it hid shows for the frame Draw's own pass could not catch (#718).
pin101:Show()
h.fire("QUEST_POI_UPDATE")
equal(pin101:IsShown(), true, "the provider's refresh re-shows the pin after the addon's draw")
equal(pass:IsShown(), true, "the frame's pass stays queued for Draw, which cannot see the pins the provider just made")
h.frame() -- the frame's OnUpdate phase only: no timer runs
equal(pin101:IsShown(), false, "the queued pass hides it before the frame ends")
equal(pin201:IsShown(), false, "every mark of the stop")
equal(pass:IsShown(), false, "and the pass frame is idle again")

-- The map opening and a map change draw their pins in the frame's OnUpdate, and the frame's pass runs there too: once
-- the flush has run the frame, the pass frame is idle again.
h.map:SetMapID(OTHER)
h.flush()
equal(pin301:IsShown(), false, "a map change hides the new map's marked pin as it draws")
equal(pass:IsShown(), false, "the frame's pass ran once and left none queued")
equal(pin101:IsShown(), true, "and gives back the old map's")
h.map:SetMapID(MAP)
h.flush()
equal(pin101:IsShown(), false, "turning back hides it again while drawing")

-- Nothing depends on the event: no stop on the shown map and no pin this pass hid (wanderer mode here), so the pass
-- walks no pin at all, once per event buffer (WFA-13).
ns.SetSetting("wanderer", true)
ns.Pins.Refresh()
h.flush()
equal(pin101:IsShown(), true, "wanderer mode gives the pins back")
local walks = h.counts.QuestPinWalks
h.fire("QUEST_LOG_UPDATE")
h.tick()
equal(h.counts.QuestPinWalks, walks, "with nothing marked or hidden, a quest-log update walks no pin")

-- ... and it allocates nothing of its own: the event queues the frame's one-shot pass, and each further event in the
-- same frame is free. Warm the paths, then measure live memory across the burst. LuaJIT's own trace recording allocates
-- as the loop heats up, so the measured frames run with it off, as the bench runs.
ns.SetSetting("wanderer", false)
ns.Pins.Refresh()
h.flush()
ns.SetSetting("wanderer", true)
ns.Pins.Refresh()
h.flush()
while ns.Settling() do
	h.tick()
end
local events = PinEvents()
for _ = 1, 100 do
	events.scripts.OnEvent(events, "QUEST_LOG_UPDATE")
end
pass.scripts.OnUpdate(pass, 1 / 60)
collectgarbage("collect")
jit.off()
local before = collectgarbage("count")
for _ = 1, 20 do
	events.scripts.OnEvent(events, "QUEST_LOG_UPDATE")
end
local burst = collectgarbage("count") - before
jit.on()
equal(burst, 0, "nothing marked or hidden: a burst of quest-log updates allocates nothing")
collectgarbage("collect")
jit.off()
before = collectgarbage("count")
pass.scripts.OnUpdate(pass, 1 / 60)
local idlePass = collectgarbage("count") - before
jit.on()
equal(idlePass, 0, "and a pass with nothing to do allocates nothing")

-- With a stop drawn, the pass runs every frame but reuses its own marked and seen tables: only the pins the provider
-- re-shows are touched (WFA-13).
ns.SetSetting("wanderer", true)
ns.Pins.Refresh()
h.flush()
ns.SetSetting("wanderer", false)
ns.Pins.Refresh()
h.flush()
while ns.Settling() do
	h.tick()
end
for _ = 1, 20 do
	events.scripts.OnEvent(events, "QUEST_LOG_UPDATE")
	pass.scripts.OnUpdate(pass, 1 / 60)
end
collectgarbage("collect")
jit.off()
before = collectgarbage("count")
for _ = 1, 20 do
	events.scripts.OnEvent(events, "QUEST_LOG_UPDATE")
	pass.scripts.OnUpdate(pass, 1 / 60)
end
local markedPass = collectgarbage("count") - before
jit.on()
equal(markedPass, 0, "a marked stop: repeated passes allocate nothing")

-- Only the questPOI CVar redraws the pins, so another CVar is not a reason to walk them.
pin101:Show()
h.fire("CVAR_UPDATE", "notQuestPOI", "0")
h.flush()
equal(pin101:IsShown(), true, "another CVar's change leaves the pin alone")
h.fire("CVAR_UPDATE", "questPOI", "1")
h.flush()
equal(pin101:IsShown(), false, "the questPOI setting's change hides it again")

equal(#h.errors, 0, table.concat(h.errors, "\n"))
print("quest_pins_spec: " .. checks .. " checks passed")
