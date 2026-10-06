---@meta
---@class AGFPoint
---@field map integer
---@field x number
---@field y number

---@class AGFProviders
---@field OnChange fun(callback: fun())
---@field DungeonEntrance fun(instanceID: integer): AGFPoint?, string?

---@class AGFPvPRank
---@field state "unavailable"|"unranked"|"ranked"|"capped"
---@field level? integer
---@field earned? number
---@field threshold? number
---@field maxLevel? integer
---@field reward? {level: integer, text: string, icon?: number}
---@class AGFPvPBattle
---@field id integer
---@field name string
---@field level integer
---@field npc? integer
---@field place? AGFPlace
---@class AGFPvP
---@field Data fun(): {rank: AGFPvPRank, battlegrounds: AGFPvPBattle[], available: boolean}
---@field Go fun(id: integer): boolean

---@class AGFTFAPI
---@field DungeonEntrance? fun(instanceID: integer): AGFPoint?
