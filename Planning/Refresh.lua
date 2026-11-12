---@type string, AGFNamespace
local _, ns = ...

if ns.broken then
	return
end
local Model = ns.Model
local NONE = {}
local Added = ns.Planner.Journeys.Added
local Carry = ns.Planner.Journeys.Carry
local Describe = ns.Planner.Steps.Describe
local Eligible = ns.Planner.Eligibility.Eligible
local FinishRoute = ns.Planner.Decoration.FinishRoute
local InZone = ns.Planner.Zones.InZone
local Index = ns.Planner.Eligibility.Index
local Locate = ns.Planner.Steps.Locate
local Opens = ns.Planner.Steps.Opens
local ReadDropped = ns.Planner.Eligibility.ReadDropped
local Ready = ns.Planner.Steps.Ready
local Route = ns.Planner.Plan.Route
local Summarise = ns.Planner.Journeys.Summarise
local Tell = ns.Planner.Steps.Tell
local LeadUrgent = ns.Planner.Laps.LeadUrgent
local Urgent = ns.Planner.Laps.Urgent

local function Copy(source)
	local copy = {}
	for key, value in pairs(source) do
		copy[key] = value
	end
	return copy
end

-- Laps clears the "here" hold when a hurry displaces the area the player stands in; the combat reorder must too.
-- Carry steps are fresh (clear in place); retained steps belong to the last route, so they get a copy instead.
---@param steps AGFStep[]
---@param was AGFStep? the head before the reorder
---@param copy boolean retained steps are shared with the last route
---@return AGFStep[]
local function ClearHere(steps, was, copy)
	local head = steps[1]
	if not was or was == head or not was.here then
		return steps
	end
	if not copy then
		was.here = nil
		return steps
	end
	local moved = Copy(was) --[[@as AGFStep]]
	moved.here = nil
	for index, step in ipairs(steps) do
		if step == was then
			steps[index] = moved
		end
	end
	return steps
end

-- The step with its urgency line read again from the live log (AGF709), so a cheap in-combat refresh neither keeps a
-- stale hurry for a quest that failed, expired or was handed in, nor loses an active timer the carry journey picked
-- up. A copy is returned only when the answer moved; an unchanged step stays the same table.
---@param log table<integer, AGFLogQuest>
---@param step AGFStep
---@return AGFStep
local function Urgency(log, step)
	local entry = Urgent(log, step)
	local reason
	if entry then
		reason = entry.deadline and ns.L.BEFORE_TIMER_RUNS_OUT
			or (entry.expiringName and ns.L.BEFORE_IT_RUNS_OUT:format(entry.expiringName))
			or ns.L.BEFORE_ITEM_RUNS_OUT
	end
	local wanted = entry ~= nil
	if (step.hurry == true) == wanted and (not wanted or step.reason == reason) then
		return step
	end
	local copy = Copy(step) --[[@as AGFStep]]
	if wanted then
		-- Keep the step's own story/chapter reason under the urgency line, so ending the timer restores it.
		copy.hurryKept = copy.hurryKept or { reason = step.reason, detail = step.detail }
		copy.hurry = true
		copy.reason, copy.detail = reason, reason
	else
		copy.hurry = nil
		copy.reason = copy.hurryKept and copy.hurryKept.reason or nil
		copy.detail = copy.hurryKept and copy.hurryKept.detail or nil
		copy.hurryKept = nil
	end
	return copy
end

-- The last route with only its objective counts read again (docs/design.md §4.4): every journey, step, order, `here`
-- hold and choice as the last build left them; an area step's objectives take the log's live counts and words. Only
-- for a burst that moved counts alone (Model.LogShape unchanged), so no objective finishes and no quest comes or goes.
---@param last AGFRoute
---@return AGFRoute
function Model.Repaint(data, log, last)
	local painted = {}
	local function Paint(step)
		if not step.objectives then
			return step
		end
		local copy = painted[step]
		if not copy then
			copy = Copy(step) --[[@as AGFStep]]
			copy.objectives = ns.Planner.Steps.LiveObjectives(data, log, step.objectives)
			Tell(copy)
			-- The title carries the counts too ("Freebooter slain: 5/6"), as the decoration writes it.
			Model.StepTitle(data, log, copy)
			painted[step] = copy
		end
		return copy
	end
	local function PaintAll(steps)
		local out = {}
		for index, step in ipairs(steps) do
			out[index] = Paint(step)
		end
		return out
	end
	local route = Copy(last) --[[@as AGFRoute]]
	route.journeys = {}
	for index, journey in ipairs(last.journeys) do
		local copy = Copy(journey) --[[@as AGFJourney]]
		copy.steps = PaintAll(journey.steps)
		route.journeys[index] = copy
		if journey.steps == last.steps then
			route.steps = copy.steps
		end
	end
	if route.steps == last.steps then
		route.steps = PaintAll(last.steps)
	end
	return route
end

-- A journey from the last full build less what went since: a quest the player has taken, done or ruled out (a group
-- choice), or handed in, leaves its town, which goes only once it is empty or skipped; the full build after combat
-- brings back anything else. The same table when nothing went.
---@param prune fun(step: AGFStep): AGFStep? the step, a copy less the quests gone, or nil when none is left
---@param log table<integer, AGFLogQuest>
---@param cap? integer the quests the log may hold
---@return AGFJourney?
local function Retained(journey, prune, log, cap)
	local steps, changed, chapterGone = {}, false, false
	local chapterID = journey.story and journey.story.members[journey.story.chapter]
	for _, step in ipairs(journey.steps) do
		local kept = prune(step)
		changed = changed or kept ~= step
		local chapterKept = false
		for _, id in ipairs(kept and kept.quests or NONE) do
			chapterKept = chapterKept or id == chapterID
		end
		if step.chapter and not chapterKept then
			chapterGone = true
			if kept then
				kept.chapter = nil -- a copy: its chapter's quest went
			end
		elseif kept and kept ~= step and step.chapter then
			-- The chapter stays: its town keeps the story's reason, as the full build gives it. A hurry line is not that
			-- reason, so the kept copy restores what the urgency line replaced.
			local own = step.hurryKept and step.hurryKept.reason or step.reason
			kept.reason, kept.detail = own, #kept.quests == 1 and own or kept.detail
		end
		if kept then
			local urgent = Urgency(log, kept)
			changed = changed or urgent ~= kept
			kept = urgent
		end
		steps[#steps + 1] = kept
	end
	-- A story step whose quest timer is active leads within its journey too, not only the carry one; the cheap order
	-- check keeps its pickups and hand-ins in place. A displaced "here" head is cleared like Laps does after Hurry.
	if #steps > 0 then
		local was = steps[1]
		local ordered = LeadUrgent(steps, log, function(route)
			return ns.Order.Valid(route, cap, log)
		end)
		ordered = ClearHere(ordered, was, true)
		changed = changed or ordered ~= steps
		steps = ordered
	end
	if not changed or #steps == 0 then
		return #steps > 0 and journey or nil
	end
	local copy = Copy(journey)
	copy.steps, copy.map = steps, steps[1].map
	-- A chapter that went takes the card's chain with it, as the full build does.
	if chapterGone then
		copy.story, copy.reason, copy.subline = nil, nil, journey.count
	end
	Summarise(copy --[[@as AGFJourney]])
	return copy --[[@as AGFJourney]]
end

-- The in-combat rebuild (Core.lua): the carry journey fresh from the live log, which is what changes in a fight, after
-- the story as the full build orders them, and every other journey as the last full build left it, less any step
-- skipped or no longer open since. Only the retained steps' quests are checked again: no eligibility pass over the
-- data, so it stays cheap; the full build runs once combat ends.
---@param last AGFRoute
---@param inputs? AGFPlanInputs as Model.Plan's; `forget` waits for the full build
function Model.Refresh(data, player, completed, log, prefs, last, mapName, inputs)
	ReadDropped(prefs, inputs and inputs.skippedQuests)
	local skipped, groups = prefs.skipped, Index(data).groups
	local function Keep(ids, open)
		local kept = {}
		for _, id in ipairs(ids) do
			kept[#kept + 1] = open(id) and id or nil
		end
		return kept
	end
	local function Open(id)
		return Eligible(data, player, completed, log, id, groups)
	end
	local function Carried(id)
		return log[id] ~= nil and log[id].complete
	end
	local function Prune(step)
		if skipped[step.key] then
			return nil
		elseif step.kind == "trainer" or step.kind == "battlemaster" then
			return step -- nothing is learned, and no battleground opens, in a fight
		end
		if not step.pickups then
			-- Keep carried quests and a lap's still-open pickups. Objective work drops completed quests;
			-- hand-ins belong to town/return steps and have no objective rows.
			local function Carrying(id)
				if log[id] == nil then
					return step.planned ~= nil and step.planned[id] ~= nil and Open(id)
				end
				return not ((step.objectives or step.entrance) and log[id].complete)
			end
			local quests = Keep(step.quests, Carrying)
			if #quests == #step.quests and not step.objectives then
				return step
			elseif #quests == 0 then
				return nil
			end
			local copy = Copy(step) --[[@as AGFStep]]
			copy.quests = quests
			if step.entrance then
				copy.group = #quests
			end
			if step.objectives then
				local objectives, slotted = {}, {}
				for _, objective in ipairs(step.objectives) do
					slotted[objective.id] = true
					objectives[#objectives + 1] = Carrying(objective.id) and objective or nil
				end
				copy.objectives = ns.Planner.Steps.LiveObjectives(data, log, objectives)
				if #objectives > 0 then
					local remaining = {}
					for _, objective in ipairs(copy.objectives) do
						remaining[objective.id] = true
					end
					copy.quests = Keep(quests, function(id)
						return not slotted[id] or remaining[id] == true
					end)
					if #copy.quests == 0 then
						return nil
					end
				end
				Tell(copy)
			end
			-- The urgency line belonged to the pre-prune step; Urgency works from the fresh reason Tell just wrote.
			copy.hurry, copy.hurryKept = nil, nil
			return copy
		end
		-- A lap's return hands in what it picks up or carries once done: kept while carried, or while still open.
		local function Due(id)
			return Carried(id) or (step.returns ~= nil and step.returns[id] ~= nil and (log[id] ~= nil or Open(id)))
		end
		local pickups, handins = Keep(step.pickups, Open), Keep(step.handins, Due)
		if #pickups + #handins == #step.quests then
			return step
		elseif #pickups + #handins == 0 then
			return nil
		end
		local copy = Copy(step) --[[@as AGFStep]]
		copy.pickups, copy.handins = pickups, handins
		Describe(data, log, player, copy)
		Opens(data, player, completed, log, copy)
		-- A point whose giver has nothing left moves to the first quest's place.
		local here = false
		for _, id in ipairs(copy.quests) do
			local spot = copy.spots[id]
			here = here or (spot.map == copy.map and spot.x == copy.x and spot.y == copy.y)
		end
		if not here then
			local spot = copy.spots[copy.quests[1]]
			copy.map, copy.x, copy.y = spot.map, spot.x, spot.y
			copy.z = spot.z
			Locate(data, copy, mapName)
		end
		-- The urgency line belonged to the pre-prune step; Urgency works from the fresh reason Describe just wrote.
		copy.hurry, copy.hurryKept = nil, nil
		return copy
	end
	-- Accepted quests remain available as one choice during combat too.
	local journeys, dismissed, zone = {}, prefs.notInterested or {}, nil
	for _, journey in ipairs(last.journeys) do
		local kept = journey.kind ~= "carry"
				and not dismissed[journey.key]
				and Retained(journey, Prune, log, player.logMax)
			or nil
		if kept and kept.kind == "story" then
			zone = kept.zone
		end
		journeys[#journeys + 1] = kept
	end
	local story = InZone(zone)
	local added = Added(data, player, completed, log, prefs, function(quest)
		return not story(quest)
	end)
	local carry = Carry(data, player, completed, log, Ready(data, log), prefs, mapName, added)
	if carry then
		-- A timer that started (or a bag item picked up) leads in a fight too: the cheap order check is Order.Valid,
		-- and the urgency line is read again from the live log rather than copied from the last full build.
		local was = carry.steps[1]
		carry.steps = LeadUrgent(carry.steps, log, function(steps)
			return ns.Order.Valid(steps, player.logMax, log)
		end)
		carry.steps = ClearHere(carry.steps, was, false)
		for index, step in ipairs(carry.steps) do
			carry.steps[index] = Urgency(log, step)
		end
		table.insert(journeys, (journeys[1] and journeys[1].kind == "story") and 2 or 1, carry)
	end
	local route = Route(journeys, prefs)
	route.stranded, route.orders, route.lead = last.stranded, last.orders, last.lead
	route.left = last.left
	FinishRoute(data, player, completed, log, route, last, prefs)
	return route
end
