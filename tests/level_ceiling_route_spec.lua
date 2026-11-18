-- Run from the repository root: luajit tests/level_ceiling_route_spec.lua
-- #846: the "Maximum quest level above yours" setting (maxQuestLevelOffset) caps what the route sends the player to.
-- Pickups were already capped (Model.Hard); a quest under way in the log past the ceiling still became the route's
-- area steps, ordered later but leading whenever a lap's return waited on it. Every card of every plan, for a level 20
-- Human in Redridge and a level 20 Orc in the Barrens with each over-ceiling quest of their zone in the log, holds no
-- step that works a quest past the ceiling; a finished one's hand-in still shows, and raising the setting brings the
-- quest back.
local ns = {}
ns.Data = dofile("tests/harness.lua").data()
dofile("tests/harness.lua").model(ns)
local Model, data, checks = ns.Model, ns.Data, 0

local function ok(value, label)
	checks = checks + 1
	if not value then
		error(label, 2)
	end
end

local prefs = { quests = true, dungeons = true, skipped = {} }
local function Works(route, id)
	for _, journey in ipairs(route.journeys) do
		for _, step in ipairs(journey.steps) do
			if step.kind ~= "turnin" and step.kind ~= "town" then
				for _, quest in ipairs(step.quests) do
					if quest == id then
						return journey.key .. " " .. step.key
					end
				end
			end
		end
	end
end
local function HandsIn(route, id)
	for _, journey in ipairs(route.journeys) do
		for _, step in ipairs(journey.steps) do
			for _, quest in ipairs(Model.Handins(step)) do
				if quest == id then
					return true
				end
			end
		end
	end
	return false
end

local CASES = {
	{ name = "Human in Redridge", side = 1, raceBit = 1, classBit = 1, map = 1433, x = 0.31, y = 0.48 },
	{ name = "Orc in the Barrens", side = 2, raceBit = 2, classBit = 1, map = 1413, x = 0.52, y = 0.30 },
}
for _, case in ipairs(CASES) do
	for _, offset in ipairs({ 0, 2 }) do
		local player = {
			level = 20,
			maxLevel = 60,
			side = case.side,
			raceBit = case.raceBit,
			classBit = case.classBit,
			map = case.map,
			x = case.x,
			y = case.y,
			logMax = 20,
			maxQuestLevelOffset = offset,
		}
		local tried = 0
		for id, quest in pairs(data.quests) do
			local over = quest.level - player.level
			if quest.zone == case.map and over > offset and over <= 8 and quest.obj and #quest.obj > 0 then
				local log = { [id] = { id = id, title = quest.title, level = quest.level, complete = false } }
				-- Tracked, so the My tracked quests card is asked for it too.
				player.tracked = { [id] = true }
				local route = Model.Plan(data, player, {}, log, prefs)
				local where = Works(route, id)
				ok(
					where == nil,
					("%s +%d: quest %d (level %d) is worked at %s"):format(
						case.name,
						offset,
						id,
						quest.level,
						tostring(where)
					)
				)
				tried = tried + 1
			end
		end
		ok(tried > 0, case.name .. ": the zone has quests past the ceiling")
	end
end

-- A finished quest past the ceiling still shows its hand-in, and a raised ceiling brings the quest's work back.
local player = { level = 20, maxLevel = 60, side = 1, raceBit = 1, classBit = 1, map = 1433, x = 0.31, y = 0.48 }
player.logMax, player.maxQuestLevelOffset = 20, 2
local found = false
for id, quest in pairs(data.quests) do
	if quest.zone == 1433 and quest.level == 25 and quest.obj and #quest.obj > 0 and quest.finish then
		found = true
		local done = { [id] = { id = id, title = quest.title, level = 25, complete = true } }
		ok(HandsIn(Model.Plan(data, player, {}, done, prefs), id), "a finished quest past the ceiling is handed in")
		player.maxQuestLevelOffset = 5
		local open = { [id] = { id = id, title = quest.title, level = 25, complete = false } }
		ok(Works(Model.Plan(data, player, {}, open, prefs), id), "a raised ceiling brings the quest's work back")
		player.maxQuestLevelOffset = 2
		-- The log's level decides over the data's, and a log level of 0 (the client gave none) leaves it to the data.
		local function Log(level)
			return { [id] = { id = id, title = quest.title, level = level, complete = false } }
		end
		ok(not Works(Model.Plan(data, player, {}, Log(0), prefs), id), "a log level of 0 falls back to the data's 25")
		ok(Works(Model.Plan(data, player, {}, Log(21), prefs), id), "the log's level 21 decides over the data's 25")
		-- The in-combat rebuild drops the quest's work too, when the setting drops between full builds.
		player.maxQuestLevelOffset = 5
		local wide = Model.Plan(data, player, {}, open, prefs)
		player.maxQuestLevelOffset = 2
		local fight = Model.Refresh(data, player, {}, open, prefs, wide)
		ok(
			not Works(fight, id),
			"the in-combat rebuild drops work past a lowered ceiling: " .. tostring((Works(fight, id)))
		)
		break
	end
end
ok(found, "Redridge has a level 25 quest to hand in")

-- The in-combat rebuild drops pickups past a lowered ceiling, and the planned work they open, as a full build does.
do
	local wide = { level = 20, maxLevel = 60, side = 1, raceBit = 1, classBit = 1, map = 1433, x = 0.31, y = 0.48 }
	wide.logMax, wide.maxQuestLevelOffset = 20, 5
	local route = Model.Plan(data, wide, {}, {}, prefs)
	local function Past(plan, ceiling)
		for _, journey in ipairs(plan.journeys) do
			for _, step in ipairs(journey.steps) do
				for _, id in ipairs(step.pickups or step.quests or {}) do
					local quest = data.quests[id]
					if quest and quest.level - wide.level > ceiling then
						return journey.key .. " " .. step.key .. " quest " .. id
					end
				end
			end
		end
	end
	ok(Past(route, 2) ~= nil, "at +5 the route picks up a quest past +2")
	wide.maxQuestLevelOffset = 2
	local fight = Model.Refresh(data, wide, {}, {}, prefs, route)
	local where = Past(fight, 2)
	ok(where == nil, "the in-combat rebuild drops pickups past a lowered ceiling: " .. tostring(where))
end
-- The log's own level past the ceiling keeps a quest off even where the data's level is within it.
for id, quest in pairs(data.quests) do
	if quest.zone == 1433 and quest.level == 20 and quest.obj and #quest.obj > 0 then
		local log = { [id] = { id = id, title = quest.title, level = 25, complete = false } }
		ok(not Works(Model.Plan(data, player, {}, log, prefs), id), "the log's level 25 decides over the data's 20")
		break
	end
end

-- A dungeon quest past the ceiling in the log leaves the dungeon card's work too.
local dungeons = 0
for id, quest in pairs(data.quests) do
	if quest.dungeon and quest.level - player.level > 2 and quest.level - player.level <= 6 and quest.side ~= 2 then
		local log = { [id] = { id = id, title = quest.title, level = quest.level, complete = false } }
		local where = Works(Model.Plan(data, player, {}, log, prefs), id)
		ok(where == nil, ("dungeon quest %d (level %d) is worked at %s"):format(id, quest.level, tostring(where)))
		dungeons = dungeons + 1
	end
end
ok(dungeons > 0, "dungeon quests past the ceiling were tried")

print(("level_ceiling_route_spec: %d checks passed"):format(checks))
