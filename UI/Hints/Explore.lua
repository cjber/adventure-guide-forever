---@type string, AGFNamespace
local _, ns = ...
local L = ns.L

-- New lands (docs/design.md §2.11): an aside after the trainer's. A land Forever added that fits the player's level,
-- with Go to its flight master for their side. It reads what the player has explored from the client
-- (C_MapExplorationInfo.GetExploredMapTextures, probe `explore`); without it, it says nothing.
---@class AGFExploreModule : AGFExplore
local Explore = {}
ns.Explore = Explore

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

--[[ The provider, after the trainer's. ]]

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

-- The client's "Discovered" retires a new land's line once its first area is seen.
local discovery = CreateFrame("Frame")
discovery:RegisterEvent("MAP_EXPLORATION_UPDATED")
discovery:SetScript("OnEvent", ns.Asides.Refresh)
