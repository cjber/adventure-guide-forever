-- Run from the repository root: luajit tests/plan_golden_spec.lua
-- Golden routes (docs/plan.md §1.5): each fixed character's journey cards and their steps, written as text in
-- tests/golden/<fixture>.txt, so every model change shows as a reviewable diff. AGF_UPDATE_GOLDEN=1 rewrites them.
local ns = {}
assert(loadfile("Data/Quests.lua"))("AdventureGuideForever", ns)
-- Core.lua for ns.L, the planner's copy; its load-time hooks into the client are stubbed, since only the copy is read.
local core = assert(loadfile("Core.lua"))
setfenv(
	core,
	setmetatable({
		EventUtil = { ContinueOnAddOnLoaded = function() end },
		SlashCmdList = {},
		CreateFrame = function()
			return { SetScript = function() end }
		end,
	}, { __index = _G })
)
core("AdventureGuideForever", ns)
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

local function Render(fixture, route)
	local lines = {
		("# %s: level %d, side %d, at %s"):format(
			fixture.name,
			fixture.level,
			fixture.side,
			Place(fixture.map, fixture.x, fixture.y)
		),
	}
	-- Every card, the chosen one marked, each followed by its steps in route order.
	for _, journey in ipairs(route.journeys) do
		lines[#lines + 1] = ("card%s | %s | %s | %s | %s | map %d"):format(
			journey.key == route.journey and " (chosen)" or "",
			journey.key,
			journey.title,
			journey.subline,
			journey.reason or "-",
			journey.map
		)
		-- The log-full note: the quests it says could go.
		if journey.drop then
			lines[#lines + 1] = "  drop | " .. table.concat(journey.drop, " ")
		end
		-- An area adds its ring and objectives (quest/slot); a town the chapters that follow its hand-ins.
		for index, step in ipairs(journey.steps) do
			local extra = {}
			for _, objective in ipairs(step.objectives or {}) do
				extra[#extra + 1] = objective.id .. "/" .. objective.slot
			end
			for _, id in ipairs(step.follow or {}) do
				extra[#extra + 1] = "then " .. id
			end
			lines[#lines + 1] = ("  step %d | %s | %s | %s | %s%s%s"):format(
				index,
				step.key,
				step.title,
				Place(step.map, step.x, step.y),
				step.reason,
				step.objectives and (" | %d yd"):format(step.r + 0.5) or "",
				#extra > 0 and " | " .. table.concat(extra, " ") or ""
			)
		end
	end
	return table.concat(lines, "\n") .. "\n"
end

local function ValidPlace(step)
	return step.map > 0 and step.x >= 0 and step.x <= 1 and step.y >= 0 and step.y <= 1
end

for _, fixture in ipairs(characters.list) do
	local player, completed, log, prefs = characters.Resolve(data, fixture)
	local route = Model.Plan(data, player, completed, log, prefs)

	-- F2: at most three journeys, each with at least one step the player can take now. The standing rules hold on
	-- every card: nothing ineligible is suggested, and no step points where the data has no place.
	equal(#route.journeys <= Model.MAX_JOURNEYS, true, fixture.name .. ": at most three cards")
	-- The saved choice while its card is built, the first card otherwise.
	local first = route.journeys[1] and route.journeys[1].key
	equal(route.journey, prefs.journey or first, fixture.name .. ": the chosen card, else the first")
	for _, journey in ipairs(route.journeys) do
		local label = fixture.name .. ": " .. journey.key
		equal(#journey.steps >= 1 and #journey.steps <= Model.MAX_STEPS, true, label .. ": 1 to 9 steps")
		equal(journey.map, journey.steps[1].map, label .. ": the card turns the map to its first step")
		for _, step in ipairs(journey.steps) do
			equal(ValidPlace(step), true, label .. ": " .. step.key .. " has a place")
			for _, id in ipairs(step.quests) do
				local takeable = log[id] ~= nil or Model.Eligible(data, player, completed, log, id)
				equal(takeable, true, label .. ": " .. step.key .. " quest " .. id .. " is eligible or in the log")
			end
		end
		-- The next-zone rule: another zone than the story's, with at least 5 quests the player can take now.
		if journey.kind == "nextzone" then
			local map, quests = tonumber(journey.key:match("%d+")), 0
			for id, quest in pairs(data.quests) do
				if
					(quest.zone or (quest.start and quest.start.map)) == map
					and Model.Eligible(data, player, completed, log, id)
					and not Model.IsGray(quest.level, player.level)
				then
					quests = quests + 1
				end
			end
			equal(quests >= 5, true, label .. ": at least 5 quests there now")
			for _, other in ipairs(route.journeys) do
				equal(other == journey or other.key ~= journey.key, true, label .. ": another zone than the story's")
			end
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

	-- The reported case (design §2.10): standing in Redridge, where the level fits two levels on, the story is
	-- Redridge's whether or not it was chosen, never Darkshore's.
	if fixture.name == "human18_redridge" then
		prefs.journey = nil
		local unchosen = Model.Plan(data, player, completed, log, prefs).journeys[1]
		prefs.journey = fixture.prefs.journey
		equal(unchosen.title, "Redridge Mountains story", "human18_redridge: the story of the zone you stand in")
		equal(route.journeys[1].title, "Redridge Mountains story", "human18_redridge: chosen, the same card")
	end

	-- The user's report: with Redridge's quests taken on (the live client gives no waypoint for one under way), the
	-- story is Redridge's and leads, its quests under way are steps at the data's objective areas, and the two log
	-- cards count every carried quest between them, placed or not. Never Carry and a Darkshore story alone.
	if fixture.name == "human19_redridge_full" then
		local story, areas = route.journeys[1], 0
		equal(story.key, "zone:1433", "human19_redridge_full: Redridge is card 1")
		-- The story goes out one lap; carry holds the areas of the laps after it.
		local steps = {}
		for _, journey in ipairs(route.journeys) do
			for _, step in ipairs(journey.steps) do
				steps[#steps + 1] = (journey == story or step.map == 1433) and step or nil
			end
		end
		for _, step in ipairs(steps) do
			if step.kind == "area" or step.kind == "dungeon" then
				areas = areas + 1
				equal(step.map, 1433, "human19_redridge_full: " .. step.key .. " is on Redridge")
				local placed = false
				for _, id in ipairs(step.quests) do
					for _, area in ipairs(data.quests[id].obj or {}) do
						placed = placed
							or (
								(area[5] or data.quests[id].zone) == step.map
								and area[2] / 1000 == step.x
								and area[3] / 1000 == step.y
							)
					end
				end
				equal(placed, true, "human19_redridge_full: " .. step.key .. " is at a data objective area")
			end
		end
		equal(areas >= 5, true, "human19_redridge_full: the quests under way are area steps")
		local counted = 0
		for _, journey in ipairs(route.journeys) do
			equal(journey.key ~= "zone:1439", true, "human19_redridge_full: no Darkshore story")
			local lines = journey.subline .. "|" .. (journey.reason or "")
			for _, pattern in ipairs({ "(%d+) ready to hand in", "(%d+) in progress", "(%d+) to hand in across" }) do
				counted = counted + tonumber(lines:match(pattern) or 0)
			end
		end
		equal(counted, #fixture.log, "human19_redridge_full: every carried quest counted once")
	end

	-- F12: a route crosses an ocean at most once, and a turn-in over there waits until the route is there.
	local function Changes(steps)
		local changes = 0
		for index = 2, #steps do
			local before, after = data.maps[steps[index - 1].map], data.maps[steps[index].map]
			changes = changes + (before.continent ~= after.continent and 1 or 0)
		end
		return changes
	end
	for _, journey in ipairs(route.journeys) do
		equal(
			Changes(journey.steps) <= 1,
			true,
			fixture.name .. ": " .. journey.key .. ": at most one continent change"
		)
	end
	local changes = Changes(route.steps)
	if fixture.name == "ne21_crosszone" then
		local last = route.steps[#route.steps]
		equal(changes, 1, "ne21_crosszone: exactly one continent change")
		equal(last.key, "turnin:168", "ne21_crosszone: the Stormwind turn-in is last")
		-- F15: 168 is a Deadmines quest, flagged and not elite, so a dungeon quest you carry shows with dungeons off.
		local deadmines = data.quests[168]
		equal(deadmines.dungeon == 36 and not deadmines.elite, true, "ne21_crosszone: 168 is flagged, not elite")
		equal(prefs.dungeons, false, "ne21_crosszone: with dungeons off")
		equal(last.reason, "Hand in when you're in Stormwind City", "ne21_crosszone: the far turn-in says where")
		-- The in-game audit: the far turn-in is finished but not ready here, and the card says each fact once.
		local carry = route.journeys[2]
		equal(carry.key, "carry", "ne21_crosszone: carry follows the story")
		equal(carry.subline, "3 ready to hand in", "ne21_crosszone: ready counts this continent only")
		equal(carry.reason, "1 to hand in across the sea", "ne21_crosszone: the far one apart")
		equal(
			Model.Plan(data, player, completed, log, prefs, function()
				return "Hurlevent"
			end).steps[#route.steps].reason,
			"Hand in when you're in Hurlevent",
			"ne21_crosszone: the client's map name wins"
		)
	end

	local text = Render(fixture, route)
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
	equal(Render(fixture, again), text, fixture.name .. ": rebuild")
	-- The in-combat rebuild keeps three cards at most: a quest looted mid-fight brings a carry card the last build
	-- lacked, in the story's wake as the full build orders them, and the last card not chosen makes way, as the full
	-- build leaves it out (design §2.10).
	local saved, last = prefs.journey, route.journeys[#route.journeys]
	local fight = { [168] = { id = 168, title = "Collecting Memories", level = 18, complete = true } }
	prefs.journey = last and last.key
	local refreshed = Model.Refresh(data, player, completed, fight, prefs, route)
	local full = Model.Plan(data, player, completed, fight, prefs)
	equal(#refreshed.journeys <= Model.MAX_JOURNEYS, true, fixture.name .. ": at most three cards in combat")
	local story = refreshed.journeys[1].kind == "story"
	equal(refreshed.journeys[story and 2 or 1].key, "carry", fixture.name .. ": the new carry card after the story")
	equal(refreshed.journey, prefs.journey, fixture.name .. ": the chosen last card keeps its slot in combat")
	equal(full.journey == prefs.journey and full.chosen, last ~= nil, fixture.name .. ": and in the full build")
	prefs.journey = saved
end

print(("plan_golden_spec: %d checks passed; %d fixtures"):format(checks, #characters.list))
