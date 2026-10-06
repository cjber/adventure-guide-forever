---@type string, AGFNamespace
local _, ns = ...
local MODULE = "AtlasLootClassic_DungeonsAndRaids"
---@class AGFLootBoss
---@field name string
---@field npcID integer
---@field items integer[]
local Loot = {}
local attemptedSource
ns.DungeonLoot = Loot

-- AtlasLoot resolves linked loot tables and difficulty inheritance through this public API.
---@param instance integer
---@return AGFLootBoss[]
---@return string? hint
function Loot.Bosses(instance)
	local atlas = AtlasLoot
	if not atlas or not atlas.ItemDB then
		return {}, ns.L.DUNGEON_LOOT_INSTALL
	end
	local database = atlas.ItemDB:Get(MODULE)
	if not database and atlas.Loader and attemptedSource ~= atlas and not InCombatLockdown() then
		attemptedSource = atlas
		atlas.Loader:LoadModule(MODULE)
		database = atlas.ItemDB:Get(MODULE)
	end
	if not database then
		return {}, InCombatLockdown() and ns.L.DUNGEON_LOOT_COMBAT or ns.L.DUNGEON_LOOT_INSTALL
	end
	local bosses = {}
	local keys = {}
	for key, content in pairs(database) do
		if type(content) == "table" and content.InstanceID == instance and content.items then
			keys[#keys + 1] = key
		end
	end
	table.sort(keys)
	local seen = {}
	for _, key in ipairs(keys) do
		local content = database[key]
		for index, boss in ipairs(content.items) do
			local npcID = type(boss.npcID) == "table" and boss.npcID[1] or boss.npcID
			if type(npcID) == "number" and not seen[npcID] then
				local ok, items =
					pcall(atlas.ItemDB.GetItemTable, atlas.ItemDB, MODULE, key, index, content.LoadDifficulty or 1)
				local drops, dropped = {}, {}
				if ok and type(items) == "table" then
					for _, entry in ipairs(items) do
						local id = entry[2]
						if type(id) == "number" and id > 0 and not dropped[id] then
							drops[#drops + 1], dropped[id] = id, true
						end
					end
					seen[npcID] = true
					bosses[#bosses + 1] = { name = boss.name, npcID = npcID, items = drops }
				end
			end
		end
	end
	return bosses, #bosses == 0 and ns.L.DUNGEON_LOOT_UNKNOWN or nil
end
