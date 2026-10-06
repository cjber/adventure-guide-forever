-- Run from the repository root: luajit tests/shown_spec.lua
-- The route as shown (Planning/Shown.lua): Shown.Build is the one pass from a snapshot of the player to the steps the
-- views draw, so the planner's route, the player's own order (docs/design.md §2.20) and giver skips are checked
-- together here, with no UI loaded.
local harness = dofile("tests/harness.lua")
local characters = dofile("tests/fixtures/characters.lua")
local checks = 0
local function eq(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- A fresh addon table per case, with the fixture character's snapshot as Core.lua would read it.
---@param name string
---@param optimised? boolean the planned (beta) order, whose committed order a rebuild keeps to
local function Case(name, optimised)
	local ns = { Data = harness.data() }
	local Shown = harness.shown(ns)
	ns.Invalidate = function() end
	ns.Setting = function(key)
		return key == "optimisedRoute" and optimised == true
	end
	for _, fixture in ipairs(characters.list) do
		if fixture.name == name then
			local player, completed, log, wanted = characters.Resolve(ns.Data, fixture)
			local prefs = ns.Prefs()
			for key, value in pairs(wanted) do
				if key ~= "skipped" then
					prefs[key] = value
				end
			end
			-- The route's own journey is the choice, as a click on its card makes it.
			prefs.journey = prefs.journey or ns.Model.Plan(ns.Data, player, completed, log, prefs).journey
			return ns, Shown, { data = ns.Data, player = player, completed = completed, log = log, prefs = prefs }
		end
	end
	error("Missing fixture: " .. name)
end

local function Keys(route)
	local keys = {}
	for _, step in ipairs(route.steps) do
		keys[#keys + 1] = step.key
	end
	return table.concat(keys, " ")
end

local function At(player, step)
	local moved = {}
	for key, value in pairs(player) do
		moved[key] = value
	end
	moved.map, moved.x, moved.y = step.map, step.x, step.y
	return moved
end

-- Nothing asked of the build: the planner's route is the route shown, and the next build's `last`.
do
	local ns, Shown, input = Case("orc18_barrens")
	local shown, full = Shown.Build(input)
	eq(shown, full, "the whole ordered route is shown")
	eq(shown.chosen, true, "the fixture's journey is chosen")
	local planned = ns.Model.Plan(input.data, input.player, input.completed, input.log, input.prefs)
	eq(Keys(shown), Keys(planned), "no order or skip: the planner's route")
	for index, step in ipairs(shown.steps) do
		eq(ns.Model.Visit(step), step.orderKey, "every shown step carries its visit identity, step " .. index)
	end
end

-- The player's order: the saved visit leads, the rest keep the suggested order, and a saved order the route's
-- dependencies forbid is repaired, never obeyed.
do
	local ns, Shown, input = Case("orc18_barrens")
	local suggested = Shown.Build(input)
	local journey, steps = suggested.journey, suggested.steps
	local movable
	for index = #steps, 2, -1 do
		local moved = {}
		for at, step in ipairs(steps) do
			moved[at] = step
		end
		table.insert(moved, 1, table.remove(moved, index))
		if not movable and ns.Order.Valid(moved, input.player.logMax, input.log) then
			movable = index
		end
	end
	local lead = steps[movable]
	local saved = { ns.Model.Visit(lead) }
	input.prefs.customOrders = { [journey] = saved }
	local shown, full = Shown.Build(input)
	eq(shown.steps[1].key, lead.key, "the saved visit leads")
	eq(full.steps[1].key, lead.key, "the full route is in the player's order too")
	for _, card in ipairs(full.journeys) do
		if card.key == journey then
			eq(lead.place ~= steps[1].place, true, "the moved stop is somewhere else")
			eq(card.hub, lead.place or lead.title, "the card's hub line names the new first stop")
		end
	end
	local rest = {}
	for _, step in ipairs(steps) do
		rest[#rest + 1] = step.key ~= lead.key and step.key or nil
	end
	eq(Keys(shown), lead.key .. " " .. table.concat(rest, " "), "the rest keep the suggested order")
	eq(#saved, 1, "a build never writes the saved order")
	for index = 2, #shown.steps do
		eq(shown.steps[index].here, nil, "only the head can be where the player stands, step " .. index)
	end
	for _, card in ipairs(shown.journeys) do
		if card.key == journey then
			eq(card.steps, shown.steps, "the chosen card shows the same steps")
		end
	end
	-- Every visit backwards: hand-ins before their work, work before its pickup.
	local backwards = {}
	for index = #steps, 1, -1 do
		backwards[#backwards + 1] = ns.Model.Visit(steps[index])
	end
	input.prefs.customOrders = { [journey] = backwards }
	local repaired = Shown.Build(input)
	eq(#repaired.steps, #steps, "a repaired order drops nothing")
	eq(ns.Order.Valid(repaired.steps, input.player.logMax, input.log), true, "a saved order never breaks a dependency")
	eq(Keys(repaired) ~= Keys(suggested), true, "what the dependencies allow of the saved order is kept")
end

-- The committed order (docs/design.md §4.3): a rebuild keeps to the last build's order though the player walked on,
-- until the order is reset, which waits out a fight for the full build.
do
	local _, Shown, input = Case("ne21_crosszone", true)
	local _, first = Shown.Build(input)
	local journey, head = first.journey, first.steps[1].key
	input.player = At(input.player, first.steps[2])
	local fresh = Shown.Build(input)
	eq(fresh.steps[1].key ~= head, true, "the fixture: a fresh plan from there leads elsewhere")
	input.last = first
	local kept, full = Shown.Build(input)
	eq(kept.steps[1].key, fresh.steps[1].key, "the rebuild leads with the stop the player walked into")
	Shown.Forget(journey)
	input.last, input.combat = full, true
	local fought, held = Shown.Build(input)
	eq(fought.steps[1].key, fresh.steps[1].key, "combat's rebuild keeps the head")
	eq(fought.skipped, nil, "combat's rebuild is the cheap one")
	input.last, input.combat = held, nil
	local reset, after = Shown.Build(input)
	eq(Keys(reset), Keys(fresh), "the reset order is the fresh plan's")
	input.last = after
	eq(Keys((Shown.Build(input))), Keys(fresh), "and the next build commits to it")
end

-- A skipped giver: its row stays on the visit, ticked; its quests leave every route; the skip stays offered back.
do
	local ns, Shown, input = Case("orc18_barrens")
	local shown, full = Shown.Build(input)
	local town = shown.steps[1]
	eq(town.kind, "town", "the fixture leads with a town")
	eq(#town.checklist > 1, true, "with more than one giver")
	local giver = town.checklist[1]
	ns.Route = function()
		return shown
	end
	eq(ns.Order.SkipGiver(town.key, giver.key), true, "the giver is skipped")
	local key = ns.Model.GiverSkip(town, giver.key)
	eq(input.prefs.skipped[key], true, "under the visit's skipped key")
	input.last = full
	local after, whole = Shown.Build(input)
	eq(whole.skipped[key], true, "the build still found the skip, so Show again keeps it")
	local dropped = {}
	for _, id in ipairs(giver.pickups) do
		dropped[id] = true
	end
	for _, id in ipairs(giver.handins) do
		dropped[id] = true
	end
	for _, card in ipairs(after.journeys) do
		for _, step in ipairs(card.steps) do
			for _, id in ipairs(step.quests) do
				eq(dropped[id], nil, "a skipped giver's quest " .. id .. " is on no route")
			end
		end
	end
	local row
	for _, step in ipairs(after.steps) do
		for _, candidate in ipairs(step.key == town.key and step.checklist or {}) do
			row = candidate.key == giver.key and candidate or row
		end
	end
	eq(row ~= nil and row.skipped, true, "the visit keeps the giver's row, skipped")
	eq(row.done, true, "and ticks it")
end

print(("shown_spec: %d checks passed"):format(checks))
