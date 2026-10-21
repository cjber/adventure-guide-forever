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

local source = harness.data()
local mirror = harness.questieMirror(source)
local built = harness.load({ questiedb = mirror, version = "0.8.0" })
assert(#built.errors == 0, table.concat(built.errors, "\n"))
local saved = built.G.AdventureGuideForeverCharDB.catalogue
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
