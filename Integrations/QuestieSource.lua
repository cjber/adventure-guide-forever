---@type string, AGFNamespace
local _, ns = ...

-- QuestieDB owns the quest catalogue. Bundled geometry still places maps and transport hubs;
-- it never limits which quests exist. Questie supplies live availability policy (including events).

local ADDON = "QuestieDB"
-- The contract this file was written against. QuestieDB checks a RANGE (its minSupportedContract..contractVersion),
-- so a newer additive QuestieDB keeps working and new quests appear automatically via GetAllIds; only a rising
-- minSupportedContract (or a removed field, caught below) makes the catalogue unavailable, and the reason is shown.
local CONTRACT = 2
-- The catalogue is built once a login, and nothing can be shown until it lands: at a millisecond a frame the tracker
-- stayed empty for most of a minute. A few frames a second for a few seconds is the smaller cost.
local SLICE_MS = 5
-- Questie can load and then never report ready, when its own startup stops on an error for one character. Waiting
-- longer than this would leave the guide on its loading line for the whole session, so the catalogue is read without
-- Questie's live policy instead. A ready callback that arrives later reads it again.
local READY_WAIT = 60
local LINK = ns.Data.townLink
-- Daily and weekly quest flags also identify repeatable work.
local REPEATABLE_FLAGS = 4096 + 32768

local QUEST_FIELDS = {
	"name",
	"questLevel",
	"requiredLevel",
	"requiredMaxLevel",
	"requiredRaces",
	"requiredClasses",
	"zoneOrSort",
	"startedBy",
	"finishedBy",
	"preQuestGroup",
	"preQuestSingle",
	"nextQuestInChain",
	"breadcrumbForQuestId",
	"questFlags",
	"specialFlags",
	"objectives",
	"triggerEnd",
}
ns.QuestieFields = {
	spawns = { "spawns" },
	drops = { "npcDrops", "objectDrops", "itemDrops" },
}
local GIVER_FIELDS = { "name", ns.QuestieFields.spawns[1], "zoneID" }
local ENTITIES = {
	{ name = "Quest", keys = "questKeys", fields = QUEST_FIELDS },
	{ name = "Npc", keys = "npcKeys", fields = GIVER_FIELDS },
	{ name = "Object", keys = "objectKeys", fields = GIVER_FIELDS },
	{ name = "Item", keys = "itemKeys", fields = ns.QuestieFields.drops },
}

---@type AGFQuestieStatus
local status = { state = "unavailable", settled = false }
ns.QuestieStatus = status

-- One of ZoneDB's tables, which QuestieDB keeps as Lua source: run with no globals, since it is only a table literal.
---@param source any
---@return table?
local function Table(source)
	local chunk = type(source) == "string" and loadstring(source)
	if not chunk then
		return nil
	end
	setfenv(chunk, {})
	local ok, value = pcall(chunk)
	return ok and type(value) == "table" and value or nil
end

---@param lib AGFQuestieDB
---@param entities {name: string, keys: string, fields: string[]}[]
---@param extraFields? table<string, string[]>
---@return string?
local function MissingField(lib, entities, extraFields)
	for _, entity in ipairs(entities) do
		local meta = lib.Meta and lib.Meta[entity.name .. "Meta"]
		local keys, reader = meta and meta[entity.keys], lib[entity.name]
		if type(keys) ~= "table" or type(reader) ~= "table" or type(reader.GetAll) ~= "function" then
			return entity.name
		end
		if extraFields and type(reader.GetAllIds) ~= "function" then
			return entity.name .. ".GetAllIds"
		end
		---@type string[]
		local fields = extraFields and extraFields[entity.name] or entity.fields
		for _, field in ipairs(fields) do
			if not keys[field] then
				return field
			end
		end
	end
end

-- QuestieDB as this file reads it, or nil and why not (an ns.L line).
---@return AGFQuestieDB?, string?, AGFQuestieZones?
local function Fit()
	local lib = LibQuestieDB
	if type(lib) ~= "table" then
		return nil, ns.L.QUESTIE_ABSENT
	end
	-- Keep QuestieDB's own mismatch message (it names both versions) rather than the generic line, so the audit shows
	-- exactly why the catalogue is unavailable.
	local called, fits, why = pcall(lib.RequireContract, CONTRACT)
	if not (called and fits) then
		return nil, why or ns.L.QUESTIE_CONTRACT
	end
	if C_AddOns.GetAddOnMetadata(ADDON, "X-Flavor") ~= "Forever" then
		return nil, ns.L.QUESTIE_FLAVOUR
	end
	local missing = MissingField(lib, ENTITIES)
	if missing then
		return nil, ns.L.QUESTIE_FIELD:format(missing)
	end
	if type(lib.Quest.GetAllIds) ~= "function" then
		return nil, ns.L.QUESTIE_FIELD:format("Quest.GetAllIds")
	end
	local zoneDB = type(lib.Support) == "table" and lib.Support.Get("ZoneDB") or {}
	local private = zoneDB["private"]
	if type(private) ~= "table" then
		return nil, ns.L.QUESTIE_ZONES
	end
	local area, parent, instances =
		Table(private.areaIdToUiMapId), Table(private.subZoneToParentZone), zoneDB.instanceIdToAreaId
	if not (area and parent and type(instances) == "table") then
		return nil, ns.L.QUESTIE_ZONES
	end
	return lib,
		nil,
		{
			area = area,
			areaOverride = Table(private.areaIdToUiMapIdOverride) or {},
			parent = parent,
			parentOverride = Table(private.subZoneToParentZoneOverride) or {},
			instances = instances,
		}
end

-- The single class a bitmask names, or nil when it names none or several.
---@param classes integer
---@return integer?
local function SingleClass(classes)
	local found
	for class = 1, 11 do
		if bit.band(classes, 2 ^ (class - 1)) ~= 0 then
			if found then
				return nil
			end
			found = class
		end
	end
	return found
end

---@param races integer
---@return integer 1 Alliance, 2 Horde, 3 both, 0 neither (tools/gen_quests.py faction)
local function Side(races)
	if races == 0 then
		return 3
	end
	return (bit.band(races, 77) ~= 0 and 1 or 0) + (bit.band(races, 178) ~= 0 and 2 or 0)
end

---@param value number
---@return number
local function Round(value)
	return math.floor(value * 1e4 + 0.5) / 1e4
end

-- A place's continent and world yards, as tools/gen_quests.py world_point; nil on a map the data doesn't place.
---@param data AGFData
---@param place {map: integer, x: number, y: number}
---@return {continent: integer, x: number, y: number}?
local function World(data, place)
	local centre = data.maps[place.map]
	return centre
		and {
			continent = centre.continent,
			x = centre.cx - (place.y - 0.5) * centre.sy,
			y = centre.cy - (place.x - 0.5) * centre.sx,
		}
end

---@param continent integer
---@param x number
---@param y number
---@return string
local function Cell(continent, x, y)
	return continent .. ":" .. math.floor(x / LINK) .. ":" .. math.floor(y / LINK)
end

-- The bundled town anchors (Data/Geometry.lua `townAnchors`) in LINK-yard cells, so a place from QuestieDB joins the
-- town of the nearest one. Route geometry, not quest data: the anchors are the distinct quest-giver town places.
---@param data AGFData
---@param yield fun()
---@return table<string, {x: number, y: number, hub: integer}[]>
local function TownCells(data, yield)
	local cells = {}
	for _, place in ipairs(data.townAnchors or {}) do
		yield()
		local at = place.hub and World(data, place)
		if at then
			local key = Cell(at.continent, at.x, at.y)
			cells[key] = cells[key] or {}
			table.insert(cells[key], { x = at.x, y = at.y, hub = place.hub })
		end
	end
	return cells
end

-- Whether sort key `a` comes before `b`.
---@param a any[]
---@param b any[]
---@return boolean
local function Before(a, b)
	for i = 1, #a do
		if a[i] ~= b[i] then
			return a[i] < b[i]
		end
	end
	return false
end

---@param data AGFData
---@param cells table<string, {x: number, y: number, hub: integer}[]>
---@param place AGFPlace
---@return integer?
local function Hub(data, cells, place)
	local at = World(data, place)
	if not at then
		return nil
	end
	local best, hub = LINK * LINK, nil
	for dx = -LINK, LINK, LINK do
		for dy = -LINK, LINK, LINK do
			for _, other in ipairs(cells[Cell(at.continent, at.x + dx, at.y + dy)] or {}) do
				local d = (other.x - at.x) ^ 2 + (other.y - at.y) ^ 2
				if d <= best then
					best, hub = d, other.hub
				end
			end
		end
	end
	return hub
end

-- The instance each area belongs to, among the instances `keep` accepts: an instance's own area, then the alias areas
-- ZoneDB lists for its dungeon. Also ZoneDB's dungeon rows by area.
---@param lib AGFQuestieDB
---@param zones AGFQuestieZones
---@param keep fun(instance: integer): boolean
---@return table<integer, integer> instanceOf, table<integer, table> dungeons
local function InstanceAreas(lib, zones, keep)
	local zoneDB = lib.Support.Get("ZoneDB")
	local dungeons = zoneDB and zoneDB.private and zoneDB.private.dungeons or {}
	local instanceOf = {}
	for instance, area in pairs(zones.instances) do
		if keep(instance) then
			instanceOf[area] = instance
		end
	end
	for instance, area in pairs(zones.instances) do
		local dungeon = keep(instance) and dungeons[area]
		for _, alias in ipairs(type(dungeon) == "table" and type(dungeon[2]) == "table" and dungeon[2] or {}) do
			instanceOf[alias] = instanceOf[alias] or instance
		end
	end
	return instanceOf, dungeons
end

-- The build, as a coroutine body: ns.Data's replacement, or an error.
---@param lib AGFQuestieDB
---@param zones AGFQuestieZones
---@param bundled AGFData
---@param yield fun()
---@return table data an AGFData
local function Build(lib, zones, bundled, yield)
	local function Parent(area)
		return zones.parentOverride[area] or zones.parent[area]
	end
	-- An area's map, or its parent zone's; only a map the data places.
	local function Map(area)
		local map = zones.areaOverride[area] or zones.area[area]
		local parent = not map and Parent(area)
		map = map or (parent and (zones.areaOverride[parent] or zones.area[parent]))
		return type(map) == "number" and bundled.maps[map] and map or nil
	end
	local instanceOf = InstanceAreas(lib, zones, function(instance)
		return bundled.instances[instance] ~= nil
	end)
	local cells = TownCells(bundled, yield)
	-- Each giver's name, its spawns on maps the data places (0-100 on its area's map), and its usual map.
	local givers = { Npc = {}, Object = {} }
	---@param kind "Npc"|"Object"
	---@param id integer
	---@return {name: string, spots: {map: integer, x: number, y: number}[], home: integer?}|false
	local function Giver(kind, id)
		local giver = givers[kind][id]
		if giver == nil then
			local values = lib[kind].GetAll(id, GIVER_FIELDS)
			giver = false
			if values and type(values[1]) == "string" and type(values[2]) == "table" then
				giver = { name = values[1], spots = {}, home = type(values[3]) == "number" and Map(values[3]) or nil }
				for area, coordinates in pairs(values[2]) do
					local map = type(area) == "number" and Map(area)
					for _, xy in ipairs(map and coordinates or {}) do
						local x, y = tonumber(xy[1]), tonumber(xy[2])
						if x and y and x >= 0 and x <= 100 and y >= 0 and y <= 100 then
							table.insert(giver.spots, { map = map, x = Round(x / 100), y = Round(y / 100) })
						end
					end
				end
			end
			givers[kind][id] = giver
		end
		return giver
	end
	-- Where a quest starts or ends among its givers' spawns: in its zone first, then on the giver's usual map, then
	-- the lowest map, name and point. An item giver or unknown spawn has no pickup waypoint.
	local function Place(by, zone)
		local best, bestKey
		for index, kind in ipairs({ "Npc", "Object" }) do
			for _, id in ipairs(type(by) == "table" and type(by[index]) == "table" and by[index] or {}) do
				local giver = Giver(kind, id)
				if giver then
					for _, spot in ipairs(giver.spots) do
						local home = spot.map == giver.home and 0 or 1
						local key = { spot.map == zone and 0 or 1, home, spot.map, giver.name, spot.x, spot.y }
						if not bestKey or Before(key, bestKey) then
							bestKey = key
							best = { map = spot.map, x = spot.x, y = spot.y, name = giver.name }
							best.npc = kind == "Npc" and id or nil
						end
					end
				end
			end
		end
		if best then
			best.hub = Hub(bundled, cells, best)
		end
		return best
	end

	local ids, quests = lib.Quest.GetAllIds(), {}
	status.catalogueCount, status.questCount = #ids, 0
	local xpSource = lib.Support.Get("QuestXP")
	local xp = xpSource and xpSource.db or {}
	for _, id in ipairs(ids) do
		local values = lib.Quest.GetAll(id, QUEST_FIELDS)
		if values then
			local v = {}
			for index, field in ipairs(QUEST_FIELDS) do
				v[field] = values[index]
			end
			local races, classes = tonumber(v.requiredRaces or 0), tonumber(v.requiredClasses or 0)
			local level, minimum = tonumber(v.questLevel), tonumber(v.requiredLevel)
			if type(v.name) == "string" and races and classes and level and minimum then
				local quest = {
					title = v.name,
					level = level,
					min = minimum,
					max = tonumber(v.requiredMaxLevel),
					side = Side(races),
					races = races ~= 0 and races or nil,
					classes = classes ~= 0 and classes or nil,
					provider = true,
				}
				local area = tonumber(v.zoneOrSort) or 0
				local zone = area > 0 and Map(area) or nil
				quest.start, quest.finish = Place(v.startedBy, zone), Place(v.finishedBy, zone)
				quest.zone = zone or (quest.start or quest.finish or {}).map
				local instance = area > 0 and (instanceOf[area] or instanceOf[Parent(area) or false])
				if instance and bundled.instances[instance] then
					quest.dungeon, quest.raid = instance, bundled.instances[instance].raid
				end
				local flags, special = tonumber(v.questFlags) or 0, tonumber(v.specialFlags) or 0
				local tag = C_QuestLog.GetQuestTagInfo and C_QuestLog.GetQuestTagInfo(id)
				quest.elite = tag and tag.tagID == 1 or nil
				quest.raid = quest.raid or bit.band(flags, 64) ~= 0 or nil
				quest.repeatable = (bit.band(special, 1) ~= 0 or bit.band(flags, REPEATABLE_FLAGS) ~= 0) or nil
				quest.xp = type(xp[id]) == "table" and tonumber(xp[id][2]) or nil
				quest.flags = bit.band(special, 2) ~= 0 and { event = true } or nil
				local following = tonumber(v.nextQuestInChain) or 0
				quest.next = following > 0 and following or nil
				local breadcrumb = tonumber(v.breadcrumbForQuestId) or 0
				quest.breadcrumb = breadcrumb > 0 and breadcrumb or nil
				-- Preserve relationships for chain displays. Live Questie policy evaluates their full semantics.
				quest.pre = type(v.preQuestGroup) == "table" and v.preQuestGroup or nil
				quest.preAny = type(v.preQuestSingle) == "table" and v.preQuestSingle or nil
				local start = quest.start
				if start and quest.classes and start.npc then
					-- A class quest's giver is its class's trainer. The bundled trainer data has no entry for Forever's
					-- extra class/race combinations, so fall back to the quest's single required class.
					local npc = bundled.npcs[start.npc]
					start.trainer = (npc and npc.class) or SingleClass(quest.classes)
				end
				if not quest.dungeon then
					quest.need, quest.obj, quest.kinds, quest.objectivesUnknown =
						ns.QuestieObjectives(lib, v.objectives, v.triggerEnd, quest.zone, bundled, Map, yield, id)
				end
				quests[id] = quest
				status.questCount = status.questCount + 1
			end
		end
		yield()
	end
	local data = { quests = quests }
	for key, value in pairs(bundled) do
		data[key] = data[key] or value
	end
	return data
end

-- Runs the build a slice a frame from login, then swaps ns.Data and rebuilds the route.
local bundled = ns.Data
local empty = {}
for key, value in pairs(bundled) do
	empty[key] = value
end
empty.quests = {}
ns.Data = empty --[[@as AGFData]]

-- Releases a route that was held for the build (Core's ns.QuestieBuilding): the catalogue either landed (the swap
-- below) or will never come (unavailable), and either way the log's route may now be built.
local function Settled()
	if ns.Invalidate then
		ns.Invalidate()
	end
end

local function Start()
	local lib, reason, zones = Fit()
	if not lib or not zones then
		status.state, status.reason, status.settled = "unavailable", reason, true
		Settled()
		return
	end
	local version = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "?"
	local started = 0
	local co = coroutine.create(Build)
	local function Yield()
		if debugprofilestop() - started >= SLICE_MS then
			coroutine.yield()
		end
	end
	status.state = "building"
	local function Step()
		started = debugprofilestop()
		local ok, result = coroutine.resume(co, lib, zones, bundled, Yield)
		if not ok then
			status.state, status.reason, status.settled =
				"unavailable", ns.L.QUESTIE_FAILED:format(tostring(result)), true
			Settled()
		elseif coroutine.status(co) ~= "dead" then
			C_Timer.After(0, Step)
		else
			status.state, status.version, status.settled = "questie", version, true
			ns.Data = result --[[@as AGFData]]
			Settled()
		end
	end
	C_Timer.After(0, Step)
end

EventUtil.ContinueAfterAllEvents(function()
	status.state = "building"
	if Questie and Questie.API and Questie.API.RegisterOnReady then
		local ready = false
		Questie.API.RegisterOnReady(function()
			ready = true
			Start()
		end)
		C_Timer.After(READY_WAIT, function()
			if not ready then
				Start()
			end
		end)
		if Questie.API.RegisterForQuestUpdates then
			Questie.API.RegisterForQuestUpdates(function()
				ns.Invalidate()
			end)
		end
	else
		Start()
	end
end, "PLAYER_LOGIN")

function ns.SourceHint()
	if status.state == "building" then
		return ns.L.AUDIT_QUESTIE_BUILDING
	end
	if status.state ~= "questie" then
		return ns.L.QUESTIE_ENABLE
	end
	if not (Questie and Questie.API and Questie.API.isReady) then
		return ns.L.QUESTIE_POLICY
	end
end

-- Optional dungeon details are read only by the visible dungeon tab. Like the quest adapter, this takes a
-- yielding caller and publishes a complete snapshot. GetAllIds is the contract's shared, read-only ID list.
---@param yield fun()
---@return AGFDungeonSource?
function ns.ReadDungeonSource(yield)
	local lib, _, zones = Fit()
	if not lib or not zones then
		return nil
	end
	local fields = {
		Npc = { "name", "rank", "spawns", "minLevel", "maxLevel" },
		Item = { "name", "npcDrops", "questRewards", "startQuest" },
	}
	if MissingField(lib, { ENTITIES[2], ENTITIES[4] }, fields) then
		return nil
	end
	local result = {
		bosses = {},
		loot = {},
		rewards = {},
		objectives = {},
		entrances = {},
		npcs = {},
		worldDrops = {},
		starts = {},
	}
	local function Dungeon(instance)
		return ns.Data.instances[instance] ~= nil and not ns.Data.instances[instance].raid
	end
	local instanceOf, dungeons = InstanceAreas(lib, zones, Dungeon)
	local npcInstances, npcInfo = {}, {}
	for instance, area in pairs(zones.instances) do
		if Dungeon(instance) then
			result.bosses[instance], result.loot[instance], result.npcs[instance] = {}, {}, {}
			local dungeon = dungeons[area]
			if type(dungeon) == "table" then
				-- Forever's support points are already converted; applying EraToForever again would move them.
				for _, spot in ipairs(type(dungeon[4]) == "table" and dungeon[4] or {}) do
					local map = zones.areaOverride[spot[1]] or zones.area[spot[1]]
					local x, y = spot[2], spot[3]
					if map and ns.Data.maps[map] and type(x) == "number" and type(y) == "number" then
						local point = { map = map, x = x / 100, y = y / 100 }
						if ns.Model.ValidPlace(point) and not result.entrances[instance] then
							result.entrances[instance] = point
						end
					end
				end
			end
		end
	end
	for _, id in ipairs(lib.Npc.GetAllIds()) do
		local values = lib.Npc.GetAll(id, fields.Npc)
		if values and type(values[1]) == "string" and type(values[3]) == "table" then
			local instance, outside
			for area, spots in pairs(values[3]) do
				if type(spots) == "table" and next(spots) then
					local parent = zones.parentOverride[area] or zones.parent[area]
					local here = instanceOf[area] or (parent and instanceOf[parent])
					outside = outside or not here or (instance and instance ~= here)
					instance = here or instance
				end
				yield()
			end
			if instance and not outside then
				npcInstances[id] = instance
				local npc = { id = id, name = values[1], rank = values[2] or 0, low = values[4], high = values[5] }
				npcInfo[id], result.npcs[instance][id] = npc, npc
				-- Elite rank alone is not evidence of an encounter. Curated AtlasLoot/EJ bosses augment this later.
				if npc.rank == 3 then
					table.insert(result.bosses[instance], npc)
				end
			end
		end
		yield()
	end
	local seen = {}
	for _, id in ipairs(lib.Item.GetAllIds()) do
		local values = not seen[id] and lib.Item.GetAll(id, fields.Item)
		seen[id] = true
		if values and type(values[1]) == "string" then
			local instance, outside
			local droppers, known = {}, {}
			for _, npc in ipairs(type(values[2]) == "table" and values[2] or {}) do
				local here = npcInstances[npc]
				outside = outside or not here or (instance and instance ~= here)
				instance = here or instance
				if here and not known[npc] then
					known[npc] = true
					droppers[#droppers + 1] = npcInfo[npc]
				end
				yield()
			end
			local item =
				{ id = id, name = values[1], startQuest = type(values[4]) == "number" and values[4] > 0 or nil }
			result.worldDrops[id] = outside or nil
			result.starts[id] = item.startQuest
			if instance and not outside then
				table.sort(droppers, function(a, b)
					return a.id < b.id
				end)
				item.droppers = droppers
				table.insert(result.loot[instance], item)
			end
			for _, quest in ipairs(type(values[3]) == "table" and values[3] or {}) do
				if ns.Data.quests[quest] then
					result.rewards[quest] = result.rewards[quest] or {}
					table.insert(result.rewards[quest], item)
				end
				yield()
			end
		end
		yield()
	end
	for _, rows in pairs(result.bosses) do
		table.sort(rows, function(a, b)
			if (a.low or 0) ~= (b.low or 0) then
				return (a.low or 0) < (b.low or 0)
			end
			return a.id < b.id
		end)
	end
	local keys = lib.Meta.QuestMeta.questKeys
	if keys.objectivesText then
		for id in pairs(ns.Data.quests) do
			local values = lib.Quest.GetAll(id, { "objectivesText" })
			if values and type(values[1]) == "table" then
				local lines = {}
				for _, line in ipairs(values[1]) do
					if type(line) == "string" then
						lines[#lines + 1] = line
					end
				end
				result.objectives[id] = table.concat(lines, "\n")
			end
			yield()
		end
	end
	return result
end
