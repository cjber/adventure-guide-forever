---@type string, AGFNamespace
local _, ns = ...

if ns.broken then
	return
end

--[[ While a RestedXP guide leads (#362), the objective tracker lists only the quests its step under way and its
     ongoing steps name. The player's own tracked quests are kept on the character when the guide takes over, and come
     back when it stops leading: another journey chosen, RestedXP guides or this setting turned off. Every change goes
     through the client's quest watches, which Questie mirrors into its own tracker on Forever, so its list follows.
     Only what this file or the client's auto quest watch tracked is taken away again: a quest the player tracks or
     untracks by hand while the guide leads stays as they left it. ]]
---@class AGFGuideWatch
local Watch = {}
ns.GuideWatch = Watch

-- Accepting a quest tracks it (the client's auto quest watch, or Questie's auto tracking a moment later), and so can
-- progress on an untracked one (QUEST_WATCH_UPDATE, then the client's auto watch). A quest tracked within a few seconds
-- of either is the client's, not the player's.
local AUTO_WINDOW = 5
---@type table<integer, number>
local auto = {}

---@param questID integer
---@return boolean
local function Watched(questID)
	return C_QuestLog.GetQuestWatchType(questID) ~= nil
end

-- The quests in the log that the guide's step under way and its ongoing steps name, in the order they read.
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

-- The guide leads: it is the chosen journey and the setting is on.
---@return boolean
local function Leads()
	local route = ns.Route()
	local first = route.steps[1]
	return ns.Setting("guideTracksQuests") == true
		and ns.RestedXP.Active()
		and route.chosen
		and first ~= nil
		and first.rxpIndex ~= nil
end

-- The player's own tracked quests come back, and what this file or the client tracked for the guide goes.
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

-- Settles the tracked quests on the route as it is now. Never in combat, and never while the route is provisional
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
	local state = prefs.guideWatch
	if not Leads() then
		if state then
			prefs.guideWatch = nil
			GiveBack(state)
		end
		return
	end
	local now = GetTime()
	local named, order = Named(ns.Route())
	if not state then
		state = { saved = {}, added = {}, named = {} }
		for index = 1, C_QuestLog.GetNumQuestWatches() do
			state.saved[#state.saved + 1] = C_QuestLog.GetQuestIDForQuestWatchIndex(index)
		end
		prefs.guideWatch = state
		for _, questID in ipairs(state.saved) do
			if not named[questID] then
				C_QuestLog.RemoveQuestWatch(questID)
			end
		end
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
		end
	end
	-- A quest the guide names anew is tracked once; one the player untracks while it stays named stays untracked.
	for _, questID in ipairs(order) do
		if not state.named[questID] and not Watched(questID) and C_QuestLog.AddQuestWatch(questID) then
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
	-- A watch change needs a look only for a quest the client may have tracked: the rest are ours or the player's.
	if event ~= "QUEST_WATCH_UPDATE" and (event ~= "QUEST_WATCH_LIST_CHANGED" or auto[questID]) then
		Later()
	end
end)
