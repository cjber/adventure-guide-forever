---@type string, AGFNamespace
local _, ns = ...

if ns.broken then
	return
end

--[[ One owner for the tracked quests while something leads the player: a RestedXP guide (#362) or one of Adventure
     Guide's own journeys (#682). The quests the leader names in the log are tracked, and every other tracked quest
     leaves. The player's own tracked quests are kept on the character when a leader takes over, and come back when it
     stops leading: another choice, no journey, or the setting turned off. Every change goes through the client's
     quest watches, which Questie mirrors into its own tracker on Forever, so its list follows. Only what this file or
     the client's auto quest watch tracked is taken away again: a quest the player tracks or untracks by hand while a
     leader leads stays as they left it. ]]
---@class AGFQuestWatch
local Watch = {}
ns.QuestWatch = Watch

-- Accepting a quest tracks it (the client's auto quest watch, or Questie's auto tracking a moment later), and so can
-- progress on an untracked one (QUEST_WATCH_UPDATE, then the client's auto watch). A quest tracked within a few seconds
-- of either is the client's, not the player's.
local AUTO_WINDOW = 5
---@type table<integer, number>
local auto = {}

-- The leader the last Sync settled, and how many of the player's own quests it currently hides for the tracker.
---@type "rxp"|"journey"|nil
local source
local hidden = 0

---@type fun()[]
local listeners = {}

---@param fn fun() called when the hidden count changes
function Watch.OnChange(fn)
	listeners[#listeners + 1] = fn
end

local function Notify()
	for _, fn in ipairs(listeners) do
		ns.core.SafeCall("quest watch listener", fn)
	end
end

---@param questID integer
---@return boolean
local function Watched(questID)
	return C_QuestLog.GetQuestWatchType(questID) ~= nil
end

-- The quests in the log that a RestedXP guide's step under way and its ongoing steps name, in the order they read.
---@param route AGFRoute
---@return table<integer, true> named
---@return integer[] order
local function Named(route)
	local named, order, log = {}, {}, ns.State.Log()
	for _, step in ipairs(route.steps) do
		if step.rxpIndex and not step.preview then
			for _, item in ipairs(step.checklist or {}) do
				local questID = item.rxpQuest
				if questID and not named[questID] and log[questID] then
					named[questID] = true
					order[#order + 1] = questID
				end
			end
		end
	end
	return named, order
end

-- Whether a RestedXP guide is the leader, and the quests it names. Its own setting keeps today's behaviour.
---@param route AGFRoute
---@return "rxp"|nil
---@return table<integer, true>?
---@return integer[]?
local function RestedXPLeader(route)
	local first = route.steps[1]
	if
		ns.RestedXP
		and ns.Setting("guideTracksQuests") == true
		and ns.RestedXP.Active()
		and route.chosen
		and first ~= nil
		and first.rxpIndex ~= nil
	then
		local named, order = Named(route)
		return "rxp", named, order
	end
end

-- Whether one of Adventure Guide's own journeys is the leader, and the quests on it that are in the log.
---@param route AGFRoute
---@return "journey"|nil
---@return table<integer, true>?
---@return integer[]?
local function JourneyLeader(route)
	local first = route.steps[1]
	if
		ns.Setting("journeyWatch") == true
		and route.chosen
		and first ~= nil
		and not first.preview
		and first.rxpIndex == nil
		and not (ns.Polestar and ns.Polestar.Active())
	then
		local named, order = ns.RouteQuests(route)
		return "journey", named, order
	end
end

-- The leader now, its quests in the log, and their order. A RestedXP guide keeps precedence because an AGF journey
-- never has a guide step at its head.
---@return "rxp"|"journey"|nil
---@return table<integer, true>?
---@return integer[]?
local function Leader()
	local route = ns.Route()
	local kind, named, order = RestedXPLeader(route)
	if kind then
		return kind, named, order
	end
	return JourneyLeader(route)
end

-- The log the last build planned from, so counting what is hidden does not walk the quest log a second time.
---@return table<integer, AGFLogQuest>
local function Log()
	if ns.RouteSettled() then
		return ns.Snapshot().log
	end
	return ns.State.Log()
end

-- The player's own tracked quests the leader is withholding and the tracker does not list now.
---@param state AGFGuideWatchState
---@return integer
local function CountHidden(state)
	local count, log = 0, nil
	for questID in pairs(state.hidden) do
		log = log or Log()
		if log[questID] and not Watched(questID) then
			count = count + 1
		end
	end
	return count
end

-- Reads the hidden count for the notice, never in combat, and tells the tracker only when it moved.
local function UpdateHidden()
	if InCombatLockdown() then
		return
	end
	local count = 0
	if source == "journey" then
		local state = ns.Prefs().guideWatch
		if state then
			count = CountHidden(state)
		end
	end
	if count ~= hidden then
		hidden = count
		Notify()
	end
end

-- The number of the player's own quests currently hidden from the tracker while an Adventure Guide journey leads.
---@return integer
function Watch.Hidden()
	return hidden
end

-- Which leader is settling the watches: "rxp", "journey" or nil. Asked by a title click before it adds anything.
---@return "rxp"|"journey"|nil
function Watch.Source()
	local kind = Leader()
	return kind
end

-- The player's own tracked quests come back, and what this file or the client tracked for the leader goes.
---@param state AGFGuideWatchState
local function GiveBack(state)
	for questID in pairs(state.added) do
		if Watched(questID) then
			C_QuestLog.RemoveQuestWatch(questID)
		end
	end
	local log = ns.State.Log()
	for _, questID in ipairs(state.saved) do
		if log[questID] and not Watched(questID) then
			C_QuestLog.AddQuestWatch(questID)
		end
	end
end

-- Settles the tracked quests on the leader as it is now. Never in combat, and never while the route is provisional
-- (completed quests or Questie's catalogue still loading, or the chosen guide not loaded yet): it would give the
-- player's list back only to take it again.
function Watch.Sync()
	if InCombatLockdown() or not ns.State.Ready() or ns.QuestieBuilding() then
		return
	end
	local prefs = ns.Prefs()
	if ns.RestedXP.Awaits(prefs.journey) then
		return
	end
	local kind, named, order = Leader()
	local switched = kind ~= source
	source = kind
	local state = prefs.guideWatch
	if not kind then
		if state then
			prefs.guideWatch = nil
			GiveBack(state)
		end
		UpdateHidden()
		return
	end
	---@cast named table<integer, true>
	---@cast order integer[]
	local now = GetTime()
	if not state then
		state = { saved = {}, added = {}, named = {}, hidden = {} }
		for index = 1, C_QuestLog.GetNumQuestWatches() do
			local questID = C_QuestLog.GetQuestIDForQuestWatchIndex(index)
			if questID then
				state.saved[#state.saved + 1] = questID
			end
		end
		prefs.guideWatch = state
		for _, questID in ipairs(state.saved) do
			if not named[questID] then
				if Watched(questID) then
					C_QuestLog.RemoveQuestWatch(questID)
				end
				state.hidden[questID] = true
			end
		end
	else
		-- A state saved before hidden counts existed: rebuild what the leader withholds from what is off the tracker.
		if not state.hidden then
			state.hidden = {}
			for _, questID in ipairs(state.saved) do
				if not named[questID] and not Watched(questID) then
					state.hidden[questID] = true
				end
			end
		end
		-- The leader changed (a RestedXP guide began, or another journey took over): a saved quest it does not name
		-- is hidden now too, unless the player already took it back by hand.
		if switched then
			for _, questID in ipairs(state.saved) do
				if not named[questID] and not state.hidden[questID] then
					if Watched(questID) then
						C_QuestLog.RemoveQuestWatch(questID)
					end
					state.hidden[questID] = true
				end
			end
		end
	end
	local saved = {}
	for _, questID in ipairs(state.saved) do
		saved[questID] = true
	end
	for questID, at in pairs(auto) do
		if now - at > AUTO_WINDOW then
			auto[questID] = nil
		elseif Watched(questID) then
			state.added[questID] = true
		end
	end
	for questID in pairs(state.added) do
		if not named[questID] then
			state.added[questID] = nil
			if Watched(questID) then
				C_QuestLog.RemoveQuestWatch(questID)
			end
			if saved[questID] then
				state.hidden[questID] = true
			end
		end
	end
	-- A quest the leader now names is given back to the tracker, even one it withheld before.
	for questID in pairs(named) do
		state.hidden[questID] = nil
	end
	-- A quest the leader names anew is tracked once; one the player untracks while it stays named stays untracked.
	for _, questID in ipairs(order) do
		if not state.named[questID] and not Watched(questID) and C_QuestLog.AddQuestWatch(questID) then
			state.added[questID] = true
		end
	end
	state.named = named
	UpdateHidden()
end

-- A watch changed by the player while no route change is due: the hidden count may have moved, and nothing else.
function Watch.Refresh()
	UpdateHidden()
end

local function Later()
	C_Timer.After(0, Watch.Sync)
end

ns.OnRouteChange(Watch.Sync)
local events = CreateFrame("Frame")
events:RegisterEvent("QUEST_ACCEPTED")
events:RegisterEvent("QUEST_WATCH_UPDATE")
events:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event, first, second)
	-- QUEST_ACCEPTED gives the quest ID alone, or the log index first on clients that keep the older signature.
	local questID = event == "QUEST_ACCEPTED" and type(second) == "number" and second or first
	if type(questID) ~= "number" then
		if event == "PLAYER_REGEN_ENABLED" then
			Later()
		end
		return
	end
	if event == "QUEST_ACCEPTED" or (event == "QUEST_WATCH_UPDATE" and not Watched(questID)) then
		auto[questID] = GetTime()
	end
	-- A watch change needs a look only for a quest the client may have tracked: the rest are ours or the player's.
	if event ~= "QUEST_WATCH_UPDATE" and (event ~= "QUEST_WATCH_LIST_CHANGED" or auto[questID]) then
		Later()
	end
	Watch.Refresh()
end)
