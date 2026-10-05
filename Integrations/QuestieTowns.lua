---@type string, AGFNamespace
local _, ns = ...

local Model = ns.Model

-- Towns from the quest places the installed QuestieDB gives (docs/design.md §2.14): a place belongs to the named area
-- of its map whose overlay rectangle holds it (Model.Hub), the areas the world map reveals as you explore
-- (Data/Geometry `towns`). A place in no area (a city map, an instance, a gap) belongs to its map itself, so a whole
-- city is one town. The client names an area (C_Map.GetAreaInfo) and a map (C_Map.GetMapInfo); the bundled English
-- AreaTable names stand in when it cannot, as in the headless harness.
---@class AGFQuestieTownsModule : AGFQuestieTowns
local Towns = {}
ns.QuestieTowns = Towns

-- The name of the town `place` stands in: the area's name in the client's language, the bundled English name
-- otherwise; the map's name for a map-level town.
---@param data AGFData
---@param place {map: integer, hub: string}
---@return string
function Towns.Name(data, place)
	local area = tonumber(place.hub:match(":(%d+)$") or "") or 0
	if area > 0 then
		local name = C_Map.GetAreaInfo and C_Map.GetAreaInfo(area)
		name = name and name ~= "" and name or (data.areaNames and data.areaNames[area])
		if name then
			return name
		end
	end
	local info = C_Map.GetMapInfo and C_Map.GetMapInfo(place.map)
	local name = info and info.name
	name = name and name ~= "" and name or (data.maps and data.maps[place.map] and data.maps[place.map].name)
	return name or tostring(place.map)
end

-- Gives every place its town (`place.hub`) and returns the towns with a name. Only the towns a place stands in are
-- named; a town no quest place reaches is named when a service NPC's place asks for it (QuestieSource.lua).
---@param data AGFData
---@param places AGFPlace[] every quest start and finish, in any order
---@param yield fun()
---@return table<string, {name: string}> hubs
function Towns.Build(data, places, yield)
	local hubs = {}
	for _, place in ipairs(places) do
		place.hub = Model.Hub(data, place)
		if place.hub and not hubs[place.hub] then
			hubs[place.hub] = { name = Towns.Name(data, place) }
		end
		yield()
	end
	return hubs
end

-- The town of `place`, or nil on a map the data doesn't place.
---@param data AGFData
---@param place {map: integer, x: number, y: number}
---@return string?
function Towns.Hub(data, place)
	return Model.Hub(data, place)
end
