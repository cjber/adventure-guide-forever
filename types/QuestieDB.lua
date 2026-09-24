---@meta

-- The part of QuestieDB's public API (the LibQuestieDB global, contract 2) that QuestieSource.lua reads, written from
-- its documented surface. QuestieDB is optional and has no licence, so nothing of its own types is copied here.

-- An entity reader: LibQuestieDB.Quest, .Npc or .Object.
---@class AGFQuestieEntity
---@field GetAll fun(id: integer, keys: string[]): table? the fields in `keys` order, with `n`; nil for an unknown ID

---@class AGFQuestieDB
---@field RequireContract fun(required: integer): boolean, string?
---@field Meta table<string, table<string, table<string, integer>>> e.g. Meta.QuestMeta.questKeys: field name -> index
---@field Quest AGFQuestieEntity
---@field Npc AGFQuestieEntity
---@field Object AGFQuestieEntity
---@field Support {Get: fun(module: string): table?} Get("ZoneDB"): its zone tables, some as Lua source

-- ZoneDB's tables as QuestieSource.lua reads them: area ID -> uiMapID, subzone -> zone, instance Map.ID -> area.
---@class AGFQuestieZones
---@field area table<integer, integer>
---@field areaOverride table<integer, integer>
---@field parent table<integer, integer>
---@field parentOverride table<integer, integer>
---@field instances table<integer, integer>

---@type AGFQuestieDB?
LibQuestieDB = nil
