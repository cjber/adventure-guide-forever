---@type string, AGFNamespace
local _, ns = ...
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

local function Copy(source)
	local copy = {}
	for key, value in pairs(source) do
		copy[key] = value
	end
	return copy
end

-- A journey from the last full build less what went since: a quest the player has taken, done or ruled out (a group
-- choice), or handed in, leaves its town, which goes only once it is empty or skipped; the full build after combat
-- brings back anything else. The same table when nothing went.
---@param prune fun(step: AGFStep): AGFStep? the step, a copy less the quests gone, or nil when none is left
---@return AGFJourney?
local function Retained(journey, prune)
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
			-- The chapter stays: its town keeps the story's reason, as the full build gives it.
			kept.reason, kept.detail = step.reason, #kept.quests == 1 and step.reason or kept.detail
		end
		steps[#steps + 1] = kept
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
			-- A log step: its quests still carried, less an objective finished in the fight, which carry hands in, and
			-- a lap's quests not yet picked up while they are still open. Objectives ticked short of that wait for the
			-- full build.
			local function Carrying(id)
				if log[id] == nil then
					return step.planned ~= nil and step.planned[id] ~= nil and Open(id)
				end
				return not ((step.objectives or step.entrance) and log[id].complete)
			end
			local quests = Keep(step.quests, Carrying)
			if #quests == #step.quests then
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
				copy.objectives = {}
				for _, objective in ipairs(step.objectives) do
					copy.objectives[#copy.objectives + 1] = Carrying(objective.id) and objective or nil
				end
				Tell(copy)
			end
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
			Locate(data, copy, mapName)
		end
		return copy
	end
	-- Accepted quests remain available as one choice during combat too.
	local journeys, dismissed, zone = {}, prefs.notInterested or {}, nil
	for _, journey in ipairs(last.journeys) do
		local kept = journey.kind ~= "carry" and not dismissed[journey.key] and Retained(journey, Prune) or nil
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
		table.insert(journeys, (journeys[1] and journeys[1].kind == "story") and 2 or 1, carry)
	end
	local route = Route(journeys, prefs)
	route.stranded, route.orders, route.lead = last.stranded, last.orders, last.lead
	route.left = last.left
	FinishRoute(data, player, completed, log, route, last, prefs)
	return route
end
