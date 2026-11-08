-- Run from the repository root: luajit tests/calling_spec.lua
-- Your calling offers the class quests this character can take, nearest first (#491). The Goldshire Taming the Beast
-- chain is the Human hunter's, so the data correction in Integrations/QuestieSource.lua keeps it off a Night Elf who
-- finished the Teldrassil chain; the card then leads with the nearest class quest rather than the lowest ID.
local harness = dofile("tests/harness.lua")
local ns = {}
local Model = harness.model(ns)
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- The real corpus, after the QuestieDB build: the Goldshire chain shares an exclusive group with the Dwarf, Night Elf
-- and Skyborne race chains, so a hunter who finished their own chain is never offered the Elwynn alternative.
do
	local data = harness.data()
	local goldshire = data.quests[94792]
	equal(goldshire.races, nil, "goldshire: still open to every Alliance hunter by race")
	equal(goldshire.group, 6063, "goldshire: one exclusive group with the race chains")
	equal(
		table.concat(goldshire.closedBy or {}, ","),
		"6063,6064,94007,94978",
		"goldshire: closes when a race chain starts"
	)
	for _, id in ipairs({ 6063, 6064, 94007, 94978 }) do
		equal(
			data.quests[id].closedBy and data.quests[id].closedBy[1],
			94792,
			"race chain " .. id .. " closes when Goldshire starts"
		)
	end
	local finished = { [6063] = true, [6101] = true, [6102] = true, [6103] = true }
	local nightelf = {
		level = 15,
		maxLevel = 60,
		side = 1,
		raceID = 4,
		raceBit = 8,
		classID = 3,
		classBit = 4,
		map = 1438,
		x = 0.5,
		y = 0.5,
	}
	local human = {
		level = 15,
		maxLevel = 60,
		side = 1,
		raceID = 1,
		raceBit = 1,
		classID = 3,
		classBit = 4,
		map = 1429,
		x = 0.5,
		y = 0.5,
	}
	local dwarf = {
		level = 15,
		maxLevel = 60,
		side = 1,
		raceID = 3,
		raceBit = 4,
		classID = 3,
		classBit = 4,
		map = 1426,
		x = 0.5,
		y = 0.5,
	}
	equal(Model.Eligible(data, nightelf, finished, {}, 94792), false, "goldshire: Night Elf after Teldrassil")
	equal(Model.Eligible(data, human, {}, {}, 94792), true, "goldshire: Human hunter")
	equal(Model.Eligible(data, dwarf, { [6064] = true }, {}, 94792), false, "goldshire: Dwarf after Dun Morogh")
	equal(
		Model.Eligible(data, nightelf, {}, {}, 94792),
		true,
		"goldshire: Night Elf before Teldrassil can still take the Elwynn alternative"
	)
	-- The race chain leads the calling before it is done, so the Elwynn alternative is not offered twice.
	local prefs = { quests = true, dungeons = false, skipped = {}, optimisedRoute = true }
	local offered = false
	for _, journey in ipairs(Model.Plan(data, nightelf, {}, {}, prefs).journeys) do
		if journey.kind == "calling" then
			for _, step in ipairs(journey.steps) do
				for _, id in ipairs(step.quests or {}) do
					offered = offered or id == 94792
				end
			end
		end
	end
	equal(offered, false, "goldshire: the race chain hides the Elwynn alternative")
end

-- Two class quests, both open now: the far one has the lower ID, the near one the higher. The card names the near
-- one, so its reason is what the player is sent to do, not the first ID the eligible list happens to hold.
do
	local data = { quests = {}, zones = { [1] = { name = "Zone", min = 10, max = 20 } } }
	local function quest(x, title)
		return {
			title = title,
			level = 10,
			min = 10,
			side = 1,
			classes = 4,
			zone = 1,
			start = { map = 1, x = x, y = 0.5, name = "Quest giver" },
			finish = { map = 1, x = x, y = 0.5, name = "Quest ender" },
		}
	end
	data.quests[2] = quest(0.9, "Far quest")
	data.quests[9] = quest(0.2, "Near quest")
	local player = {
		level = 15,
		maxLevel = 60,
		side = 1,
		raceBit = 1,
		classBit = 4,
		map = 1,
		x = 0.1,
		y = 0.5,
	}
	local prefs = { quests = true, dungeons = false, skipped = {}, optimisedRoute = true }
	local calling
	for _, journey in ipairs(Model.Plan(data, player, {}, {}, prefs).journeys) do
		if journey.kind == "calling" then
			calling = journey
		end
	end
	equal(calling ~= nil, true, "nearest: a calling card")
	equal(calling.reason, "A task for your class: Near quest", "nearest: it leads with the near quest")
end

print(("calling_spec: %d checks passed"):format(checks))
