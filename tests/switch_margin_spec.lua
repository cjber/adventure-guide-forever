-- Run from the repository root: luajit tests/switch_margin_spec.lua
-- The switch margin (docs/design.md §2.10, Model.TownChecklist and Core's Walked): a town visit's arrow stays on the
-- giver it points at while that giver has work, until another is SWITCH_YARDS nearer, so two near-equal givers do not
-- flip the waypoint as the player walks between them.
local ns = {}
local harness = dofile("tests/harness.lua")
harness.model(ns)
local Model, data, checks = ns.Model, ns.Data, 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local MAP = 1429 -- Elwynn Forest
local A = { map = MAP, x = 0.38, y = 0.50, name = "Giver A" }
local B = { map = MAP, x = 0.42, y = 0.50, name = "Giver B" }
local apart = Model.Yards(data, A, B)
equal(apart > 2 * Model.SWITCH_YARDS, true, "the givers stand well apart")

local function Step()
	return { kind = "town", map = MAP, x = 0.41, y = 0.5, pickups = { 1, 2 }, spots = { [1] = A, [2] = B } }
end
-- The player `toward` of the way from A to B (0 at A, 1 at B).
local function Player(toward)
	return { map = MAP, x = A.x + (B.x - A.x) * toward, y = 0.5 }
end
local function Point(step)
	return step.x == A.x and "A" or step.x == B.x and "B" or "elsewhere"
end

-- No earlier point: the nearest giver.
local step = Step()
Model.TownChecklist(data, Player(0.45), {}, {}, step, nil, nil)
equal(Point(step), "A", "first: the nearest")
-- Just past halfway, B is a little nearer: the arrow stays on A.
local previous = step
local margin = Model.SWITCH_YARDS / apart -- the share of the way that makes SWITCH_YARDS
step = Step()
Model.TownChecklist(data, Player(0.5 + margin / 4), {}, {}, step, previous, nil)
equal(Point(step), "A", "a little nearer: kept")
-- Far enough that B is more than SWITCH_YARDS nearer: it takes the arrow.
previous = step
step = Step()
Model.TownChecklist(data, Player(0.5 + margin), {}, {}, step, previous, nil)
equal(Point(step), "B", "SWITCH_YARDS nearer: switched")
-- Once A's work is done, B takes the arrow at once, however close the two are.
step = Step()
previous = { map = MAP, x = A.x, y = A.y, checklist = {} }
Model.TownChecklist(data, Player(0.3), {}, { [1] = { id = 1 } }, step, previous, nil)
equal(Point(step), "B", "done: the other giver at once")

-- Core's Walked asks for a rebuild only past the same margin: The Crossroads, a town visit with several givers.
do
	local h = harness.load({
		charDB = { journey = "zone:1413" },
		planned = true,
		completed = { 844 },
		log = {
			{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
		},
	})
	h.flush()
	local first = h.ns.Route().steps[1]
	equal(first.kind, "town", "walked: step 1 is a town visit")
	local current, other
	for _, row in ipairs(first.checklist) do
		local place = row.place
		if not row.done and place.map == first.map then
			if place.x == first.x and place.y == first.y then
				current = place
			elseif
				not other
				or Model.Yards(h.ns.Data, current or first, place) > Model.Yards(h.ns.Data, current or first, other)
			then
				other = place
			end
		end
	end
	assert(current and other, "walked: two givers with work")
	-- Walk from the giver the arrow points at to the farthest other one: at each point a rebuild comes exactly when
	-- some giver with work is SWITCH_YARDS nearer than the one step 1 points at, and the walk sees both cases.
	local world, kept, switched = h.ns.Data, 0, 0
	for stride = 1, 20 do
		local toward = stride / 20
		local spot = {
			map = current.map,
			x = current.x + (other.x - current.x) * toward,
			y = current.y + (other.y - current.y) * toward,
		}
		local head = h.ns.Route().steps[1]
		local nearest, at
		for _, row in ipairs(head.checklist) do
			local yards = not row.done and Model.Yards(world, spot, row.place)
			if yards and (not nearest or yards < nearest) then
				nearest = yards
			end
			if yards and row.place.x == head.x and row.place.y == head.y and row.place.map == head.map then
				at = yards
			end
		end
		local expected = (at and nearest + Model.SWITCH_YARDS <= at) and 1 or 0
		h.MovePlayer(spot.map, spot.x, spot.y)
		local plans = h.modelCalls.Plan
		h.fire("PLAYER_STARTED_MOVING")
		h.fire("PLAYER_STOPPED_MOVING")
		h.flush()
		equal(math.min(h.modelCalls.Plan - plans, 1), expected, "walked: a rebuild only past the margin, at " .. stride)
		kept, switched = kept + (expected == 0 and nearest < at and 1 or 0), switched + expected
	end
	equal(kept > 0, true, "walked: a nearer giver within the margin kept the arrow")
	equal(switched > 0, true, "walked: one past the margin took it")
	equal(#h.errors, 0, "walked: errors\n" .. table.concat(h.errors, "\n"))
end

print(("switch_margin_spec: %d checks passed"):format(checks))
