---@type string, AGFNamespace
local _, ns = ...
---@class AGFModel
-- Nine: the stock numerals (services-number-1..9) that label each step stop at 9.
local Model = { MAX_STEPS = 9 }
ns.Model = Model

-- CMaNGOS mangos-classic/src/game/Tools/Formulas.h, GetQuestGreenRange (quest, not creature XP).
local GREEN_RANGE = { 4, 4, 5, 5, 6, 6, 7, 7, 8, 9, 10, 11, 12 }
local CLOSE = 0.03 * 0.03

function Model.IsGray(questLevel, playerLevel)
	local range = GREEN_RANGE[math.min(#GREEN_RANGE, math.floor(playerLevel / 5) + 1)] or 4
	return questLevel > 0 and playerLevel - questLevel > range
end

local function ValidPlace(place)
	return place
		and type(place.map) == "number"
		and place.map > 0
		and type(place.x) == "number"
		and place.x >= 0
		and place.x <= 1
		and type(place.y) == "number"
		and place.y >= 0
		and place.y <= 1
end

local function HasBit(mask, bit)
	return not mask or mask == 0 or (bit > 0 and math.floor(mask / bit) % 2 == 1)
end

local function Distance(a, b)
	if not ValidPlace(a) or a.map ~= b.map then
		return 1000000
	end
	return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2
end

-- Only immutable bundled data is memoized; player/log/completion tables may change in place.
-- Static hub anchors keep pin/skip identities when one of a hub's quests is accepted or completed.
---@class AGFIndex
---@field ids integer[]
---@field groups table<integer, integer[]>
---@field hubs table<integer, string>
---@type table<AGFData, AGFIndex>
local indexes = setmetatable({}, { __mode = "k" })

local function Index(data)
	local index = indexes[data]
	if index then
		return index
	end
	index = { ids = {}, groups = {}, hubs = {} }
	for id in pairs(data.quests) do
		index.ids[#index.ids + 1] = id
	end
	table.sort(index.ids)
	local anchors = {}
	for _, id in ipairs(index.ids) do
		local quest = data.quests[id]
		if quest.group and quest.group > 0 then
			local group = index.groups[quest.group] or {}
			index.groups[quest.group] = group
			group[#group + 1] = id
		end
		local place = quest.start
		if ValidPlace(place) then
			local anchor
			for _, candidate in ipairs(anchors[place.map] or {}) do
				if Distance(place, candidate) <= CLOSE then
					anchor = candidate
					break
				end
			end
			if not anchor then
				anchor = place
				anchors[place.map] = anchors[place.map] or {}
				table.insert(anchors[place.map], anchor)
			end
			index.hubs[id] = string.format("%d:%.4f:%.4f", anchor.map, anchor.x, anchor.y)
		end
	end
	indexes[data] = index
	return index
end

local function Eligible(data, player, completed, log, id, groups)
	local quest = data.quests[id]
	if not quest or completed[id] or log[id] or quest.repeatable or not ValidPlace(quest.start) then
		return false
	end
	if
		(quest.side ~= 3 and quest.side ~= player.side)
		or player.level < quest.min
		or not HasBit(quest.races, player.raceBit)
		or not HasBit(quest.classes, player.classBit)
	then
		return false
	end
	for _, pre in ipairs(quest.pre or {}) do
		if pre <= 0 or not completed[pre] then
			return false
		end
	end
	if quest.preAny then
		local found = false
		for _, pre in ipairs(quest.preAny) do
			if pre > 0 and completed[pre] then
				found = true
				break
			end
		end
		if not found then
			return false
		end
	end
	for _, other in ipairs((quest.group and groups[quest.group]) or {}) do
		if completed[other] or log[other] then
			return false
		end
	end
	return true
end

function Model.Eligible(data, player, completed, log, questID)
	return Eligible(data, player, completed, log, questID, Index(data).groups)
end

local function Choices(data, player, completed, log, index, prefs)
	local choices, scores, eligible = {}, {}, {}
	for _, id in ipairs(index.ids) do
		local quest = data.quests[id]
		local group = quest.elite or quest.dungeon
		if
			Eligible(data, player, completed, log, id, index.groups)
			and not Model.IsGray(quest.level, player.level)
			and (not prefs or (group and prefs.dungeons) or (not group and prefs.quests))
		then
			eligible[#eligible + 1] = id
			local map = quest.zone or quest.start.map
			local zone = data.zones[map]
			if zone then
				if not choices[map] then
					choices[map] =
						{ map = map, name = zone.name, min = zone.min, max = zone.max, quests = 0, best = false }
					scores[map] = 0
				end
				choices[map].quests = choices[map].quests + 1
				local level = quest.level == -1 and player.level or quest.level
				-- Fit dominates; a bounded density bonus below favors enough quests for a short route.
				scores[map] = scores[map] + math.abs(level - player.level) + math.max(0, level - player.level - 2)
			end
		end
	end
	local zones = {}
	for map, choice in pairs(choices) do
		scores[map] = scores[map] / choice.quests
			+ math.max(0, choice.min - player.level, player.level - choice.max) * 2
			- math.min(choice.quests, 12) * 0.5
		zones[#zones + 1] = choice
	end
	table.sort(zones, function(a, b)
		if scores[a.map] ~= scores[b.map] then
			return scores[a.map] < scores[b.map]
		end
		if a.quests ~= b.quests then
			return a.quests > b.quests
		end
		return a.map < b.map
	end)
	while #zones > 3 do
		table.remove(zones)
	end
	if zones[1] then
		zones[1].best = true
	end
	return zones, eligible
end

function Model.Zones(data, player, completed, log)
	local zones = Choices(data, player, completed, log, Index(data))
	return zones
end

local function Optional(quest, level, player)
	return (quest and (quest.elite or quest.dungeon) and true)
		or level > player.level + 2
		or Model.IsGray(level, player.level)
end

local function Step(kind, key, title, place, id, optional, reason)
	return {
		kind = kind,
		key = key,
		title = title,
		detail = reason,
		reason = reason,
		quests = { id },
		map = place.map,
		x = place.x,
		y = place.y,
		place = place.name,
		optional = optional or nil,
	}
end

local function LogSteps(data, player, log, prefs)
	local ids, steps, objectives = {}, {}, {}
	for id in pairs(log) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for _, id in ipairs(ids) do
		local entry, quest = log[id], data.quests[id]
		local group = quest and (quest.elite or quest.dungeon)
		if (group and prefs.dungeons) or (not group and prefs.quests) then
			-- A live completion waypoint is a turn-in; an incomplete waypoint is never replaced with the starter.
			local place = ValidPlace(entry) and entry or (entry.complete and quest and quest.finish)
			if ValidPlace(place) then
				local optional = Optional(quest, entry.level, player)
				if entry.complete then
					steps[#steps + 1] = Step(
						"turnin",
						"turnin:" .. id,
						"Turn in: " .. entry.title,
						place,
						id,
						optional,
						"ready to hand in"
					)
				else
					local kind = group and "dungeon" or "objective"
					local existing
					for _, step in ipairs(objectives) do
						if step.kind == kind and Distance(step, place) <= CLOSE then
							existing = step
							break
						end
					end
					if existing then
						existing.quests[#existing.quests + 1] = id
						existing.optional = existing.optional or optional or nil
						existing.reason = #existing.quests .. " quests here"
						existing.detail = existing.reason
					else
						local step =
							Step(kind, "objective:" .. id, entry.title, place, id, optional, "quests in progress")
						objectives[#objectives + 1] = step
						steps[#steps + 1] = step
					end
				end
			end
		end
	end
	return steps
end

local function PickupSteps(data, player, eligible, zone, hubs, steps, prefs)
	local pickups, chosenGroups, pinned = {}, {}, {}
	for _, key in ipairs(prefs.pinned or {}) do
		pinned[key] = true
	end
	for _, id in ipairs(eligible) do
		local quest = data.quests[id]
		local kind = (quest.elite or quest.dungeon) and "dungeon" or "pickup"
		local key = kind .. ":" .. hubs[id]
		if
			((quest.zone or quest.start.map) == zone or pinned[key]) and not (quest.group and chosenGroups[quest.group])
		then
			if quest.group then
				chosenGroups[quest.group] = true
			end
			local step = pickups[key]
			local chain = quest.pre or quest.preAny
			if step then
				step.quests[#step.quests + 1] = id
				step.reason = #step.quests .. " quests here"
				step.detail = step.reason
				step.optional = step.optional or Optional(quest, quest.level, player) or nil
			else
				local place = quest.start
				step = Step(
					kind,
					key,
					"Pick up quests: " .. place.name,
					place,
					id,
					Optional(quest, quest.level, player),
					chain and "continues chain" or "near your level"
				)
				pickups[key] = step
				steps[#steps + 1] = step
			end
		end
	end
end

local function Cost(from, step, travel)
	if ValidPlace(from) and travel then
		local seconds = travel(from.map, from.x, from.y, step.map, step.x, step.y)
		if type(seconds) == "number" and seconds >= 0 and seconds < math.huge then
			return seconds, seconds
		end
	end
	-- A ranking estimate, never presented as measured seconds or included in the route's minutes.
	return math.sqrt(Distance(from, step)) * 1000, nil
end

local function Phase(step)
	if step.kind == "turnin" then
		return 1
	end
	return step.key:match("^objective:") and 3 or 2
end

function Model.Plan(data, player, completed, log, prefs, travel)
	local index = Index(data)
	local zones, eligible = Choices(data, player, completed, log, index, prefs)
	local zone = prefs.zone or (zones[1] and zones[1].map)
	local candidates = LogSteps(data, player, log, prefs)
	PickupSteps(data, player, eligible, zone, index.hubs, candidates, prefs)
	local byKey, selected, steps = {}, {}, {}
	for _, step in ipairs(candidates) do
		if not (prefs.skipped and prefs.skipped[step.key]) then
			byKey[step.key] = step
		end
	end
	local from, total, known = player, 0, true
	local function Append(step, seconds, pinned)
		step.seconds, step.pinned = seconds, pinned or nil
		if seconds then
			total = total + seconds
			step.detail = step.detail .. " · " .. math.max(1, math.ceil(seconds / 60)) .. " min travel"
		else
			known = false
		end
		selected[step.key] = true
		steps[#steps + 1] = step
		from = step
	end
	for _, key in ipairs(prefs.pinned or {}) do
		local step = byKey[key]
		if step and not selected[key] and #steps < Model.MAX_STEPS then
			local _, seconds = Cost(from, step, travel)
			Append(step, seconds, true)
		end
	end
	while #steps < Model.MAX_STEPS do
		local best, bestCost, bestSeconds, phase
		for _, step in ipairs(candidates) do
			local candidatePhase = Phase(step)
			if byKey[step.key] and not selected[step.key] and (not phase or candidatePhase <= phase) then
				local cost, seconds = Cost(from, step, travel)
				if
					not best
					or candidatePhase < phase
					or cost < bestCost
					or (cost == bestCost and step.key < best.key)
				then
					best, bestCost, bestSeconds, phase = step, cost, seconds, candidatePhase
				end
			end
		end
		if not best then
			break
		end
		Append(best, bestSeconds)
	end
	return { steps = steps, zones = zones, zone = zone, minutes = known and #steps > 0 and math.ceil(total / 60) or nil }
end
