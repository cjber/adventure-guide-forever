-- Run from the repository root: luajit tests/open_cost_spec.lua
-- The first open of the unchosen overview makes no journey card, since a card belongs to a chosen journey, and one
-- header per non-empty group, never one per group. Counts the frames made, not wall time.
local harness = dofile("tests/harness.lua")

local checks = 0
local function check(ok, label)
	checks = checks + 1
	if not ok then
		error(label, 2)
	end
end

local function JourneyCards(h, from)
	local cards = 0
	for index = from, #h.frames do
		if h.frames[index].template == "AdventureGuideForeverJourneyCardTemplate" then
			cards = cards + 1
		end
	end
	return cards
end

-- CreateOverviewHeader is the only builder that gives a frame a fold button and a count.
local function OverviewHeaders(h, from)
	local headers = 0
	for index = from, #h.frames do
		local frame = h.frames[index]
		if frame.CollapseButton and frame.Count and frame.Name then
			headers = headers + 1
		end
	end
	return headers
end

local function NonEmptyGroups(h)
	local route = h.ns.Route()
	local nonEmpty = 0
	for _, group in ipairs(h.ns.Overview.GROUPS) do
		if #h.ns.Overview.InGroup(route.journeys, group.key) > 0 then
			nonEmpty = nonEmpty + 1
		end
	end
	return nonEmpty
end

-- The first open: the unchosen overview makes no journey card, and only the groups it can show get a header. The old
-- build made one card per journey and one header per group, whatever the route held.
do
	local h = harness.load({ player = { level = 17 } })
	local before = #h.frames
	h.ns.OpenPanel()
	check(h.ns.PanelShown(), "first open: the guide opens on the map")
	local nonEmpty = NonEmptyGroups(h)
	check(nonEmpty < #h.ns.Overview.GROUPS, "first open: the fixture has a group with no journey")
	local cards = JourneyCards(h, before + 1)
	check(cards == 0, ("overview: made %d journey cards with no journey chosen"):format(cards))
	local headers = OverviewHeaders(h, before + 1)
	check(headers == nonEmpty, ("overview: made %d header(s) for %d non-empty group(s)"):format(headers, nonEmpty))
	h.flush()
	cards = JourneyCards(h, before + 1)
	check(cards == 0, ("overview: made %d journey cards after the first open"):format(cards))
	headers = OverviewHeaders(h, before + 1)
	check(headers == nonEmpty, ("overview: made %d header(s) for %d non-empty group(s)"):format(headers, nonEmpty))
	check(#h.errors == 0, "first open: no errors\n" .. table.concat(h.errors, "\n"))
end

-- The chosen view still makes its journey cards, once a journey is chosen.
do
	local h = harness.load({ player = { level = 17 } })
	h.ns.OpenPanel()
	h.flush()
	local card
	for _, frame in ipairs(h.frames) do
		if frame.journey ~= nil and frame.state == "shown" and frame.IconFrame == nil then
			card = frame
			break
		end
	end
	check(card ~= nil, "chosen view: the overview offers a card")
	local before = #h.frames
	h.ns.Choose(card.journey.key, false)
	h.flush()
	check(h.ns.Prefs().journey == card.journey.key, "chosen view: the journey is chosen")
	local cards = JourneyCards(h, before + 1)
	check(cards > 0, "chosen view: makes its journey cards after the choice")
	check(#h.errors == 0, "chosen view: no errors\n" .. table.concat(h.errors, "\n"))
end

print(("open cost: %d checks"):format(checks))
