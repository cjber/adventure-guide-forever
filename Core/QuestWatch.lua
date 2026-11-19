---@type string, AGFNamespace
local _, ns = ...

if ns.broken then
	return
end

--[[ One owner for the watches a leader adds: a RestedXP guide (#362) or one of Adventure Guide's own journeys (#682).
     The quests the leader names in the log are tracked, and come off the tracker again once it stops naming them. A
     quest the player tracked is never untracked (#865): only a watch this file or the client's auto quest watch added
     for the leader is taken away, and a quest the player tracks or untracks by hand stays as they left it. Every change
     goes through the client's quest watches, which Questie mirrors into its own tracker on Forever, so its list
     follows. ]]
---@class AGFQuestWatch
local Watch = {}
ns.QuestWatch = Watch

-- Accepting a quest tracks it (the client's auto quest watch, or Questie's auto tracking a moment later), and so can
-- progress on an untracked one (QUEST_WATCH_UPDATE, then the client's auto watch). A quest tracked within a few seconds
-- of either is the client's, not the player's.
local AUTO_WINDOW = 5
---@type table<integer, number>
local auto = {}

-- Watch events raised by our own changes must not rewrite the player's saved choices.
local changing = false
local function AddWatch(questID)
	changing = true
	local added = C_QuestLog.AddQuestWatch(questID)
	changing = false
	return added
end
local function RemoveWatch(questID)
	changing = true
	C_QuestLog.RemoveQuestWatch(questID)
	changing = false
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
		not ns.Setting("informationOnly")
		and ns.RestedXP
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
		not ns.Setting("informationOnly")
		and ns.Setting("journeyWatch") == true
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

-- Which leader is settling the watches: "rxp", "journey" or nil. Asked by a title click before it adds anything.
---@return "rxp"|"journey"|nil
function Watch.Source()
	local kind = Leader()
	return kind
end

-- What this file or the client tracked for the leader goes; the player's own watches stay.
---@param state AGFGuideWatchState
local function GiveBack(state)
	for questID in pairs(state.added) do
		if Watched(questID) then
			RemoveWatch(questID)
		end
	end
end

-- Earlier versions untracked the player's own quests while a leader led, keeping them in `saved` (#865). A quest still
-- in the log that the leader took off the tracker goes back on once. `saved` and `hidden` stay, empty: v1.11.0 and
-- earlier read both with ipairs and pairs, so a player who rolls back keeps a working state, and with nothing saved
-- the old reader takes none of their quests.
---@param state AGFGuideWatchState
local function Restore(state)
	if state.saved and #state.saved > 0 then
		local log = ns.State.Log()
		for _, questID in ipairs(state.saved) do
			if log[questID] and not Watched(questID) then
				AddWatch(questID)
			end
		end
	end
	state.saved, state.hidden = {}, {}
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
	local state = prefs.guideWatch
	if state then
		Restore(state)
	end
	if not kind then
		if state then
			prefs.guideWatch = nil
			GiveBack(state)
		end
		return
	end
	---@cast named table<integer, true>
	---@cast order integer[]
	if not state then
		state = { added = {}, named = {}, saved = {}, hidden = {} }
		prefs.guideWatch = state
	end
	local now = GetTime()
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
				RemoveWatch(questID)
			end
		end
	end
	-- A quest the leader names anew is tracked once; one the player untracks while it stays named stays untracked.
	for _, questID in ipairs(order) do
		if not state.named[questID] and not Watched(questID) and AddWatch(questID) then
			state.added[questID] = true
		end
	end
	state.named = named
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
	-- A quest the player tracks or untracks by hand is theirs from then on: no later sync takes it away.
	local automatic = auto[questID] and GetTime() - auto[questID] <= AUTO_WINDOW
	if event == "QUEST_WATCH_LIST_CHANGED" and not changing and not automatic then
		local state = ns.Prefs().guideWatch
		if state then
			state.added[questID] = nil
		end
	end
	-- A watch change needs a look only for a quest the client may have tracked: the rest are ours or the player's.
	if event ~= "QUEST_WATCH_UPDATE" and (event ~= "QUEST_WATCH_LIST_CHANGED" or auto[questID]) then
		Later()
	end
end)
