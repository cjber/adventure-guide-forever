---@type string, AGFNamespace
local _, ns = ...
local floor = math.floor

local KINDS = { "Npc", "Object" }
local NAME_FIELDS = { "name" }
-- An objective NPC's spawns and lowest level, in one read: the level says how hard a spot's mobs are (#152).
local NPC_SPAWN_FIELDS = { "spawns", "minLevel" }
-- A cell is one square of a map's yard grid. No map is this many yards across, so a column and a row share a number.
local ROW = 2 ^ 16

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
local function Names(lib, kinds, sources, reads)
	local count = {}
	for _, kind in pairs(kinds) do
		count[kind] = (count[kind] or 0) + 1
	end
	local names
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
			end
		end
	end
	return names
end

-- An NPC's lowest level as QuestieDB gives it (`minLevel`), or false when it gives none.
---@param value any
---@return integer|false
function ns.QuestieLevel(value)
	local level = tonumber(value)
	return level and level > 0 and floor(level) or false
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
---@return table?, AGFObjectiveArea[]?, table?, boolean? unsupported, table<integer, string>? names
function ns.QuestieObjectives(lib, objectives, trigger, zone, data, mapOf, yield, questID, reads)
	-- Questie stores icon overrides, not required counts, in objective[3] (kill credits: [4]).
	-- Zero retains the objective slot; the quest log supplies its actual count after pickup.
	local need, areas, kinds = {}, {}, {}
	-- What each slot is named by: the QuestieDB entity and id.
	---@type table<integer, {kind: string, id: integer?}>
	local sources = {}
	-- `lists` holds spawn tables, and `lists.levels` each one's NPC lowest level (false: an object, or unknown). A
	-- spot's level is the lowest of its mobs', only when every spawn in it has one.
	local function Places(slot, lists)
		local cells, ordered = {}, {}
		local levels = lists.levels or {}
		for index, spawns in ipairs(lists) do
			local level = levels[index] or false
			for area, coordinates in pairs(spawns) do
				local map = mapOf(area)
				local geometry = map and data.maps[map]
				if geometry then
					---@cast map -?
					local sx, sy = geometry.sx, geometry.sy
					local onMap = cells[map]
					if not onMap then
						onMap = {}
						cells[map] = onMap
					end
					for _, xy in ipairs(coordinates) do
						local x, y = tonumber(xy[1]), tonumber(xy[2])
						if x and y and x >= 0 and x <= 100 and y >= 0 and y <= 100 then
							x, y = x / 100, y / 100
							local key = floor(x * sx / 100) * ROW + floor(y * sy / 100)
							local cell = onMap[key]
							if not cell then
								cell = { map = map, x = x, y = y, count = 0, reach = 0, level = level }
								onMap[key] = cell
								ordered[#ordered + 1] = cell
							elseif cell.level and (not level or level < cell.level) then
								cell.level = level
							end
							cell.count = cell.count + 1
							local dx, dy = (x - cell.x) * sx, (y - cell.y) * sy
							local reach = dx * dx + dy * dy
							if reach > cell.reach then
								cell.reach = reach
							end
						end
					end
					yield()
				end
			end
		end
		table.sort(ordered, function(a, b)
			if (a.map == zone) ~= (b.map == zone) then
				return a.map == zone
			end
			if a.count ~= b.count then
				return a.count > b.count
			end
			if a.map ~= b.map then
				return a.map < b.map
			end
			if a.x ~= b.x then
				return a.x < b.x
			end
			return a.y < b.y
		end)
		for i = 1, math.min(3, #ordered) do
			local cell = ordered[i]
			areas[#areas + 1] = {
				slot,
				math.floor(cell.x * 1000 + 0.5),
				math.floor(cell.y * 1000 + 0.5),
				math.ceil(math.sqrt(cell.reach)),
				cell.map,
				cell.level or nil,
			}
		end
	end
	local function Spawns(kind, id, lists)
		local spawns = reads[kind][id]
		if spawns == nil then
			local npc = kind == "Npc"
			local values = lib[kind].GetAll(id, npc and NPC_SPAWN_FIELDS or ns.QuestieFields.spawns)
			spawns = values and type(values[1]) == "table" and values[1] or false
			reads[kind][id] = spawns
			if npc then
				reads.levels[id] = ns.QuestieLevel(values and values[2])
			end
			yield()
		end
		if spawns then
			lists[#lists + 1] = spawns
			lists.levels = lists.levels or {}
			lists.levels[#lists] = kind == "Npc" and reads.levels[id] or false
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
		Places(explore, { trigger[2] })
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
