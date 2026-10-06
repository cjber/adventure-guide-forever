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

-- The first leg that isn't a walk, and the minutes until it arrives; a trip on foot names the step's place, else the
-- step's own title, the stop we hand Shortest Path (it names only the zone a leg ends in). A new flight path on the
-- way, and a wait of a minute or more for the chosen leg, are added.
---@param detail AGFSPFDetail
---@param step AGFStep
---@return string?
local function DetailLine(detail, step)
	local chosen, elapsed, newFlightPath = nil, 0, false
	for _, leg in ipairs(detail.legs) do
		newFlightPath = newFlightPath or (leg.mode == "walk" and leg.newFlightPath == true)
		if not chosen then
			elapsed = elapsed + leg.seconds
			chosen = leg.mode ~= "walk" and leg or nil
		end
	end
	local onFoot = not chosen
	chosen = chosen or detail.legs[#detail.legs]
	local verb = chosen and VERBS[chosen.mode]
	if not verb then
		return nil
	end
	return L.TRAVEL:format(verb:format(onFoot and (step.place or step.title) or chosen.to), Minutes(elapsed))
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
			return DetailLine(detail, step), Minutes(detail.seconds), Crossing(detail)
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

local function NotifyTravel()
	for _, fn in ipairs(travelListeners) do
		fn()
	end
end

-- In combat Shortest Path has no answer to give, so the last line stands and nothing is asked (docs/design.md §2.5).
-- The area the player stands in has none: they are there, and a walk to its middle is no way to go.
function Integrations.RefreshTravel()
	if InCombatLockdown() then
		return
	end
	local step = ns.Route().steps[1]
	local line, minutes
	if step and not step.here then
		line, minutes = Fetch(step)
	end
	local changed = (travel and travel.key) ~= (step and step.key)
		or (travel and travel.line) ~= line
		or (travel and travel.minutes) ~= minutes
	travel = step and { key = step.key, line = line, minutes = minutes } or nil
	if changed then
		NotifyTravel()
	end
end

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

-- Each card's travel, keyed by its journey and first stop. While the guide is open and out of
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
	if (cardQueue[1] or ns.Session.PendingWork()) and not chained then
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
	if not ns.Session.PendingWork() and not (ns.PanelShown and ns.PanelShown()) then
		cardQueue = {}
		return
	elseif InCombatLockdown() then
		afterCombat:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	elseif ns.Settling() then
		return
	end
	-- The queue may have emptied since this frame was asked for: a route with nothing new to fetch.
	if ns.Session.PendingWork() then
		local api = SPF()
		if api and ns.Session.NextEstimate(api) then
			Chain()
		end
		return
	end
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

-- The cards now shown (a new route, or the guide opening): answers for cards no longer shown go, and every card
-- queues, a frame each, when it has no minutes or the player has moved since it asked, as step 1 asks
-- again with each route; a card's last answer stands until the new one.
---@param journeys AGFJourney[]
function Integrations.RefreshCards(journeys)
	local kept, here = {}, Here()
	cardQueue = {}
	for _, journey in ipairs(journeys) do
		local key = journey.steps[1] and CardKey(journey)
		if key then
			kept[key] = cardTravel[key]
			local fresh = kept[key] and kept[key].minutes and kept[key].from == here
			if not fresh then
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

-- True while Shortest Path is walking one of our multi-stop routes; it draws the numbered stops itself then. With its
-- "Guide me" off (Active false) the route is held, not guided: it draws nothing, so the rings come back.
---@return boolean
function Integrations.Guiding()
	local api = SPF()
	return api ~= nil and api.CurrentStop(OWNER) ~= nil and (type(api.Active) ~= "function" or api.Active() == true)
end

-- Go would replace a journey someone else started: the player's own, or another addon's (docs/design.md §2.9). Only
-- a Shortest Path with Active can tell; without it Go warns of nothing.
---@return boolean
function Integrations.ReplacesJourney()
	local api = SPF()
	return api ~= nil and type(api.Active) == "function" and api.Active() == true and api.CurrentStop(OWNER) == nil
end

-- What stands at a step, in Shortest Path's words, so its stop pin shows the game's own mark there rather than hiding
-- it. A Shortest Path that predates kinds ignores them.
---@type table<AGFStepKind, AGFSPFStopKind>
local KINDS = {
	turnin = "turnin",
	area = "objective",
	dungeon = "dungeon",
	trainer = "trainer",
	battlemaster = "battlemaster",
}

-- A town's point is one of its quests' places: the "?" when a hand-in is there, else a giver's "!". A giver is a "!".
---@param step AGFStep|AGFGiver
---@return AGFSPFStopKind?
function Integrations.Kind(step)
	if step.verb == "objective" then
		return "objective"
	end
	local kind = step.kind --[[@as AGFStepKind?]]
	if kind and kind ~= "town" then
		return KINDS[kind]
	end
	for _, id in ipairs(step.handins or {}) do
		local spot = step.spots and step.spots[id]
		if spot and spot.map == step.map and spot.x == step.x and spot.y == step.y then
			return "turnin"
		end
	end
	return "pickup"
end

-- An area step's objective shapes for Shortest Path (its own `shapes`): each on the map it already is, with its
-- yard radius. The nearest shape's radius is also the stop's reach. The area also names its quests, so Shortest Path
-- can ask the client's own inside-area state for them and show the game's own quest area instead of trusting the
-- circles. An area of exactly one quest names it as `questID` too, the only form older Shortest Path versions read.
---@param step AGFStep|AGFGiver
---@return AGFSPFShape[]?
---@return number?
---@return integer?
---@return integer[]?
local function Shapes(step)
	local kind = step.kind --[[@as AGFStepKind?]]
	if kind ~= "area" then
		return
	end
	local area = step --[[@as AGFStep]]
	local shapes, radius = {}, 30
	for _, shape in ipairs(area.shapes or {}) do
		shapes[#shapes + 1] = { map = shape.map, x = shape.x, y = shape.y, radius = shape.r }
		if shape.map == area.map and shape.x == area.x and shape.y == area.y then
			radius = math.max(radius, shape.r)
		end
	end
	local quests = area.quests or {}
	local questIDs = #quests > 0 and { unpack(quests) } or nil
	return #shapes > 0 and shapes or nil, radius, #quests == 1 and quests[1] or nil, questIDs
end

---@param steps (AGFStep|AGFGiver)[]
---@return AGFSPFStop[]
local function Stops(steps, hold)
	local stops = {}
	for index, step in ipairs(steps) do
		local shapes, radius, questID, questIDs = Shapes(step)
		stops[index] = {
			map = step.map,
			x = step.x,
			y = step.y,
			-- Shortest Path words its steps around this ("Walk to ..."), so a town is named, not described.
			title = step.kind == "town" and step.place or step.title,
			tooltip = ns.Pins.StopTooltip(step),
			kind = Integrations.Kind(step),
			radius = radius,
			questID = questID,
			questIDs = questIDs,
			shapes = shapes,
			hold = hold == true
				and step.kind ~= "trainer"
				and step.kind ~= "battlemaster"
				and (#(step.quests or {}) > 0 or #(step.handins or {}) > 0),
		}
	end
	return stops
end
-- The seam to whatever draws the way (Guidance.lua is its one caller): Shortest Path's journey by our name, and the
-- client's own waypoint. Nothing here remembers what was handed or whose it is; Guidance does.

-- Hands Shortest Path the steps as one numbered journey of ours, replacing any it held. With `hold` a stop with quests
-- stays until the journey is handed again, so standing in its first town or objective area keeps the whole route
-- visible. False when it is absent or refuses.
---@param steps (AGFStep|AGFGiver)[]
---@param hold? boolean
---@return boolean
function Integrations.Hand(steps, hold)
	local api = SPF()
	return api ~= nil and api.NavigateRoute(OWNER, Stops(steps, hold)) and true or false
end

-- Ends Shortest Path's journey by our name, never anyone else's. True when it ended one.
---@return boolean
function Integrations.Drop()
	local api = SPF()
	return api ~= nil and api.Cancel(OWNER) and true or false
end

-- The stop of our journey Shortest Path heads for, guiding it or not; nil when it holds none of ours.
---@return integer?
function Integrations.CurrentStop()
	local api = SPF()
	if api then
		return api.CurrentStop(OWNER)
	end
end

-- Why our journey ended: Shortest Path's Ended when it has it; otherwise guessed. Another journey running replaced
-- it, the player standing in its last stop's town (or inside its area ring) arrived, and anything else was cleared.
---@param last? AGFStep|AGFGiver the last stop it was handed
---@return string?
function Integrations.EndReason(last)
	local api = SPF()
	if not api then
		return nil
	elseif type(api.Ended) == "function" then
		return (api.Ended(OWNER))
	elseif type(api.Active) == "function" and api.Active() then
		return "replaced"
	end
	local player = ns.State.Player()
	local arrived = last
		and player.map
		and (
			(last.hub ~= nil and ns.Model.Hub(ns.Data, player) == last.hub)
			or (
				ns.Model.Yards(ns.Data, player --[[@as AGFStep]], last) or math.huge
			) <= (last.r or 0)
		)
	return arrived and "arrived" or "cleared"
end

-- The client's waypoint still sits at `place` (x and y within 1e-4): once the player moves or clears it, it does not.
---@param place? {map: integer, x: number, y: number}
---@return boolean
function Integrations.WaypointAt(place)
	local point = C_Map.GetUserWaypoint()
	return place ~= nil
		and point ~= nil
		and point.uiMapID == place.map
		and math.abs(point.position.x - place.x) < 1e-4
		and math.abs(point.position.y - place.y) < 1e-4
end

---@param map integer
---@return boolean
function Integrations.CanWaypoint(map)
	return C_Map.CanSetUserWaypointOnMap(map)
end

-- The client's waypoint goes to `place`; with `track` the arrow follows it, as a Go asks.
---@param place {map: integer, x: number, y: number}
---@param track? boolean
function Integrations.SetWaypoint(place, track)
	C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(place.map, place.x, place.y))
	if track then
		C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	end
end

function Integrations.ClearWaypoint()
	C_Map.ClearUserWaypoint()
	C_SuperTrack.SetSuperTrackedUserWaypoint(false)
end

-- A developer diagnostic for the travel line and guidance state (/agf travel): why a step shows no Shortest Path line
-- is otherwise invisible headlessly. Raw literals on purpose (returned, never passed straight to Print). `guidance` is
-- Guidance's own part of the line.
---@param guidance string
---@return string
function Integrations.Debug(guidance)
	local step = ns.Route().steps[1]
	local api = SPF()
	return ("spf=%s guiding=%s %s step1=%s here=%s line=%s min=%s combat=%s taxi=%s"):format(
		tostring(api ~= nil),
		tostring(Integrations.Guiding()),
		guidance,
		tostring(step and step.key),
		tostring(step and step.here),
		tostring(travel and travel.line),
		tostring(travel and travel.minutes),
		tostring(InCombatLockdown()),
		tostring(UnitOnTaxi("player"))
	)
end

---@return string?
function Integrations.Provider()
	if SPF() then
		return L.SHORTEST_PATH
	end
end
