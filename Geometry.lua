---@type string, AGFNamespace
local _, ns = ...

-- Native-geometry adapter (roadmap: stop bundling geometry the client can answer). Every function here takes an
-- injected `api` table rather than reading globals, so the module loads in the client with `api` being the real
-- namespaces ($C_Map, C_SkillInfo, C_Reputation, GetLFGDungeonInfo, UiMapPoint, ...) and in the headless specs with
-- stubs. Nothing is required or touched at load: a caller decides when to build a section and how to merge it.
--
-- What the client can answer natively, and what it cannot:
--   maps       name, continent, cx, cy, sx, sy  (C_Map.GetMapInfo / GetWorldPosFromMapPos / GetMapWorldSize)
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

-- The world map a uiMapID sits under: walk parentMapID up to the top of the chain, which is the continent the data's
-- AGFContinentShift is keyed by (0 Eastern Kingdoms, 1 Kalimdor, ...). Falls back to the map's own ID when the client
-- has no parent chain, so a map always lands in some continent bucket.
---@param api table
---@param mapID integer
---@param info table
---@return integer
local function Continent(api, mapID, info)
	local maps = ClientMap(api)
	if type(maps.GetMapInfo) ~= "function" then
		return info.mapID or mapID
	end
	local currentID, guard = mapID, 0
	while currentID and guard < 32 do
		guard = guard + 1
		local current = maps.GetMapInfo(currentID)
		if not current or not current.parentMapID or current.parentMapID == 0 then
			return (current and current.mapID) or info.mapID or mapID
		end
		currentID = current.parentMapID
	end
	return info.mapID or mapID
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

-- Every map the caller names, as AGFMapCentre minus the bundled fields: name, continent, cx, cy, sx, sy. uiMapIDs
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
				continent = Continent(api, mapID, info),
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
-- uiMapIDs omitted means none: the client exposes no list of LFG dungeons without C_LFGInfo, which this adapter
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
		out[lfgID] = {
			name = name,
			low = type(low) == "number" and low or nil,
			high = type(high) == "number" and high or nil,
		}
	end
	return out
end

-- Skill line names by SkillLine ID, as {name}, from the lines the character has (C_SkillInfo.GetNumSkillLines /
-- GetSkillLineInfo, or the Forever-missing globals GetNumSkillLines / GetSkillLineInfo) plus any IDs the caller
-- names. C_SkillInfo cannot name an unlearned line, so a quest's skill gate the character has never trained stays
-- on bundled data.
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
	elseif type(api) == "table" and type(api.GetNumSkillLines) == "function" then
		count = api.GetNumSkillLines()
	end
	local infoAt = skills.GetSkillLineInfo or (type(api) == "table" and api.GetSkillLineInfo)
	for index = 1, type(count) == "number" and count or 0 do
		local info = infoAt and infoAt(index)
		if info and info.name and info.skillID and not info.isHeader then
			out[info.skillID] = { name = info.name }
		end
	end
	return out
end

-- Faction names by Faction ID, as {name}, from C_Reputation: the IDs the caller names through
-- GetFactionDataByID, or every faction the client tracks through GetFactionDataByIndex + GetNumFactions.
---@param api table
---@param factionIDs? integer[]
---@return table<integer, {name: string?}>
function Geometry.Factions(api, factionIDs)
	local out = {}
	local reputation = ClientReputation(api)
	if type(api) ~= "table" then
		return out
	end
	if factionIDs then
		for _, id in ipairs(factionIDs) do
			local info = reputation.GetFactionDataByID and reputation.GetFactionDataByID(id)
			if info and info.name and info.name ~= "" then
				out[id] = { name = info.name }
			end
		end
		return out
	end
	if type(api.GetNumFactions) ~= "function" then
		return out
	end
	local count = api.GetNumFactions()
	local infoAt = reputation.GetFactionDataByIndex
	for index = 1, type(count) == "number" and count or 0 do
		local info = infoAt and infoAt(index)
		if info and info.factionID and info.name and info.name ~= "" then
			out[info.factionID] = { name = info.name }
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
	for id, fields in pairs(incoming or NONE) do
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
