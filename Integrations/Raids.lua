---@type string, AGFNamespace
local _, ns = ...

-- The raid tier registry (docs/dungeon-sources.md). WoW: Forever's announced raids are the 10-player Barrow Deeps
-- and the 20-player Hyjal Summit, with the returning 40-player Onyxia's Lair; launch raids need no attunement.
-- Barrow Deeps and Hyjal Summit have no client Map.ID in this build, so they stay listed here and enter the browser
-- once their rows are given a `map`. The remaining raid Map.IDs the client still carries are not the announced
-- tier; they stay browsable under their own heading, and none of them claims a Classic attunement page.

---@class AGFRaid
---@field name string
---@field players integer
---@field low integer recommended minimum level
---@field high integer recommended maximum level
---@field map? integer client Map.ID; absent while the build carries no map for the raid
---@field current? boolean an announced Forever raid tier

---@type AGFRaid[]
ns.Raids = {
	{ name = "Barrow Deeps", players = 10, low = 60, high = 60, current = true },
	{ name = "Hyjal Summit", players = 20, low = 60, high = 60, current = true },
	{ name = "Onyxia's Lair", map = 249, players = 40, low = 60, high = 60, current = true },
	-- Client-present raid maps, not part of the announced Forever tier.
	{ name = "Zul'Gurub", map = 309, players = 20, low = 60, high = 60 },
	{ name = "Ruins of Ahn'Qiraj", map = 509, players = 20, low = 60, high = 60 },
	{ name = "Molten Core", map = 409, players = 40, low = 60, high = 60 },
	{ name = "Blackwing Lair", map = 469, players = 40, low = 60, high = 60 },
	{ name = "Ahn'Qiraj Temple", map = 531, players = 40, low = 60, high = 60 },
	{ name = "Naxxramas", map = 533, players = 40, low = 60, high = 60 },
}

---@type table<integer, AGFRaid>
ns.RaidByMap = {}
for _, raid in ipairs(ns.Raids) do
	if raid.map then
		ns.RaidByMap[raid.map] = raid
	end
end
