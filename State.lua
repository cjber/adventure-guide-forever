---@type string, AGFNamespace
local _, ns = ...

---@class AGFStateModule : AGFState
local State = {}
ns.State = State

---@return integer
local function RaceBit()
	local _, _, raceID = UnitRace("player")
	return raceID and bit.lshift(1, raceID - 1) or 0
end

---@return integer
local function ClassBit()
	local _, _, classID = UnitClass("player")
	return classID and bit.lshift(1, classID - 1) or 0
end

---@return AGFPlayer
function State.Player()
	local _, englishFaction = UnitFactionGroup("player")
	local side = englishFaction == "Horde" and 2 or 1

	local map, x, y
	local bestMap = C_Map.GetBestMapForUnit("player")
	if bestMap then
		local position = C_Map.GetPlayerMapPosition(bestMap, "player")
		if position then
			map, x, y = bestMap, position:GetXY()
		end
	end

	return {
		level = UnitLevel("player"),
		side = side,
		raceBit = RaceBit(),
		classBit = ClassBit(),
		map = map,
		x = x,
		y = y,
	}
end

---@type table<integer, boolean>
local completed = {}
local ready = false

-- Every completed quest ID the game currently knows about. Nil means the game hasn't answered
-- yet (Ready() stays false); an empty table is a legitimate answer for a fresh character.
---@return boolean
local function LoadCompleted()
	local ids = C_QuestLog.GetAllCompletedQuestIDs()
	if not ids then
		return false
	end
	completed = {}
	for _, id in ipairs(ids) do
		completed[id] = true
	end
	return true
end

---@return table<integer, boolean>
function State.Completed()
	return completed
end

---@return boolean
function State.Ready()
	return ready
end

-- Keyed by quest ID, like Completed(), so the model can look either up in O(1).
---@return table<integer, AGFLogQuest>
function State.Log()
	local log = {}
	for index = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(index)
		if info and not info.isHeader then
			local map, x, y = C_QuestLog.GetNextWaypoint(info.questID)
			---@type AGFLogQuest
			log[info.questID] = {
				id = info.questID,
				title = info.title,
				complete = C_QuestLog.IsComplete(info.questID) or false,
				level = info.level or 0,
				map = map,
				x = x,
				y = y,
			}
		end
	end
	return log
end

---@type fun()[]
local listeners = {}

---@param fn fun()
function State.OnChange(fn)
	listeners[#listeners + 1] = fn
end

local function Notify()
	for _, fn in ipairs(listeners) do
		fn()
	end
end

-- QUEST_LOG_UPDATE fires often (once per objective tick); coalesce a burst into one
-- notification per frame instead of rebuilding the route for every one of them.
local pendingNotify = false
local function Coalesce()
	if pendingNotify then
		return
	end
	pendingNotify = true
	C_Timer.After(0, function()
		pendingNotify = false
		Notify()
	end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("QUEST_TURNED_IN")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:SetScript("OnEvent", function(_, event, questID)
	if event == "PLAYER_ENTERING_WORLD" then
		if not ready and LoadCompleted() then
			ready = true
		end
	elseif event == "QUEST_TURNED_IN" and questID then
		completed[questID] = true
	end
	Coalesce()
end)
