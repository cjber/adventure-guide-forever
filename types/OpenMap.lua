---@meta

-- OpenMap's public API for other addons (major 1). Read-only: the guide asks where a route stop sits on the stitched
-- world and hears when stitching starts or stops, and never writes to OpenMap's state or settings.
---@class OpenMapAPI
---@field major number
---@field version number
---@field IsStitched fun(): boolean whether the world map shows OpenMap's stitched map now
---@field WorldFromMap fun(mapID: integer, x: number, y: number): number?, number? a point on a uiMap (0..1) on the stitched world
---@field MapFromWorld fun(mapID: integer, u: number, v: number): number?, number? a stitched world point on a uiMap, fractions that can run past 0..1
---@field RegisterCallback fun(owner: table|string, event: string, method: fun(event: string, ...: any))

---@type OpenMapAPI?
OpenMapAPI = nil
