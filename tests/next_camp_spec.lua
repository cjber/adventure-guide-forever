-- Run from the repository root: luajit tests/next_camp_spec.lua
-- "Next spot" (docs/design.md §2.8, Model.Camp, ns.NextCamp): an area step with more than one objective spot offers
-- it in the step menu; each press moves the step's point to the next spot by distance from the player, nearest first,
-- round again after the last, for this session only.
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local ns = {}
harness.model(ns)
local Model = ns.Model
local data = harness.data()

-- Model.Camp on a hand-made area: three spots east of the player, 1, 2 and 3 steps away; the planner chose the
-- middle one.
local MAP = 1429
local function Shape(x)
	return { map = MAP, x = x, y = 0.5, r = 20, slot = 0, objectives = {} }
end
local near, middle, far = Shape(0.42), Shape(0.46), Shape(0.50)
local player = { map = MAP, x = 0.40, y = 0.5 }
local function Area()
	return { kind = "area", key = "area:1:0", map = MAP, x = middle.x, y = 0.5, shapes = { far, near, middle } }
end
local function Passed(...)
	local passed = {}
	for _, spot in ipairs({ ... }) do
		passed[Model.SpotKey(spot)] = true
	end
	return passed
end
local function Camp(passed, at)
	local step = Area()
	if at then
		step.x = at.x
	end
	Model.Camp(data, player, step, passed)
	return step.x
end
equal(Camp(Passed()), middle.x, "camp: nothing passed over, the planner's spot")
equal(Camp(Passed(middle)), near.x, "camp: the middle passed over, the nearest left")
equal(Camp(Passed(middle, near)), far.x, "camp: then the far one")
equal(Camp(Passed(middle, near, far)), middle.x, "camp: all passed over (NextCamp never leaves it so), nothing moves")
equal(Camp(Passed(middle), far), far.x, "camp: a spot not passed over keeps the arrow")
-- Standing in the area (#151): a spot passed over isn't standing in it (Model.Here), so the arrow leads on from there.
local function Stand(x, y)
	return { map = MAP, x = x, y = y or 0.5 }
end
local function At(x, passed, held)
	return Model.AtPassedSpot(data, Stand(x), Area(), passed, held == true)
end
equal(At(near.x, Passed()), false, "nothing passed over: never")
equal(At(near.x, Passed(near), true), true, "at a spot passed over: not here")
equal(At(middle.x, Passed(near), true), false, "at a spot not passed over: here")
equal(At(near.x, Passed(near, middle, far), true), false, "no spot left that isn't passed over: here")
-- The line between near and middle: their edges are equal there, so held decides, and CAMP_SWITCH either side.
local line = (near.x + middle.x) / 2
equal(At(line, Passed(near), true), false, "on the line, held: stays here")
equal(At(line, Passed(near), false), true, "on the line, not held: stays led on")
local step
do
	local area = Area()
	area.r = 400
	equal(Model.Here(data, Stand(near.x), { area }), 1, "Here: standing in the area")
	equal(
		Model.Here(data, Stand(near.x), { area }, nil, { [area.key] = Passed(near) }),
		nil,
		"Here: not at its spot passed over"
	)
	equal(
		Model.Here(data, Stand(middle.x), { area }, nil, { [area.key] = Passed(near) }),
		1,
		"Here: at a fresh spot, yes"
	)
	equal(
		Model.Here(data, Stand(near.x), { area }, nil, { other = Passed(near) }),
		1,
		"Here: another area's passed spots"
	)
end
-- Next spot inside the area passes over the spot the player is at, not the arrow's.
step = Area()
step.here = true
equal(Model.CampAt(data, Stand(near.x), step), near, "camp at: the spot stood in, not the arrow's")
equal(Model.CampAt(data, Stand(0.4401), step), middle, "camp at: the spot whose edge is nearest")
local wide = Shape(0.42)
wide.r = 400
step = Area()
step.here, step.shapes = true, { wide, middle }
equal(Model.CampAt(data, Stand(0.455), step), wide, "camp at: the spot stood in, though another centre is nearer")
step = Area()
step.here = true
Model.Camp(data, player, step, Passed(middle))
equal(step.x, middle.x, "camp: never moves a step that is here")
step = Area()
equal(Model.CampAt(data, player, step), step, "camp at: away from the area, the arrow's spot")
step = Area()
step.shapes = { middle, Shape(0.46) }
Model.Camp(data, player, step, Passed(middle))
equal(step.x, middle.x, "camp: two objectives at one node are one spot, which stays")
equal(#Model.Spots(step), 1, "spots: one distinct spot")

-- Through the addon: the first area step with several spots offers "Next spot", and pressing it moves its point.
do
	local h = harness.load({
		charDB = { journey = "zone:1413" },
		planned = true,
		completed = { 844 },
		log = {
			{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
			{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
		},
	})
	h.flush()
	local function RouteArea()
		for _, candidate in ipairs(h.ns.Route().steps) do
			if candidate.kind == "area" and #h.ns.Model.Spots(candidate) > 1 and not candidate.here then
				return candidate
			end
		end
	end
	local area = RouteArea()
	if area then
		local menu = {}
		h.ns.Menu.Step(
			setmetatable({}, {
				__index = function()
					return function(_, text, onClick)
						if text == h.ns.L.NEXT_CAMP then
							menu.next = onClick
						end
						return setmetatable({}, {
							__index = function()
								return function() end
							end,
						})
					end
				end,
			}),
			area
		)
		equal(menu.next ~= nil, true, "menu: Next spot offered")
		local key, before = area.key, area.x .. ":" .. area.y
		menu.next()
		h.flush()
		local function Find()
			for _, candidate in ipairs(h.ns.Route().steps) do
				if candidate.key == key then
					return candidate
				end
			end
		end
		local moved = Find()
		equal(moved ~= nil, true, "press: the step is still there")
		local after = moved.x .. ":" .. moved.y
		equal(after ~= before, true, "press: its point moved")
		h.ns.Invalidate()
		h.flush()
		equal(Find().x .. ":" .. Find().y, after, "a rebuild: the new spot stays")
	end
	-- Standing in the area, the entry is still offered (#151), and pressing it passes over a spot.
	if area then
		local inside = {}
		for key, value in pairs(area) do
			inside[key] = value
		end
		inside.here, inside.key = true, "area:inside"
		local offered
		h.ns.Menu.Step(
			setmetatable({}, {
				__index = function()
					return function(_, text, onClick)
						if text == h.ns.L.NEXT_CAMP then
							offered = onClick
						end
						return setmetatable({}, {
							__index = function()
								return function() end
							end,
						})
					end
				end,
			}),
			inside
		)
		equal(offered ~= nil, true, "menu: Next spot offered inside the area")
		offered()
		h.flush()
		local camps = h.ns.Prefs().camps["area:inside"]
		equal(camps ~= nil and next(camps) ~= nil, true, "inside press: a spot passed over")
		-- Passing over every spot starts the round again from the last one, so the arrow never settles on a spot passed over.
		local spots = h.ns.Model.Spots(inside)
		for _, spot in ipairs(spots) do
			inside.here, inside.map, inside.x, inside.y = nil, spot.map, spot.x, spot.y
			h.ns.NextCamp(inside)
		end
		local count = 0
		for _ in pairs(h.ns.Prefs().camps["area:inside"]) do
			count = count + 1
		end
		equal(count < #spots, true, "round again: never every spot passed over")
	end
	-- A town step has no Next spot.
	local labels = {}
	h.ns.Menu.Step(
		setmetatable({}, {
			__index = function()
				return function(_, text)
					labels[#labels + 1] = text
					return setmetatable({}, {
						__index = function()
							return function() end
						end,
					})
				end
			end,
		}),
		{ kind = "town", key = "town:x", title = "Town", quests = {}, map = 1413, x = 0.5, y = 0.5 }
	)
	for _, label in ipairs(labels) do
		equal(label == h.ns.L.NEXT_CAMP, false, "town: no Next spot")
	end
	equal(#h.errors, 0, "errors\n" .. table.concat(h.errors, "\n"))
	print(area and "next_camp_spec: an area step with several spots exercised" or "next_camp_spec: no multi-spot area")
	assert(area, "an area step with several spots on the Barrens route")
end

-- Walking (#151): a Duskwood area of two objectives in two places (their own camps stay out: #187 is for one place).
-- Stand at one, pass it over, walk to the spot the arrow leads to, and back; each change of spot rebuilds as the player
-- walks, though the area the player stands in stays the same.
do
	local h = harness.load({
		charDB = { journey = "zone:1431" },
		planned = true,
		log = { { id = 56, title = "The Night Watch", level = 24, complete = false } },
	})
	h.flush()
	local area
	for _, candidate in ipairs(h.ns.Route().steps) do
		area = area or (candidate.key == "area:56:0" and candidate or nil)
	end
	assert(area, "walk: the Night Watch area on the route")
	local spots = h.ns.Model.Spots(area)
	equal(#spots, 2, "walk: two objectives in two places, their own camps left out")
	local first = spots[1]
	h.MovePlayer(first.map, first.x, first.y)
	h.ns.Invalidate()
	h.flush()
	local head = h.ns.Route().steps[1]
	equal(head.key == area.key and head.here == true, true, "walk: standing at a spot, the area is here")
	h.ns.NextCamp(head)
	h.flush()
	head = h.ns.Route().steps[1]
	equal(head.key, area.key, "walk: the area still leads")
	equal(head.here, nil, "walk: Next spot inside the area leads on")
	local to = { map = head.map, x = head.x, y = head.y }
	equal(h.ns.Model.SpotKey(to), h.ns.Model.SpotKey(spots[2]), "walk: to the other spot")
	local function Walk(spot)
		h.MovePlayer(spot.map, spot.x, spot.y)
		local plans = h.modelCalls.Plan
		h.fire("PLAYER_STARTED_MOVING")
		h.fire("PLAYER_STOPPED_MOVING")
		h.flush()
		return h.modelCalls.Plan - plans
	end
	equal(Walk(to) > 0, true, "walk: arriving rebuilds")
	head = h.ns.Route().steps[1]
	equal(head.key == area.key and head.here == true, true, "walk: arriving, the area is theirs again")
	equal(Walk(to), 0, "walk: standing on at it, no rebuild")
	equal(Walk(first) > 0, true, "walk: back to the spot passed over rebuilds")
	equal(h.ns.Route().steps[1].here, nil, "walk: and leads on again")
	equal(Walk(first), 0, "walk: standing on at the spot passed over, no rebuild")
	-- The player's own order runs over the plan and sets the head's `here` again; Next spot still leads on.
	local keys = {}
	for _, routeStep in ipairs(h.ns.Route().steps) do
		keys[#keys + 1] = routeStep.orderKey
	end
	h.ns.Prefs().customOrders = { [h.ns.Route().journey] = keys }
	h.ns.Invalidate()
	h.flush()
	head = h.ns.Route().steps[1]
	equal(head.key, area.key, "custom order: the area still leads")
	equal(head.here, nil, "custom order: still leads on from the spot passed over")
	equal(#h.errors, 0, "walk: errors\n" .. table.concat(h.errors, "\n"))
end

-- One objective's own camps (#187): a quest with a single objective and three camps offers Next spot, and standing at
-- any of its camps is standing in its area.
do
	local Steps = ns.Planner.Steps
	local quest = {
		zone = MAP,
		need = { [0] = 0 },
		obj = { { 0, 420, 500, 20, MAP, 5 }, { 0, 460, 500, 20, MAP, 5 }, { 0, 500, 500, 20, MAP, 9 } },
	}
	local node = Steps.Planned(quest, 1, 5)[1]
	equal(#node.alternates, 1, "alternates: the camp not over the player's level")
	equal(("%.2f"):format(node.alternates[1].x), "0.46", "alternates: in the data's order")
	node = Steps.Planned(quest, 1, 9)[1]
	equal(#node.alternates, 2, "alternates: every other camp when none is over")
	node = Steps.Planned(quest, 1, nil)[1]
	equal(#node.alternates, 2, "alternates: every other camp with no level known")
	quest.obj[3][5] = 1436
	node = Steps.Planned(quest, 1, 9)[1]
	equal(#node.alternates, 1, "alternates: only on the node's map")
	quest.obj = { { 0, 420, 500, 20, MAP } }
	equal(Steps.Planned(quest, 1, 9)[1].alternates, nil, "alternates: none for a single camp")
	local camps = Area()
	camps.shapes = {
		{
			map = MAP,
			x = 0.42,
			y = 0.5,
			r = 20,
			slot = 0,
			objectives = {},
			alternates = {
				{ map = MAP, x = 0.46, y = 0.5, r = 20 },
				{ map = MAP, x = 0.50, y = 0.5, r = 20 },
			},
		},
	}
	camps.x, camps.r = 0.42, 20
	equal(#Model.Spots(camps), 3, "spots: the node and its camps")
	local merged = Area()
	merged.shapes = { camps.shapes[1], { map = MAP, x = 0.42, y = 0.5, r = 20, slot = 4, objectives = {} } }
	equal(#Model.Spots(merged), 1, "spots: a merged step keeps to its nodes, without one objective's camps")
	local here = Area()
	here.shapes, here.here = camps.shapes, true
	Model.PlaceCamp(data, Stand(0.50), here, Passed())
	equal(here.x, 0.50, "place: here at a camp, the step points at it")
	here.x = 0.42
	Model.PlaceCamp(data, Stand(0.47), here, Passed(camps.shapes[1].alternates[1]))
	equal(here.x, 0.50, "place: never at a camp passed over")
	equal(Model.Here(data, Stand(0.50), { camps }), 1, "here: at one of its other camps")
	equal(Model.Here(data, Stand(0.48, 0.9), { camps }), nil, "here: not away from every camp")
	Model.Camp(data, Stand(0.40), camps, Passed(camps.shapes[1]))
	equal(camps.x, 0.46, "camp: passing the node's camp over moves the arrow to the nearest other camp")
end

-- Walking one objective's camps (#187): Brotherhood of Thieves (18) collects one item in three Elwynn camps.
do
	local h = harness.load({
		spf = "ended",
		charDB = { journey = "zone:1429" },
		planned = true,
		completed = { 783 },
		log = { { id = 18, title = "Brotherhood of Thieves", level = 4, complete = false } },
	})
	h.flush()
	local area
	for _, candidate in ipairs(h.ns.Route().steps) do
		area = area or (candidate.key == "area:18:4" and candidate or nil)
	end
	assert(area, "camps: the Brotherhood of Thieves area on the route")
	equal(#area.shapes, 1, "camps: one objective place")
	local spots = h.ns.Model.Spots(area)
	equal(#spots, 3, "camps: and its three camps")
	local labels = {}
	h.ns.Menu.Step(
		setmetatable({}, {
			__index = function()
				return function(_, text)
					labels[#labels + 1] = text
					return setmetatable({}, {
						__index = function()
							return function() end
						end,
					})
				end
			end,
		}),
		area
	)
	local offered = false
	for _, label in ipairs(labels) do
		offered = offered or label == h.ns.L.NEXT_CAMP
	end
	equal(offered, true, "camps: Next spot offered for a single objective")
	local function Walk(spot)
		h.MovePlayer(spot.map, spot.x, spot.y)
		h.fire("PLAYER_STARTED_MOVING")
		h.fire("PLAYER_STOPPED_MOVING")
		h.flush()
		return h.ns.Route().steps[1]
	end
	local head = Walk(spots[1])
	equal(head.key == area.key and head.here == true, true, "camps: at the first camp, here")
	h.ns.NextCamp(head)
	h.flush()
	head = h.ns.Route().steps[1]
	equal(head.here, nil, "camps: Next spot there leads on")
	local to = { map = head.map, x = head.x, y = head.y }
	equal(h.ns.Model.SpotKey(to), h.ns.Model.SpotKey(spots[2]), "camps: to the nearest other camp")
	-- Shortest Path's stop for it is that camp: its shape and reach.
	h.ns.StartRoute()
	h.flush()
	local stop
	for _, candidate in ipairs(h.spfRoute and h.spfRoute.stops or {}) do
		stop = stop or (candidate.x == to.x and candidate.y == to.y and candidate or nil)
	end
	equal(stop ~= nil, true, "camps: Shortest Path is sent to the camp")
	equal(stop.radius, spots[2].r, "camps: with that camp's reach")
	local shaped = false
	for _, shape in ipairs(stop.shapes or {}) do
		shaped = shaped or (shape.x == to.x and shape.y == to.y)
	end
	equal(shaped, true, "camps: and its shape")
	equal(#stop.shapes, 1, "camps: only that camp, not the one passed over")
	head = Walk(to)
	equal(head.key == area.key and head.here == true, true, "camps: arriving at it, here again")
	equal(h.ns.Model.SpotKey(head), h.ns.Model.SpotKey(spots[2]), "camps: the stop is the camp stood at")
	equal(#h.errors, 0, "camps: errors\n" .. table.concat(h.errors, "\n"))
end

print(("next_camp_spec: %d checks passed"):format(checks))
