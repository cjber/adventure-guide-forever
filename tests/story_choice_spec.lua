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
equal(offered["chain:3"], nil, "Continue lists zones: a second story is not offered")
equal(offered["chain:5"], nil, "Continue lists zones: a third story is not offered")
prefs.journey = "chain:3"
local chosen = ns.Model.Plan(data, player, {}, {}, prefs)
local own = cards(chosen)
equal(own["chain:3"] ~= nil, true, "a chosen story is a card")
equal(own["chain:5"], nil, "the other stories stay hidden")
equal(own["chain:3"].title, "Quest 3", "a story uses its own known title")
equal(own["chain:3"].story.chapter, 1, "the chosen story shows its chapter")
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
prefs.notInterested = { ["chain:3"] = true }
equal(cards(ns.Model.Plan(data, player, {}, {}, prefs))["chain:3"], nil, "a dismissed chain stays hidden")
prefs.notInterested = nil
prefs.quests = false
equal(cards(ns.Model.Plan(data, player, {}, {}, prefs))["chain:3"], nil, "quests off offers no pickup story")
-- The real panel's expandable Continue group lists zones only.
local h = dofile("tests/harness.lua").load({ db = { autoStart = false }, completed = { 844 }, log = {} })
h.ns.OpenPanel()
h.flush()
local header = h.Find(function(frame)
	return frame:IsVisible() and frame.key == "continue" and frame.Name ~= nil
end)[1]
assert(header, "the Continue header exists")
h.Click(header)
h.flush()
local chainCards, zoneCards = 0, 0
for _, frame in
	ipairs(h.Find(function(frame)
		return frame:IsVisible() and frame.journey and frame.Icon and frame.Icon.Clip
	end))
do
	chainCards = chainCards + (frame.journey.key:match("^chain:") and 1 or 0)
	zoneCards = zoneCards + (frame.journey.key:match("^zone:") and 1 or 0)
end
equal(chainCards, 0, "expanding Continue exposes no story card")
equal(zoneCards > 0, true, "expanding Continue exposes zone cards")
equal(next(h.ns.Prefs().notInterested or {}), nil, "no story is dismissed")
equal(#h.errors, 0, table.concat(h.errors, "\n"))
print(("story_choice_spec: %d checks passed"):format(checks))
