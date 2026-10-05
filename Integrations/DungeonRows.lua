---@type string, AGFNamespace
local _, ns = ...
local L, Dungeons = ns.L, ns.Dungeons

---@param quest AGFDungeonQuest
---@return string
function Dungeons.QuestStatus(quest)
	local labels = {
		done = L.DUNGEON_DONE,
		log = L.DUNGEON_IN_LOG,
		available = L.DUNGEON_PICKUP,
		pre = L.DUNGEON_PRE,
		unknown = L.DUNGEON_UNAVAILABLE,
	}
	return quest.status == "level" and L.DUNGEON_LEVEL:format(quest.requiredLevel) or labels[quest.status]
end

---@param place? AGFPlace
---@return string
function Dungeons.PlaceText(place)
	if not place or not place.name or place.name == "" then
		return ""
	end
	local hub = place.hub and ns.Data.hubs[place.hub]
	local name = hub and hub.name:match("^(.-),") or hub and hub.name or ns.State.ZoneName(place.map)
	return place.name .. (name and name ~= "" and L.SEPARATOR .. name or "")
end

---@param quest AGFDungeonQuest
---@return string
function Dungeons.GiverText(quest)
	local data = ns.Data.quests[quest.id]
	return Dungeons.PlaceText(data and data.start)
end

---@param page? AGFDungeonPage
---@param expanded table<integer, boolean>
---@return table[]
function Dungeons.QuestRows(page, expanded)
	if not page then
		return {}
	end
	-- One read of the player and one walk of the quest log for the whole list, taken when the first chain row needs it.
	---@type AGFPlayer?, table<integer, AGFLogQuest>?
	local player, log
	local values = {}
	for _, quest in ipairs(page.quests) do
		values[#values + 1] = { quest = quest }
		if expanded[quest.id] then
			player = player or ns.State.Player()
			local chain = Dungeons.Chain(ns.Data, quest.id, function() end)
			local alternatives = {}
			for _, id in ipairs(chain) do
				for _, pre in ipairs((ns.Data.quests[id] or {}).preAny or {}) do
					alternatives[pre] = true
				end
			end
			for _, id in ipairs(chain) do
				if id ~= quest.id and Dungeons.ForCharacter(ns.Data.quests[id], player) then
					log = log or ns.State.Log()
					values[#values + 1] = {
						quest = Dungeons.Quest(ns.Data, player, ns.State.Completed(), log, id),
						chain = true,
						alternative = alternatives[id],
					}
				end
			end
		end
	end
	return values
end

---@param item integer
---@return string?
local function ItemName(item)
	local name = C_Item.GetItemNameByID(item)
	if not name then
		Dungeons.RequestItem(item)
	end
	return name
end

---@param page? AGFDungeonPage
---@return table[]
function Dungeons.PrepRows(page)
	if not page then
		return {}
	end
	local values, seen = {}, {}
	for _, entry in ipairs(page.prep) do
		if entry.quest then
			values[#values + 1] = {
				title = entry.quest.title,
				info = (entry.kind == "pre" and L.DUNGEON_PRE_ELSEWHERE or L.DUNGEON_OUTSIDE)
					.. L.SEPARATOR
					.. Dungeons.QuestStatus(entry.quest),
				giver = Dungeons.GiverText(entry.quest),
				quest = entry.quest,
			}
		elseif entry.gate then
			local gate = entry.gate
			---@cast gate AGFEntranceGate
			local lines = {}
			if gate.level > 0 then
				lines[#lines + 1] = L.WHY_LEVEL:format(gate.level)
			end
			if gate.items then
				local items = {}
				for _, item in ipairs(gate.items) do
					local name = ItemName(item)
					if name then
						items[#items + 1] = name
					end
				end
				if #items == #gate.items then
					lines[#lines + 1] = L.DUNGEON_REQUIRES_ITEM:format(table.concat(items, L.DUNGEON_OR))
				end
			end
			if gate.quest then
				local quest = ns.Data.quests[gate.quest]
				lines[#lines + 1] = L.WHY_COMPLETED:format(
					ns.State.QuestTitle(gate.quest) or (quest and quest.title) or L.WHY_EARLIER_QUEST
				)
			end
			if gate.conditional then
				lines[#lines + 1] = L.DUNGEON_GATE_UNKNOWN
			end
			local text = table.concat(lines, L.SEPARATOR)
			if text ~= "" and not seen[text] then
				seen[text] = true
				table.insert(values, 1, { title = L.DUNGEON_ENTRANCE_REQUIREMENTS, info = text, entrance = true })
			end
		end
	end
	return values
end

-- The catalog with its section headings: dungeons, the announced Forever raids, then the client's other raid maps.
---@param catalog AGFDungeon[]
---@return table[]
function Dungeons.CatalogRows(catalog)
	local dungeons, current, others = {}, {}, {}
	for _, entry in ipairs(catalog) do
		if entry.raid then
			if entry.current then
				current[#current + 1] = entry
			else
				others[#others + 1] = entry
			end
		else
			dungeons[#dungeons + 1] = entry
		end
	end
	local rows = {}
	if #dungeons > 0 then
		rows[#rows + 1] = { heading = true, title = L.DUNGEON_LIST_DUNGEONS }
	end
	for _, entry in ipairs(dungeons) do
		rows[#rows + 1] = entry
	end
	if #current > 0 then
		rows[#rows + 1] = { heading = true, title = L.DUNGEON_LIST_RAIDS }
	end
	for _, entry in ipairs(current) do
		rows[#rows + 1] = entry
	end
	if #others > 0 then
		rows[#rows + 1] = { heading = true, title = L.DUNGEON_LIST_OTHER_RAIDS }
	end
	for _, entry in ipairs(others) do
		rows[#rows + 1] = entry
	end
	return rows
end
