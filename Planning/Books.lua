---@type string, AGFNamespace
local _, ns = ...

if ns.broken then
	return
end
local L = ns.L
local Model = ns.Model
local NONE = {}
local ValidPlace = ns.Model.ValidPlace

-- The library books (issue #706): the quests whose object starts a book and whose librarian takes it. QuestieDB
-- supplies them at runtime (Integrations/QuestieSource.lua, `data.books`); nothing of the list is bundled. A card is
-- one territory's books, smaller zones first, ending at the librarian the books are handed to.
local Books = {}

-- The FactionGroupMask bits of AreaTable: 2 Alliance, 4 Horde, 0 contested. A mask with both (6) belongs to both.
local SIDE_MASK = { [1] = 2, [2] = 4 }
-- The librarians' NPC entries, whose hand-in steps end the journey; a mage trainer takes the level 60 books too.
local LIBRARIANS = { [211033] = true, [211022] = true }
-- The library's reward goals, in the order the library hands them out. A card shows the next one's level, the goal's
-- own level rather than its required level, as "20+" on the card (the mockup's gate).
local GOALS = { 78150, 79536, 82208 }

-- The territory the card lists: the player's own faction until they pick one from the card's menu. 1 Alliance, 2 Horde.
---@param player AGFPlayer
---@param prefs AGFPrefs
---@return integer
local function Territory(player, prefs)
	local chosen = prefs.booksTerritory
	if chosen == 1 or chosen == 2 then
		return chosen
	end
	return player.side == 2 and 2 or 1
end

-- Whether `map` is in `side`'s territory: its own zones and the contested ones, never the other faction's.
---@param data AGFData
---@param map? integer
---@param side integer
---@return boolean
local function InTerritory(data, map, side)
	local mask = map and data.territory and data.territory[map]
	if not mask then
		return false
	end
	return mask == 0 or bit.band(mask, SIDE_MASK[side]) ~= 0
end

-- Whether the player's class may take `quest`: a class-restricted book is offered only to that class.
---@param quest AGFQuest
---@param classBit integer
---@return boolean
local function ForClass(quest, classBit)
	return not quest.classes or bit.band(quest.classes, classBit) ~= 0
end

-- The book's stop in `side`'s territory: the first spawn in one of its own zones, else the first contested one, in map
-- and point order. nil when every spawn is the other faction's, or the book has none.
---@param data AGFData
---@param book AGFBook
---@param side integer
---@return AGFPlace?
local function Spot(data, book, side)
	---@type AGFPlace?
	local best
	local bestOwn
	for _, spot in ipairs(book.spots or NONE) do
		if InTerritory(data, spot.map, side) then
			local own = (data.territory[spot.map] or 0) ~= 0
			if
				not best
				or (own and not bestOwn)
				or (own == bestOwn and (spot.map < best.map or (spot.map == best.map and spot.x < best.x)))
			then
				best, bestOwn = { map = spot.map, x = spot.x, y = spot.y, z = spot.z, name = spot.name }, own
			end
		end
	end
	return best
end

-- A place's town and zone for a step line: "Valley of Spirits, Orgrimmar". The town is the area the world map names
-- at the point (QuestieTowns), else the map's name; a town already naming the zone is not repeated.
---@param data AGFData
---@param place AGFPlace
---@param mapName? AGFMapName
---@return string area
---@return string zone
local function PlaceLine(data, place, mapName)
	local hub = Model.Hub(data, place)
	local town = { map = place.map, x = place.x, y = place.y, hub = hub }
	local area = hub and ns.QuestieTowns and ns.QuestieTowns.Name(data, town) or nil
	area = area or (mapName and mapName(place.map)) or (data.maps[place.map] and data.maps[place.map].name) or ""
	local zone = (mapName and mapName(place.map)) or (data.maps[place.map] and data.maps[place.map].name) or area
	return area, zone
end

-- An entry's approved order: smaller zones first (the width of the zone's level range), then its lower level, its
-- name and the book's title. A book with no spot has no zone, so it waits after the placed ones; both stay in the
-- same order on every build.
---@param data AGFData
---@param entry {book: AGFBook, quest: AGFQuest, spot?: AGFPlace}
---@return any[]
local function Order(data, entry)
	local zone = entry.spot and data.zones and data.zones[entry.spot.map] or nil
	local name = zone and zone.name
		or (entry.spot and data.maps[entry.spot.map] and data.maps[entry.spot.map].name)
		or ""
	return {
		entry.spot and 0 or 1,
		zone and (zone.max - zone.min) or 0,
		zone and zone.min or 0,
		name,
		entry.quest.title,
		entry.book.id,
	}
end

---@param a any[]
---@param b any[]
---@return boolean
local function Before(a, b)
	for index = 1, #a do
		if a[index] ~= b[index] then
			return a[index] < b[index]
		end
	end
	return false
end

-- The next library goal's level, for the card's "N+" gate: the first reward quest the player has not completed.
---@param data AGFData
---@param completed table<integer, boolean>
---@return integer?
local function GoalLevel(data, completed)
	for _, id in ipairs(GOALS) do
		local quest = data.quests[id]
		if quest and not completed[id] then
			return quest.level
		end
	end
end

-- The hand-in NPCs of `entries`, each with the books they take, sorted with the librarian's last so the journey ends at
-- the library. Only a hand-in the data places is offered.
---@param entries {book: AGFBook, quest: AGFQuest, id: integer}[]
---@param skipped table<string, boolean>
---@return {npc: integer?, name: string, place: AGFPlace, ids: integer[]}[]
local function Handins(entries, skipped)
	local groups, order = {}, {}
	for _, entry in ipairs(entries) do
		local finish = entry.book.finish
		local key = finish and "book:handin:" .. tostring(finish.npc or finish.name)
		if finish and finish.map and ValidPlace(finish) and not skipped[key] then
			---@cast key -?
			local at = finish --[[@as {map: integer, x: number, y: number, z?: integer, name: string, npc?: integer}]]
			local group = groups[key]
			if not group then
				local place = { map = at.map, x = at.x, y = at.y, z = at.z, name = at.name }
				group = { npc = at.npc, name = at.name, place = place, ids = {} }
				groups[key] = group
				order[#order + 1] = group
			end
			group.ids[#group.ids + 1] = entry.id
		end
	end
	for _, group in ipairs(order) do
		table.sort(group.ids)
	end
	table.sort(order, function(a, b)
		local librarianA, librarianB = LIBRARIANS[a.npc] and 1 or 0, LIBRARIANS[b.npc] and 1 or 0
		if librarianA ~= librarianB then
			return librarianA < librarianB
		end
		return a.name < b.name
	end)
	return order
end

-- The library journey card for this character, or nil when QuestieDB's books are not in, the card was turned down, or
-- this territory has nothing left to pick up and nobody to hand in to.
---@param data AGFData
---@param player AGFPlayer
---@param completed table<integer, boolean>
---@param log table<integer, AGFLogQuest>
---@param prefs AGFPrefs
---@param mapName? AGFMapName
---@return AGFJourney?
function Books.Card(data, player, completed, log, prefs, mapName)
	local dismissed, skipped = prefs.notInterested or NONE, prefs.skipped or NONE
	if not data.books or not data.territory or dismissed.library then
		return nil
	end
	local side = Territory(player, prefs)
	local entries = {}
	for _, book in ipairs(data.books) do
		local quest = data.quests[book.id]
		local key = "book:" .. book.id
		if
			quest
			and not completed[book.id]
			and ForClass(quest, player.classBit)
			and not dismissed["quest:" .. book.id]
			and not skipped[key]
		then
			local spot = Spot(data, book, side)
			-- A book with no spawn at all is unlocated and shows for either faction; one whose every spawn is the
			-- other faction's simply is not this territory's.
			if spot or #(book.spots or NONE) == 0 then
				entries[#entries + 1] = {
					book = book,
					quest = quest,
					spot = spot,
					id = book.id,
					held = log[book.id] ~= nil,
					order = Order(data, { book = book, quest = quest, spot = spot }),
				}
			end
		end
	end
	if #entries == 0 then
		return nil
	end
	table.sort(entries, function(a, b)
		return Before(a.order, b.order)
	end)
	-- The route is the next actions, not the whole library: up to MAX_STEPS stops, the hand-in last. A card hands in
	-- the books just picked up and any the player already carries, so the offered hand-in always matches the route.
	local handins = Handins(entries, skipped)
	local room = math.max(1, Model.MAX_STEPS - #handins)
	local batch = {}
	for _, entry in ipairs(entries) do
		if not entry.held and #batch < room then
			batch[#batch + 1] = entry
		end
	end
	local handed, held = {}, 0
	for _, entry in ipairs(entries) do
		if entry.held then
			held = held + 1
			handed[#handed + 1] = entry
		end
	end
	for _, entry in ipairs(batch) do
		-- A book with no spawn cannot be collected, so no hand-in counts it; its row only says where it is not.
		if entry.spot then
			handed[#handed + 1] = entry
		end
	end
	handins = Handins(handed, skipped)
	if #batch == 0 and #handins == 0 then
		return nil
	end
	local books = #batch + held
	local steps = {}
	for _, entry in ipairs(batch) do
		local area, zone = "", ""
		if entry.spot then
			area, zone = PlaceLine(data, entry.spot, mapName)
		end
		local step = {
			kind = "book",
			key = "book:" .. entry.id,
			title = entry.quest.title,
			detail = entry.spot and area .. (zone ~= area and (", " .. zone) or "") or L.BOOKS_UNLOCATED,
			reason = "",
			quests = { entry.id },
			zone = entry.spot and zone or nil,
			place = entry.spot and area or nil,
			unlocated = entry.spot == nil or nil,
		}
		if entry.spot then
			step.map, step.x, step.y, step.z = entry.spot.map, entry.spot.x, entry.spot.y, entry.spot.z
		end
		steps[#steps + 1] = step
	end
	for _, group in ipairs(handins) do
		local area, zone = PlaceLine(data, group.place, mapName)
		local count = #group.ids
		steps[#steps + 1] = {
			kind = "bookhandin",
			key = "book:handin:" .. tostring(group.npc or group.name),
			title = count == 1 and L.BOOKS_HANDIN_ONE:format(group.name) or L.BOOKS_HANDIN:format(count, group.name),
			detail = area .. (zone ~= area and (", " .. zone) or ""),
			reason = "",
			quests = group.ids,
			zone = zone,
			place = area,
			map = group.place.map,
			x = group.place.x,
			y = group.place.y,
			z = group.place.z,
		}
	end
	local map
	for _, step in ipairs(steps) do
		map = map or step.map
	end
	local journey = {
		kind = "library",
		key = "library",
		title = side == 2 and L.BOOKS_HORDE or L.BOOKS_ALLIANCE,
		subline = (books == 1 and L.BOOKS_THEN_LIBRARIAN_ONE or L.BOOKS_THEN_LIBRARIAN:format(books)),
		reason = L.BOOKS_SMALLER_FIRST,
		level = GoalLevel(data, completed),
		map = map or 0,
		steps = steps,
	}
	return journey --[[@as AGFJourney]]
end

ns.Planner.Books = Books --[[@as AGFBooksModule]]
