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
equal(Camp(Passed(middle, near, far)), near.x, "camp: all passed over, the nearest other spot")
equal(Camp(Passed(middle), far), far.x, "camp: a spot not passed over keeps the arrow")
local step = Area()
step.here = true
Model.Camp(data, player, step, Passed(middle))
equal(step.x, middle.x, "camp: not while standing in the area")
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

print(("next_camp_spec: %d checks passed"):format(checks))
