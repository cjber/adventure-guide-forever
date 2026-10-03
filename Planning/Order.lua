---@type string, AGFNamespace
local _, ns = ...
---@class AGFOrderModule
local Order = {}
ns.Order = Order
local skippedQuests = {}

-- Dependencies are between complete stops: a town can never be split to make a move fit.
function Order.Dependencies(steps)
	local pickups, work, hands, edges = {}, {}, {}, {}
	for index, step in ipairs(steps) do
		edges[index] = {}
		for _, id in ipairs(step.pickups or {}) do
			pickups[id] = index
		end
		for _, objective in ipairs(step.objectives or {}) do
			work[objective.id] = work[objective.id] or {}
			work[objective.id][index] = true
		end
		for _, id in ipairs(ns.Model.Handins(step)) do
			hands[id] = index
		end
	end
	local function Before(a, b)
		if a and b and a ~= b then
			edges[b][a] = true
		end
	end
	for id, indices in pairs(work) do
		for index in pairs(indices) do
			Before(pickups[id], index)
			Before(index, hands[id])
		end
	end
	for id, index in pairs(pickups) do
		Before(index, hands[id])
	end
	return edges
end

local function Occupied(log)
	local count = 0
	for _ in pairs(log or {}) do
		count = count + 1
	end
	return count
end

local function After(step, occupied)
	local hands = ns.Model.Handins(step)
	return occupied - #hands + #(step.pickups or {})
end

function Order.Valid(steps, cap, log)
	local occupied = Occupied(log)
	for index, parents in ipairs(Order.Dependencies(steps)) do
		occupied = After(steps[index], occupied)
		if cap and occupied > cap then
			return false
		end
		for parent in pairs(parents) do
			if parent > index then
				return false
			end
		end
	end
	return true
end

function Order.Merge(steps, keys, cap, log)
	if not keys or #keys == 0 then
		return steps
	end
	local priority, used, result = {}, {}, {}
	for index, key in ipairs(keys) do
		priority[key] = priority[key] or index
	end
	local edges, occupied = Order.Dependencies(steps), Occupied(log)
	for _ = 1, #steps do
		local best, rank
		for index, step in ipairs(steps) do
			if not used[index] then
				local ready = not cap or After(step, occupied) <= cap
				for parent in pairs(edges[index]) do
					ready = ready and used[parent] == true
				end
				local value = priority[ns.Model.Visit(step)] or (#keys + index)
				if ready and (not best or value < rank) then
					best, rank = index, value
				end
			end
		end
		-- A planner cycle cannot safely be repaired by rearranging unrelated work.
		if not best then
			return steps
		end
		used[best], result[#result + 1] = true, steps[best]
		occupied = After(steps[best], occupied)
	end
	return result
end

local function Moved(steps, from, to)
	if from == to or not steps[from] or not steps[to] then
		return nil
	end
	local result = {}
	for index, step in ipairs(steps) do
		result[index] = step
	end
	table.insert(result, to, table.remove(result, from))
	return result
end

function Order.CanMove(from, to)
	local route = ns.Route()
	if not route.chosen then
		return false
	end
	local moved = Moved(route.steps, from, to)
	local world = ns.Snapshot()
	return moved ~= nil and Order.Valid(moved, world.player.logMax, world.log)
end

local function Changed()
	ns.Invalidate()
	ns.Guidance.Reroute()
end

function Order.Move(from, to)
	if not Order.CanMove(from, to) then
		return false
	end
	local route, prefs = ns.Route(), ns.Prefs()
	local moved = assert(Moved(route.steps, from, to))
	local keys, present = {}, {}
	for _, step in ipairs(moved) do
		local visit = ns.Model.Visit(step)
		keys[#keys + 1], present[visit] = visit, true
	end
	for _, key in ipairs(prefs.customOrders and prefs.customOrders[route.journey] or {}) do
		if not present[key] then
			keys[#keys + 1] = key
		end
	end
	prefs.customOrders = prefs.customOrders or {}
	prefs.customOrders[route.journey] = keys
	Changed()
	return true
end

function Order.IsCustom()
	local route, prefs = ns.Route(), ns.Prefs()
	return route.chosen and prefs.customOrders ~= nil and prefs.customOrders[route.journey] ~= nil
end

function Order.Reset()
	local route, prefs = ns.Route(), ns.Prefs()
	if not route.chosen then
		return
	end
	if prefs.customOrders then
		prefs.customOrders[route.journey] = nil
	end
	ns.Shown.Forget(route.journey)
	Changed()
end

-- The quests of each giver still skipped, by skipped key: no build offers them (Shown.Build hands them to the planner).
function Order.SkippedQuests()
	local skipped = ns.Prefs().skipped
	for key in pairs(skippedQuests) do
		if not skipped[key] then
			skippedQuests[key] = nil
		end
	end
	return skippedQuests
end

function Order.SkipGiver(stepKey, giverKey)
	for _, step in ipairs(ns.Route().steps) do
		if step.key == stepKey then
			for _, giver in ipairs(step.checklist or {}) do
				if giver.key == giverKey and not giver.done then
					local key = ns.Model.GiverSkip(step, giverKey)
					local ids = {}
					for _, id in ipairs(giver.pickups) do
						ids[#ids + 1] = id
					end
					for _, id in ipairs(giver.handins) do
						ids[#ids + 1] = id
					end
					skippedQuests[key] = ids
					ns.Skip(key, giver.text)
					return true
				end
			end
		end
	end
	return false
end
