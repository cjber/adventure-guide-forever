---@type string, AGFNamespace
local _, ns = ...

if ns.broken then
	return
end

-- OpenMap, the seamless world map addon, offers other addons a small read-only API through the global OpenMapAPI
-- (major 1): `IsStitched` says whether the world map is showing OpenMap's stitched map now, `WorldFromMap` puts a
-- point on one uiMap (0..1) on that stitched world, and `MapFromWorld` puts a stitched world point back on a uiMap,
-- in fractions that can run past 0..1 into the neighbouring zones. The guide reads those to draw the route's stops
-- in the zones around the map's own while it is stitched together, and registers one callback on
-- "OpenMap_StitchedChanged" so stitching starting or stopping redraws. Nothing here writes to OpenMap, to its
-- settings or to Blizzard's map. Without OpenMap, with another major version, or while it is not stitching, every
-- caller draws its own map's stops exactly as before.

---@class AGFOpenMapModule
---@field API fun(): OpenMapAPI?
---@field Stitched fun(): boolean
---@field Place fun(step: AGFStep, hostMapID: integer): number?, number?
---@field OnStitchedChanged fun(fn: fun())
local OpenMap = {}
ns.OpenMapStitch = OpenMap

local CALLBACK = "OpenMap_StitchedChanged"

-- OpenMapAPI when it is loaded, nil otherwise.
---@return OpenMapAPI?
function OpenMap.API()
	local api = OpenMapAPI
	if type(api) ~= "table" or api.major ~= 1 then
		return nil
	end
	return api
end

-- Whether the world map is showing OpenMap's stitched map now. The read is another addon's code, so it goes through
-- ns.core.SafeCall: a failure there leaves the guide drawing as without OpenMap.
---@return boolean
function OpenMap.Stitched()
	local api = OpenMap.API()
	if not (api and type(api.IsStitched) == "function") then
		return false
	end
	local ok, stitched = ns.core.SafeCall("OpenMap stitched", api.IsStitched)
	return ok and stitched == true
end

-- `step`'s point in `hostMapID`'s fractions: its own point on that map, or on the stitched map while OpenMap joins
-- the zones around it. nil when it is not stitching or OpenMap cannot place the point.
---@param step AGFStep
---@param hostMapID integer
---@return number?, number?
function OpenMap.Place(step, hostMapID)
	if step.map == hostMapID then
		return step.x, step.y
	end
	if not OpenMap.Stitched() then
		return nil, nil
	end
	local api = OpenMap.API()
	if not api or type(api.WorldFromMap) ~= "function" or type(api.MapFromWorld) ~= "function" then
		return nil, nil
	end
	local placed, u, v = ns.core.SafeCall("OpenMap world point", api.WorldFromMap, step.map, step.x, step.y)
	if not placed or type(u) ~= "number" or type(v) ~= "number" then
		return nil, nil
	end
	local mapped, x, y = ns.core.SafeCall("OpenMap map point", api.MapFromWorld, hostMapID, u, v)
	if not mapped or type(x) ~= "number" or type(y) ~= "number" then
		return nil, nil
	end
	return x, y
end

---@type fun()[]
local listeners = {}
local registered = false

local function Notify()
	for _, fn in ipairs(listeners) do
		fn()
	end
end

-- Registers with OpenMap once it is loaded. An older or absent OpenMap never calls back, and the guide draws as
-- before.
local function Register()
	if registered then
		return
	end
	local api = OpenMap.API()
	if not (api and type(api.RegisterCallback) == "function") then
		return
	end
	registered = ns.core.SafeCall("OpenMap callback", api.RegisterCallback, OpenMap, CALLBACK, Notify) == true
end

-- Calls `fn` whenever OpenMap switches between its stitched map and Blizzard's own. OpenMap may load after us.
---@param fn fun()
function OpenMap.OnStitchedChanged(fn)
	listeners[#listeners + 1] = fn
	Register()
	if not registered then
		EventUtil.ContinueOnAddOnLoaded("OpenMap", Register)
	end
end
