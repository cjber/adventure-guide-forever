---@type string, AGFNamespace
local _, ns = ...
local floor = math.floor

local KINDS = { "Npc", "Object" }
local NAME_FIELDS = { "name" }
-- A cell is one square of a map's yard grid. No map is this many yards across, so a column and a row share a number.
local ROW = 2 ^ 16
-- A camp's reach in yards: the spawns this near a spawn are its camp, and spawns are bucketed into squares this wide,
-- so a spawn's camp is in its own square or the eight around it.
local CAMP = 100
-- Just over CAMP squared: a square root that rounds to exactly CAMP still counts, as Camp counts it.
local CAMP_SQUARED = CAMP * CAMP * (1 + 1e-9)

-- The spawns in `spawn`'s camp (within CAMP yards of it, itself included), from the squares around it.
---@param onMap table<integer, table[]>
---@return table[] camp, number sum their summed yards from it
local function Camp(onMap, spawn, sx, sy)
	local camp, sum = {}, 0
	for dx = -ROW, ROW, ROW do
		for dy = -1, 1 do
			for _, other in ipairs(onMap[spawn.key + dx + dy] or {}) do
				local ox, oy = (other.x - spawn.x) * sx, (other.y - spawn.y) * sy
				local yards = math.sqrt(ox * ox + oy * oy)
				if yards <= CAMP then
					camp[#camp + 1], sum = other, sum + yards
					other.yards = yards
				end
			end
		end
	end
	return camp, sum
end

-- How many spawns `spawn`'s camp holds and their summed yards from it: Camp's measure without the list, since every
-- spawn of an objective is measured and only the three camps chosen need theirs. Squared yards are compared first, so
-- the square root is taken only for a member.
---@param onMap table<integer, table[]>
---@return integer size, number sum
local function CampSize(onMap, spawn, sx, sy)
	local size, sum, x, y, key = 0, 0, spawn.x, spawn.y, spawn.key
	for dx = -ROW, ROW, ROW do
		for dy = -1, 1 do
			local square = onMap[key + dx + dy]
			if square then
				for index = 1, #square do
					local other = square[index]
					local ox, oy = (other.x - x) * sx, (other.y - y) * sy
					local squared = ox * ox + oy * oy
					if squared <= CAMP_SQUARED then
						local yards = math.sqrt(squared)
						if yards <= CAMP then
							size, sum = size + 1, sum + yards
						end
					end
				end
			end
		end
	end
	return size, sum
end

-- Whether spawn `a` makes a better camp centre than `b`: the quest's zone first, then the most spawns within CAMP
-- yards, the nearest together on a tie, then by map and place so the choice is the same every build.
local function Before(a, b, zone)
	if (a.map == zone) ~= (b.map == zone) then
		return a.map == zone
	end
	if a.size ~= b.size then
		return a.size > b.size
	end
	if a.sum ~= b.sum then
		return a.sum < b.sum
	end
	if a.map ~= b.map then
		return a.map < b.map
	end
	if a.x ~= b.x then
		return a.x < b.x
	end
	return a.y < b.y
end

-- The names a client objective of a shared type is matched by (Planning/Steps.lua OpenSlots): only where two or more
-- slots share a type, since a type of its own lines up already. Each slot's QuestieDB NPC, object or item name, in the
-- client's language and lower-cased once here; a kill credit's is its root NPC's. QuestieDB's objective text overrides
-- are English only, so they are left out. nil when no slot shares a type or none has a name. A name is optional: a
-- QuestieDB without one (or one that fails to answer) leaves that slot to order.
---@param lib AGFQuestieDB
---@param kinds table<integer, string>
---@param sources table<integer, {kind: string, id: integer?}>
---@param reads AGFQuestieReads
---@return table<integer, string>?
---@return table<integer, integer>?
local function Names(lib, kinds, sources, reads)
	local count = {}
	for _, kind in pairs(kinds) do
		count[kind] = (count[kind] or 0) + 1
	end
	local names, items
	for slot, kind in pairs(kinds) do
		local source = sources[slot]
		if count[kind] > 1 and source and source.id then
			local cache = reads.names[source.kind]
			local name = cache[source.id]
			if name == nil then
				local ok, values = pcall(lib[source.kind].GetAll, source.id, NAME_FIELDS)
				local value = ok and type(values) == "table" and values[1]
				name = type(value) == "string" and value ~= "" and value:lower() or false
				cache[source.id] = name
			end
			if name then
				names = names or {}
				names[slot] = name
				if kind == "item" then
					items = items or {}
					items[slot] = source.id
				end
			end
		end
	end
	return names, items
end

-- An NPC's spawns, lowest level and rank, as one read (ns.QuestieFields, set by QuestieSource.lua, which loads after
-- this).
---@type string[]?
local npcSpawnLevel, npcSpawnLevelRank

-- An NPC's lowest level as QuestieDB gives it (`minLevel`), or false when it gives none.
---@param value any
---@return integer|false
function ns.QuestieLevel(value)
	local level = tonumber(value)
	return level and level > 0 and floor(level) or false
end

-- Whether QuestieDB's NPC rank (`rank`, CMaNGOS creature_template) is an elite's: 1 elite, 2 rare elite, 3 boss. A
-- normal (0) or rare (4) mob, or none given, is not.
---@param value any
---@return boolean
function ns.QuestieElite(value)
	local rank = tonumber(value)
	return rank == 1 or rank == 2 or rank == 3
end

-- Locations come from the provider's composed spawns. Bucket nearby spawns and choose a real point in each
-- bucket, rather than directing the player to an average that may be inside terrain or across a river.
---@param lib AGFQuestieDB
---@param objectives table?
---@param trigger table?
---@param zone integer?
---@param data AGFData
---@param mapOf fun(area: integer): integer?
---@param yield fun()
---@param questID integer
---@param reads AGFQuestieReads one catalogue build's QuestieDB answers, so a creature many quests share is read once
---@return table?, AGFObjectiveArea[]?, table?, boolean? unsupported
---@return table<integer, string>? names
---@return table<integer, integer>? items
function ns.QuestieObjectives(lib, objectives, trigger, zone, data, mapOf, yield, questID, reads)
	-- Questie stores icon overrides, not required counts, in objective[3] (kill credits: [4]).
	-- Zero retains the objective slot; the quest log supplies its actual count after pickup.
	local need, areas, kinds = {}, {}, {}
	-- What each slot is named by: the QuestieDB entity and id.
	---@type table<integer, {kind: string, id: integer?}>
	local sources = {}
	-- `lists` holds { spawns, level, elite } entries: a spawn table, its NPC's lowest level (false: an object, or
	-- unknown) and whether that NPC is an elite. A spot is a camp: the spawn with the most others within CAMP yards,
	-- the quest's zone first, the spawns nearest it on a tie, at most three apart. A spot's level is the lowest of its
	-- mobs', only when every spawn in it has one; a spot is elite only when every spawn in it is an elite's.
	local function Camps(lists)
		local camps, squares, spawns, scales = {}, {}, {}, {}
		for _, list in ipairs(lists) do
			local level, elite = list[2], list[3]
			for area, coordinates in pairs(list[1]) do
				local map = mapOf(area)
				local geometry = map and data.maps[map]
				if geometry then
					---@cast map -?
					local sx, sy = geometry.sx, geometry.sy
					scales[map] = geometry
					local onMap = squares[map]
					if not onMap then
						onMap = {}
						squares[map] = onMap
					end
					for _, xy in ipairs(coordinates) do
						local x, y = tonumber(xy[1]), tonumber(xy[2])
						if x and y and x >= 0 and x <= 100 and y >= 0 and y <= 100 then
							x, y = x / 100, y / 100
							local key = floor(x * sx / CAMP) * ROW + floor(y * sy / CAMP)
							local spawn = { map = map, key = key, x = x, y = y, level = level, elite = elite }
							local square = onMap[key]
							if not square then
								square = {}
								onMap[key] = square
							end
							square[#square + 1], spawns[#spawns + 1] = spawn, spawn
						end
					end
					yield()
				end
			end
		end
		for index, spawn in ipairs(spawns) do
			local geometry = scales[spawn.map]
			spawn.size, spawn.sum = CampSize(squares[spawn.map], spawn, geometry.sx, geometry.sy)
			if index % 64 == 0 then
				yield()
			end
		end
		-- Up to three camps, each centred on a spawn in no camp taken before it, so "Next spot" moves between camps:
		-- the first in Before's order that is still free, picked by a scan rather than sorting every spawn.
		for _ = 1, 3 do
			local spawn
			for _, other in ipairs(spawns) do
				if not other.used and (not spawn or Before(other, spawn, zone)) then
					spawn = other
				end
			end
			if not spawn then
				break
			end
			local geometry = scales[spawn.map]
			local reach, level, elite = 0, spawn.level, spawn.elite
			for _, other in ipairs((Camp(squares[spawn.map], spawn, geometry.sx, geometry.sy))) do
				other.used = true
				reach = math.max(reach, other.yards)
				level = level and other.level and math.min(level, other.level) or false
				elite = elite and other.elite
			end
			camps[#camps + 1] = {
				x = math.floor(spawn.x * 1000 + 0.5),
				y = math.floor(spawn.y * 1000 + 0.5),
				reach = math.ceil(reach),
				map = spawn.map,
				level = level or nil,
				elite = level and elite or nil,
			}
			yield()
		end
		return camps
	end
	-- The slot's camps as area records. Many quests send the player to the same creatures, so the camps of one set of
	-- QuestieDB entities (lists.key, Spawns) and quest zone are found once a build.
	local function Places(slot, lists)
		local key = lists.key and lists.key .. "@" .. tostring(zone)
		local camps = key and reads.camps[key]
		if not camps then
			camps = Camps(lists)
			if key then
				reads.camps[key] = camps
			end
		end
		for _, camp in ipairs(camps) do
			areas[#areas + 1] = {
				slot,
				camp.x,
				camp.y,
				camp.reach,
				camp.map,
				camp.level,
				-- Only after a level, so the record stays a plain list.
				camp.elite,
			}
		end
	end
	-- An NPC's spawns, lowest level and rank are one read, when the build reads levels (reads.levels).
	local levels, elites = reads.levels, reads.elite
	local fields = ns.QuestieFields
	if levels and not npcSpawnLevel then
		npcSpawnLevel = { fields.spawns[1], fields.level[1] }
	end
	if levels and elites and not npcSpawnLevelRank then
		npcSpawnLevelRank = { fields.spawns[1], fields.level[1], fields.rank[1] }
	end
	local npcFields = levels and (elites and npcSpawnLevelRank or npcSpawnLevel) or fields.spawns
	local function Spawns(kind, id, lists)
		local spawns = reads[kind][id]
		local npc = kind == "Npc"
		if spawns == nil then
			local values = lib[kind].GetAll(id, npc and npcFields or ns.QuestieFields.spawns)
			spawns = values and type(values[1]) == "table" and values[1] or false
			reads[kind][id] = spawns
			if npc and levels then
				levels[id] = ns.QuestieLevel(values and values[2])
			end
			if npc and elites then
				elites[id] = ns.QuestieElite(values and values[3])
			end
			yield()
		end
		if spawns then
			lists[#lists + 1] =
				{ spawns, npc and levels and levels[id] or false, npc and elites and elites[id] or false }
			lists.key = (lists.key or "") .. kind .. id .. ","
		end
	end
	local function Item(id, lists, seen)
		if seen[id] then
			return
		end
		seen[id] = true
		local values = reads.Item[id]
		if values == nil then
			values = lib.Item.GetAll(id, ns.QuestieFields.drops) or false
			reads.Item[id] = values
		end
		if values then
			for index, kind in ipairs(KINDS) do
				for _, source in ipairs(type(values[index]) == "table" and values[index] or {}) do
					Spawns(kind, source, lists)
				end
			end
			for _, source in ipairs(type(values[3]) == "table" and values[3] or {}) do
				Item(source, lists, seen)
			end
		end
		yield()
	end
	local slot = 0
	local function KillCredits()
		for _, objective in ipairs(objectives and objectives[5] or {}) do
			if slot > 3 then
				return false
			end
			need[slot], kinds[slot] = 0, "monster"
			sources[slot] = { kind = "Npc", id = tonumber(objective[2]) }
			local lists = {}
			for _, id in ipairs(objective[1] or {}) do
				Spawns("Npc", id, lists)
			end
			Places(slot, lists)
			slot = slot + 1
		end
		return true
	end
	local creditFirst = lib.ObjectiveFirst
		and lib.ObjectiveFirst.killCreditObjectiveFirst
		and lib.ObjectiveFirst.killCreditObjectiveFirst[questID]
	if creditFirst and not KillCredits() then
		return nil, nil, nil, true
	end
	for index, kind in ipairs(KINDS) do
		for _, objective in ipairs(objectives and objectives[index] or {}) do
			if slot > 3 then
				return nil, nil, nil, true
			end
			need[slot], kinds[slot] = 0, kind == "Npc" and "monster" or "object"
			sources[slot] = { kind = kind, id = tonumber(objective[1]) }
			local lists = {}
			Spawns(kind, objective[1], lists)
			Places(slot, lists)
			slot = slot + 1
		end
	end

	if not creditFirst and not KillCredits() then
		return nil, nil, nil, true
	end
	for index, objective in ipairs(objectives and objectives[3] or {}) do
		if index > 4 then
			return nil, nil, nil, true
		end
		slot = index + 3
		need[slot], kinds[slot] = 0, "item"
		sources[slot] = { kind = "Item", id = tonumber(objective[1]) }
		local lists = {}
		Item(objective[1], lists, {})
		Places(slot, lists)
	end
	if type(trigger) == "table" and type(trigger[2]) == "table" then
		local explore = ns.Model.EXPLORE_SLOT
		need[explore], kinds[explore] = 1, "event"
		Places(explore, { { trigger[2], false, false } })
	end
	-- Spell/reputation objectives have no compatible planner slots; use the client's live quest POI instead.
	if objectives and (next(objectives[4] or {}) or next(objectives[6] or {})) then
		return nil, nil, nil, true
	end
	return next(need) and need or nil,
		areas[1] and areas or nil,
		next(kinds) and kinds or nil,
		nil,
		Names(lib, kinds, sources, reads)
end
