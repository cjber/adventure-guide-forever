---@type string, AGFNamespace
local _, ns = ...
---@class AGFProviders
local Providers = {}
ns.Providers = Providers
local listeners, shown = {}, false
local unsubscribe, subscribed

local function Copy(value)
	if type(value) ~= "table" then
		return value
	end
	local result = {}
	for key, item in pairs(value) do
		result[key] = Copy(item)
	end
	return result
end

local function Point(point)
	return type(point) == "table"
		and type(point.map) == "number"
		and point.map > 0
		and type(point.x) == "number"
		and point.x >= 0
		and point.x <= 1
		and type(point.y) == "number"
		and point.y >= 0
		and point.y <= 1
end

local function Legacy()
	local api = LegacyForever and LegacyForever.API
	if not LegacyForever then
		return nil, "missing"
	end
	if type(api) ~= "table" or type(api.version) ~= "number" or api.version < 1 then
		return nil, "outdated"
	end
	for _, name in ipairs({ "ZoneSummary", "Targets", "Navigate", "Subscribe" }) do
		if type(api[name]) ~= "function" then
			return nil, "outdated"
		end
	end
	return api, "ready"
end

function Providers.LegacyState()
	local _, state = Legacy()
	return state
end

local function Notify()
	for _, fn in ipairs(listeners) do
		fn()
	end
end

function Providers.OnChange(callback)
	listeners[#listeners + 1] = callback
end

function Providers.SetShown(value)
	shown = value
	local api = shown and Legacy() or nil
	if api == subscribed then
		return
	end
	if unsubscribe then
		unsubscribe()
	end
	subscribed, unsubscribe = api, nil
	if api then
		unsubscribe = api.Subscribe(Notify)
	end
end

function Providers.Completion()
	local api, state = Legacy()
	local result = { state = state, zones = {} }
	if not api then
		return result
	end
	local maps, seen = {}, {}
	local function Add(map)
		if map and not seen[map] and #maps < 4 then
			maps[#maps + 1], seen[map] = map, true
		end
	end
	Add(ns.State.Player().map)
	local route = ns.Route()
	for pass = 1, 2 do
		for _, journey in ipairs(route.journeys) do
			if journey.kind == "story" or journey.kind == "nextzone" then
				if (pass == 1) == (route.chosen and journey.key == route.journey) then
					Add(tonumber(journey.key:match("^zone:(%d+)$")) or journey.map)
				end
			end
		end
	end
	for _, map in ipairs(maps) do
		local summary, err = api.ZoneSummary(map)
		local targets, targetError = api.Targets(map, 3)
		local zone =
			{ map = map, name = ns.State.MapName(map) or tostring(map), targets = {}, error = err or targetError }
		zone.summary = Copy(summary)
		if summary then
			zone.name = summary.name
			-- Empty or pending categories never prove completion.
			zone.summary.complete = #summary.categories > 0
				and summary.total > 0
				and summary.pending == 0
				and summary.done == summary.total
				and summary.complete == true
		end
		for index, target in ipairs(targets or {}) do
			if index > 3 then
				break
			end
			local copy = Copy(target)
			if not Point(copy.place) then
				copy.place = nil
			end
			zone.targets[#zone.targets + 1] = copy
		end
		result.zones[#result.zones + 1] = zone
	end
	return result
end

function Providers.NavigateCompletion(map, key)
	local api, state = Legacy()
	if not api then
		return false, state
	end
	if ns.Setting("wanderer") then
		return false, "unavailable"
	end
	return api.Navigate(map, key)
end

function Providers.DungeonEntrance(instanceID)
	local api = TweaksForever and TweaksForever.API
	if not TweaksForever then
		return nil, "missing"
	end
	if
		type(api) ~= "table"
		or type(api.version) ~= "number"
		or api.version < 1
		or type(api.DungeonEntrance) ~= "function"
	then
		return nil, "outdated"
	end
	local point = api.DungeonEntrance(instanceID)
	if not Point(point) then
		return nil, "unknown"
	end
	return { map = point.map, x = point.x, y = point.y }
end

function Providers.GoToEntrance(instanceID)
	local point, err = Providers.DungeonEntrance(instanceID)
	if not point then
		return false, err
	end
	return ns.Integrations.Navigate({
		map = point.map,
		x = point.x,
		y = point.y,
		kind = "dungeon",
		key = "entrance:" .. instanceID,
		quests = {},
		title = ns.L.GO_TO_ENTRANCE,
		reason = "",
		detail = "",
	})
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent", function(_, _, name)
	if name == "LegacyForever" or name == "TweaksForever" then
		Providers.SetShown(shown)
		Notify()
	end
end)
