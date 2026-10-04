---@type string, AGFNamespace
local _, ns = ...
local Model = ns.Model
local State = ns.Planner.State
local NONE = {}
local Cost = ns.Planner.Travel.Cost
local Describe = ns.Planner.Steps.Describe
local Docks = ns.Planner.Travel.Docks
local Enter = ns.Planner.Steps.Enter
local Gap = ns.Planner.Travel.Gap
local Locate = ns.Planner.Steps.Locate
local Opens = ns.Planner.Steps.Opens
local Position = ns.Planner.Travel.Position
local TownPoint = ns.Planner.Steps.TownPoint
local UNKNOWN = ns.Planner.Travel.UNKNOWN
local ValidPlace = ns.Model.ValidPlace

-- A stop the player only hands in at: a turn-in, or a town with hand-ins and nothing to pick up. Never a trainer's.
---@param step AGFStep
local function HandInOnly(step)
	return step.kind == "turnin" or (step.kind == "town" and #step.pickups == 0)
end

-- Orders `stops` greedily by nearest action (docs/design.md §4.1): from `from`, repeatedly the unvisited stop
-- cheapest to reach, so the route is the nearest action at every step. `group` (optional) names the town or area a
-- stop belongs to; a stop in the group the route is already in comes before the route leaves it, so nearby stops of
-- one town are finished first and the route never zig-zags between them. A stop already placed is never revisited,
-- and ties break by key, so a rebuild gives the same order.
---@param from? AGFPosition
---@param stops AGFStep[]
---@param at fun(step: AGFStep): AGFPosition?
---@param group? fun(step: AGFStep): unknown
---@return AGFStep[]
local function NearestStop(from, stops, at, group)
	local path, left = {}, {}
	for _, step in ipairs(stops) do
		left[#left + 1] = step
	end
	local here, was = from, nil
	while #left > 0 do
		local pick, pickIndex, pickCost, pickSame
		for index, step in ipairs(left) do
			local home = group and group(step) or nil
			local same = home ~= nil and home == was
			local cost = Gap(here, 0, at(step), step.r or 0)
			if
				not pick
				or (same ~= pickSame and same)
				or (same == pickSame and (cost < pickCost - 1e-6 or (cost <= pickCost + 1e-6 and step.key < pick.key)))
			then
				pick, pickIndex, pickCost, pickSame = step, index, cost, same
			end
		end
		table.remove(left, pickIndex)
		path[#path + 1] = pick
		here, was = at(pick), group and group(pick) or nil
	end
	return path
end

-- The greedy order is a planner primitive: the ordering specs call it directly (tests/order_spec.lua).
Model.Nearest = NearestStop

-- Groups the selected steps by continent, the player's first and the rest by how dear they are to reach, so the
-- route crosses each ocean once. In each group the turn-ins in `away` (another continent than the player's) go last,
-- and within a part the stops go in Nearest order, the player's nearest action at every step.
local function Order(selected, origin, where, away, planned)
	local groups, byContinent = {}, {}
	for _, step in ipairs(selected) do
		local continent = where[step].continent
		local group = byContinent[continent]
		if not group then
			group = { continent = continent, main = {}, last = {}, reach = math.huge }
			byContinent[continent] = group
			groups[#groups + 1] = group
		end
		table.insert(away[step] and group.last or group.main, step)
		group.reach = math.min(group.reach, Cost(origin, where[step]))
	end
	local home = origin and origin.continent
	table.sort(groups, function(a, b)
		if (a.continent == home) ~= (b.continent == home) then
			return a.continent == home
		end
		if a.reach ~= b.reach then
			return a.reach < b.reach
		end
		return tostring(a.continent) < tostring(b.continent)
	end)
	local steps, from = {}, origin
	local function At(step)
		return where[step]
	end
	-- The planned mode finishes a town before leaving it (Group); the nearest mode takes the nearest stop alone.
	local function Group(step)
		return planned and step.hub ~= nil and tostring(step.hub) or nil
	end
	for _, group in ipairs(groups) do
		for _, part in ipairs({ group.main, group.last }) do
			for _, step in ipairs(NearestStop(from, part, At, Group)) do
				steps[#steps + 1] = step
				from = where[step]
			end
		end
	end
	return steps
end

-- Chooses up to MAX_STEPS of `candidates` and orders them from the player (docs/design.md §4.1). `lead`, the story
-- card's chapter, is chosen first, then ordered by cost like the rest. `join` adds to the chosen steps (hand-ins to
-- their towns) before they are described and ordered, so it never adds a step. `log` titles the hand-ins.
---@param join? fun(selected: AGFStep[])
local function Build(data, player, completed, log, candidates, prefs, mapName, lead, join)
	local pool, where, docks = {}, {}, Docks(data, player.side)
	for _, step in ipairs(candidates) do
		if not prefs.skipped[step.key] then
			pool[#pool + 1] = step
			where[step] = Position(data, step, docks)
		elseif State.skippedSeen then
			State.skippedSeen[step.key] = true
		end
	end
	local origin = Position(data, player, docks)

	-- Selection grows from the player: each pick is the step cheapest to reach from the player or any step already
	-- picked, so the route is the nearest pickup, objective area or turn-in at every step (docs/design.md §4.1).
	-- Without a known place for the player (no position in an instance, a map the data lacks) most steps cost UNKNOWN
	-- from them. A turn-in among those leads, and the route grows from it instead of
	-- dropping it for whichever key sorts first.
	local measured = origin ~= nil and origin.known
	local reach, chosen, selected = {}, {}, {}
	-- A trainer's stop opens only once a stop in its town is chosen, its hub, and one at most: the route stops to
	-- train only where it passes anyway.
	local near, trained = {}, false
	local function Open(step)
		return step.kind ~= "trainer" or (near[step] and not trained)
	end
	for _, step in ipairs(pool) do
		local cost = Cost(origin, where[step])
		reach[step] = (not measured and cost >= UNKNOWN and HandInOnly(step)) and 0 or cost
	end
	local function Take(step)
		chosen[step] = true
		selected[#selected + 1] = step
		trained = trained or step.kind == "trainer"
		for _, other in ipairs(pool) do
			if not chosen[other] then
				local cost = Cost(where[step], where[other])
				reach[other] = math.min(reach[other], cost)
				near[other] = near[other]
					or (
						other.kind == "trainer"
						and step.kind ~= "trainer"
						and step.hub ~= nil
						and step.hub == other.hub
					)
			end
		end
	end
	-- The planned mode chooses the story card's chapter first; the nearest mode picks purely by distance.
	if prefs.optimisedRoute == true and lead and where[lead] then
		Take(lead)
	end
	-- Each pick is the nearest step to the player or to any step already picked; Order then keeps the continents.
	while #selected < Model.MAX_STEPS do
		local best, bestKey
		for _, step in ipairs(pool) do
			local key = reach[step]
			if
				not chosen[step]
				and Open(step)
				and (not best or key < bestKey or (key == bestKey and step.key < best.key))
			then
				best, bestKey = step, key
			end
		end
		if not best then
			break
		end
		Take(best)
	end
	if join then
		join(selected)
	end
	for _, step in ipairs(selected) do
		if step.kind == "town" then
			Describe(data, log, player, step)
			Opens(data, player, completed, log, step)
		elseif step.kind == "trainer" then
			Describe(data, log, player, step)
		end
	end

	-- A turn-in across an ocean waits for the rest of that continent's steps, and says where it is.
	local away = {}
	for _, step in ipairs(selected) do
		local position = where[step]
		if
			HandInOnly(step)
			and origin
			and origin.known
			and position.known
			and position.continent ~= origin.continent
		then
			away[step] = true
			local name = (mapName and mapName(step.map)) or data.maps[step.map].name
			if name then
				step.reason = ns.L.HAND_IN_WHEN:format(name)
				step.detail = step.reason
			end
		end
	end
	-- The order starts from the player when some step is measurable from them, from the first pick otherwise.
	local start = selected[1] and where[selected[1]]
	for _, step in ipairs(selected) do
		if Cost(origin, where[step]) < UNKNOWN then
			start = origin
			break
		end
	end
	-- Each town's point is the place of its quest nearest the stop before it (the player, for the first): a real
	-- giver, never a centre, so Shortest Path takes the player to the nearest door of the town.
	local steps, from = Order(selected, start, where, away, prefs.optimisedRoute == true), start
	for _, step in ipairs(steps) do
		if step.spots then
			TownPoint(data, step, from)
		elseif step.objectives then
			Enter(data, step, from)
		end
		Locate(data, step, mapName)
		from = Position(data, step, docks)
	end
	return steps
end

local SETTLE_SHARE = 0.15 -- a fresh order replaces the committed one only when it saves this share of the rest...
local SETTLE_YARDS = 200 -- ...and this many yards

-- Each step's identity in a card's committed order: its key, "<<" on a lap's visit back to hand in what it did, "<"
-- on another town visited only to hand in (the hand-ins split from a later lap's town), and "#n" on the nth step with
-- the same (Idents).
---@param step AGFStep|AGFAnchor
local function Ident(step)
	local only = step.pickups and #step.pickups == 0
	return step.key .. (only and (step.returns and "<<" or "<") or "")
end

---@param route AGFStep[]
---@return string[]
local function Idents(route)
	local idents, seen = {}, {}
	for index, step in ipairs(route) do
		local ident = Ident(step)
		seen[ident] = (seen[ident] or 0) + 1
		idents[index] = seen[ident] > 1 and ("%s#%d"):format(ident, seen[ident]) or ident
	end
	return idents
end

-- Each step's place in the committed order, by index, or nil for a new one: its identity's, and a town that hands in
-- and hands out at once takes the place of its committed hand-in-only visit when no step holds that, as the visit
-- split from its pickups by the last build is one again.
---@param route AGFStep[]
---@param rank table<string, integer>
---@return table<integer, number>
local function Ranks(route, rank)
	local idents, ranks, claimed = Idents(route), {}, {}
	for index, ident in ipairs(idents) do
		ranks[index], claimed[ident] = rank[ident], true
	end
	for index, step in ipairs(route) do
		-- A newly split hand-in stays before the combined visit's pickups, which need the freed log slots.
		if step.kind == "town" and not step.returns and #step.pickups == 0 and not ranks[index] and rank[step.key] then
			ranks[index] = rank[step.key] - 0.5
		end
		local back = step.kind == "town" and #step.handins > 0 and idents[index] == step.key and step.key .. "<"
		if back and rank[back] and not claimed[back] and rank[back] < (ranks[index] or math.huge) then
			ranks[index], claimed[back] = rank[back], true
		end
	end
	return ranks
end

-- The yards along `route` from `from`, else from its first stop.
---@param route AGFStep[]
---@param at fun(step: AGFStep): AGFPosition?
local function Length(route, from, at)
	local total, a, ra = 0, from, 0
	for index, step in ipairs(route) do
		local p, r = at(step), step.r or 0
		total = total + ((from or index > 1) and Gap(a, ra, p, r) or 0)
		a, ra = p, r
	end
	return total
end

-- The steps the committed order holds back in that order, and the new ones after them, before the route is checked
-- in order: so the log's limit leaves the committed pickups as they were. Stabilise then puts the new ones in place.
---@param route AGFStep[]
---@param rank table<string, integer>
---@return AGFStep[]
local function Recommit(route, rank)
	local held, fresh, at, ranks = {}, {}, {}, Ranks(route, rank)
	for index, step in ipairs(route) do
		at[step] = ranks[index]
		table.insert(ranks[index] and held or fresh, step)
	end
	table.sort(held, function(a, b)
		return at[a] < at[b]
	end)
	for _, step in ipairs(fresh) do
		held[#held + 1] = step
	end
	return held
end

-- The route in the card's committed order (docs/design.md §4.3), so a rebuild never shuffles what the player follows:
-- the steps the order holds keep their places, each new one goes where it adds the fewest yards after the head, and
-- the fresh order (`plain`, after the same head) replaces it only when that saves SETTLE_SHARE of the rest and
-- SETTLE_YARDS. A route that shares no step with the order (its lap ended), or whose steps the order cannot hold, is
-- the fresh one, else `route` as Recommit left it.
---@param route AGFStep[] the steps, the committed ones first in their order (Recommit)
---@param plain AGFStep[] the same steps in the fresh order
---@param rank table<string, integer> each identity's place in the committed order
---@param holds fun(steps: AGFStep[]): boolean
---@param at fun(step: AGFStep): AGFPosition?
---@return AGFStep[]
local function Stabilise(route, plain, rank, holds, at, origin)
	local fallback = holds(plain) and plain or route
	local ranks, kept, fresh, place = Ranks(route, rank), {}, {}, {}
	for index, step in ipairs(route) do
		place[step] = ranks[index]
		table.insert(place[step] and kept or fresh, step)
	end
	if #kept == 0 then
		return fallback
	end
	table.sort(kept, function(a, b)
		return place[a] < place[b]
	end)
	for _, step in ipairs(fresh) do
		local best, bestAdded
		local p, r = at(step), step.r or 0
		for k = 2, #kept + 1 do
			local prev, nextStop = kept[k - 1], kept[k]
			local added = Gap(at(prev), prev.r or 0, p, r)
			if nextStop then
				local q, rn = at(nextStop), nextStop.r or 0
				added = added + Gap(p, r, q, rn) - Gap(at(prev), prev.r or 0, q, rn)
			end
			if not bestAdded or added < bestAdded - 1e-6 then
				table.insert(kept, k, step)
				if holds(kept) then
					best, bestAdded = k, added
				end
				table.remove(kept, k)
			end
		end
		if not best then
			return fallback
		end
		table.insert(kept, best, step)
	end
	if not holds(kept) then
		return fallback
	end
	local head, alt = kept[1], { kept[1] }
	for _, step in ipairs(plain) do
		alt[#alt + 1] = step ~= head and step or nil
	end
	alt = holds(alt) and alt or fallback
	local from = alt[1] ~= head and origin or nil
	local was, now = Length(kept, from, at), Length(alt, from, at)
	return was - now >= math.max(SETTLE_SHARE * was, SETTLE_YARDS) and alt or kept
end

-- Whether `where` stands in area `step`, `margin` yards past its edge: within one of its shapes, the data's objective
-- circles, never the ring merged round them, which covers ground no objective is on.
---@param where {map: integer, x: number, y: number}
---@param step AGFStep
---@param margin number
---@return boolean
local function InArea(data, where, step, margin)
	for _, shape in ipairs(step.shapes) do
		local yards = Model.Yards(data, where, shape)
		if yards and yards <= shape.r + margin then
			return true
		end
	end
	return false
end

-- Whether an area is open: it holds at least one objective the player can work on. A merged area stays open while
-- any objective is not the pickup the route still has to make (`step.planned`), so an in-progress quest does not lose
-- its area to a nearby quest the same step would hand out.
---@param step AGFStep
---@return boolean
local function Workable(step)
	if not step.planned then
		return true
	end
	for _, objective in ipairs(step.objectives or NONE) do
		if not step.planned[objective.id] then
			return true
		end
	end
	return false
end

-- The open area the player stands in (docs/design.md §4.2): the head when it is one, else the first on the route.
-- An area is open while it holds an objective the player can work on; a merged-step pickup the route has yet to make
-- does not close it (Workable). While the head is an open area it is the only area that can lead, so walking into a
-- later area does not advance the route past objectives the player has not finished (a step advances only when its
-- state is satisfied). Inside is within one of its shapes (InArea); the area they stood in (`held`, its key) lets go
-- only past HERE_MARGIN more, so its edge never flickers. Nil when they stand in none.
local HERE_MARGIN = 30
---@param where? {map?: integer, x?: number, y?: number}
---@param steps AGFStep[]
---@param held? string
---@return integer?
function Model.Here(data, where, steps, held)
	if not ValidPlace(where) then
		return nil
	end
	---@cast where {map: integer, x: number, y: number}
	local head = steps[1]
	if head and head.kind == "area" and Workable(head) then
		return InArea(data, where, head, head.key == held and HERE_MARGIN or 0) and 1 or nil
	end
	for index, step in ipairs(steps) do
		if
			step.kind == "area"
			and Workable(step)
			and InArea(data, where, step, step.key == held and HERE_MARGIN or 0)
		then
			return index
		end
	end
	return nil
end

ns.Planner.Routing = {
	Build = Build,
	Ident = Ident,
	Idents = Idents,
	Recommit = Recommit,
	Stabilise = Stabilise,
}
