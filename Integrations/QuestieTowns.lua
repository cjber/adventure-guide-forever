---@type string, AGFNamespace
local _, ns = ...
local floor = math.floor

-- Towns from the quest places the installed QuestieDB gives (docs/design.md §2.14): places within LINK yards of each
-- other stand in one town, a town wider than CAP is cut again at a shorter link, and a town's name is the flight-map
-- node within REACH yards of one of its places. Only the node names are bundled (Data/Geometry.lua `towns`).
---@class AGFQuestieTownsModule : AGFQuestieTowns
local Towns = {}
ns.QuestieTowns = Towns

local LINK, CAP, REACH = ns.Data.townLink, ns.Data.townCap, ns.Data.townReach
-- A cell is one square of a yard grid. No continent is this many cells across, so a column and a row share a number.
local ROW = 2 ^ 20

-- A place's continent and world yards through its map's rectangle; nil on a map the data doesn't place.
---@param data AGFData
---@param place {map: integer, x: number, y: number}
---@return integer? continent, number? x, number? y
local function World(data, place)
	local centre = data.maps[place.map]
	if not centre then
		return nil
	end
	return centre.continent, centre.cx - (place.y - 0.5) * centre.sy, centre.cy - (place.x - 0.5) * centre.sx
end

-- The cell `dx` columns and `dy` rows from the one holding (x, y), on a grid of `size` yards.
---@param x number
---@param y number
---@param size number
---@param dx? integer
---@param dy? integer
---@return number
local function Cell(x, y, size, dx, dy)
	return (floor(x / size) + (dx or 0)) * ROW + floor(y / size) + (dy or 0)
end

-- Single linkage: the groups of `points` joined by chains of steps of at most `reach` yards, each in `points` order.
---@param points AGFTownPoint[]
---@param reach number
---@param yield fun()
---@return AGFTownPoint[][]
local function Link(points, reach, yield)
	local parent, cells = {}, {}
	local function Find(i)
		while parent[i] ~= i do
			parent[i] = parent[parent[i]]
			i = parent[i]
		end
		return i
	end
	for i, point in ipairs(points) do
		parent[i] = i
		local key = Cell(point.x, point.y, reach)
		cells[key] = cells[key] or {}
		table.insert(cells[key], i)
	end
	local limit = reach * reach
	for i, point in ipairs(points) do
		for dx = -1, 1 do
			for dy = -1, 1 do
				for _, j in ipairs(cells[Cell(point.x, point.y, reach, dx, dy)] or {}) do
					local other = points[j]
					if i < j and (point.x - other.x) ^ 2 + (point.y - other.y) ^ 2 <= limit then
						parent[Find(i)] = Find(j)
					end
				end
			end
		end
		yield()
	end
	local groups, byRoot = {}, {}
	for i, point in ipairs(points) do
		local root = Find(i)
		local group = byRoot[root]
		if not group then
			group = {}
			byRoot[root], groups[#groups + 1] = group, group
		end
		group[#group + 1] = point
	end
	return groups
end

-- Whether two of `points` are more than CAP yards apart.
---@param points AGFTownPoint[]
---@param yield fun()
---@return boolean
local function Wide(points, yield)
	local limit = CAP * CAP
	for i, a in ipairs(points) do
		for j = i + 1, #points do
			local b = points[j]
			if (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 > limit then
				return true
			end
		end
		yield()
	end
	return false
end

-- Groups at `reach`; each one wider than CAP is grouped again at `reach` - 10. One shorter cut for the whole world
-- would break towns apart, so only wide groups (the capitals) are cut.
---@param points AGFTownPoint[]
---@param reach number
---@param into AGFTownPoint[][]
---@param yield fun()
local function Split(points, reach, into, yield)
	for _, group in ipairs(Link(points, reach, yield)) do
		if reach > 10 and Wide(group, yield) then
			Split(group, reach - 10, into, yield)
		else
			into[#into + 1] = group
		end
	end
end

-- Gives every place its town (`place.hub`) and returns the towns with a name, and the lookup `Towns.Hub` reads.
-- Hubs are numbered from 1 by continent, then the town's least world x, then its least y: the same catalogue gives
-- the same numbers every session, which saved orders rely on.
---@param data AGFData
---@param places AGFPlace[] every quest start and finish, in any order
---@param yield fun()
---@return table<integer, {name: string}> hubs
---@return AGFTownGrid grid
function Towns.Build(data, places, yield)
	local byKey, continents, order, pointOf = {}, {}, {}, {}
	for _, place in ipairs(places) do
		local key = place.map .. ":" .. place.x .. ":" .. place.y
		local point = byKey[key]
		if point == nil then
			local continent, x, y = World(data, place)
			point = false
			if continent then
				point = { continent = continent, x = x, y = y, map = place.map, px = place.x, py = place.y }
			end
			byKey[key] = point
			if continent then
				if not continents[continent] then
					continents[continent] = {}
					order[#order + 1] = continent
				end
				table.insert(continents[continent], point)
			end
			yield()
		end
		pointOf[place] = point or nil
	end
	-- pairs has no order: sort so that the grouping, and with it every hub number, is the same each session.
	table.sort(order)
	local groups = {}
	for _, continent in ipairs(order) do
		local points = continents[continent]
		table.sort(points, function(a, b)
			if a.map ~= b.map then
				return a.map < b.map
			end
			if a.px ~= b.px then
				return a.px < b.px
			end
			return a.py < b.py
		end)
		yield()
		Split(points, LINK, groups, yield)
	end
	for _, group in ipairs(groups) do
		local first = group[1]
		group.continent, group.x, group.y = first.continent, first.x, first.y
		for _, point in ipairs(group) do
			group.x, group.y = math.min(group.x, point.x), math.min(group.y, point.y)
		end
	end
	yield()
	table.sort(groups, function(a, b)
		if a.continent ~= b.continent then
			return a.continent < b.continent
		end
		if a.x ~= b.x then
			return a.x < b.x
		end
		if a.y ~= b.y then
			return a.y < b.y
		end
		return a[1].map < b[1].map
	end)
	---@type AGFTownGrid
	local grid = {}
	for hub, group in ipairs(groups) do
		for _, point in ipairs(group) do
			point.hub = hub
			local cells = grid[point.continent]
			if not cells then
				cells = {}
				grid[point.continent] = cells
			end
			local key = Cell(point.x, point.y, LINK)
			cells[key] = cells[key] or {}
			table.insert(cells[key], point)
		end
		yield()
	end
	for _, place in ipairs(places) do
		place.hub = pointOf[place] and pointOf[place].hub
	end
	-- A town's name: the nearest node within REACH of any of its places, the lower node on a tie.
	local hubs, nearest = {}, {}
	local steps = math.ceil(REACH / LINK)
	for _, node in ipairs(data.towns or {}) do
		local cells = grid[node.continent] or {}
		for dx = -steps, steps do
			for dy = -steps, steps do
				for _, point in ipairs(cells[Cell(node.x, node.y, LINK, dx, dy)] or {}) do
					local yards = math.sqrt((point.x - node.x) ^ 2 + (point.y - node.y) ^ 2)
					local best = nearest[point.hub]
					if
						yards <= REACH
						and (not best or yards < best.yards or (yards == best.yards and node.node < best.node))
					then
						nearest[point.hub] = { yards = yards, node = node.node }
						hubs[point.hub] = { name = node.name }
					end
				end
			end
		end
		yield()
	end
	return hubs, grid
end

-- The town of the quest place nearest `place` within LINK yards, or nil.
---@param data AGFData
---@param grid AGFTownGrid
---@param place {map: integer, x: number, y: number}
---@return integer?
function Towns.Hub(data, grid, place)
	local continent, x, y = World(data, place)
	local cells = continent and grid[continent]
	if not cells then
		return nil
	end
	---@cast x -?
	---@cast y -?
	local best, hub = LINK * LINK, nil
	for dx = -1, 1 do
		for dy = -1, 1 do
			for _, point in ipairs(cells[Cell(x, y, LINK, dx, dy)] or {}) do
				local d = (point.x - x) ^ 2 + (point.y - y) ^ 2
				if d < best or (d == best and (not hub or point.hub < hub)) then
					best, hub = d, point.hub
				end
			end
		end
	end
	return hub
end
