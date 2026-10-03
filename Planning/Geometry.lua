---@type string, AGFNamespace
local _, ns = ...

-- Native-geometry adapter: the client answers what the data would otherwise bundle. Every function here takes an
-- injected `api` table rather than reading globals, so the module loads in the client with `api` being the real
-- namespaces (C_Map, C_SkillInfo, C_Reputation, GetLFGDungeonInfo, UiMapPoint, ...) and in the headless specs with
-- stubs. Nothing is required or touched at load: a caller decides when to build a section and how to merge it.
--
-- What the client can answer natively, and what it cannot:
--   maps       name, cx, cy, sx, sy             (C_Map.GetMapInfo / GetWorldPosFromMapPos / GetMapWorldSize)
--   zones      name only                        (level ranges have NO native API; min/max stay bundled)
--   instances  name, low, high                  (GetLFGDungeonInfo returns 1 and 7/8; raid/entrances stay bundled)
--   skills     name                             (C_SkillInfo lists only learned lines, so unlearned gates stay bundled)
--   factions   name                             (C_Reputation by ID/index; stand-in data fields stay bundled)
---@class AGFGeometry
local Geometry = {}
ns.Geometry = Geometry

-- A "None"/absent client answer: C_Map.GetMapInfo returns nil past the known maps, FactionDataByID nil for the
-- other side's factions, and several Forever builds lack a whole namespace. Empty tables are the honest result.
local NONE = {}

---@param api table injected client surface, e.g. { C_Map = C_Map, UiMapPoint = UiMapPoint }
---@return table
local function ClientMap(api)
	return api and api.C_Map or NONE
end

---@param api table
---@return table
local function ClientSkills(api)
	return api and api.C_SkillInfo or NONE
end

---@param api table
---@return table
local function ClientReputation(api)
	return api and api.C_Reputation or NONE
end

-- A UiMapPoint for GetWorldPosFromMapPos when the client has the factory; the specs and older builds may take the
-- plain {x, y} table the probe recorded.
---@param api table
---@param mapID integer
---@param x number
---@param y number
---@return any
local function MapPos(api, mapID, x, y)
	local factory = api and api.UiMapPoint
	if factory and type(factory.CreateFromCoordinates) == "function" then
		return factory.CreateFromCoordinates(mapID, x, y)
	end
	return { x = x, y = y }
end

-- A world position as x, y: a UiMapPoint (:GetXY), a {x, y} table, or a {x, y} array. Returns nil, nil when the
-- client gives nothing usable.
---@param point any
---@return number?, number?
local function XY(point)
	if type(point) ~= "table" then
		return nil, nil
	end
	if type(point.GetXY) == "function" then
		local ok, x, y = pcall(point.GetXY, point)
		if ok and type(x) == "number" and type(y) == "number" then
			return x, y
		end
	end
	if type(point.x) == "number" or type(point.y) == "number" then
		return point.x, point.y
	end
	return point[1], point[2]
end

-- A world position for one map-space point, via GetWorldPosFromMapPos, or nil, nil where the client cannot answer.
---@param api table
---@param mapID integer
---@param x number
---@param y number
---@return number?, number?
local function WorldPos(api, mapID, x, y)
	local maps = ClientMap(api)
	if type(maps.GetWorldPosFromMapPos) ~= "function" then
		return nil, nil
	end
	local ok, point = pcall(maps.GetWorldPosFromMapPos, mapID, MapPos(api, mapID, x, y))
	if not ok then
		return nil, nil
	end
	return XY(point)
end

-- A map's world rectangle: sx/sy in yards across the full map and its centre in world yards. GetMapWorldSize gives
-- the size directly; the corners of GetWorldPosFromMapPos((0,0)) and ((1,1)) give both the centre and a fallback
-- size. All nil where the client answers none.
---@param api table
---@param mapID integer
---@return number?, number?, number?, number?
local function MapRect(api, mapID)
	local maps = ClientMap(api)
	local sx, sy, cx, cy
	local x0, y0 = WorldPos(api, mapID, 0, 0)
	local x1, y1 = WorldPos(api, mapID, 1, 1)
	if x0 and x1 then
		sx, cx = x1 - x0, (x0 + x1) / 2
	end
	if y0 and y1 then
		sy, cy = y1 - y0, (y0 + y1) / 2
	end
	if type(maps.GetMapWorldSize) == "function" then
		local width, height = maps.GetMapWorldSize(mapID)
		if type(width) == "number" and width > 0 then
			sx = width
		end
		if type(height) == "number" and height > 0 then
			sy = height
		end
	end
	return sx, sy, cx, cy
end

-- Every map the caller names, as AGFMapCentre minus the bundled fields: name, cx, cy, sx, sy. uiMapIDs
-- omitted means none (the client enumerates child maps only through GetMapChildrenInfo, which the data never needs).
---@param api table
---@param uiMapIDs? integer[]
---@return table<integer, AGFMapCentre>
function Geometry.Maps(api, uiMapIDs)
	local out = {}
	local maps = ClientMap(api)
	if type(maps.GetMapInfo) ~= "function" then
		return out
	end
	for _, mapID in ipairs(uiMapIDs or NONE) do
		local info = maps.GetMapInfo(mapID)
		if info then
			local sx, sy, cx, cy = MapRect(api, mapID)
			local name = info.name ~= "" and info.name or nil
			out[mapID] = {
				name = name,
				cx = cx,
				cy = cy,
				sx = sx,
				sy = sy,
			}
		end
	end
	return out
end

-- Every zone the caller names, as {name}. The data's AGFZone also carries min/max level ranges, which the client has
-- no API for; Merge leaves those bundled values in place.
---@param api table
---@param uiMapIDs? integer[]
---@return table<integer, {name: string?}>
function Geometry.Zones(api, uiMapIDs)
	local out = {}
	local maps = ClientMap(api)
	if type(maps.GetMapInfo) ~= "function" then
		return out
	end
	for _, mapID in ipairs(uiMapIDs or NONE) do
		local info = maps.GetMapInfo(mapID)
		if info then
			out[mapID] = { name = info.name ~= "" and info.name or nil }
		end
	end
	return out
end

-- Every LFG dungeon ID the caller names, as {name, low, high}. GetLFGDungeonInfo returns the name first and the
-- recommended levels 7th and 8th (same slot Dungeons.lua already reads); GetRealZoneText is the name fallback.
-- The key is the LFG ID, not the instance Map.ID: overlay an instance by its own `.lfg` field (Merge matches those).
-- lfgIDs omitted means none: the client exposes no list of LFG dungeons without C_LFGInfo, which this adapter
-- deliberately does not pull in.
---@param api table
---@param lfgIDs? integer[]
---@return table<integer, {name: string?, low: integer?, high: integer?}>
function Geometry.Instances(api, lfgIDs)
	local out = {}
	if type(api) ~= "table" or type(api.GetLFGDungeonInfo) ~= "function" then
		return out
	end
	for _, lfgID in ipairs(lfgIDs or NONE) do
		local name, _, _, _, _, _, low, high = api.GetLFGDungeonInfo(lfgID)
		if type(name) ~= "string" or name == "" then
			name = nil
		end
		if not name and type(api.GetRealZoneText) == "function" then
			local zone = api.GetRealZoneText(lfgID)
			name = zone ~= "" and zone or nil
		end
		-- Forever answers some dungeons with the same level twice; that is not a range, so the bundled one stays.
		local ranged = type(low) == "number" and type(high) == "number" and low > 0 and high > low
		out[lfgID] = {
			name = name,
			low = ranged and low or nil,
			high = ranged and high or nil,
		}
	end
	return out
end

-- Skill line names by SkillLine ID, as {name}, from the lines the character has (C_SkillInfo.GetNumSkillLines /
-- GetSkillLineInfo) plus any IDs the caller names. C_SkillInfo cannot name an unlearned line, so a quest's skill
-- gate the character has never trained stays on bundled data.
---@param api table
---@param skillLineIDs? integer[]
---@return table<integer, {name: string?}>
function Geometry.Skills(api, skillLineIDs)
	local out = {}
	local skills = ClientSkills(api)
	for _, id in ipairs(skillLineIDs or NONE) do
		local info = skills.GetSkillLineInfoByID and skills.GetSkillLineInfoByID(id)
		if info and info.name then
			out[id] = { name = info.name }
		end
	end
	local count
	if type(skills.GetNumSkillLines) == "function" then
		count = skills.GetNumSkillLines()
	end
	local infoAt = skills.GetSkillLineInfo
	for index = 1, type(count) == "number" and count or 0 do
		local info = infoAt and infoAt(index)
		if info and info.name and info.skillID and not info.isHeader then
			out[info.skillID] = { name = info.name }
		end
	end
	return out
end

-- Faction names by Faction ID, as {name}, from C_Reputation.GetFactionDataByID for the IDs the caller names.
---@param api table
---@param factionIDs integer[]
---@return table<integer, {name: string?}>
function Geometry.Factions(api, factionIDs)
	local out = {}
	local reputation = ClientReputation(api)
	for _, id in ipairs(factionIDs) do
		local info = reputation.GetFactionDataByID and reputation.GetFactionDataByID(id)
		if info and info.name and info.name ~= "" then
			out[id] = { name = info.name }
		end
	end
	return out
end

-- copy only the fields native actually has: a nil (a missing name, or an ID the client did not know) leaves the
-- bundled value alone.
---@param target table
---@param incoming table
---@return table
function Geometry.Overlay(target, incoming)
	for id, fields in pairs(incoming) do
		local entry = target[id]
		if not entry then
			entry = {}
			target[id] = entry
		end
		for key, value in pairs(fields) do
			if value ~= nil then
				entry[key] = value
			end
		end
	end
	return target
end

-- AGFInstance is keyed by instance Map.ID while Geometry.Instances is keyed by LFG ID. Rewrite the native keys
-- through each data entry's `.lfg` so the levels land on the instance that names that dungeon; an LFG ID the data
-- does not carry is created under its own key, the best a caller without Map.ID can do.
---@param instances table<integer, table>
---@param incoming table<integer, table>
---@return table<integer, table>
local function ByInstanceID(instances, incoming)
	local byLFG = {}
	for id, entry in pairs(instances) do
		if entry.lfg then
			byLFG[entry.lfg] = id
		end
	end
	local resolved = {}
	for lfgID, fields in pairs(incoming) do
		resolved[byLFG[lfgID] or lfgID] = fields
	end
	return resolved
end

-- Overlay one native table onto an existing data table without clobbering fields native cannot provide: a zone
-- keeps its bundled min/max, an instance its raid/entrances/lfg, a map any field outside the five native ones.
-- `native` is a map of section name -> table: { maps = Geometry.Maps(api, ...), zones = ... }. A section the
-- caller did not build is left untouched; a map the data lacks is created.
---@param data AGFData
---@param native table<string, table>
---@return AGFData
function Geometry.Merge(data, native)
	if type(data) ~= "table" or type(native) ~= "table" then
		return data
	end
	for _, section in ipairs({ "maps", "zones", "instances", "skills", "factions" }) do
		local incoming = native[section]
		if incoming then
			data[section] = data[section] or {}
			if section == "instances" then
				incoming = ByInstanceID(data[section], incoming)
			end
			Geometry.Overlay(data[section], incoming)
		end
	end
	return data
end

--[[ Runtime seam: overlay the client's answers onto the live data ]]
--
-- Everything above builds one section from an injected `api` and merges it by hand. This is the one place the addon
-- actually calls them: Geometry.EnsureNative() reads whichever table ns.Data is at the moment the planner is about to
-- read it (QuestieSource swaps ns.Data for its own build once QuestieDB loads), overlays only the fields the client
-- answers, and remembers it did. It never replaces ns.Data or a section table: Merge mutates the section tables in
-- place, and QuestieSource reuses those same section tables across its swap, so the enrichment survives the swap.

-- A native number that is a real, plausibly-world-scale coordinate or length. A client that answers with a nil
-- corner, a zero-size map or a NaN would otherwise move routing maths off the bundled geometry, so a value that
-- fails this (or a missing one) leaves the bundled value in place.
local WORLD_LIMIT = 1e6 -- yards: a continent shift is tens of thousands, so this only rejects absurd answers

---@param value any
---@return boolean
local function Sane(value)
	return type(value) == "number"
		and value == value -- not NaN
		and value ~= math.huge
		and value ~= -math.huge
		and math.abs(value) <= WORLD_LIMIT
end

-- Native map fields without the world-rect answers the client cannot give sanely. Because those fields are nil,
-- Merge leaves the bundled ones untouched. `continent` is never native: the data keys its `continents` shifts and
-- its routing by the client's Map.dbc ID (0 Eastern Kingdoms, 1 Kalimdor, 30 Alterac Valley), a space no client
-- API exposes, so the bundled value always stays.
---@param maps table<integer, AGFMapCentre>
---@return table<integer, AGFMapCentre>
local function NativeMaps(maps)
	for _, entry in pairs(maps) do
		if not (Sane(entry.cx) and Sane(entry.cy)) then
			entry.cx, entry.cy = nil, nil
		end
		if not (Sane(entry.sx) and entry.sx > 0) then
			entry.sx = nil
		end
		if not (Sane(entry.sy) and entry.sy > 0) then
			entry.sy = nil
		end
	end
	return maps
end

-- Overlay one data table with every section the client can answer for the IDs that table already names. It builds
-- only the sections the data carries, so it creates no keys the planner never reads and clobbers nothing native
-- cannot answer (zones.min/max, instances.raid/lfg/entrances, crossings, zoneArt, towns, roles). Kept
-- pure over `api` so the specs drive it with stubs; Geometry.EnsureNative supplies the real client.
---@param data AGFData?
---@param api table
---@return AGFData?
function Geometry.Apply(data, api)
	if type(data) ~= "table" then
		return data
	end
	local mapIDs, zoneIDs, lfgIDs, skillIDs, factionIDs = {}, {}, {}, {}, {}
	for id in pairs(data.maps or NONE) do
		mapIDs[#mapIDs + 1] = id
	end
	for id in pairs(data.zones or NONE) do
		zoneIDs[#zoneIDs + 1] = id
	end
	for _, entry in pairs(data.instances or NONE) do
		if entry.lfg then
			lfgIDs[#lfgIDs + 1] = entry.lfg
		end
	end
	for id in pairs(data.skills or NONE) do
		skillIDs[#skillIDs + 1] = id
	end
	for id in pairs(data.factions or NONE) do
		factionIDs[#factionIDs + 1] = id
	end
	return Geometry.Merge(data, {
		maps = NativeMaps(Geometry.Maps(api, mapIDs)),
		zones = Geometry.Zones(api, zoneIDs),
		instances = Geometry.Instances(api, lfgIDs),
		skills = Geometry.Skills(api, skillIDs),
		factions = Geometry.Factions(api, factionIDs),
	})
end

-- The real client surface, read through the chunk's own globals (not _G), so it resolves under the specs' setfenv.
-- The Forever-missing globals GetNumSkillLines / GetSkillLineInfo / GetNumFactions are not named: Apply passes the
-- data's own skill and faction IDs explicitly, and C_SkillInfo names a learned line by ID.
---@return table
local function ClientApi()
	return {
		C_Map = C_Map,
		UiMapPoint = UiMapPoint,
		C_SkillInfo = C_SkillInfo,
		C_Reputation = C_Reputation,
		GetLFGDungeonInfo = GetLFGDungeonInfo,
		GetRealZoneText = GetRealZoneText,
	}
end

-- data table -> true, so a swap re-applies once and a repeat call within one table's life is free. Weak keys: a
-- table QuestieSource throws away does not pin its section tables forever.
local applied = setmetatable({}, { __mode = "k" })

---@param api? table for specs
---@return AGFData?
function Geometry.EnsureNative(api)
	local data = ns.Data
	if type(data) ~= "table" or applied[data] then
		return data
	end
	local result = Geometry.Apply(data, api or ClientApi())
	applied[data] = true
	return result
end
