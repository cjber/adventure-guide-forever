---@type string, AGFNamespace
local _, ns = ...

-- Read-only answers for other addons (docs/api.md). Nothing here rebuilds the route, starts guidance or hands out a
-- table the guide keeps: nil means the route is still settling, so ask again later.
---@class AGFAPI
local API = { version = 1 }

local NEXT_LIMIT = 8

---@param step AGFStep
---@return AGFAPIStop?
local function Stop(step)
	if not ns.Model.ValidPlace(step) then
		return nil
	end
	return {
		map = step.map,
		x = step.x,
		y = step.y,
		name = step.place or step.zone or step.title,
		isTown = step.kind == "town",
		handins = #ns.Model.Handins(step),
		pickups = step.pickups and #step.pickups or 0,
	}
end

-- The tracker's step and its place in the settled route.
---@return AGFStep?, integer?
local function Current()
	if not ns.RouteSettled() then
		return nil
	end
	local step = ns.Guidance.CurrentStep()
	for index, candidate in ipairs(ns.Route().steps) do
		if candidate == step then
			return step, index
		end
	end
end

---@return AGFAPIStop?
function API.CurrentStop()
	local step = Current()
	return step and Stop(step)
end

---@param limit? integer how many stops after the current one, 2 unless given
---@return AGFAPIStop[]?
function API.NextStops(limit)
	if limit == nil then
		limit = 2
	elseif type(limit) ~= "number" or limit < 0 or limit % 1 ~= 0 then
		return nil
	end
	local _, index = Current()
	if not index then
		return nil
	end
	local stops, steps = {}, ns.Route().steps
	for offset = 1, math.min(limit, NEXT_LIMIT) do
		local stop = steps[index + offset] and Stop(steps[index + offset])
		if not stop then
			break
		end
		stops[#stops + 1] = stop
	end
	return stops
end

AdventureGuideForever = AdventureGuideForever or {}
AdventureGuideForever.API = API
