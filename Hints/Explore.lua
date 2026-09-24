---@type string, AGFNamespace
local _, ns = ...
local L = ns.L

-- Exploration and new lands (roadmap #13 and #14, docs/design.md §2.11): two asides after the trainer's. A land
-- Forever added that fits the player's level, with Go to its flight master for their side; else an area of the zone
-- they stand in that they haven't seen, as text only. Both read what the player has explored from the client
-- (C_MapExplorationInfo.GetExploredMapTextures, probe `explore`); without it neither says anything.
---@class AGFExploreModule : AGFExplore
local Explore = {}
ns.Explore = Explore

-- Levels: an area this far above the player is still suggested, as the next zone looks two levels on.
local AHEAD = 2
-- A zone map's art is 1002 by 668 pixels (tools/gen_quests.py CANVAS), so across is worth 1.5 times down.
local ACROSS, DOWN = 3, 2

---@param ox number
---@param oy number
---@return string
local function Key(ox, oy)
	return ox .. ":" .. oy
end

-- Each overlay the player has explored on `map`, by its offset; nil when the client can't say.
---@param map integer
---@return table<string, true>?
function Explore.Explored(map)
	local api = C_MapExplorationInfo
	if not (api and api.GetExploredMapTextures) then
		return nil
	end
	local seen = {}
	for _, info in ipairs(api.GetExploredMapTextures(map) or {}) do
		seen[Key(info.offsetX, info.offsetY)] = true
	end
	return seen
end

-- The area to suggest on the player's map: one they haven't explored, at most AHEAD levels above them, an area
-- Forever added before the rest, then the nearest (the lowest area ID with no place for them). Nil when every one is
-- explored, or the map has none.
---@param data AGFData
---@param player AGFPlayer
---@param explored table<string, true> the player's map's explored overlays (Explore.Explored)
---@return AGFOverlay?
function Explore.Unexplored(data, player, explored)
	---@type AGFOverlay[]
	local overlays = player.map and data.overlays and data.overlays[player.map] or {}
	local added = data.forever and data.forever.areas or {}
	local best, bestFirst, bestNear
	for _, overlay in ipairs(overlays) do
		if overlay.level <= player.level + AHEAD and not explored[Key(overlay.ox, overlay.oy)] then
			local first, near = added[overlay.area] and 0 or 1, 0
			if player.x and player.y then
				near = ((overlay.x - player.x) * ACROSS) ^ 2 + ((overlay.y - player.y) * DOWN) ^ 2
			end
			if
				not best
				or first < bestFirst
				or first == bestFirst and (near < bestNear or near == bestNear and overlay.area < best.area)
			then
				best, bestFirst, bestNear = overlay, first, near
			end
		end
	end
	return best
end

-- The land to suggest: one Forever added whose range holds the player's level, that has a flight master for their
-- side and where they have explored nothing and don't stand; the lowest map ID first. Its first such flight master is
-- where Go takes them. Nil when there is none, or the client can't say what they have explored.
---@param data AGFData
---@param player AGFPlayer
---@param explored fun(map: integer): table<string, true>? Explore.Explored
---@return integer? map
---@return AGFLand? land
---@return AGFLandTaxi? taxi
function Explore.NewLand(data, player, explored)
	local lands = data.forever and data.forever.lands or {}
	local maps = {}
	for map in pairs(lands) do
		maps[#maps + 1] = map
	end
	table.sort(maps)
	for _, map in ipairs(maps) do
		local land = lands[map]
		if land.min <= player.level and player.level <= land.max and map ~= player.map then
			for _, taxi in ipairs(land.taxi) do
				if bit.band(taxi.side, player.side) ~= 0 then
					local seen = explored(map)
					if seen and next(seen) == nil then
						return map, land, taxi
					end
					break
				end
			end
		end
	end
	return nil
end

--[[ The providers, after the trainer's: a new land first, then the zone's unexplored area. ]]

ns.Asides.Register(function()
	local map, land, taxi = Explore.NewLand(ns.Data, ns.State.Player(), Explore.Explored)
	if not (map and land and taxi) then
		return nil
	end
	local name = ns.State.MapName(map) or land.name
	-- The minimap's flight master mark (CSV:1330).
	return {
		key = "land:" .. map,
		text = L.NEW_LAND:format(name, land.min, land.max),
		icon = "flightmaster",
		place = taxi,
	}
end)

ns.Asides.Register(function()
	local player = ns.State.Player()
	local explored = player.map and Explore.Explored(player.map)
	local overlay = explored and Explore.Unexplored(ns.Data, player, explored)
	if not overlay then
		return nil
	end
	local name = C_Map.GetAreaInfo and C_Map.GetAreaInfo(overlay.area)
	-- The guide tab's own compass (CSV:3202): no ring and no place, only the area's name.
	return {
		key = "explore",
		text = L.UNEXPLORED:format(name and name ~= "" and name or overlay.name),
		icon = "islands-queue-prop-compass",
	}
end)

-- The client's "Discovered" retires the line at once, and a new land's once its first area is seen.
local discovery = CreateFrame("Frame")
discovery:RegisterEvent("MAP_EXPLORATION_UPDATED")
discovery:SetScript("OnEvent", ns.Asides.Refresh)
