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
local chunk = assert(loadfile("Planning/Geometry.lua"))
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
equal(maps[12].name, nil, 'Maps: an empty client name is nil, not ""')
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
	C_Reputation = {
		GetFactionDataByID = function(factionID)
			if factionID == 72 then
				return { factionID = 72, name = "Stormwind" }
			end
			return nil
		end,
	},
}

local namedFactions = Geometry.Factions(factionApi, { 72, 999 })
equal(namedFactions[72].name, "Stormwind", "Factions: a named ID")
equal(namedFactions[999], nil, "Factions: an unknown ID is left out")
equal(next(Geometry.Factions({}, { 72 })), nil, "Factions: an API without C_Reputation answers nothing")

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

--[[ Apply / EnsureNative: the runtime seam ]]

-- A client that answers for map 200 only, with a real world rectangle and the level/name sections.
local applyApi = {
	UiMapPoint = {
		CreateFromCoordinates = function(mapID, x, y)
			return { x = x, y = y, mapID = mapID }
		end,
	},
	C_Map = {
		GetMapInfo = function(mapID)
			if mapID == 200 then
				return { mapID = 200, name = "Client Zone", parentMapID = 0 }
			end
		end,
		GetMapWorldSize = function(mapID)
			if mapID == 200 then
				return 500, 700
			end
		end,
		GetWorldPosFromMapPos = function(mapID, pos)
			if mapID == 200 then
				return { x = 100 + 500 * pos.x, y = 200 + 700 * pos.y }
			end
		end,
	},
	GetLFGDungeonInfo = function(lfgID)
		if lfgID == 7 then
			return "Client Dungeon", 0, 0, 0, 0, 0, 13, 18
		end
	end,
	GetRealZoneText = function()
		return ""
	end,
	C_SkillInfo = {
		GetSkillLineInfoByID = function(skillLineID)
			if skillLineID == 164 then
				return { skillID = 164, name = "Client Smithing" }
			end
		end,
	},
	C_Reputation = {
		GetFactionDataByID = function(factionID)
			if factionID == 72 then
				return { factionID = 72, name = "Client Faction" }
			end
		end,
	},
}

-- Bundled values for one of each section: fields native can answer (name, geometry, levels) and fields it cannot
-- (continent, zone min/max, instance raid/lfg/entrances, and a field outside the adapter's shape).
local function bundled()
	return {
		maps = {
			[200] = { name = "Bundled Zone", continent = 0, cx = 1, cy = 2, sx = 3, sy = 4, dy = "keep" },
			[201] = { name = "Bundled Other", continent = 0, cx = -10, cy = -20, sx = 30, sy = 40 },
		},
		zones = { [200] = { name = "Bundled Zone", min = 1, max = 10 } },
		instances = { [33] = { name = "Bundled Dungeon", lfg = 7, raid = true, entrances = { { trigger = 1 } } } },
		skills = { [164] = { name = "Bundled Smithing" } },
		factions = { [72] = { name = "Bundled Faction" } },
	}
end

local applied = Geometry.Apply(bundled(), applyApi)
equal(applied.maps[200].name, "Client Zone", "Apply: native map name overlays the bundled one")
equal(applied.maps[200].cx, 350, "Apply: native corner rect overlays bundled cx")
equal(applied.maps[200].cy, 550, "Apply: native corner rect overlays bundled cy")
equal(applied.maps[200].sx, 500, "Apply: native map width overlays bundled sx")
equal(applied.maps[200].sy, 700, "Apply: native map height overlays bundled sy")
equal(applied.maps[200].continent, 0, "Apply: native continent is dropped, the bundled Map.dbc ID stays")
equal(applied.maps[200].dy, "keep", "Apply: a bundled map field native cannot answer survives")
equal(applied.maps[201].name, "Bundled Other", "Apply: a map the client does not answer keeps its bundled name")
equal(applied.maps[201].cx, -10, "Apply: a map the client does not answer keeps its bundled geometry")
equal(applied.zones[200].name, "Client Zone", "Apply: native zone name overlays the bundled one")
equal(applied.zones[200].min, 1, "Apply: bundled zone min survives")
equal(applied.zones[200].max, 10, "Apply: bundled zone max survives")
equal(applied.instances[33].name, "Client Dungeon", "Apply: native instance name overlays the bundled one")
equal(applied.instances[33].low, 13, "Apply: native instance low level is added")
equal(applied.instances[33].high, 18, "Apply: native instance high level is added")
equal(applied.instances[33].raid, true, "Apply: bundled instance raid flag survives")
equal(applied.instances[33].entrances ~= nil, true, "Apply: bundled instance entrances survive")
equal(applied.instances[33].lfg, 7, "Apply: bundled instance lfg field survives")
equal(applied.skills[164].name, "Client Smithing", "Apply: native skill name overlays the bundled one")
equal(applied.factions[72].name, "Client Faction", "Apply: native faction name overlays the bundled one")

-- A missing/None client answer leaves every bundled value alone.
local untouched = Geometry.Apply(bundled(), {})
equal(untouched.maps[200].name, "Bundled Zone", "Apply: no C_Map leaves the bundled map name")
equal(untouched.maps[200].cx, 1, "Apply: no C_Map leaves the bundled map geometry")
equal(untouched.zones[200].name, "Bundled Zone", "Apply: no C_Map leaves the bundled zone name")
equal(untouched.instances[33].name, "Bundled Dungeon", "Apply: no GetLFGDungeonInfo leaves the bundled instance")
equal(untouched.skills[164].name, "Bundled Smithing", "Apply: no C_SkillInfo leaves the bundled skill name")
equal(untouched.factions[72].name, "Bundled Faction", "Apply: no C_Reputation leaves the bundled faction name")

-- An insane native rectangle (NaN / zero / negative) is refused, so the bundled geometry stays.
local insane = {
	C_Map = {
		GetMapInfo = function(mapID)
			if mapID == 200 then
				return { mapID = 200, name = "Client Zone", parentMapID = 0 }
			end
		end,
		GetWorldPosFromMapPos = function()
			return { x = math.huge, y = math.huge }
		end,
		GetMapWorldSize = function()
			return 0, -5
		end,
	},
}
local guarded = Geometry.Apply(bundled(), insane)
equal(guarded.maps[200].cx, 1, "Apply: an insane native cx is refused, the bundled cx stays")
equal(guarded.maps[200].cy, 2, "Apply: an insane native cy is refused, the bundled cy stays")
equal(guarded.maps[200].sx, 3, "Apply: a zero native width is refused, the bundled sx stays")
equal(guarded.maps[200].sy, 4, "Apply: a negative native height is refused, the bundled sy stays")
equal(guarded.maps[200].name, "Client Zone", "Apply: only the sane native field is taken")

equal(Geometry.Apply(nil, applyApi), nil, "Apply: no data is a no-op")

-- Safe to call twice: the second pass is idempotent.
local twice = bundled()
Geometry.Apply(twice, applyApi)
Geometry.Apply(twice, applyApi)
equal(twice.maps[200].name, "Client Zone", "Apply: a second call keeps the native name")
equal(twice.maps[201].cx, -10, "Apply: a second call keeps the bundled geometry")

-- EnsureNative: reads ns.Data, applies once, and is memoized per data table.
local nsData = bundled()
ns.Data = nsData
equal(Geometry.EnsureNative(applyApi), nsData, "EnsureNative: returns the table it enriched")
equal(nsData.maps[200].name, "Client Zone", "EnsureNative: enriches ns.Data")
nsData.maps[200].name = "Changed"
Geometry.EnsureNative(applyApi)
equal(nsData.maps[200].name, "Changed", "EnsureNative: a repeat call is memoized and re-overlays nothing")

-- QuestieSource swaps ns.Data for a shallow copy (its section tables shared). EnsureNative must read the table
-- ns.Data is now, not a table captured earlier: a swap triggers one more overlay onto the new identity.
local swapped = {}
for key, value in pairs(nsData) do
	swapped[key] = value
end
swapped.maps[200].name = "Reset By Swap"
ns.Data = swapped
Geometry.EnsureNative(applyApi)
equal(swapped.maps[200].name, "Client Zone", "EnsureNative: re-overlays the swapped ns.Data table")

print(("geometry_spec: %d checks passed"):format(checks))
