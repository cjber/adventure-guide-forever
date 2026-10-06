---@type string, AGFNamespace
local _, ns = ...
local L = ns.L
---@class AGFRecommendations
local Recommendations = {}
ns.Recommendations = Recommendations
Recommendations.FOCUSES = { "balanced", "quests", "training", "professions", "dungeons" }

local function Offered(focus)
	for _, value in ipairs(Recommendations.FOCUSES) do
		if focus == value then
			return true
		end
	end
	return false
end

function Recommendations.Focus()
	local focus = ns.Prefs().recommendationFocus
	return Offered(focus) and focus --[[@as AGFRecommendationFocus]] or "balanced"
end

function Recommendations.SetFocus(focus)
	if Offered(focus) and focus ~= Recommendations.Focus() then
		ns.Prefs().recommendationFocus = focus
		ns.Window.Refresh()
	end
end

---@param route AGFRoute
---@param asides AGFAside[]
---@param focus AGFRecommendationFocus
---@param player AGFPlayer
---@return AGFRecommendation[]
function Recommendations.Build(route, asides, focus, player)
	local result, seen = {}, {}
	local function Journey(journey)
		local step = journey.steps[1]
		local key = "journey:" .. journey.key
		if not step or seen[key] then
			return
		end
		local dungeon = journey.kind == "dungeon" or journey.instance ~= nil
		if
			focus ~= "balanced"
			and not (
				focus == "dungeons" and dungeon
				or focus == "quests" and not dungeon and journey.kind ~= "battleground"
			)
		then
			return
		end
		seen[key] = true
		result[#result + 1] = {
			key = key,
			title = step.title,
			reason = step.reason or journey.reason or L.NEXT_REASON_JOURNEY:format(journey.title),
			icon = ns.Overview.KIND_ICONS[journey.kind],
			journey = journey.key,
			step = step,
		}
	end
	local function Aside(aside)
		local key = "aside:" .. aside.key
		if seen[key] or focus ~= "balanced" and focus ~= aside.category then
			return
		end
		seen[key] = true
		result[#result + 1] = {
			key = key,
			title = aside.text,
			reason = aside.reason or L.NEXT_REASON_ASIDE,
			icon = aside.texture or aside.icon,
			aside = aside,
		}
	end
	-- A chosen journey stays first even when paused. Nearby training precedes an unchosen route only.
	if not route.chosen and focus == "balanced" then
		for _, aside in ipairs(asides) do
			local place = aside.place
			local yards = place and place.map == player.map and ns.Model.Yards(ns.Data, player, place)
			if aside.category == "training" and yards and yards <= 600 then
				Aside(aside)
			end
		end
	end
	for _, journey in ipairs(route.journeys) do
		if journey.key == route.journey then
			Journey(journey)
		end
	end
	for _, aside in ipairs(asides) do
		Aside(aside)
	end
	for _, journey in ipairs(route.journeys) do
		Journey(journey)
	end
	return result
end

---@return AGFRecommendation[]
function Recommendations.Current()
	if not ns.RouteSettled() then
		return {}
	end
	return Recommendations.Build(ns.Route(), ns.Asides.All(), Recommendations.Focus(), ns.State.Player())
end

---@param item AGFRecommendation
---@return string
function Recommendations.ActionLabel(item)
	if item.aside then
		return L.GO
	end
	local route = ns.RouteSettled() and ns.Route()
	if route and route.chosen and item.journey == route.journey then
		if ns.Guidance.Status() == "paused" then
			return L.RESUME_ADVENTURE
		elseif ns.Prefs().guided == route.journey and ns.Guidance.Owns() then
			return L.SHOW_ON_MAP
		end
	end
	return L.START_ADVENTURE
end

---@param item AGFRecommendation
---@return boolean
function Recommendations.CanAct(item)
	local place = item.step or item.aside and item.aside.place
	return ns.RouteSettled()
		and not ns.Session.Info().pending
		and not InCombatLockdown()
		and not ns.Setting("wanderer")
		and ns.Model.ValidPlace(place)
end

---@param item AGFRecommendation
---@return boolean
function Recommendations.Act(item)
	if not Recommendations.CanAct(item) then
		return false
	end
	for _, current in ipairs(Recommendations.Current()) do
		if current.key == item.key then
			local before = item.step or item.aside and item.aside.place
			local now = current.step or current.aside and current.aside.place
			if
				not Recommendations.CanAct(current)
				or not before
				or not now
				or before.map ~= now.map
				or before.x ~= now.x
				or before.y ~= now.y
				or item.step and current.step and item.step.key ~= current.step.key
				or item.aside and current.aside and item.aside.renew ~= current.aside.renew
			then
				return false
			end
			if current.aside then
				return ns.Asides.Go(current.aside)
			end
			local route = ns.Route()
			if not route.chosen or route.journey ~= current.journey then
				ns.Choose(current.journey, true)
				return true
			elseif ns.Guidance.Status() == "paused" or ns.Prefs().guided ~= route.journey or not ns.Guidance.Owns() then
				return ns.StartRoute()
			end
			ns.Overview.ShowOnMap(current.step)
			return true
		end
	end
	return false
end
