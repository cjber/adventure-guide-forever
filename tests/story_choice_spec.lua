-- #759: two available chains can be chosen without dismissing the zone's suggested story.
local ns = {}
dofile("tests/harness.lua").model(ns)
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local data = { quests = {}, zones = { [1] = { name = "Here", min = 10, max = 20 } } }
for id = 1, 6 do
	data.quests[id] = {
		title = "Quest " .. id,
		level = 16,
		min = 10,
		side = 2,
		zone = 1,
		start = { map = 1, x = id / 10, y = 0.5, name = "Giver" },
		finish = { map = 1, x = id / 10, y = 0.5, name = "Ender" },
	}
end
data.quests[1].next, data.quests[2].pre = 2, { 1 }
data.quests[3].next, data.quests[4].pre = 4, { 3 }
data.quests[5].next, data.quests[6].pre = 6, { 5 }
local player = { level = 16, maxLevel = 60, side = 2, raceBit = 2, classBit = 64, map = 1, x = 0.5, y = 0.5 }
local prefs = { quests = true, dungeons = false, skipped = {}, optimisedRoute = true }
local function cards(route)
	local found = {}
	for _, card in ipairs(route.journeys) do
		found[card.key] = card
	end
	return found
end
local route = ns.Model.Plan(data, player, {}, {}, prefs)
local offered = cards(route)
equal(offered["zone:1"] ~= nil, true, "the suggested zone remains")
equal(offered["chain:3"] ~= nil, true, "a second story is directly offered")
equal(offered["chain:5"] ~= nil, true, "a third story is directly offered")
equal(offered["chain:3"].title, "Quest 3", "a story uses its own known title")
equal(offered["chain:3"].story.chapter, 1, "the new story shows its chapter")
prefs.journey = "chain:3"
local chosen = ns.Model.Plan(data, player, {}, {}, prefs)
equal(chosen.journey, "chain:3", "the second story can be chosen")
equal(chosen.chosen, true, "the selection is retained")
equal(prefs.notInterested, nil, "choosing never dismisses a story")
for _, step in ipairs(chosen.steps) do
	for _, id in ipairs(step.pickups or {}) do
		equal(id, 3, "only the chosen chain is picked up")
	end
end
local accepted = ns.Model.Plan(
	data,
	player,
	{},
	{ [3] = { id = 3, title = "Quest 3", level = 16, complete = true } },
	prefs
)
equal(accepted.journey, "chain:3", "accepting its chapter preserves the chosen story")
equal(accepted.steps[1].quests[1], 3, "the chosen story keeps its accepted quest")
equal(accepted.steps[1].verb, "turnin", "the chosen story keeps its ready hand-in")
equal(cards(accepted)["chain:3"].story.chapter, 1, "an accepted chapter retains its story progress")
local continued = cards(ns.Model.Plan(data, player, { [3] = true }, {}, prefs))["chain:3"]
equal(continued ~= nil, true, "a started chain remains offered")
equal(continued.story.chapter, 2, "the started story shows its current chapter")
prefs.notInterested = { ["chain:5"] = true }
equal(cards(ns.Model.Plan(data, player, {}, {}, prefs))["chain:5"], nil, "a dismissed chain stays hidden")
prefs.quests = false
equal(cards(ns.Model.Plan(data, player, {}, {}, prefs))["chain:3"], nil, "quests off offers no pickup story")
-- The real panel exposes the extra chains through its existing expandable Continue group.
local h = dofile("tests/harness.lua").load({ db = { autoStart = false }, completed = { 844 }, log = {} })
h.ns.OpenPanel()
h.flush()
local header = h.Find(function(frame)
	return frame:IsVisible() and frame.key == "continue" and frame.Name ~= nil
end)[1]
assert(header, "the Continue header exists")
h.Click(header)
h.flush()
local alternative = h.Find(function(frame)
	return frame:IsVisible() and frame.journey and frame.journey.key:match("^chain:") and frame.Icon and frame.Icon.Clip
end)[1]
equal(alternative ~= nil, true, "expanding Continue exposes an actual alternative story")
local picked = alternative.journey.key
h.Click(alternative)
h.flush()
equal(h.ns.Prefs().journey, picked, "clicking the alternative chooses that chain")
equal(h.ns.Route().journey, picked, "the chosen story reaches the real route")
equal(next(h.ns.Prefs().notInterested or {}), nil, "a panel choice dismisses no other story")
equal(#h.errors, 0, table.concat(h.errors, "\n"))
print(("story_choice_spec: %d checks passed"):format(checks))
