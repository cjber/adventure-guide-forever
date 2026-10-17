-- Run from the repository root: luajit tests/polestar_aside_spec.lua
-- Stepping aside for Polestar (Integrations/Polestar.lua, docs/design.md "Alongside Polestar"): while Polestar has a
-- guide running, the route starts and restores nothing, stops what it had started, draws no map marks and the tracker
-- shows one line, whose click takes over. Off with Polestar absent or idle, or with the setting off.
local harness = dofile("tests/harness.lua")
local checks = 0
local function check(condition, label)
	checks = checks + 1
	if not condition then
		error(label, 2)
	end
end

local LOG = { { id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 } }

-- A stand-in for the two calls Adventure Guide makes: Engine.GetGuide, and On for GUIDE_CHANGED when `bus` is set.
local function Stub(guide, bus)
	local stub = { guide = guide, handlers = {} }
	stub.global = {
		Engine = {
			GetGuide = function()
				return stub.guide
			end,
		},
	}
	if bus then
		stub.global.On = function(message, fn)
			stub.handlers[message] = fn
			return {}
		end
	end
	return stub
end

local function Load(stub, db, charDB)
	return harness.load({
		spf = "v1",
		completed = { 844 },
		log = LOG,
		db = db,
		charDB = charDB,
		setup = function(h)
			h.G.Polestar = stub and stub.global
		end,
	})
end

-- No Polestar: nothing changes, the route starts itself as before.
do
	local h = Load(nil)
	h.flush()
	check(not h.ns.Polestar.Active(), "no Polestar, no stepping aside")
	check(h.spf.NavigateRoute >= 1, "the route starts itself without Polestar")
	check(h.tracker.liveBlocks.polestar == nil, "and the tracker has no Polestar line")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

-- Polestar loaded but idle: no guide, no stepping aside.
do
	local h = Load(Stub(nil, true))
	h.flush()
	check(not h.ns.Polestar.Active(), "an idle Polestar is not guiding")
	check(h.spf.NavigateRoute >= 1, "so the route starts itself")
end

-- Polestar guiding: the route stays off, the tracker says so, and its click takes over.
do
	local stub = Stub({ id = "forever/horde/the-barrens" }, true)
	local h = Load(stub, { showMapPins = true, showQuestGivers = true })
	h.flush()
	local ns = h.ns
	-- The map pins shown on the zone the player is in.
	local function Shown()
		h.G.C_Map.OpenWorldMap()
		h.flush()
		h.map:SetMapID(1413)
		h.providers[1]:RefreshAllData()
		local count = 0
		for _, pins in pairs(h.pins) do
			for _, pin in ipairs(pins) do
				count = count + (pin:IsShown() and 1 or 0)
			end
		end
		return count
	end
	check(ns.Polestar.Active(), "a running Polestar guide steps the route aside")
	check(h.spf.NavigateRoute == 0, "nothing starts itself while Polestar guides")
	check(ns.Prefs().guided == nil, "and no journey is recorded as guided")
	check(stub.handlers.GUIDE_CHANGED ~= nil, "Polestar's GUIDE_CHANGED is the re-check")
	local line = h.tracker.liveBlocks.polestar
	check(line ~= nil and line.used ~= false, "the tracker shows the Polestar line")
	check(line.header == ns.L.POLESTAR_GUIDING, "in the guide's words")
	check(h.tracker.layoutOrder[1] == "polestar" and #h.tracker.layoutOrder == 1, "and nothing else")
	check(h.tracker.Header.Text:GetText() == ns.L.TITLE, "the tracker names no journey of its own")
	check(Shown() == 0, "no route rings or givers on the map")

	h.tracker:OnBlockHeaderClick(line, "RightButton")
	check(ns.Polestar.Active(), "a right-click does not take over")
	h.tracker:OnBlockHeaderClick(line, "LeftButton")
	h.flush()
	check(not ns.Polestar.Active(), "a click on the line takes over")
	check(h.spf.NavigateRoute >= 1, "and starts the route")
	check(h.tracker.liveBlocks.polestar == nil or not h.tracker.liveBlocks.polestar.used, "the line goes")
	check(Shown() > 0, "and the map marks come back")

	-- The same guide again (a tab switch back, a reload of its steps) keeps the player's take-over.
	stub.handlers.GUIDE_CHANGED("forever/horde/the-barrens")
	h.flush()
	check(not ns.Polestar.Active(), "the guide taken over from stays taken over")

	-- Polestar starts another guide: the route steps aside again and stops what it had started.
	local cancels = h.spf.Cancel
	stub.guide = { id = "forever/horde/stonetalon" }
	stub.handlers.GUIDE_CHANGED(stub.guide.id)
	h.flush()
	check(ns.Polestar.Active(), "a new Polestar guide steps aside again")
	check(h.spf.Cancel > cancels, "and the route Adventure Guide started stops")
	check(ns.Prefs().guided == nil, "with nothing left marked as guided")

	-- Go on a card is the player taking over too.
	ns.StartRoute()
	h.flush()
	check(not ns.Polestar.Active(), "Go takes over")

	-- Polestar's guide closes: nothing to step aside for, and the take-over is forgotten.
	stub.guide = nil
	stub.handlers.GUIDE_CHANGED(nil)
	h.flush()
	check(not ns.Polestar.Active(), "no Polestar guide, no stepping aside")
	stub.guide = { id = "forever/horde/stonetalon" }
	stub.handlers.GUIDE_CHANGED(stub.guide.id)
	h.flush()
	check(ns.Polestar.Active(), "a guide started afresh steps aside, even the one taken over from before")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

-- The setting off: Polestar guiding changes nothing; turning it on steps aside at once.
do
	local h = Load(Stub({ id = "forever/horde/the-barrens" }, true), { polestarAside = false })
	h.flush()
	check(not h.ns.Polestar.Active(), "with the setting off the route never steps aside")
	check(h.spf.NavigateRoute >= 1, "and starts itself as usual")
	local cancels = h.spf.Cancel
	h.ns.SetSetting("polestarAside", true)
	h.flush()
	check(h.ns.Polestar.Active(), "turning the setting on steps aside")
	check(h.spf.Cancel > cancels, "and stops the route it had started")
end

-- A Polestar with no message bus is read again on a slow timer.
do
	local stub = Stub(nil, false)
	local h = Load(stub)
	h.flush()
	check(not h.ns.Polestar.Active(), "idle at first")
	check(next(h.ticking) ~= nil, "a timer stands in for the message bus")
	stub.guide = { id = "forever/alliance/elwynn" }
	h.tickers()
	h.flush()
	check(h.ns.Polestar.Active(), "the timer notices the guide")
end

-- A GetGuide that errors reads as no guide, never as an error of ours.
do
	local stub = Stub(nil, true)
	stub.global.Engine.GetGuide = function()
		error("not ready")
	end
	local h = Load(stub)
	h.flush()
	check(not h.ns.Polestar.Active(), "an erroring Polestar is treated as idle")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

print(("polestar_aside_spec: %d checks passed"):format(checks))
