---@type string, AGFNamespace
local _, ns = ...
local L, Model = ns.L, ns.Model

-- The dungeon browser's headless model (docs/design.md §2.21). A caller supplies Yield when building a page;
-- the hidden tab never asks for one. Instance IDs are Map.ID throughout, never names or UiMapIDs.
---@class AGFDungeons
local Dungeons = {}
ns.Dungeons = Dungeons

---@param data AGFData
---@param player AGFPlayer
---@param yield fun()
---@return AGFDungeon[]
function Dungeons.List(data, player, yield)
	local byID, list = {}, {}
	for id, instance in pairs(data.instances) do
		if not instance.raid then
			local entry = {
				id = id,
				name = instance.name,
				quests = {},
				suitable = false,
				low = instance.low,
				high = instance.high,
			}
			if instance.lfg and GetLFGDungeonInfo then
				local _, _, _, _, _, _, low, high = GetLFGDungeonInfo(instance.lfg)
				if type(low) == "number" and type(high) == "number" and low > 0 and high > low then
					entry.low, entry.high = low, high
				end
			end
			byID[id], list[#list + 1] = entry, entry
			for _, gate in ipairs(instance.entrances or {}) do
				entry.minimum = math.min(entry.minimum or gate.level, gate.level)
			end
		end
	end
	for id, quest in pairs(data.quests) do
		local entry = quest.dungeon and byID[quest.dungeon]
		if entry and not quest.raid then
			entry.quests[#entry.quests + 1] = id
		end
		yield()
	end
	for _, entry in ipairs(list) do
		table.sort(entry.quests, function(a, b)
			local qa, qb = data.quests[a], data.quests[b]
			return qa.level < qb.level or (qa.level == qb.level and a < b)
		end)
		entry.suitable = entry.low ~= nil and player.level >= entry.low and player.level <= entry.high
	end
	table.sort(list, function(a, b)
		local al, bl = a.low or math.huge, b.low or math.huge
		if al == bl and (a.low ~= nil) ~= (b.low ~= nil) then
			return a.low ~= nil
		end
		return al < bl or (al == bl and a.id < b.id)
	end)
	return list
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
		if quest and quest.start and data.maps[quest.start.map] then
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
	for _, gate in ipairs(data.instances[dungeon.id].entrances or {}) do
		page.prep[#page.prep + 1] = { kind = "entrance", gate = gate }
	end
	return page
end

---@param id integer
---@return boolean
function Dungeons.Go(id)
	local row = Dungeons.Quest(ns.Data, ns.State.Player(), ns.State.Completed(), ns.State.Log(), id)
	local place = row.place
	if not place then
		return false
	end
	return ns.Integrations.Navigate({
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

-- Explicit-instance reads do not change the player's Encounter Journal selection or loot filters.
---@param instance integer
---@param yield fun()
---@return AGFDungeonBoss[]?, integer?, integer?
function Dungeons.Journal(instance, yield)
	if not (C_EncounterJournal and C_EncounterJournal.GetInstanceForGameMap and EJ_GetEncounterInfoByIndex) then
		return nil
	end
	local journal = C_EncounterJournal.GetInstanceForGameMap(instance)
	if not journal or journal == 0 then
		return nil
	end
	local rows, index = {}, 1
	while true do
		local name, _, id = EJ_GetEncounterInfoByIndex(index, journal)
		if not name or name == "" or not id then
			break
		end
		rows[#rows + 1] = { id = id, name = name, rank = 3 }
		index = index + 1
		yield()
	end
	local icon
	if EJ_GetInstanceInfo then
		local _, _, _, _, _, texture = EJ_GetInstanceInfo(journal)
		icon = type(texture) == "number" and texture > 0 and texture or nil
	end
	return #rows > 0 and rows or nil, journal, icon
end

---@param instance integer
---@param source? AGFDungeonSource
---@return AGFPoint?
function Dungeons.Entrance(instance, source)
	local point = source and source.entrances and source.entrances[instance]
	return Model.ValidPlace(point) and point or (ns.Providers.DungeonEntrance(instance))
end

---@param instance integer
---@param source? AGFDungeonSource
---@return boolean
function Dungeons.GoEntrance(instance, source)
	local point = Dungeons.Entrance(instance, source)
	if not point then
		return false
	end
	return ns.Integrations.Navigate({
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
---@param source? AGFDungeonSource
---@return string?
function Dungeons.Objective(id, source)
	local text = source and source.objectives[id]
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
