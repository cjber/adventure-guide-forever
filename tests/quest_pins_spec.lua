-- Run from the repository root: luajit tests/quest_pins_spec.lua
-- The game's own quest pins and the guide's numbered stops (#468): while a stop is drawn on the world map, the game's
-- pin for each quest that stop marks is hidden, so the stop reads once. A stop the player stands in draws no marker,
-- so its pin stays; quests outside the journey keep theirs; a pin we did not hide is never shown by us; and a provider
-- refresh that re-shows a pin is followed a frame later by hiding it again.
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

local route = { steps = {}, journeys = {}, chosen = false }
local function AddStep(fields)
	local step = { map = MAP, x = 0.4, y = 0.4, kind = "area", title = "Step", quests = {}, key = "area:1:1" }
	for key, value in pairs(fields) do
		step[key] = value
	end
	route.steps[#route.steps + 1] = step
	return step
end

local numbered = AddStep({ key = "area:101:1", quests = { 101, 201 }, rxpIndex = 1 })
AddStep({ key = "area:301:1", map = OTHER, quests = { 301 } })
local here = AddStep({ key = "area:401:1", quests = { 401 }, here = true })

ns.Route = function()
	return route
end

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
route.steps = {}
ns.Pins.Refresh()
equal(pin101:IsShown(), true, "an empty route restores the pins")
equal(pin201:IsShown(), true, "both of them")
equal(foreign:IsShown(), false, "and still leaves the other addon's pin alone")

-- The provider re-acquires and re-shows its pins on its own events; our pass walks them a frame later.
route.steps = { numbered, here }
ns.Pins.Refresh()
h.flush()
pin101:Show()
h.fire("QUEST_LOG_UPDATE")
equal(pin101:IsShown(), true, "the provider's refreshed pin starts shown")
h.tick()
equal(pin101:IsShown(), false, "a frame later the stopped quest's pin is hidden again")
h.flush()

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
