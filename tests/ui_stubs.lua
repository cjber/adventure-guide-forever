-- TEMPORARY (guide batch 4, presentation slice): tests/harness.lua with what the window, panel and pins need from the
-- model slice (Session.lua, Order.lua, PvP.Data, Providers.lua, step verbs and checklists, the new copy) and from
-- the harness (CreateRadio, WowStyle1DropdownTemplate, SetCursor/ResetCursor, SetHitRectInsets) until both land.
-- Every piece installs only where the real one is absent, so after the merge this file passes straight through to
-- the harness and can be deleted along with the `dofile("tests/ui_stubs.lua")` lines that load it.
local harness = dofile("tests/harness.lua")

local ADDON = "AdventureGuideForever"

-- The copy the model slice adds to Core.lua (its values), plus STOP_MORE and ORDER_DRAG requested of it.
local COPY = {
	TAB_PVP = "PvP",
	TAB_COMPLETION = "Completion",
	GO_TO_ENTRANCE = "Go to entrance",
	TWEAKS_MISSING = "Install Tweaks Forever to find dungeon entrances.",
	TWEAKS_OUTDATED = "Update Tweaks Forever to find dungeon entrances.",
	ENTRANCE_UNKNOWN = "The entrance location is unknown.",
	LEGACY_MISSING = "Install Legacy Forever to see your completion progress.",
	LEGACY_OUTDATED = "Update Legacy Forever to see your completion progress.",
	COMPLETION_EMPTY = "No completion categories are available here.",
	COMPLETION_LOADING = "Loading completion progress…",
	COMPLETION_UNAVAILABLE = "Completion progress is unavailable here.",
	COMPLETION_COUNTS = "%d/%d",
	COMPLETION_PENDING = "%d pending",
	COMPLETION_CHARACTER = "Character",
	COMPLETION_ACCOUNT = "Account",
	COMPLETION_GO = "Go to objective",
	COMPLETION_NO_LOCATION = "Location unknown",
	COMPLETION_CATEGORY_AREAS = "Areas",
	COMPLETION_CATEGORY_TAXIS = "Flight paths",
	COMPLETION_CATEGORY_DUNGEONS = "Dungeons",
	COMPLETION_CATEGORY_RAIDS = "Raids",
	COMPLETION_CATEGORY_LEGACY = "Legacy",
	COMPLETION_CATEGORY_REPUTATIONS = "Reputations",
	COMPLETION_CATEGORY_QUESTS = "Quests",
	PVP_RANK = "Rank %d",
	PVP_RANK_POINTS = "%d/%d rank points",
	PVP_UNRANKED = "Unranked",
	PVP_CAPPED = "Highest rank reached",
	PVP_UNAVAILABLE = "Rank progress is unavailable.",
	PVP_NO_BATTLEGROUNDS = "No battlegrounds are available at your level.",
	PVP_NO_BATTLEMASTER = "No known battlemaster location",
	PVP_BATTLEGROUND_LEVEL = "From level %d",
	PVP_GO_BATTLEMASTER = "Go to battlemaster",
	PVP_NEXT_REWARD = "Next reward: rank %d · %s",
	SESSION_LABEL = "Time for this journey",
	SESSION_UNLIMITED = "No limit",
	SESSION_MINUTES = "%d min",
	SESSION_ABOUT = "About %d min",
	SESSION_EMPTY = "No complete task fits this session.",
	SESSION_PENDING = "Estimating this session…",
	ORDER_SOONER = "Do this sooner",
	ORDER_LATER = "Do this later",
	ORDER_NEXT = "Do this next",
	ORDER_RESET = "Back to suggested order",
	ORDER_CUSTOM = "Your order",
	ORDER_SUGGESTED = "Suggested",
	ORDER_DRAG = "Drag to change the order",
	TOWN_SKIP_GIVER = "Skip this giver",
	TOWN_GIVER = "%s: %s",
	TOWN_COUNTS = "pick up %d, turn in %d",
	TODAY_MORE = "+%d more",
	STOP_VISIT = "Stop %d: %s",
	STOP_MORE = "+%d",
	SET_HEARTH = "Set your hearth in %s",
}

-- Blizzard's WowStyle1DropdownTemplate (Mainline Blizzard_Menu/DropdownButton.xml): a Text the selected radio's
-- label fills on GenerateMenu, as WowStyleDropdownMixin does.
local function Dropdown(h, frame)
	frame.stockTemplate = frame.stockTemplate and frame.stockTemplate .. ", WowStyle1DropdownTemplate"
		or "WowStyle1DropdownTemplate"
	frame:SetSize(120, 25)
	local text = frame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	-- A stock innard, not the addon's: off the parent's regions, into its internals.
	table.remove(frame.regions)
	text.parentKey, frame.Text = "Text", text
	frame.internals = frame.internals or {}
	frame.internals.Text = text
	function frame.GenerateMenu(self)
		if not self.menuGenerator then
			return
		end
		local saved = h.menu
		local root = h.OpenMenu(self)
		h.menu = saved
		for _, entry in ipairs(root.entries) do
			if entry.kind == "radio" and entry.isSelected(entry.data) then
				self.Text:SetText(entry.text)
			end
		end
	end
end

local function Fill(target, defaults)
	for key, value in pairs(defaults) do
		if target[key] == nil then
			target[key] = value
		end
	end
	return target
end

-- The client and harness pieces.
local function Client(h)
	local G = h.G
	local frame = G.CreateFrame("Frame")
	local Methods = getmetatable(frame).__index
	h.counts.CreateFrame = h.counts.CreateFrame - 1
	if not Methods.SetHitRectInsets then
		function Methods:SetHitRectInsets(left, right, top, bottom)
			self.hitRectInsets = { left, right, top, bottom }
		end
	end
	local root = h.OpenMenu({ menuGenerator = function() end })
	h.menu = nil
	local Description = getmetatable(root).__index
	if not Description.CreateRadio then
		function Description:CreateRadio(text, isSelected, setSelected, data)
			local entry = self:CreateButton(text)
			entry.kind, entry.isSelected, entry.data = "radio", isSelected, data
			entry.onClick = function()
				return setSelected(data)
			end
			return entry
		end
	end
	h.cursor = nil
	if not G.SetCursor then
		G.SetCursor = function(cursor)
			h.cursor = cursor
		end
		G.ResetCursor = function()
			h.cursor = nil
		end
	end
	local probe = pcall(G.CreateFrame, "DropdownButton", nil, nil, "WowStyle1DropdownTemplate")
	h.counts.CreateFrame = h.counts.CreateFrame - 1
	if not probe then
		local create = G.CreateFrame
		G.CreateFrame = function(objectType, name, parent, template)
			if template ~= "WowStyle1DropdownTemplate" then
				return create(objectType, name, parent, template)
			end
			local dropdown = create(objectType, name, parent)
			Dropdown(h, dropdown)
			return dropdown
		end
	end
end

-- The model slice's modules, faked from `options` where the real ones are absent.
local function Model(h, options)
	local G, ns = h.G, h.ns
	Fill(ns.L, COPY)
	if G.LegacyForever == nil and options.legacy then
		local legacy = options.legacy
		h.legacyNavigated = {}
		G.LegacyForever = {
			API = {
				version = legacy.version or 1,
				ZoneSummary = function(map)
					return (legacy.summaries or {})[map], legacy.error
				end,
				Targets = function(map)
					return (legacy.targets or {})[map] or {}
				end,
				Navigate = function(map, key)
					h.legacyNavigated[#h.legacyNavigated + 1] = { map, key }
					return legacy.navigateError == nil, legacy.navigateError
				end,
				Subscribe = function(fn)
					h.legacySubscriber = fn
					return function()
						h.legacySubscriber = nil
					end
				end,
			},
		}
	end
	if G.TweaksForever == nil and options.entrances then
		G.TweaksForever = {
			API = {
				version = 1,
				DungeonEntrance = function(instance)
					return options.entrances[instance]
				end,
			},
		}
	end
	if not ns.Providers then
		local listeners = {}
		h.entrancesGone, h.providersShown = {}, false
		local function Legacy()
			local api = G.LegacyForever and G.LegacyForever.API
			if not G.LegacyForever then
				return nil, "missing"
			elseif type(api) ~= "table" or (api.version or 0) < 1 then
				return nil, "outdated"
			end
			return api, "ready"
		end
		local Providers = {}
		function Providers.LegacyState()
			return (select(2, Legacy()))
		end
		function Providers.OnChange(fn)
			listeners[#listeners + 1] = fn
		end
		function Providers.SetShown(shown)
			h.providersShown = shown
		end
		function Providers.Completion()
			local api, state = Legacy()
			local result = { state = state, zones = {} }
			if not api then
				return result
			end
			local maps = {}
			for map in pairs(options.legacy and options.legacy.summaries or {}) do
				maps[#maps + 1] = map
			end
			table.sort(maps, function(a, b)
				if (a == h.player.map) ~= (b == h.player.map) then
					return a == h.player.map
				end
				return a < b
			end)
			for _, map in ipairs(maps) do
				local summary, err = api.ZoneSummary(map)
				result.zones[#result.zones + 1] = {
					map = map,
					name = summary and summary.name or tostring(map),
					summary = summary,
					targets = api.Targets(map, 3),
					error = err,
				}
			end
			return result
		end
		function Providers.NavigateCompletion(map, key)
			local api, state = Legacy()
			if not api then
				return false, state
			end
			return api.Navigate(map, key) -- multi-value: Legacy's own answer
		end
		function Providers.DungeonEntrance(instance)
			local api = G.TweaksForever and G.TweaksForever.API
			if not G.TweaksForever then
				return nil, "missing"
			elseif type(api) ~= "table" or (api.version or 0) < 1 or type(api.DungeonEntrance) ~= "function" then
				return nil, "outdated"
			end
			local point = api.DungeonEntrance(instance)
			if not point then
				return nil, "unknown"
			end
			return point
		end
		function Providers.GoToEntrance(instance)
			h.entrancesGone[#h.entrancesGone + 1] = instance
			return Providers.DungeonEntrance(instance) ~= nil
		end
		ns.Providers = Providers
		h.legacyChanged = h.legacyChanged or function()
			for _, fn in ipairs(listeners) do
				h.call(fn)
			end
		end
	end
	if not (ns.PvP and ns.PvP.Data) then
		ns.PvP = ns.PvP or {}
		h.pvpGone = {}
		function ns.PvP.Data()
			return options.pvp or { rank = { state = "unavailable" }, battlegrounds = {}, available = false }
		end
		function ns.PvP.Go(id)
			h.pvpGone[#h.pvpGone + 1] = id
			return true
		end
	end
	if not ns.Session then
		local session = Fill(options.session or {}, { minutes = 0, pending = false, empty = false, trimmed = false })
		h.session = session
		ns.Session = {
			Get = function()
				return session.minutes
			end,
			Set = function(minutes)
				session.minutes = minutes
				ns.Invalidate()
			end,
			Info = function()
				return {
					minutes = session.minutes,
					seconds = session.seconds,
					pending = session.pending,
					empty = session.empty,
					trimmed = session.trimmed,
				}
			end,
		}
	end
	if not ns.Order then
		-- `order = {custom?, refuse? = {[to] = true}}`; moves, resets and skips are recorded.
		local order = options.order or {}
		h.orderMoves, h.orderResets, h.giverSkips = {}, 0, {}
		ns.Order = {
			CanMove = function(from, to)
				local route = ns.Route()
				return route.chosen
					and from ~= to
					and to >= 1
					and to <= #route.steps
					and not (order.refuse and order.refuse[to])
			end,
			Move = function(from, to)
				h.orderMoves[#h.orderMoves + 1] = { from, to }
				order.custom = true
				ns.Invalidate()
				return true
			end,
			IsCustom = function()
				return ns.Route().chosen and order.custom == true
			end,
			Reset = function()
				h.orderResets = h.orderResets + 1
				order.custom = false
				ns.Invalidate()
			end,
			SkipGiver = function(stepKey, giverKey)
				h.giverSkips[#h.giverSkips + 1] = { stepKey, giverKey }
				return true
			end,
		}
	end
	-- `decorate(route)` adds what the model slice gives each step (verb, checklist) to a route the old model built.
	if options.decorate then
		local route = ns.Route
		ns.Route = function()
			local built = route()
			options.decorate(built)
			return built
		end
	end
	-- The model slice's new window tabs, when the TOC doesn't list them yet.
	for _, file in ipairs({ "WindowPvP.lua", "WindowCompletion.lua" }) do
		local listed = false
		for line in io.lines(ADDON .. ".toc") do
			listed = listed or line:gsub("\r", "") == file
		end
		if not listed then
			local chunk = assert(loadfile(file))
			setfenv(chunk, G)
			h.call(chunk, ADDON, ns)
		end
	end
end

local stubs = setmetatable({}, { __index = harness })

function stubs.load(options)
	options = options or {}
	local setup = options.setup
	options.setup = function(h)
		Client(h)
		Model(h, options)
		if setup then
			setup(h)
		end
	end
	return harness.load(options)
end

-- A step's verb as the model slice will set it, from what the old model's step already says.
function stubs.Verb(step)
	if step.kind == "town" then
		return "town"
	elseif step.kind == "turnin" then
		return "turnin"
	elseif step.kind == "pickup" then
		return "pickup"
	elseif step.kind == "trainer" then
		return "trainer"
	end
	return "objective"
end

return stubs
