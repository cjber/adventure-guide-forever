---@type string, AGFNamespace
local _, ns = ...
---@class AGFSession
local Session = {}
ns.Session = Session
local info = { minutes = 0, pending = false, empty = false, trimmed = false }
local job

function Session.Get()
	local minutes = ns.Prefs().sessionMinutes
	return (minutes == 15 or minutes == 30 or minutes == 60) and minutes or 0
end

function Session.Set(minutes)
	if minutes ~= 0 and minutes ~= 15 and minutes ~= 30 and minutes ~= 60 then
		return
	end
	if Session.Get() == minutes then
		return
	end
	ns.Prefs().sessionMinutes, ns.Prefs().sessionCommit, job = minutes, nil, nil
	ns.Invalidate()
end

function Session.Info()
	return {
		minutes = info.minutes,
		seconds = info.seconds,
		pending = info.pending,
		empty = info.empty,
		trimmed = info.trimmed,
	}
end

function Session.Work(step)
	if step.kind == "dungeon" or step.kind == "battlemaster" then
		return nil
	end
	if not step.objectives then
		return 10 * math.max(1, #(step.checklist or {}))
	end
	local seconds = 0
	for _, objective in ipairs(step.objectives) do
		if objective.slot == 16 or not objective.need then
			return nil
		end
		seconds = seconds + math.max(0, objective.need - (objective.have or 0)) * 4
	end
	return seconds
end

-- Only prefixes which keep a newly accepted quest's complete planned work and return qualify.
function Session.Prefix(steps, seconds, budget)
	local endpoint, total, estimate = 0, 0, 0
	local work, handin = {}, {}
	for index, step in ipairs(steps) do
		for _, objective in ipairs(step.objectives or {}) do
			work[objective.id] = index
		end
		for _, id in ipairs(step.handins or (step.kind == "turnin" and step.quests) or {}) do
			handin[id] = index
		end
	end
	local need, unsupported = 0, false
	for index, step in ipairs(steps) do
		if not seconds[index] then
			break
		end
		total = total + seconds[index]
		if total > budget then
			break
		end
		for _, id in ipairs(step.pickups or {}) do
			if not work[id] or not handin[id] then
				unsupported = true
			end
			need = math.max(need, work[id] or #steps + 1, handin[id] or #steps + 1)
		end
		if not unsupported and index >= need then
			endpoint, estimate = index, total
		end
	end
	return endpoint, estimate
end

local function Signature(route)
	local map, x, y = ns.State.Where()
	local keys = { route.journey or "", string.format("%s:%.4f:%.4f", tostring(map), x or 0, y or 0) }
	for _, step in ipairs(route.steps) do
		keys[#keys + 1] =
			string.format("%s:%d:%.5f:%.5f:%s", step.key, step.map, step.x, step.y, tostring(Session.Work(step)))
	end
	return table.concat(keys, "|")
end

local function Commit(pending)
	local endpoint, seconds = Session.Prefix(pending.steps, pending.seconds, pending.minutes * 60)
	local keys, members = {}, {}
	for index = 1, endpoint do
		local step = pending.steps[index]
		local key = step.orderKey or step.key
		keys[key], members[key] = true, {}
		for _, id in ipairs(step.quests) do
			members[key][tostring(id)] = true
		end
		for _, objective in ipairs(step.objectives or {}) do
			members[key][objective.id .. ":" .. objective.slot] = true
		end
	end
	ns.Prefs().sessionCommit = {
		journey = pending.journey,
		minutes = pending.minutes,
		keys = keys,
		members = members,
		seconds = endpoint > 0 and seconds or nil,
	}
	job = nil
end

function Session.PendingWork()
	return job ~= nil
end

-- Called only by Integrations' shared, one-call-per-frame estimate queue.
function Session.NextEstimate(api)
	if not job then
		return false
	end
	local pending, index = job, job.index
	local step = pending.steps[index]
	local from = index == 1 and pending.origin or pending.steps[index - 1]
	local work = Session.Work(step)
	local seconds, err
	if work and from.map and from.x and from.y then
		seconds, err = api.Estimate(from.map, from.x, from.y, step.map, step.x, step.y)
	end
	if err == "combat" then
		return false
	end
	pending.seconds[index] = seconds and seconds >= 0 and work and seconds + work or nil
	if not pending.seconds[index] or index == #pending.steps then
		Commit(pending)
		ns.Invalidate()
	else
		pending.index = index + 1
	end
	return true
end

function Session.Apply(route)
	local minutes, prefs = Session.Get(), ns.Prefs()
	info = { minutes = minutes, pending = false, empty = false, trimmed = false }
	if not route.chosen or minutes == 0 then
		job = nil
		return route
	end
	local commit = prefs.sessionCommit
	if not commit or commit.journey ~= route.journey or commit.minutes ~= minutes then
		local signature = Signature(route)
		if not job or job.signature ~= signature or job.minutes ~= minutes then
			job = {
				signature = signature,
				journey = route.journey,
				minutes = minutes,
				steps = route.steps,
				origin = ns.State.Player(),
				seconds = {},
				index = 1,
			}
		end
		if #route.steps == 0 then
			Commit(job)
		elseif not ns.Integrations.Provider() then
			for index, step in ipairs(job.steps) do
				local from = index == 1 and job.origin or job.steps[index - 1]
				-- Geometry alone only establishes a local outdoor leg.
				local yards = from.map == step.map and ns.Model.Yards(ns.Data, from, step)
				local work = Session.Work(step)
				job.seconds[index] = yards and work and yards / 7 + work or nil
			end
			Commit(job)
		else
			info.pending = true
		end
		commit = prefs.sessionCommit
	end
	local steps, retained = {}, {}
	if commit and commit.journey == route.journey and commit.minutes == minutes then
		local edges = ns.Order.Dependencies(route.steps)
		for index, step in ipairs(route.steps) do
			local key = step.orderKey or step.key
			local keep, members = commit.keys[key] == true, commit.members and commit.members[key]
			if members then
				for _, id in ipairs(step.quests) do
					keep = keep and members[tostring(id)] == true
				end
				for _, objective in ipairs(step.objectives or {}) do
					keep = keep and members[objective.id .. ":" .. objective.slot] == true
				end
			end
			for parent in pairs(edges[index]) do
				keep = keep and retained[parent] == true
			end
			retained[index] = keep
		end
		-- A newly unavailable return invalidates its pickup town and everything that depends on it.
		for _ = 1, #route.steps do
			for index, step in ipairs(route.steps) do
				for parent in pairs(edges[index]) do
					if not retained[parent] then
						retained[index] = false
					end
					if not retained[index] and #(route.steps[parent].pickups or {}) > 0 then
						retained[parent] = false
					end
				end
				if retained[index] and step.pickups and #step.pickups > 0 then
					for later, parents in ipairs(edges) do
						if parents[index] and not retained[later] then
							retained[index] = false
						end
					end
				end
			end
		end
		for index, step in ipairs(route.steps) do
			if retained[index] then
				steps[#steps + 1] = step
			end
		end
	end
	info.seconds = commit and commit.journey == route.journey and commit.seconds or nil
	info.empty, info.trimmed = not info.pending and #steps == 0, #steps < #route.steps
	local result = {}
	for key, value in pairs(route) do
		result[key] = value
	end
	result.steps, result.journeys = steps, {}
	for index, card in ipairs(route.journeys) do
		if card.key == route.journey then
			local copy = {}
			for key, value in pairs(card) do
				copy[key] = value
			end
			copy.steps = steps
			result.journeys[index] = copy
		else
			result.journeys[index] = card
		end
	end
	return result --[[@as AGFRoute]]
end
