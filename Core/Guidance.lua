---@type string, AGFNamespace
local _, ns = ...

--[[ The guidance lifecycle (docs/design.md §2.10, §4.2): choosing a journey, starting, stopping and restoring its
     route, following it as its steps change, and ending it. The cards, the tracker, the menus and the map's rings all
     come through here, so every route AGF starts runs on the chosen journey. This file alone writes prefs.guided
     (which journey's route AGF started) and prefs.waypoint (the native waypoint Go set); Integrations.lua is the seam
     to Shortest Path and the client's waypoint, and keeps nothing of its own. Core calls Guidance.Ended on each full
     build's commit and Guidance.RouteChanged ahead of every route listener. ]]

---@class AGFGuidanceModule : AGFGuidance
local Guidance = {}
ns.Guidance = Guidance

local Integrations = ns.Integrations

-- Go and Stop run from the footer, the step menu and the tracker; each tells these so the footer's Stop follows.
---@type fun()[]
local listeners = {}

---@param fn fun()
function Guidance.OnChange(fn)
	listeners[#listeners + 1] = fn
end

local function Notify()
	for _, fn in ipairs(listeners) do
		fn()
	end
end

-- What the last Go handed Shortest Path, which may no longer be the chosen journey's steps.
---@type (AGFStep|AGFGiver)[]
local guided = {}
-- Shortest Path held our journey at the last look, and it ended at its last stop since.
local ours, arrived = false, false
-- The chosen journey whose route the player cleared or another journey replaced, until something is handed again.
---@type string?
local stopped
-- A quest was handed in since the last full build: a chosen journey that ends there was completed, not abandoned.
local turnedIn = false
-- A start waiting for the rebuild that has the chosen journey's steps, or for combat's end. Shortest Path refuses every
-- route in combat, and the rebuild PLAYER_REGEN_ENABLED brings (Core's afterCombat) runs it.
local pendingStart = false
-- The player pressed Stop: a journey the autoStart (below) would otherwise start itself stays off until they choose one
-- again. Session-scoped, like the route it stops.
local autoStartBlocked = false

-- Yards past which a stop's point has moved (a town's point moving to its next giver): the town linkage
-- (tools/gen_quests.py LINK). Nearer, the stock "!" and "?" marks show the way.
local LINK = 100

-- QUEST_TURNED_IN, from State.lua: latched for the ending below, then the chapter-end fanfare.
---@param questID integer
function ns.TurnedIn(questID)
	turnedIn = true
	if ns.OnTurnIn then
		ns.OnTurnIn(questID)
	end
end

---@param steps (AGFStep|AGFGiver)[]
---@param hold? boolean
---@return boolean
local function Send(steps, hold)
	if not Integrations.Hand(steps, hold) then
		return false
	end
	guided, ours, arrived, stopped = steps, true, false, nil
	ns.Pins.Refresh()
	Notify()
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
function Guidance.Stale(handed, index, steps, far)
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
	return (a.checklist ~= nil and (a.map ~= b.map or a.x ~= b.x or a.y ~= b.y)) or (yards ~= nil and yards > LINK)
end

-- The stops Shortest Path walks, while it guides; empty otherwise.
---@return (AGFStep|AGFGiver)[]
function Guidance.Guided()
	return Integrations.Guiding() and guided or {}
end

-- Resolve the exact stop handed to SPF, including a route which starts after an occupied objective area.
-- Standing in the head area pins the tracker to it until its objectives are done, whatever its own stop index has
-- advanced to: a step advances only when its state is satisfied (docs/design.md §4.2).
---@return AGFStep?
function Guidance.CurrentStep()
	local head = ns.Route().steps[1]
	if head and head.here then
		return head
	end
	local index = Integrations.Guiding() and Integrations.CurrentStop()
	local sent = index and guided[index]
	if sent and not sent.key then
		return nil
	end
	if sent then
		for _, step in ipairs(ns.Route().steps) do
			if step.key == sent.key then
				return step
			end
		end
		return nil
	end
	return ns.Route().steps[1]
end

-- With Shortest Path, the step and every step after it become one numbered journey. When it declines (it returns
-- false when it cannot plan the route) or is absent, the native waypoint takes the step instead, so Go always
-- leaves a destination on any map the client allows one on. True when something now guides the player. A wanderer
-- (roadmap #24) is never guided: nothing is set, and nothing is said.
---@param step AGFStep|AGFGiver
---@param follow? boolean the chosen journey will replace held quest stops when progress changes
---@return boolean
function Guidance.Navigate(step, follow)
	if ns.Setting("wanderer") or not ns.Model.ValidPlace(step) then
		return false
	end
	local routed = Integrations.Provider() ~= nil
	-- Shortest Path refuses every route in combat, which is no sign it cannot plan this one: a journey an earlier Go
	-- started keeps guiding, and without one the waypoint takes the step as for any refusal.
	if routed and InCombatLockdown() then
		if Integrations.CurrentStop() ~= nil then
			return false
		end
		routed = false
	end
	if routed then
		local steps, found = {}, false
		for _, each in ipairs(ns.Route().steps) do
			found = found or each == step
			steps[#steps + 1] = found and each or nil
		end
		-- Whatever this guides, ns.StartRoute says whether it is the chosen journey's.
		ns.Prefs().guided = nil
		if Send(found and steps or { step }, follow and found) then
			return true
		end
	end
	if not Integrations.CanWaypoint(step.map) then
		-- The red line the world map shows when a pin can't go on a map, so Go never fails silently. Any journey an
		-- earlier Go started keeps guiding: a failed Go changes nothing.
		UIErrorsFrame:AddExternalErrorMessage(ns.L.NO_WAYPOINT)
		return false
	end
	-- A refusal leaves the journey an earlier Go started drawn; the waypoint below replaces it.
	if routed and Integrations.Drop() then
		ns.Pins.Refresh()
	end
	Integrations.SetWaypoint(step, true)
	-- Saved per character, so Stop still knows the waypoint as ours after a /reload.
	ns.Prefs().waypoint, ns.Prefs().guided = { map = step.map, x = step.x, y = step.y }, nil
	Notify()
	return true
end

-- Explicit place buttons reveal their destination; automatic route maintenance never opens a panel.
---@param step AGFStep|AGFGiver
---@return boolean
function Guidance.ShowOnMap(step)
	if ns.Setting("wanderer") or not ns.Model.ValidPlace(step) then
		return false
	end
	local routed = Guidance.Navigate(step)
	ns.Pins.Reveal(step)
	return routed
end

-- The native waypoint is ours while it is still where Go put it; once the player moves or clears it, it is theirs,
-- and the saved one is forgotten.
---@return boolean
local function OwnsWaypoint()
	local prefs = ns.Prefs()
	local same = Integrations.WaypointAt(prefs.waypoint)
	if not same then
		prefs.waypoint = nil
	end
	return same
end

-- Go's guidance is still running: our Shortest Path journey (guided or held), or the waypoint Go set.
---@return boolean
function Guidance.Owns()
	return OwnsWaypoint() or Integrations.CurrentStop() ~= nil
end

-- Stop: ends only what Go started. Shortest Path's journey by our name, and the native waypoint only while it is ours.
function Guidance.Cancel()
	ns.Prefs().guided, ours, arrived, stopped = nil, false, false, nil
	if Integrations.Drop() then
		ns.Pins.Refresh()
	end
	if OwnsWaypoint() then
		Integrations.ClearWaypoint()
		ns.Prefs().waypoint = nil
	end
	Notify()
end

-- Our journey ended since the last look (docs/design.md §2.10): arriving keeps the choice's guidance, so new steps
-- extend it; the player clearing it or another journey replacing it forgets it, so nothing sends it again. Our own
-- Cancel already forgot it.
local function Watch()
	local now = Integrations.CurrentStop() ~= nil
	if ours and not now then
		local reason = Integrations.EndReason(guided[#guided], LINK)
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
	local spf, route, prefs = Integrations.Provider() ~= nil, ns.Route(), ns.Prefs()
	if spf then
		Watch()
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
		if moved and Integrations.CanWaypoint(first.map) then
			Integrations.SetWaypoint(first)
			prefs.waypoint = { map = first.map, x = first.x, y = first.y }
			Notify()
		end
		return
	end
	if not spf then
		return
	end
	local index = Integrations.CurrentStop()
	if index then
		if
			Integrations.Guiding()
			and (
				Guidance.Stale(guided --[[@as AGFStep[] ]], index, route.steps, Far)
			)
		then
			Send(route.steps, true)
		end
	elseif arrived and Unhanded(route.steps) then
		Send(route.steps, true)
	end
end

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
			Notify()
		end)
	end
end)

-- Our journey reached its last stop, and nothing was handed since.
---@return boolean
local function Arrived()
	return arrived and not Integrations.Guiding()
end

-- The chosen journey's key a filter hides (Quests, Dungeons or Battlegrounds off in the cog): the player's own toggle
-- can bring it back, so the choice is kept. With no next zone (roadmap #21) Dungeons hides nothing, so a dungeon that
-- went ended.
---@param key string
---@param prefs AGFPrefs
---@param route AGFRoute
---@return boolean
local function Filtered(key, prefs, route)
	return (key:find("^dungeon:") ~= nil and not prefs.dungeons and not route.stranded)
		or ((key:find("^zone:") ~= nil or key:find("^chain:") ~= nil or key == "calling") and not prefs.quests)
		or (key:find("^battleground:") ~= nil and not prefs.battlegrounds)
end

-- A chosen journey the full build no longer has ends (docs/design.md §2.10): its route stops, and the choice is
-- cleared, so the cards are whole again; after a turn-in the tracker says it is complete. A filter keeps the key but
-- stops the route. Judged only on full builds (Core's commit, out of combat): combat's cheap one keeps the last
-- journeys.
---@param route AGFRoute
function Guidance.Ended(route)
	local prefs, completed = ns.Prefs(), turnedIn
	turnedIn = false
	-- QuestieSource starts after the first login events. Until it has settled, the empty/log-only route is
	-- provisional; clearing a saved story here would make a reload lose the player's choice before Questie loads.
	if ns.QuestieBuilding() then
		return
	end
	local key = prefs.journey
	if not key or route.chosen then
		return
	end
	if not Filtered(key, prefs, route) then
		prefs.journey, pendingStart = nil, false
		if completed and ns.OnJourneyComplete then
			ns.OnJourneyComplete()
		end
	end
	if prefs.guided == key then
		Guidance.Cancel()
	end
end

-- Chooses `key`, or none. With `start` its route starts on the rebuild that has its steps. Leaving the journey whose
-- route AGF started stops that route, unless the new choice's start replaces it; never anyone else's.
---@param key? string
---@param start? boolean
function ns.Choose(key, start)
	if ns.Prefs().journey ~= key then
		ns.Prefs().sessionCommit = nil
	end
	local prefs = ns.Prefs()
	local was = prefs.guided
	prefs.journey = key
	-- A wanderer's choice starts nothing (StartRoute), so nothing waits for combat's end either.
	pendingStart = key ~= nil and start == true and not ns.Setting("wanderer")
	if was and was ~= key and not pendingStart then
		Guidance.Cancel()
	end
	ns.Invalidate()
end

-- Guidance along the chosen journey from `step`, its first by default. With none chosen, the route's own journey (the
-- first card) is chosen first. With Shortest Path loaded a start in combat waits for
-- combat's end. True when something now guides the player, or the start waits.
---@param step? AGFStep
---@return boolean
function ns.StartRoute(step)
	local route, prefs = ns.Route(), ns.Prefs()
	if not route.journey then
		return false
	end
	if not route.chosen then
		prefs.journey = route.journey
		ns.Invalidate()
	end
	-- A wanderer (roadmap #24) chooses the journey and sets off on foot: nothing to start, now or after combat.
	if ns.Setting("wanderer") then
		pendingStart = false
		return false
	elseif ns.Session.Info().pending then
		pendingStart = true
		return true
	elseif InCombatLockdown() and Integrations.Provider() then
		pendingStart = true
		return true
	end
	pendingStart = false
	step = step or route.steps[1]
	if step and Guidance.Navigate(step, true) then
		prefs.guided = route.journey
		return true
	end
	return false
end

-- The player's Stop, from the footer or a step's menu: what the back arrow does while it runs, so no journey is left
-- chosen with nothing to resume it.
function ns.Stop()
	autoStartBlocked = true
	Guidance.Cancel()
	ns.Choose(nil)
end

-- The player reordered the chosen journey's steps: the route AGF runs for it starts again from its new first step,
-- on the frame after the rebuild the reorder asked for.
function Guidance.Reroute()
	if ns.Prefs().guided == ns.Prefs().journey and Guidance.Owns() then
		C_Timer.After(0, function()
			ns.StartRoute()
		end)
	end
end

-- The route AGF started for the chosen journey stopped without the player's Stop: cleared in Shortest Path, replaced
-- by another journey, refused after a /reload, or its waypoint moved. It has steps, nothing of ours guides it and no
-- start is on its way, so its card and the tracker title resume it rather than clear the choice. A route that arrived
-- at its last stop is done, not paused.
---@return boolean
local function Paused()
	local route = ns.Route()
	local key = route.journey
	return route.chosen
		and (ns.Prefs().guided == key or stopped == key)
		and #route.steps > 0
		and ns.Setting("titleStartsRoute") == true
		and not pendingStart
		and not Guidance.Owns()
		and not Arrived()
end

-- Where the chosen journey's guidance stands, when it is not simply running or absent: "queued" while a start waits
-- for combat's end, "paused" while its route stopped without the player's Stop (its card, the tracker title and Show
-- on Map resume it), "arrived" once it reached its last stop with nothing handed since. Whether anything of ours guides
-- at all is Guidance.Owns.
---@return AGFGuidanceStatus?
function Guidance.Status()
	if pendingStart and InCombatLockdown() then
		return "queued"
	elseif Paused() then
		return "paused"
	elseif Arrived() then
		return "arrived"
	end
end

-- A start that waited (for the rebuild with the journey's steps, the session's estimate or combat's end) runs. A
-- chosen journey whose steps ran out while its route ran stops it, and waits for the session to fill again.
local function StartWaiting()
	local route = ns.Route()
	if route.chosen and #route.steps == 0 and ns.Prefs().guided == route.journey and Guidance.Owns() then
		local waiting = ns.Session.Info().pending
		Guidance.Cancel()
		pendingStart = pendingStart or waiting
	end
	if pendingStart and not InCombatLockdown() and ns.Route().chosen then
		ns.StartRoute()
	end
end

-- No journey chosen draws nothing (docs/design.md §2.10): however the choice went (a click, Not interested, Stop, the
-- journey ending or leaving the cards), what AGF guides stops with it. Only ours: Cancel ends Shortest Path's journey
-- by our name and the waypoint only while it sits where Go put it. Judged on full builds, as Ended is: combat's cheap
-- one can drop a card it will bring back.
local wasChosen = false
local function StopUnchosen()
	if InCombatLockdown() then
		return
	end
	local chosen = ns.Route().chosen
	if wasChosen and not chosen and Guidance.Owns() then
		Guidance.Cancel()
	end
	wasChosen = chosen
end

-- Shortest Path's journeys end with the session, so a /reload or login brings back the route AGF had started for the
-- chosen journey (prefs.guided), once, on the first full build that has its steps. With autoStart (default on) a
-- journey the player has not started yet is started too, so the map route is drawn without a click. Never over someone
-- else's journey, never for a wanderer, and never once the player cleared the route themselves. The native waypoint
-- needs nothing: the client keeps it.
local restoring = true
local function Restore()
	if not restoring or InCombatLockdown() or not ns.State.Ready() or ns.QuestieBuilding() then
		return
	end
	local prefs, route = ns.Prefs(), ns.Route()
	-- Someone (this addon or the player) already holds the route: leave it be.
	if Guidance.Owns() then
		restoring = false
		return
	end
	-- The route AGF had started for the chosen journey comes back, as it was started. Never the waypoint: the client
	-- kept any that was ours.
	if prefs.guided and route.chosen and route.journey == prefs.guided then
		if not Integrations.Provider() or Integrations.ReplacesJourney() then
			restoring, prefs.guided = false, nil
		elseif not ns.Setting("wanderer") and Send(route.steps, true) then
			restoring = false
		end
		return
	end
	-- Nothing to restore: start the offered journey, unless the player set off on foot, cleared this route, or nothing
	-- can guide it (no Shortest Path, so no route line anyway).
	restoring = false
	if
		ns.Setting("autoStart")
		and not autoStartBlocked
		and route.journey
		and not ns.Setting("wanderer")
		and stopped ~= route.journey
		and Integrations.Provider()
	then
		ns.StartRoute()
	end
end

-- The route changed (Core, ahead of every listener, so the views already read the route as started or stopped). The
-- order is the lifecycle's own: a waiting start, then a choice that went, then the restore; the quest selection
-- (Focus.lua) settles next, so one cleared on walking out is gone before the route is handed on.
function Guidance.RouteChanged()
	StartWaiting()
	StopUnchosen()
	Restore()
	ns.Focus.Sync()
	Follow()
end

-- Guidance's part of /agf travel's line (Integrations.Debug).
---@return string
function Guidance.Debug()
	return Integrations.Debug(
		("arrived=%s stopped=%s ours=%s guidedN=%d"):format(
			tostring(arrived),
			tostring(stopped),
			tostring(ours),
			#guided
		)
	)
end
