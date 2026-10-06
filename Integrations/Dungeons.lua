---@type string, AGFNamespace
local _, ns = ...
local Model = ns.Model

---@class AGFDungeons
local Dungeons = {}
ns.Dungeons = Dungeons

-- Permanent character restrictions only. Other unproven requirements stay visible as locked.
---@param quest? AGFQuest
---@param player AGFPlayer
---@return boolean
function Dungeons.ForCharacter(quest, player)
	return not quest
		or (
			(quest.side ~= 1 and quest.side ~= 2 or quest.side == player.side)
			and (player.raceBit == 0 or Model.HasBit(quest.races, player.raceBit))
			and (player.classBit == 0 or Model.HasBit(quest.classes, player.classBit))
		)
end

---@param data AGFData
---@param id integer
---@param yield fun()
---@return integer[]
function Dungeons.Chain(data, id, yield)
	local seen, chain = {}, {}
	local function Visit(other)
		if seen[other] then
			return
		end
		seen[other] = true
		local quest = data.quests[other]
		if quest then
			for _, pre in ipairs(quest.pre or {}) do
				Visit(pre)
			end
			for _, pre in ipairs(quest.preAny or {}) do
				Visit(pre)
			end
		end
		chain[#chain + 1] = other
		yield()
	end
	Visit(id)
	return chain
end

local requestedItems = {}
---@param id integer
function Dungeons.RequestItem(id)
	if not requestedItems[id] then
		requestedItems[id] = true
		C_Item.RequestLoadItemDataByID(id)
	end
end

-- A dungeon's way in: QuestieDB's point, else Tweaks Forever's, else why neither has one. One answer for every view,
-- from the first draw.
---@param instance integer
---@return AGFPoint?
---@return string? reason "missing", "outdated" or "unknown" when there is no point
function Dungeons.Entrance(instance)
	local point = ns.DungeonEntrance(instance)
	if point then
		return point
	end
	return ns.Providers.DungeonEntrance(instance)
end

---@param instance integer
---@return boolean
function Dungeons.GoEntrance(instance)
	local point = Dungeons.Entrance(instance)
	if not point then
		return false
	end
	return ns.Guidance.ShowOnMap({
		map = point.map,
		x = point.x,
		y = point.y,
		kind = "dungeon",
		key = "entrance:" .. instance,
		quests = {},
		title = ns.L.GO_TO_ENTRANCE,
		reason = "",
		detail = "",
	})
end
