-- Run from the repository root: luajit tests/geometry_spec.lua
-- Geometry.lua on its own, against stub client surfaces: every section builds pure tables from the injected API,
-- an absent client answers nothing rather than erroring, and Merge overlays native fields without clobbering the
-- bundled ones native cannot provide.
local checks = 0

local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local function truthy(actual, label)
	checks = checks + 1
	if not actual then
		error(("%s: expected truthy, got %s"):format(label, tostring(actual)), 2)
	end
end

local ns = {}
local chunk = assert(loadfile("Geometry.lua"))
chunk("AdventureGuideForever", ns)
local Geometry = ns.Geometry
truthy(Geometry, "Geometry.lua registers ns.Geometry")

--[[ Maps ]]

local INFO = {
	[10] = { mapID = 10, name = "Elwynn Forest", parentMapID = 0 },
	[11] = { mapID = 11, name = "Goldshire", parentMapID = 10 },
	[12] = { mapID = 12, name = "", parentMapID = 0 },
	[13] = { mapID = 13, name = "Method Map" },
}
local SIZE = {
	[10] = { 1000, 2000 },
}
local CORNERS = {
	[10] = { x0 = 100, x1 = 1100, y0 = 50, y1 = 2050 },
	[11] = { x0 = 0, x1 = 100, y0 = 0, y1 = 50 },
}
local mapApi = {
	UiMapPoint = {
		CreateFromCoordinates = function(mapID, x, y)
			return { x = x, y = y, mapID = mapID, created = true }
		end,
	},
	C_Map = {
		GetMapInfo = function(mapID)
			return INFO[mapID]
		end,
		GetMapWorldSize = function(mapID)
			local size = SIZE[mapID]
			if size then
				return size[1], size[2]
			end
		end,
		-- Map 13 hands back UiMapPoints with :GetXY instead of plain tables, as the client does.
		GetWorldPosFromMapPos = function(mapID, pos)
			if mapID == 13 then
				local x, y = pos.x * 10, pos.y * 20
				return {
					GetXY = function()
						return x, y
					end,
				}
			end
			local corner = CORNERS[mapID]
			if not corner then
				return nil
			end
			return {
				x = corner.x0 + (corner.x1 - corner.x0) * pos.x,
				y = corner.y0 + (corner.y1 - corner.y0) * pos.y,
			}
		end,
	},
}

local maps = Geometry.Maps(mapApi, { 10, 11, 12, 13, 99 })
equal(maps[10].name, "Elwynn Forest", "Maps: client name")
equal(maps[10].continent, 10, "Maps: a root map is its own continent")
equal(maps[11].continent, 10, "Maps: continent walks parentMapID to the top")
equal(maps[12].name, nil, 'Maps: an empty client name is nil, not ""')
equal(maps[12].continent, 12, "Maps: a nameless root still has a continent")
equal(maps[99], nil, "Maps: an unknown map is left out")
equal(maps[10].sx, 1000, "Maps: GetMapWorldSize wins for sx")
equal(maps[10].sy, 2000, "Maps: GetMapWorldSize wins for sy")
equal(maps[10].cx, 600, "Maps: corner midpoint is the world centre x")
equal(maps[10].cy, 1050, "Maps: corner midpoint is the world centre y")
equal(maps[11].sx, 100, "Maps: corners give sx where GetMapWorldSize is absent")
equal(maps[11].sy, 50, "Maps: corners give sy where GetMapWorldSize is absent")
equal(maps[11].cx, 50, "Maps: corners give cx")
equal(maps[11].cy, 25, "Maps: corners give cy")
equal(maps[13].sx, 10, "Maps: a UiMapPoint :GetXY corner is read")
equal(maps[13].sy, 20, "Maps: a UiMapPoint :GetXY corner is read for y")
equal(maps[13].cx, 5, "Maps: :GetXY corners give cx")
equal(maps[13].cy, 10, "Maps: :GetXY corners give cy")

equal(next(Geometry.Maps(mapApi)), nil, "Maps: no IDs means no entries")
equal(next(Geometry.Maps({}, { 10 })), nil, "Maps: an API without C_Map answers nothing")
equal(next(Geometry.Maps(nil, { 10 })), nil, "Maps: no API at all answers nothing")

--[[ Zones ]]

local zones = Geometry.Zones(mapApi, { 10, 11, 99 })
equal(zones[10].name, "Elwynn Forest", "Zones: client name")
equal(zones[11].name, "Goldshire", "Zones: client name")
equal(zones[99], nil, "Zones: an unknown map is left out")
equal(zones[10].min, nil, "Zones: the client has no level range, so min is absent")
equal(zones[10].max, nil, "Zones: the client has no level range, so max is absent")
equal(next(Geometry.Zones({}, { 10 })), nil, "Zones: an API without C_Map answers nothing")

--[[ Instances ]]

local instanceApi = {
	GetLFGDungeonInfo = function(lfgID)
		if lfgID == 1 then
			return "Ragefire Chasm", 0, 0, 0, 0, 0, 13, 18
		end
		if lfgID == 2 then
			return ""
		end
		return nil
	end,
	GetRealZoneText = function(mapID)
		if mapID == 2 then
			return "The Deadmines"
		end
		return ""
	end,
}

local instances = Geometry.Instances(instanceApi, { 1, 2, 3 })
equal(instances[1].name, "Ragefire Chasm", "Instances: LFG name")
equal(instances[1].low, 13, "Instances: 7th LFG return is the low level")
equal(instances[1].high, 18, "Instances: 8th LFG return is the high level")
equal(instances[2].name, "The Deadmines", "Instances: GetRealZoneText is the empty-name fallback")
equal(instances[3].name, nil, "Instances: a client with no answer leaves the name nil")
equal(instances[3].low, nil, "Instances: a client with no answer leaves the level nil")
equal(next(Geometry.Instances({}, { 1 })), nil, "Instances: an API without GetLFGDungeonInfo answers nothing")
equal(next(Geometry.Instances(instanceApi)), nil, "Instances: no LFG IDs means no entries")

--[[ Skills ]]

local skillApi = {
	C_SkillInfo = {
		GetNumSkillLines = function()
			return 2
		end,
		GetSkillLineInfo = function(index)
			if index == 1 then
				return { skillID = 6, name = "Mining", isHeader = false, rank = 75 }
			end
			return { skillID = 0, name = "Professions", isHeader = true }
		end,
		GetSkillLineInfoByID = function(skillLineID)
			if skillLineID == 6 then
				return { skillID = 6, name = "Mining" }
			end
			return nil
		end,
	},
}

local skills = Geometry.Skills(skillApi, { 6, 171 })
equal(skills[6].name, "Mining", "Skills: a learned line names itself")
equal(skills[171], nil, "Skills: an unlearned line the client cannot name is absent")
equal(next(Geometry.Skills({})), nil, "Skills: an API without C_SkillInfo answers nothing")

--[[ Factions ]]

local factionApi = {
	GetNumFactions = function()
		return 2
	end,
	C_Reputation = {
		GetFactionDataByID = function(factionID)
			if factionID == 72 then
				return { factionID = 72, name = "Stormwind" }
			end
			return nil
		end,
		GetFactionDataByIndex = function(index)
			if index == 1 then
				return { factionID = 72, name = "Stormwind" }
			end
			return { factionID = 76, name = "Stormwind Guard" }
		end,
	},
}

local allFactions = Geometry.Factions(factionApi)
equal(allFactions[72].name, "Stormwind", "Factions: index enumeration")
equal(allFactions[76].name, "Stormwind Guard", "Factions: every tracked faction")
local namedFactions = Geometry.Factions(factionApi, { 72, 999 })
equal(namedFactions[72].name, "Stormwind", "Factions: a named ID")
equal(namedFactions[999], nil, "Factions: an unknown ID is left out")
equal(next(Geometry.Factions({})), nil, "Factions: an API without C_Reputation answers nothing")

--[[ Merge ]]

local data = {
	zones = { [10] = { name = "Bundled", min = 1, max = 5 } },
	instances = { [5] = { name = "Bundled", raid = true, entrances = { {} } } },
	maps = { [10] = { name = "Bundled", cx = 0, dy = "bundled-only" } },
}
local native = {
	zones = { [10] = { name = "Client" }, [11] = { name = "Client New" }, [12] = { name = nil } },
	instances = { [5] = { name = "Client Dungeon", low = 10, high = 20 } },
	maps = { [10] = { name = "Client", continent = 1, cx = 5, cy = 6, sx = 7, sy = 8 } },
	skills = { [6] = { name = "Mining" } },
}
local merged = Geometry.Merge(data, native)
equal(merged, data, "Merge: returns the data table it mutated")
equal(data.zones[10].name, "Client", "Merge: native name wins")
equal(data.zones[10].min, 1, "Merge: bundled zone min survives")
equal(data.zones[10].max, 5, "Merge: bundled zone max survives")
equal(data.zones[11].name, "Client New", "Merge: a zone the data lacks is created")
truthy(data.zones[12], "Merge: a native key with no fields still creates the entry")
equal(data.instances[5].name, "Client Dungeon", "Merge: native instance name wins")
equal(data.instances[5].raid, true, "Merge: bundled raid flag survives")
equal(data.instances[5].entrances ~= nil, true, "Merge: bundled entrances survive")
equal(data.instances[5].low, 10, "Merge: native low is added")
equal(data.instances[5].high, 20, "Merge: native high is added")
equal(data.maps[10].name, "Client", "Merge: native map name wins")
equal(data.maps[10].cx, 5, "Merge: native map geometry wins")
equal(data.maps[10].dy, "bundled-only", "Merge: a bundled map field native cannot provide survives")
equal(data.skills[6].name, "Mining", "Merge: a section the data lacks is created")

-- Geometry.Instances keys by LFG ID; the data keys by Map.ID. Merge resolves through the data entry's `.lfg`.
local keyed = { instances = { [5] = { name = "Bundled", lfg = 100, raid = true } } }
Geometry.Merge(keyed, { instances = { [100] = { name = "Client Dungeon", low = 13, high = 18 } } })
equal(keyed.instances[100], nil, "Merge: an LFG ID is not left as a stray key")
equal(keyed.instances[5].name, "Client Dungeon", "Merge: an LFG-keyed instance lands on its Map.ID")
equal(keyed.instances[5].low, 13, "Merge: levels land on the Map.ID entry")
equal(keyed.instances[5].raid, true, "Merge: the Map.ID entry keeps its raid flag")
local stray = { instances = {} }
Geometry.Merge(stray, { instances = { [100] = { name = "Unknown Map" } } })
equal(stray.instances[100].name, "Unknown Map", "Merge: an LFG ID the data lacks is created as a last resort")

local empty = {}
equal(Geometry.Merge(empty, {}), empty, "Merge: no native sections returns data untouched")
equal(Geometry.Merge(nil, native), nil, "Merge: no data is a no-op")
equal(Geometry.Merge(data, nil), data, "Merge: no native table is a no-op")

print(("geometry_spec: %d checks passed"):format(checks))
