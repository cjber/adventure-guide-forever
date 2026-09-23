---@type string, AGFNamespace
local addonName, ns = ...

-- Only WoW: Forever loads this addon, so in game it is simply the Adventure Guide.
ns.TITLE = "Adventure Guide"

-- Account-wide settings (Settings.lua), one key per row on the AddOns page. A missing key
-- always reads as its default here, so an old save file and a new option agree (WFA-14).
---@type table<string, boolean>
local DEFAULTS = {
	showTracker = true,
	showMapPins = true,
	showQuestGivers = true,
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
local cachedRoute = { steps = {}, zones = {} }
local dirty = true
local pendingRebuild = false
---@type fun()[]
local routeListeners = {}

local function BuildRoute()
	return ns.Model.Plan(ns.Data, ns.State.Player(), ns.State.Completed(), ns.State.Log(), ns.Prefs())
end

local function Rebuild()
	pendingRebuild = false
	if not ns.State.Ready() then
		-- Completed-quest data hasn't loaded yet; an empty route beats a wrong one.
		cachedRoute = { steps = {}, zones = {} }
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
		C_Timer.After(0, ns.Integrations.RefreshTravel)
	end)
end

--[[ Slash command and audit ]]

local function Audit()
	local data = ns.Data
	local clientVersion, clientBuild = GetBuildInfo()
	ns.Print(("data from build %s, client build %s.%s"):format(data.build, clientVersion, clientBuild))

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

	ns.Print(("%d bundled quests, %d eligible now, %d completed known"):format(bundled, eligible, completedKnown))
	if not ns.State.Ready() then
		ns.Print("completed-quest data hasn't finished loading yet; the counts above may be low.")
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
		ns.Print("open the world map and use the Adventure Guide tab.")
		ns.Print("/agf audit - check the bundled data against the game")
		ns.Print("/agf dump - save the guide's layout for a bug report")
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
