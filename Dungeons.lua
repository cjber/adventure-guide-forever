---@type string, AGFNamespace
local _, ns = ...
local L, Model = ns.L, ns.Model

-- The dungeon browser's headless model (docs/design.md §2.21). A caller supplies Yield when building a page;
-- the hidden tab never asks for one. Instance IDs are Map.ID throughout, never names or UiMapIDs.
---@class AGFDungeons
local Dungeons = {}
ns.Dungeons = Dungeons

-- The bundled boss database is gone (docs/dungeon-sources.md). The dungeon UI still probes this
-- field when neither AtlasLoot nor the native Encounter Journal is installed, so keep it present
-- and empty rather than letting that probe index nil.
ns.DungeonBosses = ns.DungeonBosses or {}

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
	local byID, list = {}, {}
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
			byID[id], list[#list + 1] = entry, entry
			for _, gate in ipairs(instance.entrances or {}) do
				entry.minimum = math.min(entry.minimum or gate.level, gate.level)
			end
		end
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
	for _, entry in ipairs(list) do
		table.sort(entry.quests, function(a, b)
			local qa, qb = data.quests[a], data.quests[b]
			return qa.level < qb.level or (qa.level == qb.level and a < b)
		end)
		entry.suitable = not entry.hostile
			and entry.low ~= nil
			and player.level >= entry.low
			and player.level <= entry.high
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
	if not place or not Dungeons.ForCharacter(ns.Data.quests[id], ns.State.Player()) then
		return false
	end
	return ns.Integrations.ShowOnMap({
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
		local name, description, id = EJ_GetEncounterInfoByIndex(index, journal)
		if not name or name == "" or not id then
			break
		end
		rows[#rows + 1] = { id = id, name = name, rank = 3, journal = true, description = description }
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

-- AtlasLoot's normal instance pages, read in their encounter order. Its optional module is load-on-demand.
-- No data or source from AtlasLoot is bundled (docs/dungeon-sources.md).
---@param yield fun()
---@return AGFDungeonSource?
function Dungeons.Source(yield)
	local source = ns.ReadDungeonSource(yield)
	local atlas = AtlasLoot
	if not (atlas and atlas.ItemDB and type(atlas.ItemDB.Get) == "function") then
		return source
	end
	local moduleName = "AtlasLootClassic_DungeonsAndRaids"
	if not atlas.ItemDB:Get(moduleName) and not InCombatLockdown() and C_AddOns.DoesAddOnExist(moduleName) then
		C_AddOns.LoadAddOn(moduleName)
	end
	local module = atlas.ItemDB:Get(moduleName)
	local normal = module and type(module.GetDifficultyByName) == "function" and module:GetDifficultyByName("n")
	if not module or not normal then
		return source
	end
	local pages = {}
	for key, entry in pairs(module) do
		if type(entry) == "table" and entry.InstanceID and type(entry.items) == "table" then
			pages[#pages + 1] = { key = key, entry = entry }
		end
	end
	table.sort(pages, function(a, b)
		local aLevel, bLevel =
			a.entry.LevelRange and a.entry.LevelRange[2] or 0, b.entry.LevelRange and b.entry.LevelRange[2] or 0
		return aLevel < bLevel or (aLevel == bLevel and a.key < b.key)
	end)
	local curated = {}
	for _, page in ipairs(pages) do
		local entry = page.entry
		local instance = type(entry) == "table" and entry.InstanceID
		if
			instance
			and ns.Data.instances[instance]
			and not ns.Data.instances[instance].raid
			and type(entry.items) == "table"
		then
			source = source or { bosses = {}, loot = {}, rewards = {}, objectives = {}, entrances = {} }
			local current = curated[instance] or { bosses = {}, items = {}, seen = {} }
			curated[instance] = current
			local bosses, items, seen = current.bosses, current.items, current.seen
			for _, group in ipairs(entry.items) do
				local ids = type(group.npcID) == "table" and group.npcID or { group.npcID }
				local npc = not group.ExtraList and type(ids[1]) == "number" and ids[1]
				local trash = group.ExtraList
					and atlas.Locales
					and (group.name == atlas.Locales["Trash"] or group.name == atlas.Locales["Trash Mobs"])
				if not group.IgnoreAsSource and (npc or trash) then
					local boss
					if npc and type(group.name) == "string" then
						local level = type(group.Level) == "number" and group.Level or nil
						boss = { id = npc, name = group.name, rank = 3, low = level, high = level }
						bosses[#bosses + 1] = boss
					end
					for _, drop in ipairs(type(group[normal]) == "table" and group[normal] or {}) do
						local id = type(drop) == "table" and drop[2]
						if
							type(id) == "number"
							and id > 0
							and not seen[id]
							and not (source.worldDrops and source.worldDrops[id])
						then
							seen[id] = true
							items[#items + 1] = {
								id = id,
								name = "",
								droppers = boss and { boss } or {},
								startQuest = source.starts and source.starts[id],
							}
						end
					end
				end
				yield()
			end
			if #bosses > 0 then
				source.bosses[instance], source.loot[instance] = bosses, items
				source.curated = source.curated or {}
				source.curated[instance] = true
			end
		end
		yield()
	end
	return source
end

---@param source? AGFDungeonSource
---@param instance integer
---@param journal? AGFDungeonBoss[]
---@return AGFDungeonBoss[]
function Dungeons.Bosses(source, instance, journal)
	-- AtlasLoot's curated encounters win, the native Encounter Journal fills the gaps, and the
	-- runtime NPC source is the last resort. With none of them the result is empty, never an error.
	local listed = source and source.bosses[instance] or {}
	if source and source.curated and source.curated[instance] then
		local rows, seen = {}, {}
		for _, boss in ipairs(listed) do
			rows[#rows + 1] = boss
			seen[boss.id], seen[boss.name] = true, true
		end
		for _, encounter in ipairs(journal or {}) do
			if not seen[encounter.id] and not seen[encounter.name] then
				rows[#rows + 1] = encounter
			end
		end
		return rows
	end
	if journal then
		local rows, seen = {}, {}
		for _, encounter in ipairs(journal) do
			local matches = {}
			for _, npc in pairs(source and source.npcs and source.npcs[instance] or {}) do
				if
					(encounter.journal and npc.name == encounter.name)
					or (not encounter.journal and npc.id == encounter.id)
				then
					matches[#matches + 1] = npc
				end
			end
			local boss = #matches == 1 and matches[1] or encounter
			rows[#rows + 1] = boss
			if not boss.journal then
				seen[boss.id] = true
			end
		end
		for _, boss in ipairs(listed) do
			if not seen[boss.id] then
				rows[#rows + 1] = boss
			end
		end
		return rows
	end
	return listed
end

local requestedLoot = {}
---@param source AGFDungeonSource
---@param instance integer
---@param bosses AGFDungeonBoss[]
---@return table[]
function Dungeons.LootRows(source, instance, bosses)
	local groups, order, seen = {}, {}, {}
	for _, boss in ipairs(bosses) do
		if not boss.journal then
			groups[boss.id] = { boss = boss, items = {} }
			order[#order + 1] = groups[boss.id]
		end
	end
	local trash = { items = {} }
	order[#order + 1] = trash
	for _, item in ipairs(source.loot[instance] or {}) do
		local quality = C_Item.GetItemQualityByID(item.id)
		local name = C_Item.GetItemNameByID(item.id)
		if (not quality or not name) and not requestedLoot[item.id] then
			requestedLoot[item.id] = true
			C_Item.RequestLoadItemDataByID(item.id)
		end
		if not seen[item.id] and (item.startQuest or (quality and quality >= 2)) then
			seen[item.id] = true
			local group = trash
			for _, boss in ipairs(bosses) do
				for _, npc in ipairs(item.droppers or {}) do
					if not boss.journal and npc.id == boss.id and group == trash then
						group = groups[boss.id]
					end
				end
			end
			local itemName, itemQuality, requiredLevel, itemType, itemSubType, equipSlot
			if C_Item.GetItemInfo then
				local itemInfo = { C_Item.GetItemInfo(item.id) }
				itemName, itemQuality, requiredLevel, itemType, itemSubType, equipSlot =
					itemInfo[1], itemInfo[3], itemInfo[5], itemInfo[6], itemInfo[7], itemInfo[9]
			end
			local meta = {}
			if itemType and itemType ~= "" then
				meta[#meta + 1] = itemSubType and itemType .. L.SEPARATOR .. itemSubType or itemType
			end
			equipSlot = equipSlot and _G[equipSlot] or equipSlot
			if equipSlot and equipSlot ~= "" and equipSlot ~= "INVTYPE_NON EQUIP" then
				meta[#meta + 1] = equipSlot
			end
			if requiredLevel and requiredLevel > 0 then
				meta[#meta + 1] = L.DUNGEON_ITEM_REQUIRED_LEVEL:format(requiredLevel)
			end
			group.items[#group.items + 1] = {
				title = itemName or name or item.name,
				item = item.id,
				quality = itemQuality or quality,
				info = table.concat(meta, L.SEPARATOR),
			}
		end
	end
	local rows = {}
	for _, group in ipairs(order) do
		if #group.items > 0 then
			local boss = group.boss
			rows[#rows + 1] = {
				title = boss and boss.name or ns.L.DUNGEON_TRASH,
				bossID = boss and boss.id,
				heading = true,
				info = boss and boss.low and boss.low > 0 and ns.L.DUNGEON_LEVEL:format(boss.low) or "",
			}
			for _, item in ipairs(group.items) do
				rows[#rows + 1] = item
			end
		end
	end
	return rows
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
	return ns.Integrations.ShowOnMap({
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
