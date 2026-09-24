-- Run from the repository root: luajit tests/explore_spec.lua
-- Exploration and new lands (Hints/Explore.lua, roadmap #13 and #14): the choice of area and land on the bundled data
-- and on small fixtures, then both asides through tests/harness.lua against a stubbed C_MapExplorationInfo.
local harness = dofile("tests/harness.lua")
local checks = 0

local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local function clean(h, label)
	equal(#h.errors, 0, label .. ": errors\n" .. table.concat(h.errors, "\n"))
end

-- ui_spec's level-18 orc shaman in The Barrens (harness defaults), with `player` over them. `explored` maps a uiMapID
-- to the areas explored there, by name; nil leaves C_MapExplorationInfo out, as a client without it.
local function Load(player, explored)
	local h = harness.load({ player = player })
	if explored then
		h.explored = explored
		h.G.C_MapExplorationInfo = {
			GetExploredMapTextures = function(map)
				local textures = {}
				for _, overlay in ipairs(h.ns.Data.overlays[map] or {}) do
					if h.explored[map] and h.explored[map][overlay.name] then
						textures[#textures + 1] = { offsetX = overlay.ox, offsetY = overlay.oy, fileDataIDs = {} }
					end
				end
				-- As the client's MayReturnNothing: nothing, not an empty table, when nothing is explored.
				return textures[1] and textures or nil
			end,
		}
	end
	return h
end

-- Step 1's travel frame, where the providers are asked.
local function Settle(h)
	h.ns.Invalidate()
	h.flush()
end

local function Text(h)
	local aside = h.ns.Asides.Current()
	return aside and aside.text
end

--[[ The generated data ]]

do
	local h = Load()
	local data, Explore = h.ns.Data, h.ns.Explore
	-- The probe's Darkshore overlays (GetExploredMapTextures(1439) at level 18) are in the data by the same offsets.
	local darkshore = {}
	for _, overlay in ipairs(data.overlays[1439]) do
		darkshore[overlay.ox .. ":" .. overlay.oy] = overlay.name
	end
	equal(darkshore["324:306"], "Ameth'Aran", "the probe's first texture")
	equal(darkshore["318:162"], "Auberdine", "its second")
	equal(darkshore["365:181"], "Bashal'Aran", "its third")
	for map, overlays in pairs(data.overlays) do
		for _, overlay in ipairs(overlays) do
			equal(overlay.level > 0, true, ("%d %s: an ExplorationLevel"):format(map, overlay.name))
		end
	end
	-- Riverglades: 36 to 44, a flight master for each side; Mount Hyjal and Shen'dralas (all level 0) are no land.
	local riverglades = data.forever.lands[2548]
	equal(riverglades.min .. "-" .. riverglades.max, "36-44", "Riverglades' range")
	equal(riverglades.taxi[1].name .. "/" .. riverglades.taxi[1].side, "Rog'mar, Riverglades/2", "the Horde's")
	equal(riverglades.taxi[2].name .. "/" .. riverglades.taxi[2].side, "Farholde Keep, Riverglades/1", "the Alliance's")
	equal(data.forever.lands[2482], nil, "no Mount Hyjal")
	equal(data.forever.lands[2652], nil, "no Shen'dralas")
	equal(data.forever.lands[2521].min .. "-" .. data.forever.lands[2521].max, "3-12", "Zephras Isle's range")
	equal(#data.forever.lands[2521].taxi, 0, "and no flight master")

	-- Unexplored: the nearest area of the player's map they haven't explored, at most two levels above them.
	local player = { level = 18, side = 2, map = 1413, x = 0.52, y = 0.30 }
	local function Name(explored)
		local overlay = Explore.Unexplored(data, player, explored)
		return overlay and overlay.name
	end
	equal(Name({}), "The Crossroads", "the nearest")
	equal(Name({ ["431:118"] = true }), "Thorn Hill", "an explored one is passed over")
	player.x, player.y = 0.45, 0.8
	equal(Name({}), "Blackthorn Ridge", "Bael Modan (25) is nearer, but too high")
	player.x, player.y = nil, nil
	equal(Name({}), "Camp Taurajo", "no place for the player: the lowest area ID")
	local all = {}
	for _, overlay in ipairs(data.overlays[1413]) do
		all[overlay.ox .. ":" .. overlay.oy] = true
	end
	equal(Name(all), nil, "every one explored")
	player.map = 1454
	equal(Name({}), nil, "a capital has none")
	player.map = nil
	equal(Name({}), nil, "nor does no map")
	clean(h, "data")
end

-- An area Forever added comes before a nearer one, and a level above the window never shows.
do
	local h = Load()
	local Explore = h.ns.Explore
	local data = {
		overlays = {
			[7] = {
				{ area = 1, name = "Near", level = 5, ox = 0, oy = 0, x = 0.5, y = 0.5 },
				{ area = 2, name = "Far and new", level = 5, ox = 10, oy = 0, x = 0.9, y = 0.9 },
				{ area = 3, name = "New but high", level = 8, ox = 20, oy = 0, x = 0.5, y = 0.5 },
			},
		},
		forever = { areas = { [2] = true, [3] = true } },
	}
	local player = { level = 5, side = 1, map = 7, x = 0.5, y = 0.5 }
	equal(Explore.Unexplored(data, player, {}).name, "Far and new", "Forever's first")
	equal(Explore.Unexplored(data, player, { ["10:0"] = true }).name, "Near", "then the nearest")
	player.level = 6
	equal(Explore.Unexplored(data, player, {}).name, "New but high", "8 is within two levels of 6: nearer, and new")
	clean(h, "added first")
end

--[[ New lands ]]

do
	local h = Load()
	local data, Explore = h.ns.Data, h.ns.Explore
	local explored = {}
	local function Seen(map)
		return explored[map] or {}
	end
	local function Land(level, side, map)
		local found, land, taxi = Explore.NewLand(data, { level = level, side = side, map = map or 1413 }, Seen)
		return found and ("%d %s %s"):format(found, land.name, taxi.name) or nil
	end
	equal(Land(38, 2), "2548 Riverglades Rog'mar, Riverglades", "the Horde's flight master")
	equal(Land(38, 1), "2548 Riverglades Farholde Keep, Riverglades", "the Alliance's")
	equal(Land(36, 2) ~= nil and Land(44, 2) ~= nil, true, "its range holds both ends")
	equal(Land(35, 2), nil, "never before its range: no teaser")
	equal(Land(45, 2), nil, "nor after")
	equal(Land(38, 2, 2548), nil, "not while standing in it")
	explored[2548] = { ["504:215"] = true }
	equal(Land(38, 2), nil, "not once any of it is explored")
	equal(Land(8, 1), nil, "Zephras Isle has no flight master the data places")
	local found = Explore.NewLand(data, { level = 38, side = 2, map = 1413 }, function()
		return nil
	end)
	equal(found, nil, "nothing when the client can't say what is explored")
	clean(h, "new lands")
end

--[[ The asides ]]

-- Without C_MapExplorationInfo, neither says anything.
do
	local h = Load({ level = 38 })
	Settle(h)
	equal(Text(h), nil, "no exploration API: no aside")
	clean(h, "no API")
end

-- An unexplored area of the zone: text only, retired by the client's discovery.
do
	local h = Load(nil, { [1413] = {} })
	Settle(h)
	local aside = h.ns.Asides.Current()
	equal(aside.text, "You haven't seen The Crossroads yet", "the nearest area")
	equal(aside.key, "explore", "one key for every area, so Not interested ends them all")
	equal(aside.icon, "islands-queue-prop-compass", "the guide's compass")
	equal(aside.place, nil, "no place: never a ring or a waypoint")
	equal(h.ns.Asides.Go(aside), false, "so Go goes nowhere")
	h.explored[1413]["The Crossroads"] = true
	h.fire("MAP_EXPLORATION_UPDATED")
	equal(Text(h), "You haven't seen Thorn Hill yet", "discovery retires it at once")
	-- The client's own name for the area wins.
	h.G.C_Map.GetAreaInfo = function(area)
		return area == 1699 and "Colline des Épines" or nil
	end
	h.fire("MAP_EXPLORATION_UPDATED")
	equal(Text(h), "You haven't seen Colline des Épines yet", "the client's name")
	h.ns.Asides.Decline(h.ns.Asides.Current())
	h.explored[1413]["Thorn Hill"] = true
	Settle(h)
	equal(Text(h), nil, "not interested: no more areas")
	clean(h, "unexplored")
end

-- A new land comes before the zone's area, with Go to the flight master for the player's side.
do
	local h = Load({ level = 38 }, { [1413] = {} })
	Settle(h)
	local aside = h.ns.Asides.Current()
	equal(aside.text, "Map 2548 · For levels 36-44", "the client's name for the land, and its levels")
	equal(aside.key, "land:2548", "one key per land")
	equal(aside.icon, "flightmaster", "the flight master mark")
	equal(aside.place.name, "Rog'mar, Riverglades", "the Horde's flight master")
	equal(h.ns.Asides.Go(aside), true, "Go")
	equal(h.waypoint.uiMapID, 2548, "a waypoint on the land")
	equal(h.waypoint.position.x .. "," .. h.waypoint.position.y, "0.5961,0.4506", "at the flight master")
	h.explored[2548] = { ["Rog'mar"] = true }
	h.fire("MAP_EXPLORATION_UPDATED")
	equal(Text(h), "You haven't seen The Crossroads yet", "once seen, the zone's area again")
	clean(h, "new land")
end

-- In combat the last answers stand, as for every aside.
do
	local h = Load(nil, { [1413] = {} })
	Settle(h)
	h.combat = true
	h.explored[1413]["The Crossroads"] = true
	h.fire("MAP_EXPLORATION_UPDATED")
	equal(Text(h), "You haven't seen The Crossroads yet", "combat: unchanged")
	h.combat = false
	Settle(h)
	equal(Text(h), "You haven't seen Thorn Hill yet", "after combat: asked again")
	clean(h, "combat")
end

print(("explore_spec: %d checks passed"):format(checks))
