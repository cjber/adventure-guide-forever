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
				local value = priority[step.orderKey or step.key] or (#keys + index)
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

function Order.Apply(route, prefs)
	if not prefs.customOrders or not next(prefs.customOrders) then
		return
	end
	local player, log = ns.State.Player(), ns.State.Log()
	for _, card in ipairs(route.journeys) do
		local keys = prefs.customOrders and prefs.customOrders[card.key]
		if keys then
			card.steps = Order.Merge(card.steps, keys, player.logMax, log)
			local here = ns.Model.Here(ns.Data, player, card.steps)
			for index, step in ipairs(card.steps) do
				step.here = index == 1 and here == 1 or nil
			end
		end
		if route.journey == card.key then
			route.steps = card.steps
		end
	end
end

local function Moved(steps, from, to)
	if
		type(from) ~= "number"
		or type(to) ~= "number"
		or from % 1 ~= 0
		or to % 1 ~= 0
		or from == to
		or not steps[from]
		or not steps[to]
	then
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
	return moved ~= nil and Order.Valid(moved, ns.State.Player().logMax, ns.State.Log())
end

local function Changed()
	local guiding = ns.Prefs().guided == ns.Prefs().journey and ns.Integrations.Owns()
	ns.Invalidate()
	if guiding then
		C_Timer.After(0, function()
			ns.StartRoute()
		end)
	end
end

function Order.Move(from, to)
	if not Order.CanMove(from, to) then
		return false
	end
	local route, prefs = ns.Route(), ns.Prefs()
	local moved = assert(Moved(route.steps, from, to))
	local keys, present = {}, {}
	for _, step in ipairs(moved) do
		keys[#keys + 1], present[step.orderKey or step.key] = step.orderKey or step.key, true
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
	if route.orders then
		route.orders[route.journey] = nil
	end
	Changed()
end

function Order.SkippedQuests(seen)
	local quests, skipped = {}, ns.Prefs().skipped
	for key, ids in pairs(skippedQuests) do
		if skipped[key] then
			if seen then
				seen[key] = true
			end
			for _, id in ipairs(ids) do
				quests[id] = true
			end
		else
			skippedQuests[key] = nil
		end
	end
	return quests
end

function Order.IsGiverSkipped(stepKey, giverKey)
	return ns.Prefs().skipped["giver:" .. stepKey .. ":" .. giverKey] == true
end

function Order.SkipGiver(stepKey, giverKey)
	for _, step in ipairs(ns.Route().steps) do
		if step.key == stepKey then
			for _, giver in ipairs(step.checklist or {}) do
				if giver.key == giverKey and not giver.done then
					local visit = step.orderKey or stepKey
					local key = "giver:" .. visit .. ":" .. giverKey
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
