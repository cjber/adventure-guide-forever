-- Run from the repository root: luajit tests/suggestions_spec.lua
-- API.Suggestions answers the guide's cards in the order the panel draws them, from the settled route and never by
-- planning for its caller; API.StartSuggestion starts one as the guide's own Start does (docs/api.md, minor 2).
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local h = harness.load({
	spf = "ended",
	completed = { 844 },
	log = {
		{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
		{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
	},
})
local API = h.G.AdventureGuideForever.API
equal(API.version, 1, "version stays 1")
equal(API.minor, 3, "Stats raises minor to 3")
h.ns.Invalidate()
equal(API.Suggestions(), nil, "a route due a rebuild says ask again later")
equal(API.StartSuggestion("carry"), false, "nothing starts while the route settles")
h.flush()

local ns = h.ns
-- The panel's order (UI/Panel.lua LayoutJourneys): a chosen card, then the rest as the route offered them; with none
-- chosen, the headers' cards in turn (LayoutOverview).
local function Expected()
	local route, cards = ns.Route(), {}
	if route.chosen then
		for _, journey in ipairs(route.journeys) do
			if journey.key == route.journey then
				cards[1] = journey
			end
		end
		for _, journey in ipairs(route.journeys) do
			if journey.key ~= route.journey then
				cards[#cards + 1] = journey
			end
		end
		return cards
	end
	for _, group in ipairs(ns.Overview.GROUPS) do
		for _, journey in ipairs(ns.Overview.InGroup(route.journeys, group.key)) do
			cards[#cards + 1] = journey
		end
	end
	return cards
end

-- Model.Cards on a route whose order and headers disagree: chosen keeps the route's order, unchosen the headers'.
do
	local function Card(key, section)
		return { key = key, section = section }
	end
	local journeys = { Card("z", "zones"), Card("c1", "continue"), Card("d", "dungeons"), Card("c2", "continue") }
	local function Keys(route)
		local keys = {}
		for _, card in ipairs(ns.Model.Cards(route)) do
			keys[#keys + 1] = card.key
		end
		return table.concat(keys, " ")
	end
	equal(Keys({ journeys = journeys, chosen = false, journey = "z" }), "c1 c2 z d", "unchosen: by header")
	equal(Keys({ journeys = journeys, chosen = true, journey = "d" }), "d z c1 c2", "chosen: it, then route order")
end

local route = ns.Route()
equal(route.chosen and route.journey, "carry", "the fixture starts with Quests in your log chosen")
assert(#route.journeys > 5, "the fixture needs more cards than the cap")
local navigations = h.spf.NavigateRoute
local suggestions = assert(API.Suggestions(), "a settled route answers")
equal(#suggestions, 5, "five unless the caller says otherwise")
equal(suggestions[1].id, "carry", "the chosen card leads, as the panel draws it")
local expected = Expected()
for index, suggestion in ipairs(suggestions) do
	local journey = expected[index]
	equal(suggestion.id, journey.key, "card " .. index .. " in the panel's order")
	equal(suggestion.title, journey.title, "card " .. index .. " title")
	equal(suggestion.kind, journey.kind, "card " .. index .. " kind")
	equal(suggestion.map, journey.steps[1].map, "card " .. index .. " map is its first stop's")
	equal(suggestion.level, (ns.Model.LevelRange(ns.Data, journey)), "card " .. index .. " level is the card's lowest")
	local step = journey.steps[1]
	equal(suggestion.x, step.x, "card " .. index .. " x is its first stop's")
	equal(suggestion.y, step.y, "card " .. index .. " y is its first stop's")
end
equal(suggestions[1].level, nil, "Quests in your log shows no level")
equal(suggestions[2].level, 10, "The Barrens story's level is the zone's lowest")
suggestions[2].title = "changed"
equal(API.Suggestions()[2].title, expected[2].title, "every call copies")

equal(#API.Suggestions(2), 2, "a limit is honoured")
equal(#API.Suggestions(0), 0, "zero is an empty list")
equal(#API.Suggestions(100), 5, "five at most")
equal(API.Suggestions(-1), nil, "a negative limit")
equal(API.Suggestions(1.5), nil, "a fractional limit")
equal(API.Suggestions("2"), nil, "a string limit")
equal(h.spf.NavigateRoute, navigations, "reads never start guidance")

-- With nothing chosen the headers' order holds alone: the story under "continue" before the next zones.
ns.Choose(nil)
h.flush()
local unchosen = assert(API.Suggestions())
expected = Expected()
equal(unchosen[1].id, expected[1].key, "unchosen: the first header's first card leads")
equal(unchosen[1].kind ~= "nextzone", true, "unchosen: continue's cards come before the zones")
equal(unchosen[5].id, expected[5].key, "unchosen: the panel's fifth card")

-- Starting a card chooses it and starts its route through Shortest Path on the rebuild that has its steps.
equal(API.StartSuggestion("nope"), false, "an unknown id starts nothing")
equal(API.StartSuggestion(nil), false, "a missing id starts nothing")
navigations = h.spf.NavigateRoute
equal(API.StartSuggestion("zone:1440"), true, "a card starts")
h.flush()
route = ns.Route()
equal(route.chosen and route.journey, "zone:1440", "the card is chosen")
equal(ns.Prefs().guided, "zone:1440", "its route runs")
equal(h.spf.NavigateRoute, navigations + 1, "through Shortest Path")
equal(ns.Guidance.Owns(), true, "AGF owns the route it started")

-- Again on the card already running: nothing new starts.
navigations = h.spf.NavigateRoute
equal(API.StartSuggestion("zone:1440"), true, "the running card is accepted")
h.flush()
equal(h.spf.NavigateRoute, navigations, "and not started a second time")

-- A chosen card whose route is not running starts it, as the guide's Start does.
ns.Choose("zone:1421")
h.flush()
equal(ns.Prefs().guided == "zone:1421", false, "choosing alone does not start it")
navigations = h.spf.NavigateRoute
equal(API.StartSuggestion("zone:1421"), true, "a chosen card that is not running starts")
h.flush()
equal(ns.Prefs().guided, "zone:1421", "its route runs")
equal(h.spf.NavigateRoute, navigations + 1, "through Shortest Path")

assert(#h.errors == 0, table.concat(h.errors, "\n"))
print(("suggestions_spec: %d checks passed"):format(checks))
