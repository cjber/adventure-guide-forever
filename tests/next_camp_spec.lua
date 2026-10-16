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
-- Standing in the area (#151): the spot that counts is the one the player stands in, not the arrow's.
local function Inside(at, passed)
	local step = Area()
	step.here = true
	local stand = { map = MAP, x = at.x, y = 0.5 }
	local camp = Model.CampAt(data, stand, step)
	Model.Camp(data, stand, step, passed)
	return step, camp
end
local step, at = Inside(near, Passed())
equal(step.here, true, "inside: in a spot not passed over, the area stays theirs")
equal(step.x, middle.x, "inside: and the point stays")
equal(at, near, "inside: the spot passed over is the one stood in, not the arrow's")
step = Inside(near, Passed(near))
equal(step.here, nil, "inside: in a spot passed over, the step stops being here")
equal(step.x, middle.x, "inside: and points at the nearest spot not passed over")
step = Inside(middle, Passed(near))
equal(step.here, true, "inside: walking into the next spot makes it theirs again")
step = Inside({ x = 0.42 + 0.0005 }, Passed(far))
equal(step.here, true, "inside: a step off a spot's centre is still at it")
local _, nearestEdge = Inside({ x = 0.4401 }, Passed(near))
equal(nearestEdge, middle, "camp at: the spot whose edge is nearest")
local wide = Shape(0.42)
wide.r = 400
step = Area()
step.here, step.shapes = true, { wide, middle }
equal(
	Model.CampAt(data, { map = MAP, x = 0.455, y = 0.5 }, step),
	wide,
	"camp at: the spot stood in, though another centre is nearer"
)
step = Area()
step.here = true
Model.Camp(data, { map = MAP, x = 0.43, y = 0.9 }, step, Passed(near))
equal(step.here, nil, "in the ring, nearest a spot passed over: on to the nearest spot not passed over")
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

-- Walking (#151): a Duskwood area of two spots. Stand at one, pass it over, walk to the spot the arrow leads to, and
-- back; each change of spot rebuilds as the player walks, though the area the player stands in stays the same.
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
	equal(#spots, 2, "walk: two spots")
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
	equal(h.ns.Model.SpotKey(head), h.ns.Model.SpotKey(spots[2]), "walk: to the other spot")
	local function Walk(spot)
		h.MovePlayer(spot.map, spot.x, spot.y)
		local plans = h.modelCalls.Plan
		h.fire("PLAYER_STARTED_MOVING")
		h.fire("PLAYER_STOPPED_MOVING")
		h.flush()
		return h.modelCalls.Plan - plans
	end
	equal(Walk(spots[2]) > 0, true, "walk: arriving rebuilds")
	head = h.ns.Route().steps[1]
	equal(head.key == area.key and head.here == true, true, "walk: arriving, the area is theirs again")
	equal(Walk(spots[2]), 0, "walk: standing on at it, no rebuild")
	equal(Walk(first) > 0, true, "walk: back to the spot passed over rebuilds")
	equal(h.ns.Route().steps[1].here, nil, "walk: and leads on again")
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

print(("next_camp_spec: %d checks passed"):format(checks))
