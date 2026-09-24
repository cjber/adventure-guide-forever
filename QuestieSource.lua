---@type string, AGFNamespace
local _, ns = ...

--[[ QuestieDB, when it is loaded (docs/design.md §2.14): after login the quests are rebuilt from it a few
     milliseconds a frame. The bundled data serves until then, and for good when QuestieDB is absent or fails a
     check. QuestieDB gives each quest its title, levels, races, classes, zone, givers and their spawns,
     prerequisites, exclusive quests, chain and skill and reputation gates. The rest stays bundled: towns, maps, NPC
     roles, instances, crossings and elite quests, and whatever QuestieDB leaves out (a level, a dungeon, a giver's
     place). Only the bundled data's quests are read, and a start only where the bundled data has one: its lack is a
     gate, an event or an event-only giver, none of which QuestieDB says. A start is also withheld whenever QuestieDB
     names a requirement the planner cannot check.
     Nothing of Questie's is shipped: this reads the installed addon at runtime. ]]

local ADDON = "QuestieDB"
local CONTRACT = 2
local SLICE_MS = 2
local LINK = 100 -- yards: a giver this near a bundled town's place stands in that town (tools/gen_quests.py LINK)
-- CMaNGOS quest flags: 1024 and 16384 gate the start (as tools/gen_quests.py), 4096 and 32768 make it repeatable.
local GATED_FLAGS, REPEATABLE_FLAGS = 1024 + 16384, 4096 + 32768

local QUEST_FIELDS = {
	"name",
	"questLevel",
	"requiredLevel",
	"requiredRaces",
	"requiredClasses",
	"zoneOrSort",
	"startedBy",
	"finishedBy",
	"preQuestGroup",
	"preQuestSingle",
	"exclusiveTo",
	"nextQuestInChain",
	"questFlags",
	"specialFlags",
	"requiredSkill",
	"requiredMinRep",
	"requiredMaxRep",
}
-- A start is withheld when any of these is set (requiredMaxLevel: below the cap): the planner has no state for them.
local GATES = {
	"parentQuest",
	"breadcrumbForQuestId",
	"requiredSpell",
	"requiredSpecialization",
	"requiredMaxLevel",
	"availableUntilCompleted",
	"availableStartingWith",
	"requiredRanks",
	"disabledByQuest",
}
for _, field in ipairs(GATES) do
	QUEST_FIELDS[#QUEST_FIELDS + 1] = field
end
local GIVER_FIELDS = { "name", "spawns", "zoneID" }
local ENTITIES = {
	{ name = "Quest", keys = "questKeys", fields = QUEST_FIELDS },
	{ name = "Npc", keys = "npcKeys", fields = GIVER_FIELDS },
	{ name = "Object", keys = "objectKeys", fields = GIVER_FIELDS },
}

---@type AGFQuestieStatus
local status = { state = "bundled" }
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

-- QuestieDB as this file reads it, or nil and why not (an ns.L line).
---@return AGFQuestieDB?, string?, AGFQuestieZones?
local function Fit()
	local lib = LibQuestieDB
	if type(lib) ~= "table" then
		return nil, ns.L.QUESTIE_ABSENT
	end
	local ok, fits = pcall(lib.RequireContract, CONTRACT)
	if not (ok and fits) then
		return nil, ns.L.QUESTIE_CONTRACT
	end
	if C_AddOns.GetAddOnMetadata(ADDON, "X-Flavor") ~= "Forever" then
		return nil, ns.L.QUESTIE_FLAVOUR
	end
	for _, entity in ipairs(ENTITIES) do
		local meta = lib.Meta and lib.Meta[entity.name .. "Meta"]
		local keys, reader = meta and meta[entity.keys], lib[entity.name]
		if type(keys) ~= "table" or type(reader) ~= "table" or type(reader.GetAll) ~= "function" then
			return nil, ns.L.QUESTIE_FIELD:format(entity.name)
		end
		for _, field in ipairs(entity.fields) do
			if not keys[field] then
				return nil, ns.L.QUESTIE_FIELD:format(field)
			end
		end
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

-- The bundled data's town places in LINK-yard cells, so a place from QuestieDB joins the town of the nearest one.
---@param data AGFData
---@param yield fun()
---@return table<string, {x: number, y: number, hub: integer}[]>
local function TownCells(data, yield)
	local cells = {}
	for _, quest in pairs(data.quests) do
		yield()
		for _, place in ipairs({ quest.start or false, quest.finish or false }) do
			local at = place and place.hub and World(data, place)
			if place and at then
				local key = Cell(at.continent, at.x, at.y)
				cells[key] = cells[key] or {}
				table.insert(cells[key], { x = at.x, y = at.y, hub = place.hub })
			end
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
	local instanceOf = {}
	for instance, area in pairs(zones.instances) do
		instanceOf[area] = instance
	end
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
	-- the lowest map, name and point (tools/gen_quests.py pick). An item giver has no place. A giver QuestieDB can't
	-- place keeps the bundled place when the bundled data names the same NPC.
	local function Place(by, zone, old)
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
		elseif old and old.npc and type(by) == "table" and type(by[1]) == "table" then
			for _, id in ipairs(by[1]) do
				if id == old.npc and not best then
					best = {}
					for key, value in pairs(old) do
						best[key] = value
					end
				end
			end
		end
		return best
	end

	local quests, exclusive, withheld = {}, {}, {}
	for id, old in pairs(bundled.quests) do
		local values = lib.Quest.GetAll(id, QUEST_FIELDS)
		if not values then
			-- QuestieDB lacks it: the bundled quest stands.
			quests[id] = old
		else
			local v = {}
			for index, field in ipairs(QUEST_FIELDS) do
				v[field] = values[index]
			end
			local races, classes = tonumber(v.requiredRaces) or 0, tonumber(v.requiredClasses) or 0
			local quest = {
				title = type(v.name) == "string" and v.name or old.title,
				level = tonumber(v.questLevel) or 0,
				min = tonumber(v.requiredLevel) or old.min,
				side = Side(races),
				races = races ~= 0 and races or nil,
				classes = classes ~= 0 and classes or nil,
				elite = old.elite,
			}
			-- A level of -1 scales with the player: the bundled level.
			quest.level = quest.level >= 0 and quest.level or old.level
			local area = tonumber(v.zoneOrSort) or 0
			local zone = area > 0 and Map(area) or nil
			quest.start, quest.finish = Place(v.startedBy, zone, old.start), Place(v.finishedBy, zone, old.finish)
			quest.zone = zone and bundled.zones[zone] and zone or (quest.start or quest.finish or {}).map
			-- A raid's quest stays one wherever QuestieDB files it: the bundled flag also says a quest is typed Raid.
			local instance = area > 0 and (instanceOf[area] or instanceOf[Parent(area) or false])
			if instance and bundled.instances[instance] then
				quest.dungeon, quest.raid = instance, bundled.instances[instance].raid or old.raid
			else
				quest.dungeon, quest.raid = old.dungeon, old.raid
			end
			local start = quest.start
			if start and quest.classes and start.npc then
				local npc = bundled.npcs[start.npc]
				local trainer = old.start and old.start.npc == start.npc and old.start.trainer
				start.trainer = trainer or (npc and npc.class) or nil
			end
			-- Prerequisites: every one of the group, and one of the singles (a lone single joins the group).
			local unknown = false
			local pre, preAny = {}, {}
			local group = type(v.preQuestGroup) == "table" and v.preQuestGroup or {}
			local single = type(v.preQuestSingle) == "table" and v.preQuestSingle or {}
			for _, list in ipairs({ group, single }) do
				for _, other in ipairs(list) do
					unknown = unknown or not bundled.quests[other]
					table.insert((list == group or #single == 1) and pre or preAny, other)
				end
			end
			quest.pre, quest.preAny = pre[1] and pre or nil, preAny[1] and preAny or nil
			for _, other in ipairs(type(v.exclusiveTo) == "table" and v.exclusiveTo or {}) do
				if bundled.quests[other] then
					exclusive[#exclusive + 1] = { id, other }
				else
					unknown = true
				end
			end
			local following = tonumber(v.nextQuestInChain) or 0
			quest.next = following > 0 and following or nil
			local flags, special = tonumber(v.questFlags) or 0, tonumber(v.specialFlags) or 0
			quest.repeatable = (bit.band(special, 1) ~= 0 or bit.band(flags, REPEATABLE_FLAGS) ~= 0) or nil
			-- Skill and reputation gates, as tools/gen_quests.py requirements: only on lines and factions the data
			-- names, and a minimum and maximum on one faction.
			local gates, gated = {}, false
			local skill = v.requiredSkill
			if type(skill) == "table" and (tonumber(skill[2]) or 0) > 0 then
				gated = gated or not (bundled.skills and bundled.skills[skill[1]])
				gates.skill = { id = skill[1], value = skill[2] }
			end
			local low, high = v.requiredMinRep, v.requiredMaxRep
			low, high = type(low) == "table" and low or nil, type(high) == "table" and high or nil
			if low or high then
				local faction = (low or high)[1]
				gated = gated
					or (low and high and low[1] ~= high[1])
					or not (bundled.factions and bundled.factions[faction])
				gates.rep = { faction = faction, min = low and low[2], max = high and high[2] }
			end
			for _, field in ipairs(GATES) do
				local value = v[field]
				gated = gated or (value ~= nil and value ~= 0 and not (field == "requiredMaxLevel" and value == 255))
			end
			if
				unknown
				or gated
				or not old.start
				or bit.band(flags, GATED_FLAGS) ~= 0
				or quest.side == 0
				or quest.level == 0
			then
				withheld[id] = true
			elseif start then
				quest.skill, quest.rep = gates.skill, gates.rep
			end
			quests[id] = quest
		end
		yield()
	end
	-- Exclusive quests close each other: each set joined through any member is one group, named by its lowest ID.
	local root = {}
	local function Find(id)
		while root[id] ~= id do
			id = root[id]
		end
		return id
	end
	for _, pair in ipairs(exclusive) do
		local a, b = pair[1], pair[2]
		root[a], root[b] = root[a] or a, root[b] or b
		a, b = Find(a), Find(b)
		root[math.max(a, b)] = math.min(a, b)
	end
	for id, quest in pairs(quests) do
		yield()
		if quest ~= bundled.quests[id] then
			quest.group = root[id] and Find(id) or nil
			quest.start = not withheld[id] and quest.start or nil
		end
	end
	local data = { quests = quests }
	for key, value in pairs(bundled) do
		data[key] = data[key] or value
	end
	return data
end

-- Runs the build a slice a frame from login, then swaps ns.Data and rebuilds the route.
local function Start()
	local lib, reason, zones = Fit()
	if not lib or not zones then
		status.reason = reason
		return
	end
	local version = C_AddOns.GetAddOnMetadata(ADDON, "Version") or "?"
	local bundled, started = ns.Data, 0
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
			status.state, status.reason = "bundled", ns.L.QUESTIE_FAILED:format(tostring(result))
		elseif coroutine.status(co) ~= "dead" then
			C_Timer.After(0, Step)
		elseif ns.Data == bundled then
			result.source = ADDON .. " " .. version
			status.state, status.version = "questie", version
			ns.Data = result --[[@as AGFData]]
			ns.Invalidate()
		end
	end
	C_Timer.After(0, Step)
end

EventUtil.ContinueAfterAllEvents(Start, "PLAYER_LOGIN")
