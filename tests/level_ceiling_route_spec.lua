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
for id, quest in pairs(data.quests) do
	if quest.zone == 1433 and quest.level == 25 and quest.obj and #quest.obj > 0 and quest.finish then
		local done = { [id] = { id = id, title = quest.title, level = 25, complete = true } }
		ok(HandsIn(Model.Plan(data, player, {}, done, prefs), id), "a finished quest past the ceiling is handed in")
		player.maxQuestLevelOffset = 5
		local open = { [id] = { id = id, title = quest.title, level = 25, complete = false } }
		ok(Works(Model.Plan(data, player, {}, open, prefs), id), "a raised ceiling brings the quest's work back")
		player.maxQuestLevelOffset = 2
		break
	end
end

print(("level_ceiling_route_spec: %d checks passed"):format(checks))
