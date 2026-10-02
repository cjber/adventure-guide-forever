---@type string, AGFNamespace
local _, ns = ...
local floor = math.floor

local SPAWNS = { "spawns" }
local DROPS = { "npcDrops", "objectDrops", "itemDrops" }
local KINDS = { "Npc", "Object" }
-- A cell is one square of a map's yard grid. No map is this many yards across, so a column and a row share a number.
local ROW = 2 ^ 16

-- Locations come from the provider's composed spawns. Bucket nearby spawns and choose a real point in each
-- bucket, rather than directing the player to an average that may be inside terrain or across a river.
---@param lib AGFQuestieDB
---@param objectives table?
---@param trigger table?
---@param zone integer?
---@param data AGFData
---@param mapOf fun(area: integer): integer?
---@param yield fun()
---@param questID integer
---@return table?, AGFObjectiveArea[]?, table?, boolean? unsupported
function ns.QuestieObjectives(lib, objectives, trigger, zone, data, mapOf, yield, questID)
	-- Questie stores icon overrides, not required counts, in objective[3] (kill credits: [4]).
	-- Zero retains the objective slot; the quest log supplies its actual count after pickup.
	local need, areas, kinds = {}, {}, {}
	local function Places(slot, lists)
		local cells, ordered = {}, {}
		for _, spawns in ipairs(lists) do
			for area, coordinates in pairs(spawns) do
				local map = mapOf(area)
				local geometry = map and data.maps[map]
				if geometry then
					---@cast map -?
					local sx, sy = geometry.sx, geometry.sy
					local onMap = cells[map]
					if not onMap then
						onMap = {}
						cells[map] = onMap
					end
					for _, xy in ipairs(coordinates) do
						local x, y = tonumber(xy[1]), tonumber(xy[2])
						if x and y and x >= 0 and x <= 100 and y >= 0 and y <= 100 then
							x, y = x / 100, y / 100
							local key = floor(x * sx / 100) * ROW + floor(y * sy / 100)
							local cell = onMap[key]
							if not cell then
								cell = { map = map, x = x, y = y, count = 0, reach = 0 }
								onMap[key] = cell
								ordered[#ordered + 1] = cell
							end
							cell.count = cell.count + 1
							local dx, dy = (x - cell.x) * sx, (y - cell.y) * sy
							local reach = dx * dx + dy * dy
							if reach > cell.reach then
								cell.reach = reach
							end
						end
					end
					yield()
				end
			end
		end
		table.sort(ordered, function(a, b)
			if (a.map == zone) ~= (b.map == zone) then
				return a.map == zone
			end
			if a.count ~= b.count then
				return a.count > b.count
			end
			if a.map ~= b.map then
				return a.map < b.map
			end
			if a.x ~= b.x then
				return a.x < b.x
			end
			return a.y < b.y
		end)
		for i = 1, math.min(3, #ordered) do
			local cell = ordered[i]
			areas[#areas + 1] = {
				slot,
				math.floor(cell.x * 1000 + 0.5),
				math.floor(cell.y * 1000 + 0.5),
				math.ceil(math.sqrt(cell.reach)),
				cell.map,
			}
		end
	end
	local function Spawns(kind, id, lists)
		local values = lib[kind].GetAll(id, SPAWNS)
		if values and type(values[1]) == "table" then
			lists[#lists + 1] = values[1]
		end
		yield()
	end
	local function Item(id, lists, seen)
		if seen[id] then
			return
		end
		seen[id] = true
		local values = lib.Item.GetAll(id, DROPS)
		if values then
			for index, kind in ipairs(KINDS) do
				for _, source in ipairs(type(values[index]) == "table" and values[index] or {}) do
					Spawns(kind, source, lists)
				end
			end
			for _, source in ipairs(type(values[3]) == "table" and values[3] or {}) do
				Item(source, lists, seen)
			end
		end
		yield()
	end
	local slot = 0
	local function KillCredits()
		for _, objective in ipairs(objectives and objectives[5] or {}) do
			if slot > 3 then
				return false
			end
			need[slot], kinds[slot] = 0, "monster"
			local lists = {}
			for _, id in ipairs(objective[1] or {}) do
				Spawns("Npc", id, lists)
			end
			Places(slot, lists)
			slot = slot + 1
		end
		return true
	end
	local creditFirst = lib.ObjectiveFirst
		and lib.ObjectiveFirst.killCreditObjectiveFirst
		and lib.ObjectiveFirst.killCreditObjectiveFirst[questID]
	if creditFirst and not KillCredits() then
		return nil, nil, nil, true
	end
	for index, kind in ipairs(KINDS) do
		for _, objective in ipairs(objectives and objectives[index] or {}) do
			if slot > 3 then
				return nil, nil, nil, true
			end
			need[slot], kinds[slot] = 0, kind == "Npc" and "monster" or "object"
			local lists = {}
			Spawns(kind, objective[1], lists)
			Places(slot, lists)
			slot = slot + 1
		end
	end

	if not creditFirst and not KillCredits() then
		return nil, nil, nil, true
	end
	for index, objective in ipairs(objectives and objectives[3] or {}) do
		if index > 4 then
			return nil, nil, nil, true
		end
		slot = index + 3
		need[slot], kinds[slot] = 0, "item"
		local lists = {}
		Item(objective[1], lists, {})
		Places(slot, lists)
	end
	if type(trigger) == "table" and type(trigger[2]) == "table" then
		need[16], kinds[16] = 1, "event"
		Places(16, { trigger[2] })
	end
	-- Spell/reputation objectives have no compatible planner slots; use the client's live quest POI instead.
	if objectives and (next(objectives[4] or {}) or next(objectives[6] or {})) then
		return nil, nil, nil, true
	end
	return next(need) and need or nil, areas[1] and areas or nil, next(kinds) and kinds or nil
end
