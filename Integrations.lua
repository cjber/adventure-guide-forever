---@type string, AGFNamespace
local _, ns = ...

---@class AGFIntegrationsModule : AGFIntegrations
local Integrations = {}
ns.Integrations = Integrations

-- Passed to Shortest Path so it can tell our journeys apart from the player's own.
local OWNER = "AdventureGuideForever"

-- The v1 members; types/Namespace.lua AGFSPFAPI is the contract, and tests/contract_spec.lua holds this list to
-- exactly its non-optional functions. A Shortest Path missing any of them is treated as absent.
local REQUIRED = { "Estimate", "Navigate", "NavigateRoute", "CurrentStop", "Cancel" }

---@return AGFSPFAPI?
local function SPF()
	local api = ShortestPathForever and ShortestPathForever.API
	if type(api) ~= "table" or api.version ~= 1 then
		return nil
	end
	for _, name in ipairs(REQUIRED) do
		if type(api[name]) ~= "function" then
			return nil
		end
	end
	---@cast api AGFSPFAPI
	return api
end

-- Step 1's travel line, fetched in its own frame after each rebuild (Core.lua), so the rebuild itself never asks
-- Shortest Path anything. No cache here: Shortest Path keeps its own for 5 s.
---@type {key: string, line: string?, minutes: integer?}?
local travel
---@type fun()[]
local travelListeners = {}

local L = ns.L
---@type table<AGFSPFMode, string>
local VERBS = {
	walk = L.TRAVEL_WALK,
	flight = L.TRAVEL_FLIGHT,
	boat = L.TRAVEL_BOAT,
	zeppelin = L.TRAVEL_ZEPPELIN,
	lift = L.TRAVEL_LIFT,
	tram = L.TRAVEL_TRAM,
	portal = L.TRAVEL_PORTAL,
	passage = L.TRAVEL_PASSAGE,
}

---@param seconds number
---@return integer
local function Minutes(seconds)
	return math.max(1, math.ceil(seconds / 60))
end

-- The first leg that isn't a walk, and the minutes until it arrives; a trip on foot names where it ends. A new
-- flight path on the way, and a wait of a minute or more for the chosen leg, are added (docs/plan.md F10).
---@param detail AGFSPFDetail
---@return string?
local function DetailLine(detail)
	local chosen, elapsed, newFlightPath = nil, 0, false
	for _, leg in ipairs(detail.legs) do
		newFlightPath = newFlightPath or (leg.mode == "walk" and leg.newFlightPath == true)
		if not chosen then
			elapsed = elapsed + leg.seconds
			chosen = leg.mode ~= "walk" and leg or nil
		end
	end
	chosen = chosen or detail.legs[#detail.legs]
	local verb = chosen and VERBS[chosen.mode]
	if not verb then
		return nil
	end
	return L.TRAVEL:format(verb:format(chosen.to), Minutes(elapsed))
		.. (newFlightPath and L.TRAVEL_NEW_FLIGHT_PATH or "")
		.. (chosen.wait and L.TRAVEL_WAIT:format(Minutes(chosen.wait)) or "")
end

-- The first boat or zeppelin leg's mode, which a card names when it has room.
---@param detail AGFSPFDetail
---@return AGFSPFMode?
local function Crossing(detail)
	for _, leg in ipairs(detail.legs) do
		if leg.mode == "boat" or leg.mode == "zeppelin" then
			return leg.mode
		end
	end
end

-- The travel line, the whole trip's minutes and any crossing, from one call.
---@param step AGFStep
---@return string? line
---@return integer? minutes
---@return AGFSPFMode? crossing
local function Fetch(step)
	local api = SPF()
	local player = ns.State.Player()
	if not (api and player.map and player.x and player.y) or InCombatLockdown() then
		return nil
	end
	if type(api.EstimateDetail) == "function" then
		local detail = api.EstimateDetail(player.map, player.x, player.y, step.map, step.x, step.y)
		if detail then
			return DetailLine(detail), Minutes(detail.seconds), Crossing(detail)
		end
		return nil
	end
	local seconds = api.Estimate(player.map, player.x, player.y, step.map, step.x, step.y)
	if seconds then
		return L.TRAVEL_ABOUT:format(Minutes(seconds)), Minutes(seconds)
	end
end

---@param step AGFStep
---@return string?
function Integrations.TravelLine(step)
	return (Fetch(step))
end

-- Tweaks Forever's spells to train (F16), from its API.lua when a version 1 is loaded.
---@return AGFTFSpell[]?
function Integrations.Trainable()
	local api = TweaksForever and TweaksForever.API
	if type(api) ~= "table" or api.version ~= 1 or type(api.TrainableSpells) ~= "function" then
		return nil
	end
	---@cast api AGFTFAPI
	return api.TrainableSpells()
end

-- The trainer line's count, fetched with the travel line and when the spellbook changes; nil (no Tweaks Forever,
-- no answer yet, nothing to train) means no line.
---@type string?
local trainer

local function NotifyTravel()
	for _, fn in ipairs(travelListeners) do
		fn()
	end
end

---@return boolean changed
local function RefreshTrainer()
	local spells = Integrations.Trainable()
	local count = spells and #spells or 0
	local line = count > 0 and (count == 1 and L.TRAINER_SPELL or L.TRAINER_SPELLS:format(count)) or nil
	local changed = line ~= trainer
	trainer = line
	return changed
end

---@return string?
function Integrations.Trainer()
	return trainer
end

-- In combat Shortest Path has no answer to give, so the last line stands and nothing is asked (docs/design.md §2.5).
function Integrations.RefreshTravel()
	if InCombatLockdown() then
		return
	end
	local step = ns.Route().steps[1]
	local line, minutes
	if step then
		line, minutes = Fetch(step)
	end
	local changed = (travel and travel.key) ~= (step and step.key)
		or (travel and travel.line) ~= line
		or (travel and travel.minutes) ~= minutes
	travel = step and { key = step.key, line = line, minutes = minutes } or nil
	if RefreshTrainer() or changed then
		NotifyTravel()
	end
end

-- A spell learned at the trainer shortens the line at once.
local spellbook = CreateFrame("Frame")
spellbook:RegisterEvent("SPELLS_CHANGED")
spellbook:SetScript("OnEvent", function()
	if not InCombatLockdown() and RefreshTrainer() then
		NotifyTravel()
	end
end)

-- The last fetched line, only for the step it was fetched for; never an SPF call.
---@param step AGFStep
---@return string?
function Integrations.Travel(step)
	return travel and travel.key == step.key and travel.line or nil
end

-- The whole trip's minutes, fetched with the line.
---@param step AGFStep
---@return integer?
function Integrations.TravelMinutes(step)
	return travel and travel.key == step.key and travel.minutes or nil
end

---@param fn fun()
function Integrations.OnTravelChange(fn)
	travelListeners[#travelListeners + 1] = fn
end

-- Each card's travel (docs/plan.md §7.4), keyed by its journey and first stop. While the guide is open and out of
-- combat, one estimate a frame asks Shortest Path, never in a rebuild's frame or step 1's travel frame: while one is
-- due (ns.Settling) the chain stops, and step 1's travel frame starts it again (ResumeCards), whatever order the
-- frame's timers run in. In combat the last answers stand. The chosen card's first stop is step 1's, which Shortest
-- Path has cached for 5 s.
---@type table<string, AGFCardTravel>
local cardTravel = {}
---@type AGFJourney[]
local cardQueue = {}
local chained = false
---@type fun()[]
local cardListeners = {}

---@param journey AGFJourney
---@return string
local function CardKey(journey)
	return journey.key .. ":" .. journey.steps[1].key
end

-- Where the player stands, so a card's answer knows where it was asked from.
---@return string?
local function Here()
	local player = ns.State.Player()
	return player.map and player.x and player.y and string.format("%d:%.4f:%.4f", player.map, player.x, player.y) or nil
end

local NextCard

-- The next queued card asks a frame on, unless a chain already will.
local function Chain()
	if cardQueue[1] and not chained then
		chained = true
		C_Timer.After(0, NextCard)
	end
end

-- A fight holds the queue; its end asks for the rest. Registered only while cards wait, so no event runs otherwise.
local afterCombat = CreateFrame("Frame")
afterCombat:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	Chain()
end)

function NextCard()
	chained = false
	if not (ns.PanelShown and ns.PanelShown()) then
		cardQueue = {}
		return
	elseif InCombatLockdown() then
		afterCombat:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	elseif ns.Settling() then
		return
	end
	-- The queue may have emptied since this frame was asked for: a route with nothing new to fetch.
	local journey = table.remove(cardQueue, 1)
	if journey then
		local line, minutes, crossing = Fetch(journey.steps[1])
		cardTravel[CardKey(journey)] = { line = line, minutes = minutes, crossing = crossing, from = Here() }
		for _, fn in ipairs(cardListeners) do
			fn()
		end
	end
	Chain()
end

-- The cards now shown (a new route, or the guide opening): answers for cards no longer shown go, and up to 3 cards
-- queue, a frame each, when they have no minutes or the player has moved since they asked, as step 1 asks again with
-- each route; a card's last answer stands until the new one.
---@param journeys AGFJourney[]
function Integrations.RefreshCards(journeys)
	local kept, here = {}, Here()
	cardQueue = {}
	for _, journey in ipairs(journeys) do
		local key = journey.steps[1] and CardKey(journey)
		if key then
			kept[key] = cardTravel[key]
			local fresh = kept[key] and kept[key].minutes and kept[key].from == here
			if not fresh and #cardQueue < ns.Model.MAX_JOURNEYS then
				cardQueue[#cardQueue + 1] = journey
			end
		end
	end
	cardTravel = kept
	if SPF() and not ns.Settling() then
		Chain()
	end
end

-- Step 1's travel frame is over (Core): the queued cards ask from the next frame.
function Integrations.ResumeCards()
	if SPF() then
		Chain()
	end
end

-- The card's last answer, never an SPF call.
---@param journey AGFJourney
---@return AGFCardTravel?
function Integrations.CardTravel(journey)
	return journey.steps[1] and cardTravel[CardKey(journey)] or nil
end

---@param fn fun()
function Integrations.OnCardTravel(fn)
	cardListeners[#cardListeners + 1] = fn
end

-- Go and Stop run from the footer, the step menu and the tracker; each tells these so the footer's Stop follows.
---@type fun()[]
local guidanceListeners = {}

---@param fn fun()
function Integrations.OnGuidanceChange(fn)
	guidanceListeners[#guidanceListeners + 1] = fn
end

local function NotifyGuidance()
	for _, fn in ipairs(guidanceListeners) do
		fn()
	end
end

-- True while Shortest Path is walking one of our multi-stop routes; it draws the numbered stops itself then.
---@return boolean
function Integrations.Guiding()
	local api = SPF()
	return api ~= nil and api.CurrentStop(OWNER) ~= nil
end

-- Go would replace a journey someone else started: the player's own, or another addon's (docs/design.md §2.9). Only
-- a Shortest Path with Active can tell; without it Go warns of nothing.
---@return boolean
function Integrations.ReplacesJourney()
	local api = SPF()
	return api ~= nil and type(api.Active) == "function" and api.Active() == true and api.CurrentStop(OWNER) == nil
end

-- What the last Go handed Shortest Path, which may no longer be the chosen journey's steps.
---@type (AGFStep|AGFGiver)[]
local guided = {}

---@return (AGFStep|AGFGiver)[]
function Integrations.Guided()
	return Integrations.Guiding() and guided or {}
end

-- With Shortest Path, the step and every step after it become one numbered journey. When it declines (it returns
-- false when it cannot plan the route) or is absent, the native waypoint takes the step instead, so Go always
-- leaves a destination on any map the client allows one on. True when something now guides the player.
---@param step AGFStep|AGFGiver
---@return boolean
function Integrations.Navigate(step)
	local api = SPF()
	-- Shortest Path refuses every route in combat, which is no sign it cannot plan this one: a journey an earlier Go
	-- started keeps guiding, and without one the waypoint takes the step as for any refusal.
	if api and InCombatLockdown() then
		if Integrations.Guiding() then
			return false
		end
		api = nil
	end
	if api then
		local stops, steps, found = {}, {}, false
		for _, each in ipairs(ns.Route().steps) do
			found = found or each == step
			if found then
				stops[#stops + 1] = { map = each.map, x = each.x, y = each.y, title = each.title }
				steps[#steps + 1] = each
			end
		end
		if not found then
			stops[1] = { map = step.map, x = step.x, y = step.y, title = step.title }
			steps[1] = step
		end
		if api.NavigateRoute(OWNER, stops) then
			-- Whatever this guides, ns.StartRoute says whether it is the chosen journey's.
			ns.Prefs().guided = nil
			guided = steps
			ns.Pins.Refresh()
			NotifyGuidance()
			return true
		end
	end
	if not C_Map.CanSetUserWaypointOnMap(step.map) then
		-- The red line the world map shows when a pin can't go on a map, so Go never fails silently. Any journey an
		-- earlier Go started keeps guiding: a failed Go changes nothing.
		UIErrorsFrame:AddExternalErrorMessage(ns.L.NO_WAYPOINT)
		return false
	end
	-- A refusal leaves the journey an earlier Go started drawn; the waypoint below replaces it.
	if api and api.Cancel(OWNER) then
		ns.Pins.Refresh()
	end
	C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(step.map, step.x, step.y))
	C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	-- Saved per character, so Stop still knows the waypoint as ours after a /reload.
	ns.Prefs().waypoint, ns.Prefs().guided = { map = step.map, x = step.x, y = step.y }, nil
	NotifyGuidance()
	return true
end

-- The native waypoint is ours while it is still where Go put it (x and y within 1e-4); once the player moves or clears
-- it, it is theirs, and the saved one is forgotten.
---@return boolean
local function OwnsWaypoint()
	local prefs = ns.Prefs()
	local saved, point = prefs.waypoint, C_Map.GetUserWaypoint()
	local same = saved ~= nil
		and point ~= nil
		and point.uiMapID == saved.map
		and math.abs(point.position.x - saved.x) < 1e-4
		and math.abs(point.position.y - saved.y) < 1e-4
	if not same then
		prefs.waypoint = nil
	end
	return same
end

---@return boolean
function Integrations.Owns()
	local owns = OwnsWaypoint()
	return owns or Integrations.Guiding()
end

-- Stop: ends only what Go started. Shortest Path's journey by our name, and the native waypoint only while it is ours.
function Integrations.Cancel()
	ns.Prefs().guided = nil
	local api = SPF()
	if api and api.Cancel(OWNER) then
		ns.Pins.Refresh()
	end
	if OwnsWaypoint() then
		C_Map.ClearUserWaypoint()
		C_SuperTrack.SetSuperTrackedUserWaypoint(false)
		ns.Prefs().waypoint = nil
	end
	NotifyGuidance()
end

---@return string?
function Integrations.Provider()
	if SPF() then
		return L.SHORTEST_PATH
	end
end
