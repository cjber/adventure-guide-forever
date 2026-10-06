-- Read one installed AtlasLoot table for the mock, without vendoring its data.
local json = dofile("tests/json.lua")
local file = assert(io.open(assert(arg[1])))
local source = file:read("*a")
file:close()
local first = assert(source:find('data["WailingCaverns"]', 1, true))
local last = assert(source:find('data["TheDeadmines"]', first, true))
local data = {}
local env = {
	data = data,
	AL = setmetatable({}, {
		__index = function(_, key)
			return key
		end,
	}),
	C_Map = {
		GetAreaInfo = function()
			return "Wailing Caverns"
		end,
	},
	LTNX = "",
	NORMAL_DIFF = 1,
	DUNGEON_CONTENT = 1,
	ATLAS_MODULE_NAME = "Atlas_ClassicWoW",
	GetForVersion = function(classic)
		return classic
	end,
}
local chunk = assert(loadstring(source:sub(first, last - 1)))
setfenv(chunk, env)
chunk()
local content = data.WailingCaverns
local bosses = {}
for _, boss in ipairs(content.items) do
	local drops = {}
	for _, row in ipairs(boss[1] or {}) do
		if type(row[2]) == "number" and row[2] > 0 then
			drops[#drops + 1] = { row[1], row[2] }
		end
	end
	bosses[#bosses + 1] = { name = boss.name, npcID = boss.npcID, ["1"] = drops }
end
print(json.encode({ WailingCaverns = { InstanceID = content.InstanceID, items = bosses } }, "%.0f"))
