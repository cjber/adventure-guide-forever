-- Dumps the test corpus as JSON lines for tools/check_refresh.py's refresh guard: one line per quest (in id order),
-- then one per book, with only the fields the guard compares. Run as:
--   luajit tools/corpus_dump.lua <corpus-dir> <out.jsonl>
-- <corpus-dir> holds quests.lua (a table keyed by quest id) and books.lua (a list), as tools/gen_corpus.py writes
-- them; absent fields are left out of the line. JSON is hand-rolled (LuaJIT ships no cjson) and object keys are
-- sorted, so the same corpus dumps byte for byte identically.
local corpus, output = ...
if not corpus or not output then
	error("usage: luajit tools/corpus_dump.lua <corpus-dir> <out.jsonl>")
end

local escapes = {
	['"'] = '\\"',
	["\\"] = "\\\\",
	["\b"] = "\\b",
	["\f"] = "\\f",
	["\n"] = "\\n",
	["\r"] = "\\r",
	["\t"] = "\\t",
}

local function json_string(value)
	local body = value:gsub('[%c"\\]', function(char)
		return escapes[char] or ("\\u%04x"):format(char:byte())
	end)
	return '"' .. body .. '"'
end

local json

local function json_table(value)
	-- An array is a table whose keys are exactly 1..n; anything else is an object with sorted keys.
	local count = 0
	local array = true
	for key in pairs(value) do
		count = count + 1
		if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > count then
			array = false
		end
	end
	if array then
		local items = {}
		for index = 1, count do
			items[index] = json(value[index])
		end
		return "[" .. table.concat(items, ",") .. "]"
	end
	local keys = {}
	for key in pairs(value) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	local parts = {}
	for _, key in ipairs(keys) do
		parts[#parts + 1] = json_string(key) .. ":" .. json(value[key])
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

function json(value)
	local kind = type(value)
	if kind == "nil" then
		return "null"
	elseif kind == "boolean" then
		return tostring(value)
	elseif kind == "number" then
		return ("%.14g"):format(value)
	elseif kind == "string" then
		return json_string(value)
	elseif kind == "table" then
		return json_table(value)
	end
	return error("cannot serialize a " .. kind)
end

-- A place keeps only where it is: the corpus's hub, name and npc stay in the corpus, not in the guard's view.
local function dump_place(place)
	if not place then
		return nil
	end
	return { map = place.map, x = place.x, y = place.y, z = place.z }
end

local function dump_ids(ids)
	if not ids then
		return nil
	end
	local list = {}
	for index, id in ipairs(ids) do
		list[index] = id
	end
	return list
end

local function dump_quest(id, quest)
	return {
		kind = "quest",
		id = id,
		level = quest.level,
		xp = quest.xp,
		min = quest.min,
		side = quest.side,
		start = dump_place(quest.start),
		finish = dump_place(quest.finish),
		pre = dump_ids(quest.pre),
		preAny = dump_ids(quest.preAny),
		next = quest.next,
		breadcrumb = quest.breadcrumb,
		group = quest.group,
		-- The corpus's dungeon field is the dungeon's map id, not a flag.
		dungeon = quest.dungeon,
		raid = quest.raid,
		repeatable = quest.repeatable,
		title = quest.title,
	}
end

local function dump_book(book)
	local spots = {}
	for index, spot in ipairs(book.spots or {}) do
		spots[index] = { map = spot.map, x = spot.x, y = spot.y }
	end
	local finish = book.finish
	return {
		kind = "book",
		id = book.id,
		spots = spots,
		finish = finish and { map = finish.map, npc = finish.npc } or nil,
	}
end

local quests = assert(dofile(corpus .. "/quests.lua"))
local books = assert(dofile(corpus .. "/books.lua"))
local ids = {}
for id in pairs(quests) do
	ids[#ids + 1] = id
end
table.sort(ids)
table.sort(books, function(first, second)
	return first.id < second.id
end)

local file = assert(io.open(output, "w"))
for _, id in ipairs(ids) do
	assert(file:write(json(dump_quest(id, quests[id])), "\n"))
end
for _, book in ipairs(books) do
	assert(file:write(json(dump_book(book)), "\n"))
end
assert(file:close())
print(("corpus_dump: %d quests, %d books -> %s"):format(#ids, #books, output))
