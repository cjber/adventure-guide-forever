---@type string, AGFNamespace
local _, ns = ...

if ns.broken then
	return
end

-- Two of Questie's own options the guide sets for the player, each through Questie's own option or function, never by
-- moving or hiding a frame of Questie's:
--
-- * Objective type (#363). On its first run Questie asks which objective marks to show, and its "Questie" and
--   "pfQuest" answers turn the game's quest areas off (QuestieOptionsUtils.ExecuteTheme sets the questPOI CVar to 0),
--   so the map loses the blue areas the guide's steps are drawn round. While that question is still unanswered, the
--   guide answers it with Questie's own "Blizzard" theme, once, and marks it answered, so a new player keeps the
--   game's quest areas. An answer the player already gave is never changed: the tracker's hint offers the areas back.
-- * Questie's tracker (#366). While the guide's tracker shows, Questie's own tracker is off
--   (Questie.db.profile.trackerEnabled), so the quests are not listed twice. Questie's own choice is kept and put back
--   when the setting or the guide's tracker is turned off, and before the game saves at logout, so Questie's saved
--   settings never carry the guide's change.
---@class AGFQuestieOptions
local QuestieOptions = {}
ns.QuestieOptions = QuestieOptions

---@class AGFQuestieSavedProfile
---@field trackerEnabled? boolean

---@class AGFQuestieSaved
---@field profile? AGFQuestieSavedProfile
---@field global? {tutorialObjectiveTypeChosen?: boolean}

---@return AGFQuestieSaved?
local function DB()
	local questie = rawget(_G, "Questie")
	local db = type(questie) == "table" and questie.db
	return type(db) == "table" and db or nil
end

-- One of Questie's modules by name, or nil when Questie has no loader.
---@param name string
---@return table?
local function Module(name)
	local loader = rawget(_G, "QuestieLoader")
	if type(loader) ~= "table" or type(loader.ImportModule) ~= "function" then
		return nil
	end
	local ok, module = pcall(loader.ImportModule, loader, name)
	return ok and type(module) == "table" and module or nil
end

local events = CreateFrame("Frame")
-- The Blizzard theme waits for Questie to be ready, and for combat to end.
local themePending = false
-- Questie's own trackerEnabled from before the guide turned its tracker off; nil while the guide leaves it alone.
---@type boolean?
local held

-- A Questie without RegisterOnReady is asked once a second, at most this many times.
local READY_TRIES = 60
local tries = 0

local function ApplyTheme()
	if not themePending then
		return
	end
	local api = rawget(_G, "Questie").API
	if not (type(api) == "table" and api.isReady) then
		if tries < READY_TRIES then
			tries = tries + 1
			C_Timer.After(1, ApplyTheme)
		end
		return
	end
	if InCombatLockdown() then
		events:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	local utils = Module("QuestieOptionsUtils")
	if utils and type(utils.ExecuteTheme) == "function" then
		themePending = false
		ns.core.SafeCall("Questie objective type", utils.ExecuteTheme, nil, "blizzard")
	end
end

-- Answers Questie's first-run objective type question with its Blizzard theme, when it is still unanswered.
-- Marking it answered happens at once, before Questie's login stage would ask; the theme itself waits until Questie
-- is ready.
local function DefaultTheme()
	local db = DB()
	local global = db and db.global
	if type(global) ~= "table" or global.tutorialObjectiveTypeChosen or GetCVar("questPOI") == nil then
		return
	end
	global.tutorialObjectiveTypeChosen = true
	themePending = true
	local api = rawget(_G, "Questie").API
	if type(api) == "table" and type(api.RegisterOnReady) == "function" and not api.isReady then
		api.RegisterOnReady(ApplyTheme)
	else
		ApplyTheme()
	end
end

-- Questie redraws its tracker from its own option; one that never started this session needs a /reload to show.
---@param showing boolean
local function UpdateTracker(showing)
	local tracker = Module("QuestieTracker")
	if not (tracker and tracker.started and type(tracker.Update) == "function") then
		if showing then
			ns.Print(ns.L.QUESTIE_TRACKER_RELOAD)
		end
		return
	end
	if InCombatLockdown() then
		events:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	ns.core.SafeCall("Questie tracker", tracker.Update, tracker)
end

-- Questie's tracker off while the guide's shows and the setting asks for it; Questie's own choice back otherwise.
---@param quiet? boolean at login, before Questie has built anything, nothing needs redrawing
function QuestieOptions.ApplyTracker(quiet)
	local db = DB()
	local profile = db and db.profile
	if type(profile) ~= "table" then
		return
	end
	local off = ns.Setting("hideQuestieTracker") == true and ns.Setting("showTracker") == true
	if off and held == nil then
		held = profile.trackerEnabled ~= false
		if held then
			profile.trackerEnabled = false
			if not quiet then
				UpdateTracker(false)
			end
		end
	elseif not off and held ~= nil then
		local was = held
		profile.trackerEnabled, held = was, nil
		if was and not quiet then
			UpdateTracker(true)
		end
	end
end

-- Whether Questie is loaded, so its setting has something to act on.
---@return boolean
function QuestieOptions.Available()
	return DB() ~= nil
end

-- Run once the guide's settings are loaded (Core.lua), before Questie's login stages build its tracker or ask its
-- question; PLAYER_LOGIN tries again for a Questie whose settings were not ready yet.
function QuestieOptions.Load()
	DefaultTheme()
	QuestieOptions.ApplyTracker(true)
	events:RegisterEvent("PLAYER_LOGIN")
	events:RegisterEvent("PLAYER_LOGOUT")
end

events:SetScript("OnEvent", function(self, event)
	if event == "PLAYER_LOGIN" then
		self:UnregisterEvent("PLAYER_LOGIN")
		DefaultTheme()
		QuestieOptions.ApplyTracker(true)
	elseif event == "PLAYER_REGEN_ENABLED" then
		self:UnregisterEvent("PLAYER_REGEN_ENABLED")
		ApplyTheme()
		local tracker = Module("QuestieTracker")
		if tracker and tracker.started and type(tracker.Update) == "function" then
			ns.core.SafeCall("Questie tracker", tracker.Update, tracker)
		end
	elseif event == "PLAYER_LOGOUT" then
		-- Questie saves its settings after this: its own choice goes back first.
		local db = DB()
		if held ~= nil and db and type(db.profile) == "table" then
			db.profile.trackerEnabled = held
		end
	end
end)
