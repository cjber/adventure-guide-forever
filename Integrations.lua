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

-- The first leg that isn't a walk, and the minutes until it arrives; a trip on foot names where it ends, the step's
-- town when it has one (Shortest Path names only the zone). A new flight path on the way, and a wait of a minute or
-- more for the chosen leg, are added (docs/plan.md F10).
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
	return L.TRAVEL:format(verb:format(onFoot and step.place or chosen.to), Minutes(elapsed))
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

-- Tweaks Forever's spells to train (F16), from its API.lua when a version 1 is loaded, for the trainer aside
-- (Asides.lua) and a chosen journey's trainer stop (roadmap #5): how many, and the highest level among them. Nil
-- without Tweaks Forever or its answer, and with nothing to train.
---@return AGFTraining?
function Integrations.Training()
	local api = TweaksForever and TweaksForever.API
	if type(api) ~= "table" or api.version ~= 1 or type(api.TrainableSpells) ~= "function" then
		return nil
	end
	---@cast api AGFTFAPI
	local spells = api.TrainableSpells()
	if not spells or #spells == 0 then
		return nil
	end
	local level = 0
	for _, spell in ipairs(spells) do
		level = math.max(level, spell.level)
	end
	return { count = #spells, level = level }
end

local function NotifyTravel()
	for _, fn in ipairs(travelListeners) do
		fn()
	end
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

-- The cards now shown (a new route, or the guide opening): answers for cards no longer shown go, and every card
-- (MAX_JOURNEYS) queues, a frame each, when it has no minutes or the player has moved since it asked, as step 1 asks
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

-- True while Shortest Path holds one of our multi-stop routes, guiding it or not.
---@param api? AGFSPFAPI
---@return boolean
local function Ours(api)
	return api ~= nil and api.CurrentStop(OWNER) ~= nil
end

-- True while Shortest Path is walking one of our multi-stop routes; it draws the numbered stops itself then. With its
-- "Guide me" off (Active false) the route is held, not guided: it draws nothing, so the rings come back.
---@return boolean
function Integrations.Guiding()
	local api = SPF()
	return api ~= nil and Ours(api) and (type(api.Active) ~= "function" or api.Active() == true)
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
-- Shortest Path held our journey at the last look, and it ended at its last stop since.
local ours, arrived = false, false
-- The chosen journey whose route the player cleared or another journey replaced, until something is handed again.
---@type string?
local stopped

-- Yards past which a stop's point has moved (a town's point moving to its next giver): the town linkage
-- (tools/gen_quests.py LINK). Nearer, the stock "!" and "?" marks show the way.
local LINK = 100

-- What stands at a step, in Shortest Path's words, so its stop pin shows the game's own mark there rather than hiding
-- it. A Shortest Path that predates kinds ignores them.
---@type table<AGFStepKind, AGFSPFStopKind>
local KINDS = {
	turnin = "turnin",
	objective = "objective",
	dungeon = "dungeon",
	trainer = "trainer",
	battlemaster = "battlemaster",
}

-- A town's point is one of its quests' places: the "?" when a hand-in is there, else a giver's "!". A giver is a "!".
---@param step AGFStep|AGFGiver
---@return AGFSPFStopKind?
function Integrations.Kind(step)
	local kind = step.kind --[[@as AGFStepKind?]]
	if kind and kind ~= "hub" then
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

---@param steps (AGFStep|AGFGiver)[]
---@return AGFSPFStop[]
local function Stops(steps)
	local stops = {}
	for index, step in ipairs(steps) do
		stops[index] = { map = step.map, x = step.x, y = step.y, title = step.title, kind = Integrations.Kind(step) }
	end
	return stops
end

-- Every quest start and finish in each town, by hub, built on first use of each ns.Data (QuestieSource.lua swaps it).
---@type table<integer, AGFPlace[]>
local hubPlaces = {}
---@type AGFData?
local hubPlacesOf

-- The player stands in `step`'s town: within the town linkage of any of its quests' places, the extent the generator
-- drew the town by, whatever work is left there. A town the generator could not place is its point alone.
---@param player AGFPlayer
---@param step AGFStep
---@return boolean
local function InTown(player, step)
	local places = { step }
	if step.hub then
		if hubPlacesOf ~= ns.Data then
			hubPlaces, hubPlacesOf = {}, ns.Data
			for _, quest in pairs(ns.Data.quests) do
				for _, place in ipairs({ quest.start or false, quest.finish or false }) do
					if place and place.hub then
						hubPlaces[place.hub] = hubPlaces[place.hub] or {}
						table.insert(hubPlaces[place.hub], place)
					end
				end
			end
		end
		places = hubPlaces[step.hub] or places
	end
	for _, place in ipairs(places) do
		local yards = ns.Model.Yards(ns.Data, player --[[@as AGFStep]], place --[[@as AGFStep]])
		if yards and yards <= LINK then
			return true
		end
	end
	return false
end

-- What Shortest Path is handed of `steps`: all of them, except while the player stands in step 1's town (InTown)
-- with more steps after it. Then the town alone, so
-- Shortest Path arrives there and draws no way out of town while the stock "!" and "?" marks show its givers; the
-- journey goes on once the town is done (Follow).
---@param steps (AGFStep|AGFGiver)[]
---@return (AGFStep|AGFGiver)[]
local function Hand(steps)
	local first = steps[1] --[[@as AGFStep?]]
	local player = ns.State.Player()
	if first and first.spots and #steps > 1 and player.map and InTown(player, first) then
		return { first }
	end
	return steps
end

-- Hands Shortest Path `steps` as one numbered journey (Hand); true when it took them.
---@param api AGFSPFAPI
---@param steps (AGFStep|AGFGiver)[]
---@return boolean
local function Send(api, steps)
	steps = Hand(steps)
	if not api.NavigateRoute(OWNER, Stops(steps)) then
		return false
	end
	guided, ours, arrived, stopped = steps, true, false, nil
	ns.Pins.Refresh()
	NotifyGuidance()
	return true
end

-- True when the guidance handed to Shortest Path no longer matches the journey (docs/design.md §2.10): a stop it has
-- yet to reach has left the steps (a town emptied, a step skipped, a quest abandoned or grey), step 1 is neither the
-- stop it heads for nor the one it just reached (the player was taken elsewhere, or a new chapter opens at another
-- town), or step 1's point has moved `far` from the stop it heads for. Later stops reordering alone is not stale.
---@param handed AGFStep[] what was last handed, in order
---@param index integer the stop Shortest Path heads for (CurrentStop)
---@param steps AGFStep[] the chosen journey's steps now
---@param far? fun(a: AGFStep, b: AGFStep): boolean
---@return boolean
function Integrations.Stale(handed, index, steps, far)
	local keys = {}
	for _, step in ipairs(steps) do
		keys[step.key] = true
	end
	for stop = index, #handed do
		if not keys[handed[stop].key] then
			return true
		end
	end
	local first, current, previous = steps[1], handed[index], handed[index - 1]
	if not first then
		return false
	end
	if current and first.key == current.key then
		return far ~= nil and far(first, current)
	end
	-- The town just reached, where Shortest Path has already moved on: sending it again would arrive at once.
	return not (previous and first.key == previous.key)
end

---@param a AGFStep
---@param b AGFStep
---@return boolean
local function Far(a, b)
	local yards = ns.Model.Yards(ns.Data, a, b)
	return yards ~= nil and yards > LINK
end

-- Hands Shortest Path the chosen journey's steps again, as they were started (Core's restore after a /reload). Never
-- the waypoint: the client kept any that was ours. True when it took them.
---@param steps AGFStep[]
---@return boolean
function Integrations.Restore(steps)
	local api = SPF()
	return api ~= nil and not InCombatLockdown() and not ns.Setting("wanderer") and Send(api, steps)
end

---@return (AGFStep|AGFGiver)[]
function Integrations.Guided()
	return Integrations.Guiding() and guided or {}
end

-- With Shortest Path, the step and every step after it become one numbered journey. When it declines (it returns
-- false when it cannot plan the route) or is absent, the native waypoint takes the step instead, so Go always
-- leaves a destination on any map the client allows one on. True when something now guides the player. A wanderer
-- (roadmap #24) is never guided: nothing is set, and nothing is said.
---@param step AGFStep|AGFGiver
---@return boolean
function Integrations.Navigate(step)
	if ns.Setting("wanderer") then
		return false
	end
	local api = SPF()
	-- Shortest Path refuses every route in combat, which is no sign it cannot plan this one: a journey an earlier Go
	-- started keeps guiding, and without one the waypoint takes the step as for any refusal.
	if api and InCombatLockdown() then
		if Ours(api) then
			return false
		end
		api = nil
	end
	if api then
		local steps, found = {}, false
		for _, each in ipairs(ns.Route().steps) do
			found = found or each == step
			steps[#steps + 1] = found and each or nil
		end
		-- Whatever this guides, ns.StartRoute says whether it is the chosen journey's.
		ns.Prefs().guided = nil
		if Send(api, found and steps or { step }) then
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
	-- A held route is still ours to stop.
	local owns = OwnsWaypoint()
	return owns or Ours(SPF())
end

-- Stop: ends only what Go started. Shortest Path's journey by our name, and the native waypoint only while it is ours.
function Integrations.Cancel()
	ns.Prefs().guided, ours, arrived, stopped = nil, false, false, nil
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

-- Guidance follows the chosen journey (docs/design.md §2.10): on each rebuild, a route AGF started for the chosen
-- journey that no longer matches its steps is sent again, at most once. Never in combat (Shortest Path refuses), in
-- the air, where the player's position is unknown (at sea, in an instance), or while Shortest Path isn't guiding it.
-- Why our journey ended: Shortest Path's Ended when it has it; otherwise guessed. Another journey running replaced
-- it, the player standing within the town linkage of its last stop arrived, and anything else was cleared.
---@param api AGFSPFAPI
---@return string?
local function EndReason(api)
	if type(api.Ended) == "function" then
		return (api.Ended(OWNER))
	elseif type(api.Active) == "function" and api.Active() then
		return "replaced"
	end
	local last, player = guided[#guided], ns.State.Player()
	local yards = last and player.map and ns.Model.Yards(ns.Data, player --[[@as AGFStep]], last)
	return yards and yards <= LINK and "arrived" or "cleared"
end

-- Our journey ended since the last look (docs/design.md §2.10): arriving keeps the choice's guidance, so new steps
-- extend it; the player clearing it or another journey replacing it forgets it, so nothing sends it again. Our own
-- Cancel already forgot it.
---@param api AGFSPFAPI
local function Watch(api)
	local now = api.CurrentStop(OWNER) ~= nil
	if ours and not now then
		local reason = EndReason(api)
		if reason == "arrived" then
			arrived = true
		elseif reason == "cleared" or reason == "replaced" then
			stopped, ns.Prefs().guided = ns.Prefs().guided, nil
		end
		ns.Pins.Refresh()
	end
	ours = now
end

-- A step the route has that Shortest Path was never handed: arrived, the journey goes on.
---@param steps AGFStep[]
---@return boolean
local function Unhanded(steps)
	local handed = {}
	for _, step in ipairs(guided) do
		handed[step.key] = true
	end
	for _, step in ipairs(steps) do
		if not handed[step.key] then
			return true
		end
	end
	return false
end

-- Guidance follows the chosen journey (docs/design.md §2.10): on each rebuild, and on the frame after Shortest Path's
-- own super-tracking events, a route AGF started for the chosen journey that no longer matches its steps is sent
-- again, at most once, and one that arrived goes on to steps it was never handed. Never in combat (Shortest Path
-- refuses), in the air, where the player's position is unknown (at sea, in an instance), or once it no longer guides.
local function Follow()
	local api, route, prefs = SPF(), ns.Route(), ns.Prefs()
	if api then
		Watch(api)
	end
	if not (route.chosen and prefs.guided == route.journey and ns.State.Player().map) then
		return
	elseif InCombatLockdown() or UnitOnTaxi("player") then
		return
	end
	local first, saved = route.steps[1], prefs.waypoint
	-- The native waypoint Go set for the chosen journey moves to its new step 1, quietly: where the client allows no
	-- pin it stays, with no error line, since the player asked for nothing just now.
	if first and saved and OwnsWaypoint() then
		local moved = first.map ~= saved.map
			or math.abs(first.x - saved.x) >= 1e-4
			or math.abs(first.y - saved.y) >= 1e-4
		if moved and C_Map.CanSetUserWaypointOnMap(first.map) then
			C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(first.map, first.x, first.y))
			prefs.waypoint = { map = first.map, x = first.x, y = first.y }
			NotifyGuidance()
		end
		return
	end
	if not api then
		return
	end
	local index, hand = api.CurrentStop(OWNER), Hand(route.steps)
	-- Shortest Path heading past the town the player stands in, with work left there: the town alone again.
	local leaving = #hand < #route.steps and guided[index] ~= nil and guided[index].key ~= hand[1].key
	if index then
		if
			Integrations.Guiding()
			and (
				leaving or Integrations.Stale(guided --[[@as AGFStep[] ]], index, route.steps, Far)
			)
		then
			Send(api, route.steps)
		end
	elseif arrived and Unhanded(hand) then
		Send(api, route.steps)
	end
end
ns.OnRouteChange(Follow)

-- Shortest Path ending our journey and the player clearing or moving the waypoint: the super-tracking events Shortest
-- Path itself registers. Handled on the next frame, once its own handler has run, with the guide open or closed.
local events, eventPending = CreateFrame("Frame"), false
events:RegisterEvent("SUPER_TRACKING_CHANGED")
events:RegisterEvent("USER_WAYPOINT_UPDATED")
events:SetScript("OnEvent", function()
	if not eventPending then
		eventPending = true
		C_Timer.After(0, function()
			eventPending = false
			Follow()
			NotifyGuidance()
		end)
	end
end)

-- The chosen journey whose route the player cleared or another journey replaced, until something is handed again.
---@return string?
function Integrations.Stopped()
	return stopped
end

-- Our journey reached its last stop, and nothing was handed since.
---@return boolean
function Integrations.Arrived()
	return arrived and not Integrations.Guiding()
end

---@return string?
function Integrations.Provider()
	if SPF() then
		return L.SHORTEST_PATH
	end
end
