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

---@type table<integer, integer>
local skills, caps = {}, {}
local primaries = 0

local PROFESSION = 11 -- SkillLine.CategoryID of a profession, which takes a slot; secondary skills (9) take none

-- Every learned skill line's rank and cap by SkillLine ID, and how many professions the character has, read again on
-- SKILL_LINES_CHANGED. Forever has no global GetSkillLineInfo; C_SkillInfo lists only the lines the character has,
-- so an unlearned one is absent (rank 0).
local function LoadSkills()
	skills, caps, primaries = {}, {}, 0
	for index = 1, C_SkillInfo.GetNumSkillLines() do
		local info = C_SkillInfo.GetSkillLineInfo(index)
		if info and not info.isHeader and info.skillID then
			skills[info.skillID] = info.rank
			caps[info.skillID] = info.maxRank
			primaries = primaries + (info.skillLineCategoryID == PROFESSION and 1 or 0)
		end
	end
end

---@return table<integer, integer>
function State.Skills()
	return skills
end

-- The player's reputation with a faction on the data's scale (0 starts Neutral, 3000 Friendly, 42000 Exalted);
-- nil when the client gives none, as for the other side's factions.
---@param factionID integer
---@return integer?
function State.Reputation(factionID)
	local info = C_Reputation.GetFactionDataByID(factionID)
	return info and info.currentStanding or nil
end

-- The ranks and standings the data's gates name, as last read. SKILL_LINES_CHANGED fires on every weapon skill-up
-- and UPDATE_FACTION on every reputation kill; one that moves no gated line or faction rebuilds nothing.
---@type table<string, integer|false>
local gated = {}

---@return boolean
local function GatesMoved()
	local moved = false
	for id in pairs(ns.Data.skills or {}) do
		local rank = skills[id] or 0
		moved = moved or gated["skill" .. id] ~= rank
		gated["skill" .. id] = rank
	end
	for id in pairs(ns.Data.factions or {}) do
		local standing = State.Reputation(id) or false
		moved = moved or gated["rep" .. id] ~= standing
		gated["rep" .. id] = standing
	end
	return moved
end

-- The client's names for a skill line the character has, a faction it gives a standing for, and a standing
-- (1 Hated to 8 Exalted), for the why-not lines; nil when it has none.
---@param skillLineID integer
---@return string?
function State.SkillName(skillLineID)
	local info = C_SkillInfo.GetSkillLineInfoByID(skillLineID)
	return info and info.name or nil
end

---@param factionID integer
---@return string?
function State.FactionName(factionID)
	local info = C_Reputation.GetFactionDataByID(factionID)
	return info and info.name ~= "" and info.name or nil
end

---@param reaction integer
---@return string?
function State.StandingName(reaction)
	local label = _G["FACTION_STANDING_LABEL" .. reaction]
	return type(label) == "string" and label or nil
end

-- The battlegrounds that open at each level, as the client lists them (C_PvP.GetLevelUpBattlegrounds: Warsong Gulch at
-- 10, Arathi Basin at 20, Darkspear Islands at 30 in the probe); they never change, so each level is asked once.
---@type table<integer, LevelUpBattlegroundInfo[]>
local opensAt = {}

-- Roadmap #12: every battleground open to the player, the newest first (then by ID), each at the level it opened. Only
-- the client's level-up list says so: the probe found `canEnter` false for all three at level 19, so it gates nothing,
-- and a battleground behind a condition (Battle for Blackrock) or with no levels (Battle for Gilneas) is on no list.
-- Empty on a client without the API.
---@return AGFBattleground[]
function State.Battlegrounds()
	local pvp, open, seen = C_PvP, {}, {}
	if not (pvp and pvp.GetLevelUpBattlegrounds) then
		return open
	end
	for level = 1, UnitLevel("player") do
		opensAt[level] = opensAt[level] or pvp.GetLevelUpBattlegrounds(level) or {}
		for _, info in ipairs(opensAt[level]) do
			if not seen[info.id] then
				seen[info.id] = true
				open[#open + 1] = { id = info.id, name = info.name, level = level }
			end
		end
	end
	table.sort(open, function(a, b)
		if a.level ~= b.level then
			return a.level > b.level
		end
		return a.id < b.id
	end)
	return open
end

-- Rested XP (roadmap #11): GetXPExhaustion is nil with none, and IsResting is true in an inn or a city. The level's XP
-- only when the client has UnitXPMax, which the Forever probes never asked about.
---@return integer rested
---@return integer? xpMax
---@return boolean resting
local function Rest()
	local xpMax = UnitXPMax and UnitXPMax("player") or nil
	return GetXPExhaustion() or 0, xpMax, IsResting() == true
end

---@return AGFPlayer
function State.Player()
	local englishFaction = UnitFactionGroup("player")
	local side = englishFaction == "Horde" and 2 or 1

	local map, x, y
	local bestMap = C_Map.GetBestMapForUnit("player")
	if bestMap then
		local position = C_Map.GetPlayerMapPosition(bestMap, "player")
		if position then
			map, x, y = bestMap, position:GetXY()
		end
	end

	local rested, xpMax, resting = Rest()
	return {
		rested = rested,
		xpMax = xpMax,
		resting = resting,
		level = UnitLevel("player"),
		maxLevel = GetMaxPlayerLevel(),
		side = side,
		raceBit = RaceBit(),
		classBit = ClassBit(),
		map = map,
		x = x,
		y = y,
		skills = skills,
		caps = caps,
		primaries = primaries,
		reputation = State.Reputation,
		battlegrounds = State.Battlegrounds(),
	}
end

-- The client's name for a map, in the player's language; nil when it has none, so the caller falls back to data.
---@param map integer
---@return string?
function State.MapName(map)
	local info = C_Map.GetMapInfo(map)
	return info and info.name ~= "" and info.name or nil
end

-- The client's name for an instance Map.ID (a dungeon card's title), in the player's language; nil when it has none.
---@param id integer
---@return string?
function State.InstanceName(id)
	local name = GetRealZoneText(id)
	return name ~= "" and name or nil
end

-- The client's title for a quest in the player's language, when it has it cached; nil otherwise, for the data's.
---@param questID integer
---@return string?
function State.QuestTitle(questID)
	local title = C_QuestLog.GetTitleForQuestID(questID)
	return title ~= "" and title or nil
end

-- The client's names for a race and a class ID, for the why-not lines; nil when it has none.
---@param raceID integer
---@return string?
function State.RaceName(raceID)
	local info = C_CreatureInfo.GetRaceInfo(raceID)
	return info and info.raceName or nil
end

---@param classID integer
---@return string?
function State.ClassName(classID)
	local info = C_CreatureInfo.GetClassInfo(classID)
	return info and info.className or nil
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

-- Whether the last stop's rest line would change (Model.RestLow, and resting ticks it): XP and rest events fire on
-- every kill and every rested tick, and only a flip rebuilds anything.
---@type integer?
local restWas

---@return boolean
local function RestMoved()
	local rested, xpMax, resting = Rest()
	local low = ns.Model.RestLow({
		level = UnitLevel("player"),
		maxLevel = GetMaxPlayerLevel(),
		rested = rested,
		xpMax = xpMax,
	})
	local now = (low and 1 or 0) + (resting and 2 or 0)
	local moved = now ~= restWas
	restWas = now
	return moved
end

---@type fun()[]
local listeners = {}
---@type fun()[]
local loginListeners = {}

-- Called on PLAYER_ENTERING_WORLD for a login only, never for a /reload or a loading screen.
---@param fn fun()
function State.OnInitialLogin(fn)
	loginListeners[#loginListeners + 1] = fn
end

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
-- A skill rank or a standing changed: skill- and reputation-gated quests may open or close (roadmap #8, GatesMoved).
events:RegisterEvent("SKILL_LINES_CHANGED")
events:RegisterEvent("UPDATE_FACTION")
-- Rest and XP (roadmap #11), by feature detection: the Forever probes never registered these, and the client raises
-- on an event it lacks, so one it refuses just leaves the rest line to the next rebuild.
for _, event in ipairs({ "PLAYER_UPDATE_RESTING", "UPDATE_EXHAUSTION", "PLAYER_XP_UPDATE" }) do
	pcall(events.RegisterEvent, events, event)
end
-- The first argument is PLAYER_ENTERING_WORLD's isInitialLogin, and QUEST_TURNED_IN's questID.
events:SetScript("OnEvent", function(_, event, arg)
	if event == "PLAYER_ENTERING_WORLD" then
		if not ready and LoadCompleted() then
			ready = true
		end
		LoadSkills()
		GatesMoved()
		RestMoved()
		if arg == true then
			for _, fn in ipairs(loginListeners) do
				fn()
			end
		end
	elseif event == "SKILL_LINES_CHANGED" or event == "UPDATE_FACTION" then
		if event == "SKILL_LINES_CHANGED" then
			LoadSkills()
		end
		if not GatesMoved() then
			return
		end
	elseif event == "PLAYER_UPDATE_RESTING" or event == "UPDATE_EXHAUSTION" or event == "PLAYER_XP_UPDATE" then
		if not RestMoved() then
			return
		end
	elseif event == "QUEST_TURNED_IN" and arg then
		completed[arg] = true
		ns.TurnedIn(arg)
	end
	Coalesce()
end)
