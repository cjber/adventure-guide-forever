---@type string, AGFNamespace
local addonName, ns = ...

-- Only WoW: Forever loads this addon, so in game it is simply the Adventure Guide.
ns.TITLE = "Adventure Guide"

-- Every line the player reads, in one table: new copy lands here from the start, so one place holds the
-- game's voice (WFA-6) and a later locale only has to replace values. Format strings keep their specifiers.
---@type AGFStrings
ns.L = {
	AUDIT_BUILD = "data from build %s, client build %s.%s",
	AUDIT_COUNTS = "%d bundled quests, %d eligible now, %d completed known",
	AUDIT_NOT_READY = "completed-quest data hasn't finished loading yet; the counts above may be low.",
	HELP_OPEN = "open the world map and use the Adventure Guide tab.",
	HELP_AUDIT = "/agf audit - check the bundled data against the game",
	HELP_DUMP = "/agf dump - save the guide's layout for a bug report",
	HAND_IN_WHEN = "Hand in when you're in %s",
	-- Journey cards (docs/design.md §2.2 and §3): a title, a subline that counts, and a reason when there is one.
	JOURNEY_CARRY = "Finish what you carry",
	JOURNEY_STORY = "A %s story",
	JOURNEY_NEXT_ZONE = "Head to %s at %d",
	CARRY_READY = "%d quests ready to hand in",
	CARRY_READY_ONE = "1 quest ready to hand in",
	CARRY_IN_PROGRESS = "%d quests in progress",
	CARRY_IN_PROGRESS_ONE = "1 quest in progress",
	QUESTS_NEAR = "%d quests near your level",
	QUESTS_NEAR_ONE = "1 quest near your level",
	READY_TO_HAND_IN = "Ready to hand in",
	NOTHING_NEARBY = "Nothing nearby fits your level. Try another zone.",
	LOADING = "Loading your completed quests...",
	SETTING_MAP_PINS_TOOLTIP = "Every Adventure Guide mark on the world map: the route's numbered steps while their "
		.. "zone is shown, and quest givers when those are on too.",
	SETTING_DUNGEONS_DEFAULT_TOOLTIP = "Suggest dungeon and group quests for a character the first time you open "
		.. "the guide. Change it any time from the guide's settings menu.",
	SETTING_GIVERS_TOOLTIP = 'A "!" on the world map over everyone with a quest you can take now. '
		.. "Needs route pins on the map as well.",
	-- The client's own line, localised, where it has one.
	NO_WAYPOINT = MAP_PIN_INVALID_MAP or "You can't place a pin on this map.",
}
local L = ns.L

-- Account-wide settings (Settings.lua), one key per row on the AddOns page. A missing key
-- always reads as its default here, so an old save file and a new option agree (WFA-14).
---@type table<string, boolean>
local DEFAULTS = {
	showTracker = true,
	-- Opt-in: with the Adventure tab closed the map shows no Adventure Guide mark unless the player asks for them.
	showMapPins = false,
	showQuestGivers = false,
	includeDungeonsDefault = false,
}
ns.DEFAULTS = DEFAULTS

-- Per-character prefs (AGFPrefs). `dungeons` seeds from the account-wide default the first
-- time this character is seen; every other key is a plain default merged in on load.
local PREFS_DEFAULTS = {
	quests = true,
	dungeons = false,
	legacy = false,
	professions = false,
	pinned = {},
}

---@type table<string, any>?
local db
---@type AGFPrefs?
local charDB
-- Skipped steps never survive a reload: a step hidden this session is worth seeing again
-- next time the route is rebuilt from scratch.
---@type table<string, boolean>
local sessionSkipped = {}

---@param msg string
function ns.Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99" .. ns.TITLE .. "|r " .. msg)
end

local function LoadDB()
	local loaded = type(AdventureGuideForeverDB) == "table" and AdventureGuideForeverDB or {}
	for key, value in pairs(DEFAULTS) do
		if type(loaded[key]) ~= type(value) then
			loaded[key] = value
		end
	end
	AdventureGuideForeverDB = loaded
	db = loaded
end

local function LoadCharDB()
	local loaded = type(AdventureGuideForeverCharDB) == "table" and AdventureGuideForeverCharDB or {}
	-- First time this character is seen: honour the account-wide default instead of PREFS_DEFAULTS.dungeons.
	if loaded.dungeons == nil then
		loaded.dungeons = db and db.includeDungeonsDefault or false
	end
	for key, value in pairs(PREFS_DEFAULTS) do
		if key ~= "dungeons" and type(loaded[key]) ~= type(value) then
			loaded[key] = type(value) == "table" and {} or value
		end
	end
	if loaded.zone ~= nil and type(loaded.zone) ~= "number" then
		loaded.zone = nil
	end
	if loaded.journey ~= nil and type(loaded.journey) ~= "string" then
		loaded.journey = nil
	end
	-- The defaults loop above guarantees every AGFPrefs field except `skipped`, which ns.Prefs()
	-- always sets before returning; nothing else reads charDB directly.
	---@cast loaded AGFPrefs
	AdventureGuideForeverCharDB = loaded
	charDB = loaded
end

---@param key string
---@return any
function ns.Setting(key)
	local value = db and db[key]
	if value == nil then
		return DEFAULTS[key]
	end
	return value
end

---@param key string
---@param value any
function ns.SetSetting(key, value)
	if not db then
		return
	end
	db[key] = value
	-- Cheap: this only wakes listeners (Panel/Pins/Tracker) to redraw with the new setting;
	-- the route itself rarely depends on an account-wide setting.
	ns.Invalidate()
end

---@return AGFPrefs
function ns.Prefs()
	charDB = charDB or { quests = true, dungeons = false, legacy = false, professions = false, pinned = {} }
	charDB.skipped = sessionSkipped
	return charDB
end

---@param key string
function ns.Skip(key)
	sessionSkipped[key] = true
	ns.Invalidate()
end

---@param key string
function ns.TogglePin(key)
	local prefs = ns.Prefs()
	for index, pinned in ipairs(prefs.pinned) do
		if pinned == key then
			table.remove(prefs.pinned, index)
			ns.Invalidate()
			return
		end
	end
	prefs.pinned[#prefs.pinned + 1] = key
	ns.Invalidate()
end

--[[ Route: rebuilt lazily, with invalidations from events/prefs coalesced onto one
     C_Timer.After(0) so a burst of QUEST_LOG_UPDATE events costs one rebuild. ]]

---@type AGFRoute
local cachedRoute = { journeys = {}, steps = {}, zones = {} }
local dirty = true
local pendingRebuild = false
---@type fun()[]
local routeListeners = {}

-- Combat ends: the full build the fight put off. Registered only while one is owed, so no event runs otherwise.
local afterCombat = CreateFrame("Frame")
afterCombat:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	ns.Invalidate()
end)

-- In combat only the cheap rebuild runs (the log's steps; the rest as the last full build left them), and the full
-- one waits for PLAYER_REGEN_ENABLED: looting a quest item mid-fight must not cost a frame.
local function BuildRoute()
	local state = ns.State
	if InCombatLockdown() then
		afterCombat:RegisterEvent("PLAYER_REGEN_ENABLED")
		return ns.Model.Refresh(ns.Data, state.Player(), state.Log(), ns.Prefs(), cachedRoute, state.MapName)
	end
	return ns.Model.Plan(ns.Data, state.Player(), state.Completed(), state.Log(), ns.Prefs(), state.MapName)
end

local function Rebuild()
	pendingRebuild = false
	if not ns.State.Ready() then
		-- Completed-quest data hasn't loaded yet; an empty route beats a wrong one.
		cachedRoute = { journeys = {}, steps = {}, zones = {} }
		return
	end
	cachedRoute = BuildRoute()
	dirty = false
end

---@return AGFRoute
function ns.Route()
	if dirty then
		Rebuild()
	end
	return cachedRoute
end

---@param fn fun()
function ns.OnRouteChange(fn)
	routeListeners[#routeListeners + 1] = fn
end

local function NotifyRouteChange()
	for _, fn in ipairs(routeListeners) do
		fn()
	end
end

-- Skipped when an invalidation landed since the rebuild: ns.Route() would rebuild in this frame too, and the
-- pending rebuild queues its own refresh.
local function RefreshTravel()
	if not pendingRebuild then
		ns.Integrations.RefreshTravel()
	end
end

function ns.Invalidate()
	dirty = true
	if pendingRebuild then
		return
	end
	pendingRebuild = true
	C_Timer.After(0, function()
		Rebuild()
		NotifyRouteChange()
		-- Step 1's travel line gets a frame of its own: at most one Shortest Path estimate, never in the rebuild's.
		C_Timer.After(0, RefreshTravel)
	end)
end

--[[ Slash command and audit ]]

local function Audit()
	local data = ns.Data
	local clientVersion, clientBuild = GetBuildInfo()
	ns.Print(L.AUDIT_BUILD:format(data.build, clientVersion, clientBuild))

	local bundled = 0
	for _ in pairs(data.quests) do
		bundled = bundled + 1
	end

	local player, completed, log = ns.State.Player(), ns.State.Completed(), ns.State.Log()
	local eligible = 0
	for questID in pairs(data.quests) do
		if ns.Model.Eligible(data, player, completed, log, questID) then
			eligible = eligible + 1
		end
	end

	local completedKnown = 0
	for _ in pairs(completed) do
		completedKnown = completedKnown + 1
	end

	ns.Print(L.AUDIT_COUNTS:format(bundled, eligible, completedKnown))
	if not ns.State.Ready() then
		ns.Print(L.AUDIT_NOT_READY)
	end
end

SLASH_ADVENTUREGUIDEFOREVER1 = "/agf"
SLASH_ADVENTUREGUIDEFOREVER2 = "/adventureguide"
SlashCmdList.ADVENTUREGUIDEFOREVER = function(msg)
	local command = strtrim(msg or ""):lower()
	if command == "audit" then
		Audit()
	elseif command == "dump" then
		ns.Dump()
	elseif command == "" then
		if ns.OpenPanel then
			ns.OpenPanel()
		end
	else
		ns.Print(L.HELP_OPEN)
		ns.Print(L.HELP_AUDIT)
		ns.Print(L.HELP_DUMP)
	end
end

function AdventureGuideForever_OnAddonCompartmentClick()
	if not WorldMapFrame:IsShown() then
		ToggleWorldMap()
	end
	if ns.OpenPanel then
		ns.OpenPanel()
	end
end

-- Deferred to ADDON_LOADED: every TOC file (including State.lua and Settings.lua, which load
-- after this one) has run by then, so forward references to ns.State/ns.RegisterSettings resolve.
EventUtil.ContinueOnAddOnLoaded(addonName, function()
	LoadDB()
	LoadCharDB()
	ns.State.OnChange(ns.Invalidate)
	if ns.RegisterSettings then
		ns.RegisterSettings()
	end
end)
