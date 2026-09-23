-- Run from the repository root: luajit tests/plan_golden_spec.lua
-- Golden routes (docs/plan.md §1.5): each fixed character's zone choices and route, written as text in
-- tests/golden/<fixture>.txt, so every model change shows as a reviewable diff. AGF_UPDATE_GOLDEN=1 rewrites them.
local ns = {}
assert(loadfile("Data/Quests.lua"))("AdventureGuideForever", ns)
assert(loadfile("Model.lua"))("AdventureGuideForever", ns)
local characters = dofile("tests/fixtures/characters.lua")
local Model, data, checks = ns.Model, ns.Data, 0
local update = os.getenv("AGF_UPDATE_GOLDEN") == "1"

local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local function Place(map, x, y)
	return ("%d %.4f,%.4f"):format(map, x, y)
end

local function Render(fixture, zones, route)
	local lines = {
		("# %s: level %d, side %d, at %s"):format(
			fixture.name,
			fixture.level,
			fixture.side,
			Place(fixture.map, fixture.x, fixture.y)
		),
	}
	-- Today's cards are the route's zone choices, as the panel shows them; journey cards replace them in F2.
	for _, zone in ipairs(zones) do
		lines[#lines + 1] = ("card | %d %s | %d quests"):format(zone.map, zone.name, zone.quests)
	end
	for index, step in ipairs(route.steps) do
		lines[#lines + 1] = ("step %d | %s | %s | %s | %s"):format(
			index,
			step.key,
			step.title,
			Place(step.map, step.x, step.y),
			step.reason
		)
	end
	return table.concat(lines, "\n") .. "\n"
end

local function ValidPlace(step)
	return step.map > 0 and step.x >= 0 and step.x <= 1 and step.y >= 0 and step.y <= 1
end

for _, fixture in ipairs(characters.list) do
	local player, completed, log, prefs = characters.Resolve(data, fixture)
	local route = Model.Plan(data, player, completed, log, prefs)
	local zones = route.zones

	-- The standing rules: nothing ineligible is suggested, and no step points where the data has no place.
	equal(#route.steps <= Model.MAX_STEPS, true, fixture.name .. ": step cap")
	equal(#zones <= 3, true, fixture.name .. ": at most three cards")
	for _, step in ipairs(route.steps) do
		equal(ValidPlace(step), true, fixture.name .. ": " .. step.key .. " has a place")
		for _, id in ipairs(step.quests) do
			local takeable = log[id] ~= nil or Model.Eligible(data, player, completed, log, id)
			equal(takeable, true, fixture.name .. ": " .. step.key .. " quest " .. id .. " is eligible or in the log")
		end
	end

	-- F0: a turn-in in the next zone follows every step on this map and precedes every other-continent step.
	if fixture.name == "ne21_crosszone" then
		local next
		for index, step in ipairs(route.steps) do
			next = step.key == "turnin:967" and index or next
		end
		equal(next ~= nil, true, "ne21_crosszone: the Ashenvale turn-in is on the route")
		for index, step in ipairs(route.steps) do
			if step.map == fixture.map then
				equal(index < next, true, "ne21_crosszone: " .. step.key .. " (Darkshore) comes first")
			elseif data.maps[step.map].continent ~= data.maps[fixture.map].continent then
				equal(index > next, true, "ne21_crosszone: " .. step.key .. " (another continent) comes after")
			end
		end
	end

	local text = Render(fixture, zones, route)
	local path = "tests/golden/" .. fixture.name .. ".txt"
	if update then
		local handle = assert(io.open(path, "w"))
		handle:write(text)
		handle:close()
	end
	local handle = assert(io.open(path), path .. " missing: run with AGF_UPDATE_GOLDEN=1")
	local stored = handle:read("*a")
	handle:close()
	equal(text, stored, fixture.name .. ": golden route (AGF_UPDATE_GOLDEN=1 rewrites it)")
	-- Deterministic: a second build of the same state gives the same text.
	local again = Model.Plan(data, player, completed, log, prefs)
	equal(Render(fixture, again.zones, again), text, fixture.name .. ": rebuild")
end

print(("plan_golden_spec: %d checks passed; %d fixtures"):format(checks, #characters.list))
