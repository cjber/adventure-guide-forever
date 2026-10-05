---@type string, AGFNamespace
local _, ns = ...
local L, Model = ns.L, ns.Model

-- The dungeon browser's headless model (docs/design.md §2.21). A caller supplies Yield when building a page;
-- the hidden tab never asks for one. Instance IDs are Map.ID throughout, never names or UiMapIDs.
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

-- The entrances are inside faction capitals: Orgrimmar and Stormwind, respectively.
local CAPITAL_DUNGEONS = { [389] = 2, [34] = 1 }

---@param data AGFData
---@param player AGFPlayer
---@param yield fun()
---@return AGFDungeon[]
function Dungeons.List(data, player, yield)
	local byID, dungeons, raids = {}, {}, {}
	for id, instance in pairs(data.instances) do
		if not instance.raid then
			local entry = {
				id = id,
				name = instance.name,
				quests = {},
				suitable = false,
				hostile = CAPITAL_DUNGEONS[id] ~= nil and CAPITAL_DUNGEONS[id] ~= player.side,
				excludedFaction = 0,
				excludedCharacter = 0,
				low = instance.low,
				high = instance.high,
			}
			if instance.lfg and GetLFGDungeonInfo then
				local _, _, _, _, _, _, low, high = GetLFGDungeonInfo(instance.lfg)
				if type(low) == "number" and type(high) == "number" and low > 0 and high > low then
					entry.low, entry.high = low, high
				end
			end
			byID[id], dungeons[#dungeons + 1] = entry, entry
			for _, gate in ipairs(instance.entrances or {}) do
				entry.minimum = math.min(entry.minimum or gate.level, gate.level)
			end
		end
	end
	-- Raids come from the curated registry (Raids.lua): the announced Forever tiers first, then the client's
	-- other raid maps. A registered raid with no client Map.ID yet is not browsable.
	for _, raid in ipairs(ns.Raids) do
		if raid.map then
			local instance = data.instances[raid.map]
			local entry = {
				id = raid.map,
				name = instance and instance.name or raid.name,
				raid = true,
				current = raid.current == true,
				players = raid.players,
				quests = {},
				suitable = false,
				hostile = false,
				excludedFaction = 0,
				excludedCharacter = 0,
				low = raid.low,
				high = raid.high,
			}
			byID[raid.map], raids[#raids + 1] = entry, entry
		end
		yield()
	end
	for id, quest in pairs(data.quests) do
		local entry = quest.dungeon and byID[quest.dungeon]
		if entry and not quest.raid then
			if Dungeons.ForCharacter(quest, player) then
				entry.quests[#entry.quests + 1] = id
			elseif (quest.side == 1 or quest.side == 2) and quest.side ~= player.side then
				entry.excludedFaction = entry.excludedFaction + 1
			else
				entry.excludedCharacter = entry.excludedCharacter + 1
			end
		end
		yield()
	end
	for _, entry in ipairs(dungeons) do
		table.sort(entry.quests, function(a, b)
			local qa, qb = data.quests[a], data.quests[b]
			return qa.level < qb.level or (qa.level == qb.level and a < b)
		end)
		entry.suitable = not entry.hostile
			and entry.low ~= nil
			and player.level >= entry.low
			and player.level <= entry.high
	end
	table.sort(dungeons, function(a, b)
		local al, bl = a.low or math.huge, b.low or math.huge
		if al == bl and (a.low ~= nil) ~= (b.low ~= nil) then
			return a.low ~= nil
		end
		return al < bl or (al == bl and a.id < b.id)
	end)
	for _, entry in ipairs(raids) do
		entry.suitable = entry.low ~= nil
			and player.level >= entry.low
			and entry.high ~= nil
			and player.level <= entry.high
		dungeons[#dungeons + 1] = entry
	end
	return dungeons
end

---@param data AGFData
---@param player AGFPlayer
---@param completed table<integer, boolean>
---@param log table<integer, AGFLogQuest>
---@param id integer
---@return AGFDungeonQuest
function Dungeons.Quest(data, player, completed, log, id)
	local quest = data.quests[id]
	local row = { id = id, status = "unknown", title = quest and quest.title or L.WHY_EARLIER_QUEST }
	if not quest then
		return row
	end
	row.level, row.xp = quest.level, Model.QuestXP(quest, player.level)
	if completed[id] then
		row.status = "done"
	elseif log[id] then
		row.status = "log"
	elseif Model.Eligible(data, player, completed, log, id) then
		row.status = "available"
	elseif quest.start then
		if quest.min > player.level then
			row.status, row.requiredLevel = "level", quest.min
		else
			for _, pre in ipairs(quest.pre or {}) do
				if not completed[pre] then
					row.status = "pre"
				end
			end
			if quest.preAny then
				local met = false
				for _, pre in ipairs(quest.preAny) do
					met = met or completed[pre] == true
				end
				if not met then
					row.status = "pre"
				end
			end
		end
	end
	if Model.ValidPlace(quest.start) then
		row.place = quest.start
	end
	return row
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

---@param data AGFData
---@param player AGFPlayer
---@param completed table<integer, boolean>
---@param log table<integer, AGFLogQuest>
---@param dungeon AGFDungeon
---@param yield fun()
---@return AGFDungeonPage
function Dungeons.Page(data, player, completed, log, dungeon, yield)
	local page = { dungeon = dungeon, quests = {}, prep = {}, xp = 0 }
	local prepared, groups = {}, {}
	local function Prep(id, kind)
		if prepared[id] or completed[id] or log[id] then
			return
		end
		prepared[id] = true
		local quest = data.quests[id]
		if quest and Dungeons.ForCharacter(quest, player) and quest.start and data.maps[quest.start.map] then
			page.prep[#page.prep + 1] = { kind = kind, quest = Dungeons.Quest(data, player, completed, log, id) }
		end
	end
	-- Prove the whole prerequisite path with the planner, including exclusive groups, professions and reputation.
	-- A log quest can be finished; an unavailable or cyclic prerequisite can never prove a future pickup.
	local function Reachable(id, after, visiting)
		if after[id] or log[id] then
			after[id] = true
			return true
		end
		local quest = data.quests[id]
		if not quest or visiting[id] then
			return false
		end
		visiting[id] = true
		for _, pre in ipairs(quest.pre or {}) do
			if not Reachable(pre, after, visiting) then
				visiting[id] = nil
				return false
			end
		end
		if quest.preAny then
			local met = false
			for _, pre in ipairs(quest.preAny) do
				local branch = setmetatable({}, { __index = after })
				if Reachable(pre, branch, visiting) then
					for key, value in pairs(branch) do
						after[key] = value
					end
					after[pre], met = true, true
					break
				end
			end
			if not met then
				visiting[id] = nil
				return false
			end
		end
		visiting[id] = nil
		yield()
		if Model.Eligible(data, player, after, log, id) then
			after[id] = true
			return true
		end
		return false
	end
	for _, id in ipairs(dungeon.quests) do
		local row = Dungeons.Quest(data, player, completed, log, id)
		page.quests[#page.quests + 1] = row
		local quest = data.quests[id]
		local after = setmetatable({}, { __index = completed })
		if row.status ~= "done" and row.xp and Reachable(id, after, {}) then
			if quest.group then
				groups[quest.group] = math.max(groups[quest.group] or 0, row.xp)
			else
				page.xp = page.xp + row.xp
			end
		end
		if row.status ~= "done" then
			Prep(id, "pickup")
			for _, pre in ipairs(Dungeons.Chain(data, id, yield)) do
				if pre ~= id then
					Prep(pre, "pre")
				end
			end
		end
		yield()
	end
	for _, xp in pairs(groups) do
		page.xp = page.xp + xp
	end
	for _, gate in ipairs((data.instances[dungeon.id] or {}).entrances or {}) do
		page.prep[#page.prep + 1] = { kind = "entrance", gate = gate }
	end
	return page
end

---@param id integer
---@return boolean
function Dungeons.Go(id)
	local player = ns.State.Player()
	local row = Dungeons.Quest(ns.Data, player, ns.State.Completed(), ns.State.Log(), id)
	local place = row.place
	if not place or not Dungeons.ForCharacter(ns.Data.quests[id], player) then
		return false
	end
	return ns.Guidance.ShowOnMap({
		map = place.map,
		x = place.x,
		y = place.y,
		kind = "town",
		key = "dungeon-quest:" .. id,
		quests = { id },
		title = row.title,
		reason = "",
		detail = "",
	})
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

---@param id integer
---@param details? AGFDungeonDetails
---@return string?
function Dungeons.Objective(id, details)
	local text = details and details.objectives[id]
	if text and text ~= "" then
		return text
	end
	local index = C_QuestLog.GetLogIndexForQuestID(id)
	if index then
		local _, objective = GetQuestLogQuestText(index)
		if objective and objective ~= "" then
			return objective
		end
	end
end

-- A position exists only for a complete, unbranched prerequisite path ending at the page's quest.
---@param data AGFData
---@param id integer
---@param selected integer
---@return integer?, integer?
function Dungeons.ChainPosition(data, id, selected)
	local chain, seen = {}, {}
	---@type integer?
	local current = id
	while current do
		local quest = data.quests[current]
		if not quest or seen[current] or quest.preAny or #(quest.pre or {}) > 1 then
			return nil
		end
		seen[current], chain[#chain + 1] = true, current
		current = quest.pre and quest.pre[1]
	end
	if #chain > 1 then
		for index, quest in ipairs(chain) do
			if quest == selected then
				return #chain - index + 1, #chain
			end
		end
	end
end

-- Planning is persistent even when the character has no eligible preparation quests.
---@param instance integer
---@return boolean
function Dungeons.Planned(instance)
	return ns.Prefs().plannedDungeons[instance] == true
end

---@param instance integer
---@param planned boolean
function Dungeons.SetPlanned(instance, planned)
	local prefs, key = ns.Prefs(), "dungeon:" .. instance
	prefs.plannedDungeons[instance] = planned or nil
	if planned then
		prefs.dungeons = true
		prefs.notInterested[key] = nil
		for _, card in ipairs(ns.Route().journeys) do
			if card.key == key then
				ns.Choose(key, false)
				return
			end
		end
	elseif prefs.journey == key then
		ns.Choose(nil)
		return
	end
	ns.Invalidate()
end
