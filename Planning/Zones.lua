---@type string, AGFNamespace
local _, ns = ...
local Model = ns.Model
local NONE = {}
local Cost = ns.Planner.Travel.Cost
local Docks = ns.Planner.Travel.Docks
local Dropped = ns.Planner.Eligibility.Dropped
local Eligible = ns.Planner.Eligibility.Eligible
local Hard = ns.Model.Hard
local HasBit = ns.Model.HasBit
local ORANGE = ns.Planner.Eligibility.ORANGE
local Position = ns.Planner.Travel.Position
local SimpleOpen = ns.Planner.Eligibility.SimpleOpen
local ValidPlace = ns.Model.ValidPlace
local Yards = ns.Planner.Travel.Yards

---@param quest AGFQuest
local function OutdoorElite(quest)
	return quest.elite and not quest.dungeon
end

-- A raid's quests belong to no zone card.
---@param quest AGFQuest
---@return integer|false|nil
local function QuestZone(quest)
	return not quest.raid and (quest.zone or (quest.start and quest.start.map))
end

---@return fun(quest: AGFQuest): boolean
local function InZone(zone)
	return function(quest)
		return QuestZone(quest) == zone
	end
end

-- A zone's level rank is the average of its quests' own (Model.LevelPreference), so content below the player's level
-- ranks ahead of content above it. The zone's last level is ranked the same way, which costs nothing while the player
-- is still inside the zone's range and more the further past it they are: a starting zone kept afloat by one
-- near-level quest does not outrank a zone that fits. More useful quests is better, and travel breaks ties.
local ZONE_QUEST, ZONE_QUESTS = 0.25, 8 -- this less a quest, for this many at most

-- The maps of the zones that fit `level` for the quests `ids`, best first. An
-- outdoor elite is optional: it rides along on its zone's cards but never picks the zone a solo player is
-- sent to. A raid's quest, which no card offers, never picks one either. `far` is a zone's distance cost from the
-- player (Journeys' Far).
---@param far fun(map: integer): number
---@return integer[] maps
local function Rank(data, ids, level, far)
	local choices, scores, quests = {}, {}, {}
	for _, id in ipairs(ids) do
		local quest = data.quests[id]
		local map = QuestZone(quest)
		local zone = map and data.zones[map]
		if
			map
			and zone
			and not Model.IsGray(quest.level, level)
			and quest.level - level < ORANGE
			and not OutdoorElite(quest)
		then
			if not quests[map] then
				choices[#choices + 1], quests[map], scores[map] = map, 0, 0
			end
			quests[map] = quests[map] + 1
			local questLevel = quest.level == -1 and level or quest.level
			scores[map] = scores[map] + Model.LevelPreference(questLevel, level)
		end
	end
	for _, map in ipairs(choices) do
		local zone = data.zones[map]
		scores[map] = scores[map] / quests[map]
			+ Model.LevelPreference(math.min(zone.max, level), level)
			- math.min(quests[map], ZONE_QUESTS) * ZONE_QUEST
			+ far(map)
	end
	table.sort(choices, function(a, b)
		if scores[a] ~= scores[b] then
			return scores[a] < scores[b]
		end
		if quests[a] ~= quests[b] then
			return quests[a] > quests[b]
		end
		return a < b
	end)
	return choices
end

-- Current-level choices include useful green/yellow quests and explicitly pinned grey quests.
-- Existing log quests also contribute to zone ranking; orange/red pickups never do.
---@param far fun(map: integer): number
local function Choices(data, player, completed, log, index, prefs, far)
	local eligible, ranked, pinned = {}, {}, prefs.pinned or {}
	for id in pairs(prefs.quests and log or NONE) do
		ranked[#ranked + 1] = data.quests[id] and not Dropped(id) and id or nil
	end
	table.sort(ranked)
	local sideCandidates = index.choicesByLevel[player.side]
	if not sideCandidates then
		sideCandidates = index.choicesByLevel[0]
		if not sideCandidates then
			sideCandidates = {}
			index.choicesByLevel[0] = sideCandidates
		end
	end
	-- Joined, not formatted as integers: the 32nd race's bit is past what the client's %d holds.
	local choiceKey = player.level .. ":" .. (player.raceBit or 0) .. ":" .. (player.classBit or 0)
	local candidates = sideCandidates[choiceKey]
	if not candidates then
		candidates = {}
		for _, id in ipairs(index.sides[player.side] or index.ids) do
			local quest = data.quests[id]
			if
				quest.min <= player.level
				and not Model.IsGray(quest.level, player.level)
				and ValidPlace(quest.start)
				and HasBit(quest.races, player.raceBit)
				and HasBit(quest.classes, player.classBit)
			then
				candidates[#candidates + 1] = id
			end
		end
		sideCandidates[choiceKey] = candidates
	end
	-- Pinned quests may intentionally be grey. They join the static shortlist only for this build.
	local candidateIDs, extras = candidates, nil
	for id in pairs(pinned) do
		local quest = data.quests[id]
		local sideOpen = index.sides[player.side] == nil or quest and (quest.side == 3 or quest.side == player.side)
		if sideOpen and quest and quest.min <= player.level and Model.IsGray(quest.level, player.level) then
			extras = extras or {}
			extras[#extras + 1] = id
		end
	end
	if extras then
		candidateIDs = {}
		for _, id in ipairs(candidates) do
			candidateIDs[#candidateIDs + 1] = id
		end
		for _, id in ipairs(extras) do
			candidateIDs[#candidateIDs + 1] = id
		end
		table.sort(candidateIDs)
	end
	for _, id in ipairs(candidateIDs) do
		local quest = data.quests[id]
		local instance = quest.dungeon ~= nil
		-- The completion first: Eligible would say no to most for it, at more cost.
		if
			not completed[id]
			and ((instance and prefs.dungeons) or (not instance and prefs.quests))
			and not Dropped(id)
			and (pinned[id] or not Model.IsGray(quest.level, player.level))
			and not Hard(quest, player)
			and (
				SimpleOpen(quest, player, completed, log, id)
				or Eligible(data, player, completed, log, id, index.groups)
			)
		then
			eligible[#eligible + 1] = id
			ranked[#ranked + 1] = id
		end
	end
	local zones = Rank(data, ranked, player.level, far)
	return zones, eligible
end

-- A rank point per ZONE_YARDS yards to a zone's middle on the player's own continent, at most ZONE_NEAR.
local ZONE_YARDS, ZONE_NEAR = 4000, 1.5

-- Each zone's middle, placed once (Far).
---@type table<AGFData, table<integer, AGFPosition|false>>
local middles = setmetatable({}, { __mode = "k" })

-- A zone's distance cost from the player for Rank: none when the data cannot place them both, so the ranking never
-- guesses. On their own continent it stops at ZONE_NEAR; across an ocean it is the whole way, through the docks
-- their side sails from (Cost), so a zone next door beats one overseas unless it fits clearly worse.
---@return fun(map: integer): number
local function Far(data, player)
	local here = Position(data, player, Docks(data, player.side))
	local kept = middles[data] or {}
	middles[data] = kept
	return function(map)
		kept[map] = kept[map] or Position(data, { map = map, x = 0.5, y = 0.5 }) or false
		local there = here and here.known and kept[map] or nil
		if not (here and there and there.known) then
			return 0
		elseif there.continent ~= here.continent then
			return Cost(here, there) / ZONE_YARDS
		end
		return math.min(Yards(here, there) / ZONE_YARDS, ZONE_NEAR)
	end
end

ns.Planner.Zones = {
	Choices = Choices,
	Far = Far,
	InZone = InZone,
	OutdoorElite = OutdoorElite,
}
