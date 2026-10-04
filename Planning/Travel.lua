---@type string, AGFNamespace
local _, ns = ...
local Model = ns.Model
local State = ns.Planner.State
local NONE = {}
local HasBit = ns.Model.HasBit
local ValidPlace = ns.Model.ValidPlace

local CLOSE = 0.03 * 0.03

local function Distance(a, b)
	if not ValidPlace(a) or a.map ~= b.map then
		return 1000000
	end
	return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2
end

-- One cost in yards, offline, so a rebuild never waits on travel maths (docs/design.md §4.1). A place goes into one
-- frame: its map's world rectangle, then its continent's place on the Azeroth map, so two steps an ocean apart still
-- get a distance. Across an ocean it runs through the player's side's boat or zeppelin docks, so the far side's step
-- nearest the landing is the one the route enters at.
local CROSSING = 10000 -- the wait and the sail, which the distance to and from the docks cannot see
local UNKNOWN = 1000000 -- no way to measure: dearer than any crossing, so it never ties by accident

-- A place's point in its frame, without a table: x, y, continent and whether the data places it on the Azeroth map.
---@return number?, number, integer|string, boolean
local function Point(data, place)
	if not ValidPlace(place) then
		return nil, 0, "", false
	end
	local map = data.maps and data.maps[place.map]
	local shift = map and data.continents and data.continents[map.continent]
	if not shift then
		return place.x, place.y, "map " .. place.map, false
	end
	return shift.x - map.cy + (place.x - 0.5) * map.sx, shift.y - map.cx + (place.y - 0.5) * map.sy, map.continent, true
end

---@return AGFPosition?
local function Position(data, place, docks)
	local x, y, continent, known = Point(data, place)
	if not x then
		return nil
	end
	return { x = x, y = y, continent = continent, known = known, docks = known and docks or nil }
end

-- Both directions of every crossing `side` may take whose continents the data places on the Azeroth map.
---@return AGFFrameCrossing[]
local function Docks(data, side)
	local kept = State.planDocks and State.planDocks.data == data and State.planDocks[side]
	if kept then
		return kept
	end
	local docks = {}
	local function Frame(dock)
		local shift = data.continents and data.continents[dock.continent]
		return shift and { x = shift.x - dock.y, y = shift.y - dock.x }
	end
	for _, crossing in ipairs(data.crossings or NONE) do
		local a, b = Frame(crossing.a), Frame(crossing.b)
		if a and b and HasBit(crossing.side, side) then
			docks[#docks + 1] = { from = crossing.a.continent, to = crossing.b.continent, leave = a, land = b }
			docks[#docks + 1] = { from = crossing.b.continent, to = crossing.a.continent, leave = b, land = a }
		end
	end
	if State.planDocks and State.planDocks.data == data then
		State.planDocks[side] = docks
	end
	return docks
end

local function Yards(a, b)
	return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end

-- Yards between two places on one continent the data places; nil when it cannot say (another continent, or a map
-- the data has no geometry for).
---@param a {map: integer, x: number, y: number}
---@param b {map: integer, x: number, y: number}
---@return number?
function Model.Yards(data, a, b)
	local ax, ay, here, aKnown = Point(data, a)
	local bx, by, there, bKnown = Point(data, b)
	if aKnown and bKnown and here == there then
		return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
	end
end

---@param a AGFPosition?
local function CostTo(a, bx, by, bContinent, bKnown)
	if not (a and bx) or (a.continent ~= bContinent and not (a.known and bKnown)) then
		return UNKNOWN
	end
	local straight = math.sqrt((a.x - bx) ^ 2 + (a.y - by) ^ 2)
	if a.continent == bContinent then
		return straight
	end
	local best
	for _, dock in ipairs(a.docks or NONE) do
		if dock.from == a.continent and dock.to == bContinent then
			local via = Yards(a, dock.leave) + math.sqrt((dock.land.x - bx) ^ 2 + (dock.land.y - by) ^ 2)
			best = (best and best < via) and best or via
		end
	end
	-- No boat for this side between them: the straight line across the sea.
	return CROSSING + (best or straight)
end

---@param a AGFPosition?
---@param b AGFPosition?
local function Cost(a, b)
	if not b then
		return UNKNOWN
	end
	return CostTo(a, b.x, b.y, b.continent, b.known)
end

-- Whether the data places both on the Azeroth map, on different continents.
local function Oversea(data, a, b)
	local _, _, here, aKnown = Point(data, a)
	local _, _, there, bKnown = Point(data, b)
	return aKnown and bKnown and here ~= there
end

-- The cost between two stops: an area is entered at its ring, so both radii come off.
local function Gap(a, ra, b, rb)
	return math.max(0, Cost(a, b) - ra - rb)
end

ns.Planner.Travel = {
	CLOSE = CLOSE,
	Cost = Cost,
	CostTo = CostTo,
	Distance = Distance,
	Docks = Docks,
	Gap = Gap,
	Oversea = Oversea,
	Point = Point,
	Position = Position,
	UNKNOWN = UNKNOWN,
	Yards = Yards,
}
