---@type string, AGFNamespace
local _, ns = ...
local Widgets = ns.Widgets

-- A quest outline: only the planner supplies actionable steps.
-- Questie prerequisites order the outline; no future quest is sent to navigation or tracking.
---@param data AGFData
---@param player AGFPlayer
---@param completed table<integer, boolean>
---@param journey AGFJourney
---@param steps AGFStep[]
---@return integer[]
function Widgets.GuideOutline(data, player, completed, journey, steps)
	if journey.instance then
		local active, future, seen = {}, {}, {}
		for _, step in ipairs(steps) do
			for _, id in ipairs(step.quests) do
				active[id] = true
			end
		end
		local ids = {}
		for id, quest in pairs(data.quests) do
			if quest.dungeon == journey.instance and not quest.raid and ns.Dungeons.ForCharacter(quest, player) then
				ids[#ids + 1] = id
			end
		end
		table.sort(ids)
		for _, id in ipairs(ids) do
			if not completed[id] then
				for _, before in ipairs(ns.Dungeons.Chain(data, id, function() end)) do
					local quest = data.quests[before]
					if
						quest
						and not seen[before]
						and not active[before]
						and not completed[before]
						and ns.Dungeons.ForCharacter(quest, player)
					then
						future[#future + 1], seen[before] = before, true
					end
				end
			end
		end
		return future
	end
	local zone = journey.zone
	if not zone then
		return {}
	end
	local active = {}
	---@type table<integer, AGFQuest>
	local candidates = {}
	---@type integer[]
	local ids = {}
	for _, step in ipairs(steps) do
		for _, id in ipairs(step.quests) do
			active[id] = true
		end
	end
	local Matches = ns.Model.HasBit
	for id, quest in pairs(data.quests) do
		if
			(quest.zone == zone or (quest.start and quest.start.map == zone))
			and (quest.side == 3 or quest.side == player.side)
			and Matches(quest.races, player.raceBit)
			and Matches(quest.classes, player.classBit)
			and not quest.repeatable
			and not quest.dungeon
			and not completed[id]
			and not active[id]
		then
			candidates[id] = quest
			ids[#ids + 1] = id
		end
	end
	-- Follow-ups to this lap first, then useful levels, then the rest of the zone.
	local follows, following = {}, {}
	local function FollowsRoute(id)
		if active[id] then
			return true
		end
		if follows[id] ~= nil then
			return follows[id]
		end
		if following[id] or not candidates[id] then
			return false
		end
		following[id] = true
		local quest = candidates[id]
		local result = false
		for _, requirements in ipairs({ quest.pre or {}, quest.preAny or {} }) do
			for _, before in ipairs(requirements) do
				if before > 0 and FollowsRoute(before) then
					result = true
				end
			end
		end
		following[id], follows[id] = nil, result
		return result
	end
	local function Rank(id)
		if FollowsRoute(id) then
			return 0
		end
		local level = candidates[id].level
		if level < 0 or (level >= player.level - 5 and level <= player.level) then
			return 1
		end
		return level > player.level and 2 or 3
	end
	table.sort(ids)
	local ranks = {}
	for _, id in ipairs(ids) do
		ranks[id] = Rank(id)
	end
	table.sort(ids, function(a, b)
		if ranks[a] ~= ranks[b] then
			return ranks[a] < ranks[b]
		end
		local left, right = candidates[a], candidates[b]
		local al, bl = left.level, right.level
		return al < bl or (al == bl and a < b)
	end)
	local ordered, visited = {}, {}
	local function Visit(id)
		if visited[id] or not candidates[id] then
			return
		end
		visited[id] = true
		local quest = candidates[id]
		for _, requirements in ipairs({ quest.pre or {}, quest.preAny or {} }) do
			for _, before in ipairs(requirements) do
				if before > 0 then
					Visit(before)
				end
			end
		end
		ordered[#ordered + 1] = id
	end
	for _, id in ipairs(ids) do
		Visit(id)
	end
	return ordered
end

---@class AGFGuideRow : AGFWindowRow, AGFStepHoverRow
---@field step? AGFStep
---@field index? integer
---@field questID? integer
