-- SavedVariables serializes these plain Lua tables as literals. Count the same deterministic representation before
-- (the previous expanded shape) and after packing so catalogue changes have a documented parse-size ceiling.
local harness = dofile("tests/harness.lua")

local function Write(value)
	local kind = type(value)
	if kind == "string" then
		return ("%q"):format(value)
	end
	if kind == "number" or kind == "boolean" then
		return tostring(value)
	end
	assert(kind == "table", "catalogue contains a non-serializable value: " .. kind)
	local parts, n = {}, #value
	for index = 1, n do
		if value[index] ~= nil then
			parts[#parts + 1] = "[" .. index .. "]=" .. Write(value[index])
		end
	end
	for key, item in pairs(value) do
		if type(key) ~= "number" or key < 1 or key > n then
			parts[#parts + 1] = "[" .. Write(key) .. "]=" .. Write(item)
		end
	end
	return "{" .. table.concat(parts, ",") .. "}"
end

-- Two places are the same when every field and value is.
local function SamePlace(a, b)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for key, value in pairs(a) do
		if not SamePlace(value, b[key]) then
			return false
		end
	end
	for key in pairs(b) do
		if a[key] == nil then
			return false
		end
	end
	return true
end

local source = harness.data()
local mirror = harness.questieMirror(source)
local built = harness.load({ questiedb = mirror, version = "0.8.0" })
assert(#built.errors == 0, table.concat(built.errors, "\n"))
local saved = built.G.AdventureGuideForeverCharDB.catalogue
-- A quest handed in where it was picked up saves its place once: `finish = false` stands for a copy of `start`, and
-- the build reads it back as before. A quest handed in elsewhere keeps its own place.
local finishField
for index, field in ipairs(saved.fields) do
	if field == "finish" then
		finishField = index
	end
end
assert(finishField ~= nil, "the catalogue names finish")
local shared, distinct = 0, 0
for id, quest in pairs(built.ns.Data.quests) do
	assert(quest.finish ~= false, ("quest %d kept a place the route can read"):format(id))
	local record = saved.data.quests[id]
	if quest.start ~= nil and SamePlace(quest.start, quest.finish) then
		shared = shared + 1
		assert(record[-finishField] == false, ("quest %d saved its start place twice"):format(id))
	elseif quest.finish ~= nil then
		distinct = distinct + 1
		assert(type(record[-finishField]) == "table", ("quest %d lost its finish place"):format(id))
	end
end
assert(shared > 0 and distinct > 0, ("a place saved once: %d shared, %d distinct"):format(shared, distinct))
local before = {
	key = saved.key,
	quests = built.ns.Data.quests,
	hubs = built.ns.Data.hubs,
	npcs = built.ns.Data.npcs,
}
local beforeBytes, afterBytes = #Write(before), #Write(saved)
assert(beforeBytes > afterBytes, ("packing did not shrink catalogue: %d -> %d bytes"):format(beforeBytes, afterBytes))
assert(afterBytes <= 1700000, ("saved catalogue exceeded 1,700,000 byte budget: %d"):format(afterBytes))
print(("catalogue serialized bytes: %d -> %d (budget 1,700,000)"):format(beforeBytes, afterBytes))
