-- Run from the repository root: luajit tests/smoke_spec.lua
-- The whole interactive surface, headless: every saved setting, every window tab and its buttons, the map panel, its
-- context menus and its pins, across representative profiles, each action asserting no Lua error (h.errors). A crash
-- in game shows up here named by the setting, frame or screen that raised it. What it cannot reach is the client a
-- /reload runs against; the native block clicks live in tracker_host_spec.
local harness = dofile("tests/harness.lua")
local checks = 0

-- What the run exercised, for its closing line: distinct frames, clicks, hovers, menus, pins and settings writes.
local stats = {
	profiles = 0,
	tabs = 0,
	frames = 0,
	frameSet = {},
	clicks = 0,
	hovers = 0,
	menus = 0,
	pins = 0,
	settings = 0,
	rows = 0,
}

-- Every action, wrapped: the errors it added, or the driver's own throw, become one failure naming the action.
local function Run(h, label, fn)
	checks = checks + 1
	local before = #h.errors
	local ok, err = xpcall(fn, debug.traceback)
	if not ok then
		error(("%s: driver threw:\n%s"):format(label, tostring(err)), 2)
	end
	if #h.errors > before then
		local raised = {}
		for index = before + 1, #h.errors do
			raised[#raised + 1] = h.errors[index]
		end
		error(("%s: %d Lua error(s):\n%s"):format(label, #raised, table.concat(raised, "\n---\n")), 2)
	end
end

-- The harness holds no Lua error: loading raises outside any action, so this is the check that sees it.
local function Clean(h, label)
	checks = checks + 1
	if #h.errors > 0 then
		error(("%s: %d Lua error(s):\n%s"):format(label, #h.errors, table.concat(h.errors, "\n---\n")), 2)
	end
end

-- A frame's name for a failure: its global name, else its label, else its type and parent.
local function Name(frame)
	local name = frame.name
	if not name then
		name = frame.text
	end
	if not name then
		local parent = frame.parent
		name = (frame.objectType or "Frame") .. "@" .. tostring(parent and (parent.name or parent.objectType) or "?")
	end
	return name
end

local function Descends(frame, root)
	local node = frame
	while node do
		if node == root then
			return true
		end
		node = node.parent
	end
	return false
end

local function Interactive(frame)
	local scripts = frame.scripts
	return (scripts and (scripts.OnClick or scripts.OnMouseUp or scripts.OnMouseDown)) or frame.mouseUpHandler ~= nil
end

local function Hoverable(frame)
	local scripts = frame.scripts
	return (scripts and (scripts.OnEnter or scripts.OnLeave)) or frame.OnMouseEnter ~= nil
end

local function ClickFrame(h, frame, button)
	local scripts = frame.scripts or {}
	if scripts.OnClick then
		h.call(scripts.OnClick, frame, button)
	end
	if scripts.OnMouseUp then
		h.call(scripts.OnMouseUp, frame, button)
	end
	if frame.mouseUpHandler then
		h.call(frame.mouseUpHandler, frame, button, true)
	end
	if scripts.OnMouseDown then
		h.call(scripts.OnMouseDown, frame, button)
	end
end

local function HoverFrame(h, frame, enter)
	local scripts = frame.scripts or {}
	if enter then
		if frame.OnMouseEnter then
			h.call(frame.OnMouseEnter, frame)
		elseif scripts.OnEnter then
			h.call(scripts.OnEnter, frame)
		end
		frame.mouseOver = true
	else
		if frame.OnMouseLeave then
			h.call(frame.OnMouseLeave, frame)
		elseif scripts.OnLeave then
			h.call(scripts.OnLeave, frame)
		end
		frame.mouseOver = false
	end
end

-- A menu entry's callback (and its enabled predicate) can raise: h.call records it.
local function Enabled(h, entry)
	local enabled = true
	if entry.IsEnabled then
		h.call(function()
			enabled = entry:IsEnabled()
		end)
	end
	return enabled
end

-- Every context/menu a click opened: each button's callback, then whatever it opens, bounded.
local function DrainMenu(h, label, depth)
	depth = depth or 0
	if depth > 5 then
		return
	end
	local menu = h.menu
	h.menu = nil
	if type(menu) ~= "table" or type(menu.entries) ~= "table" then
		return
	end
	for _, entry in ipairs(menu.entries) do
		if type(entry) == "table" and entry.onClick and Enabled(h, entry) then
			stats.menus = stats.menus + 1
			Run(h, ("%s menu %s"):format(label, tostring(entry.text)), function()
				h.call(entry.onClick)
			end)
			DrainMenu(h, ("%s > %s"):format(label, tostring(entry.text)), depth + 1)
		elseif type(entry) == "table" and #(entry.entries or {}) > 0 then
			h.menu = entry
			DrainMenu(h, ("%s > %s"):format(label, tostring(entry.text)), depth + 1)
		end
	end
end

-- Every visible interactive frame under `root` (all frames when nil): hover, then left, right, shift and a second
-- left click, and drain any menu the click opened. `reopen` puts a root back that a click hid, so its later
-- frames stay reachable.
local function DriveScope(h, root, label, reopen)
	local list = {}
	for _, frame in ipairs(h.frames) do
		if (not root or Descends(frame, root)) and frame:IsVisible() and (Interactive(frame) or Hoverable(frame)) then
			list[#list + 1] = frame
		end
	end
	local function keep()
		if reopen and root and not root:IsVisible() then
			Run(h, label .. " reopen", reopen)
		end
	end
	for _, frame in ipairs(list) do
		if frame:IsVisible() then
			local tag = label .. " " .. Name(frame)
			if not stats.frameSet[frame] then
				stats.frameSet[frame] = true
				stats.frames = stats.frames + 1
			end
			if Hoverable(frame) then
				stats.hovers = stats.hovers + 2
				Run(h, tag .. " enter", function()
					HoverFrame(h, frame, true)
				end)
				Run(h, tag .. " leave", function()
					HoverFrame(h, frame, false)
				end)
			end
			if Interactive(frame) then
				stats.clicks = stats.clicks + 4
				for _, button in ipairs({ "LeftButton", "RightButton" }) do
					Run(h, tag .. " click " .. button, function()
						h.menu = nil
						ClickFrame(h, frame, button)
						DrainMenu(h, tag)
					end)
					keep()
				end
				Run(h, tag .. " shift-click", function()
					h.menu = nil
					h.Shift(function()
						ClickFrame(h, frame, "LeftButton")
					end)
					DrainMenu(h, tag)
				end)
				keep()
				Run(h, tag .. " second click", function()
					h.menu = nil
					ClickFrame(h, frame, "LeftButton")
					DrainMenu(h, tag)
				end)
				keep()
			end
		end
	end
end

local PIN_TEMPLATES = {
	"AdventureGuideForeverPinTemplate",
	"AdventureGuideForeverGiverPinTemplate",
	"AdventureGuideForeverPingPinTemplate",
}

-- Every live pin: its tooltip, then its click (a step ring's right-click returns to the story's start).
local function DrivePins(h, label)
	for _, template in ipairs(PIN_TEMPLATES) do
		for index, pin in ipairs(h.pins[template] or {}) do
			stats.pins = stats.pins + 1
			local tag = ("%s %s#%d"):format(label, template, index)
			if pin.OnMouseEnter then
				Run(h, tag .. " enter", function()
					h.call(pin.OnMouseEnter, pin)
				end)
			end
			if pin.OnMouseLeave then
				Run(h, tag .. " leave", function()
					h.call(pin.OnMouseLeave, pin)
				end)
			end
			if pin.OnClick then
				for _, button in ipairs({ "LeftButton", "RightButton" }) do
					Run(h, tag .. " click " .. button, function()
						h.menu = nil
						h.call(pin.OnClick, pin, button)
						DrainMenu(h, tag)
					end)
				end
				Run(h, tag .. " shift-click", function()
					h.Shift(function()
						h.call(pin.OnClick, pin, "LeftButton")
					end)
				end)
			end
		end
	end
end

local function SortedKeys(table_)
	local keys = {}
	for key in pairs(table_) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	return keys
end

--[[ Profiles: the representative states the task names, curated so each dimension is present without a full product. ]]

local function Base(extra)
	local log = {
		{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
		{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
	}
	local options = { completed = { 844 }, log = log }
	for key, value in pairs(extra or {}) do
		options[key] = value
	end
	return options
end

local FULL_LOG = {}
for index = 1, 40 do
	FULL_LOG[index] = {
		id = 100000 + index,
		title = "Quest " .. index,
		level = 13,
		complete = index % 2 == 0,
		map = 1413,
		x = 0.5,
		y = 0.5,
	}
end

local TF_V1 = {
	version = 1,
	spells = { { spellID = 1, name = "Sprint", level = 8, cost = 0, line = "Combat", lineID = 38, general = false } },
}

local TF_V2 = {
	version = 2,
	spells = { { spellID = 2, name = "Gouge", level = 10, cost = 50, line = "Combat", lineID = 38, general = false } },
	trainers = { { npc = 999001, name = "Aranis Hammerhand", map = 1413, x = 0.52, y = 0.4 } },
}

-- A Tweaks Forever reply its API did not place: a known, affordable fee with no level. The addon must leave it out,
-- never raise on a rebuild (the owner's setting-click crash: Integrations.Training's math.max).
local TF_UNPLACED = {
	version = 1,
	spells = {
		{ spellID = 1, name = "No level", cost = 0, line = "Combat", lineID = 38, general = false },
		{ spellID = 2, name = "Placed", level = 5, cost = 0, line = "Combat", lineID = 38, general = false },
	},
}

local function Mirror()
	return harness.questieMirror(harness.data())
end

-- Each profile is {name, options, settle?}: `settle` runs after load, before driving (to force a QuestieDB build).
local profiles = {
	{ "bare", Base() },
	{ "journey", Base({ charDB = { journey = "zone:1413" } }) },
	{ "empty-log", Base({ log = {} }) },
	{ "full-log", Base({ log = FULL_LOG }) },
	{ "spf-v1", Base({ spf = "v1" }) },
	{ "spf-ended", Base({ spf = "ended", charDB = { journey = "zone:1413" } }) },
	{ "tf-v1", Base({ tf = TF_V1 }) },
	{ "tf-v2", Base({ tf = TF_V2 }) },
	{ "tf-unplaced", Base({ tf = TF_UNPLACED, charDB = { journey = "zone:1413" } }) },
	{ "questie", Base({ questiedb = Mirror(), charDB = { journey = "zone:1413" } }) },
	{
		"questie-building",
		Base({ questiedb = Mirror(), charDB = { journey = "zone:1413" } }),
		-- Mid-build, as the sliced catalogue really is between frames; then ready, and drive both.
		function(h)
			h.ns.QuestieStatus.state = "building"
		end,
	},
	{
		"kitchen-sink",
		Base({
			questiedb = Mirror(),
			spf = "ended",
			tf = TF_V2,
			db = { showMapPins = true, showQuestGivers = true, optimisedRoute = true },
			charDB = { journey = "zone:1413", battlegrounds = true },
			log = FULL_LOG,
		}),
	},
}

-- The map and the tracker host that a phase must not double-drive as "leftovers".
local function KnownRoots(h)
	return {
		h.G.AdventureGuideForeverWindow,
		h.G.AdventureGuideForeverPanel,
		h.G.WorldMapFrame,
		h.G.AdventureGuideForeverObjectiveTracker,
		h.G.ForeverTrackerCompanion,
	}
end

local function UnderKnown(h, frame)
	for _, root in ipairs(KnownRoots(h)) do
		if root and Descends(frame, root) then
			return true
		end
	end
	return false
end

local function DriveSettings(h, label)
	for _, key in ipairs(SortedKeys(h.ns.DEFAULTS)) do
		for _, value in ipairs({ true, false }) do
			stats.settings = stats.settings + 1
			Run(h, ("%s SetSetting %s=%s"):format(label, key, tostring(value)), function()
				h.ns.SetSetting(key, value)
				h.flush()
			end)
		end
	end
	-- The real Settings row callback, as the checkbox fires it (Settings.lua), not just ns.SetSetting.
	for _, setting in ipairs(h.addonSettings) do
		stats.rows = stats.rows + 1
		Run(h, ("%s settings row %s"):format(label, setting.key), function()
			if setting.valueChanged then
				setting.valueChanged(setting, not h.ns.Setting(setting.key))
			end
			h.flush()
		end)
	end
end

local function Drive(h, label)
	-- The window: each tab selected, refreshed, then every interactive frame on it.
	Run(h, label .. " open window", function()
		h.ns.OpenWindow()
		h.flush()
	end)
	local window = h.G.AdventureGuideForeverWindow
	if window then
		local tabs = h.ns.Window.Tabs()
		for index, tab in ipairs(tabs) do
			stats.tabs = stats.tabs + 1
			Run(h, ("%s select tab %s"):format(label, tab.key), function()
				h.ns.Window.Select(index)
				h.ns.Window.Refresh()
				h.flush()
			end)
			DriveScope(h, window, ("%s window/%s"):format(label, tab.key), function()
				window:Show()
				h.ns.Window.Refresh()
			end)
		end
		for index, button in ipairs(window.Tabs) do
			Run(h, ("%s tab button %d"):format(label, index), function()
				h.Click(button)
				h.flush()
			end)
		end
	end

	-- The map sidebar: its buttons, then the two side tabs.
	Run(h, label .. " open panel", function()
		h.ns.OpenPanel()
		h.flush()
	end)
	local panel = h.G.AdventureGuideForeverPanel
	if panel then
		DriveScope(h, panel, label .. " panel", function()
			h.ns.OpenPanel()
			h.flush()
		end)
		if h.G.AdventureGuideForeverTab then
			Run(h, label .. " guide tab", function()
				h.ClickTab(h.G.AdventureGuideForeverTab)
				h.flush()
			end)
			DriveScope(h, panel, label .. " panel-guide", h.ns.OpenPanel)
		end
		if h.G.AdventureGuideForeverQuestsTab then
			Run(h, label .. " quests tab", function()
				h.ClickTab(h.G.AdventureGuideForeverQuestsTab)
				h.flush()
			end)
		end
		if h.G.AdventureGuideForeverTab then
			Run(h, label .. " guide tab again", function()
				h.ClickTab(h.G.AdventureGuideForeverTab)
				h.flush()
			end)
		end
	end

	-- The world map and every live pin. Rings preview while the guide is open; givers need both switches, so turn
	-- them on and refresh before driving the pins (a setting click rebuilds and re-acquires them).
	Run(h, label .. " open map", function()
		h.G.OpenWorldMap(h.player.map)
		h.flush()
	end)
	DriveScope(h, h.G.WorldMapFrame, label .. " map", function()
		h.G.OpenWorldMap(h.player.map)
		h.flush()
	end)
	Run(h, label .. " show pins", function()
		h.ns.SetSetting("showMapPins", true)
		h.ns.SetSetting("showQuestGivers", true)
		h.flush()
		h.ns.OpenPanel()
		h.flush()
		h.G.OpenWorldMap(h.player.map)
		h.flush()
	end)
	DrivePins(h, label .. " pin")

	-- Closing and reopening the world map runs its OnHide/OnShow hooks (pins, tooltips, the guide's own refresh).
	Run(h, label .. " close map", function()
		h.G.WorldMapFrame:Hide()
		h.flush()
	end)
	Run(h, label .. " reopen map", function()
		h.G.OpenWorldMap(h.player.map)
		h.flush()
	end)

	-- Every saved setting, then every Settings row callback.
	DriveSettings(h, label)

	-- Anything interactive outside the known roots (a standalone frame the addon owns).
	local leftovers = {}
	for _, frame in ipairs(h.frames) do
		if frame:IsVisible() and (Interactive(frame) or Hoverable(frame)) and not UnderKnown(h, frame) then
			leftovers[#leftovers + 1] = frame
		end
	end
	for _, frame in ipairs(leftovers) do
		DriveScope(h, frame, label .. " leftover/" .. Name(frame))
	end
end

--[[ Run the matrix: every profile out of combat, then in it. ]]

for _, profile in ipairs(profiles) do
	local name, options, settle = profile[1], profile[2], profile[3]
	for _, combat in ipairs({ false, true }) do
		stats.profiles = stats.profiles + 1
		local state = combat and "combat" or "peace"
		local label = ("%s[%s]"):format(name, state)
		local h = harness.load(options)
		Clean(h, label .. " load")
		if settle then
			Run(h, label .. " settle", function()
				settle(h)
				h.flush()
			end)
		end
		if combat then
			Run(h, label .. " enter combat", function()
				h.SetCombat(true)
			end)
		end
		Drive(h, label)
		if combat then
			Run(h, label .. " leave combat", function()
				h.SetCombat(false)
				h.flush()
			end)
			-- The deferred opens run when combat ends; drive once more so they are exercised.
			Drive(h, label .. " after-combat")
		end
		Clean(h, label .. " final")
	end
end

-- QuestieDB building then ready in one session: the held route is rebuilt when the catalogue lands.
do
	stats.profiles = stats.profiles + 1
	local label = "questie-transition"
	local h = harness.load(Base({ questiedb = Mirror(), charDB = { journey = "zone:1413" } }))
	Run(h, label .. " force building", function()
		h.ns.QuestieStatus.state = "building"
		h.ns.Invalidate()
		h.flush()
	end)
	Drive(h, label .. "/building")
	Run(h, label .. " catalogue ready", function()
		h.ns.QuestieStatus.state = "questie"
		h.ns.Invalidate()
		h.flush()
	end)
	Drive(h, label .. "/ready")
	Clean(h, label .. " final")
end

print(
	(
		"smoke_spec: %d checks passed; %d profile runs, %d distinct interactive frames, %d clicks, %d hovers, %d menus, "
		.. "%d pins, %d setting writes, %d settings rows"
	):format(
		checks,
		stats.profiles,
		stats.frames,
		stats.clicks,
		stats.hovers,
		stats.menus,
		stats.pins,
		stats.settings,
		stats.rows
	)
)
