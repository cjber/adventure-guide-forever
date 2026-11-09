-- Run from the repository root: luajit tests/cleanup_spec.lua
-- Clean up my log (docs/design.md §2.18): the carry card counts what is ready, grey and unfinishable from here, its
-- tooltip names them, and its right-click menu opens a grey or elsewhere quest on the map without the guide
-- abandoning it.
local harness = dofile("tests/harness.lua")
local checks = 0
local function check(value, label)
	assert(value, label)
	checks = checks + 1
end

local function Carry(ns)
	for _, journey in ipairs(ns.Route().journeys) do
		if journey.kind == "carry" then
			return journey
		end
	end
end

-- The overview's card for `key`, once the panel has drawn it.
local function Card(h, key)
	for _, frame in
		ipairs(h.Find(function(f)
			return f:IsVisible() and f.IconFrame ~= nil and f.journey ~= nil
		end))
	do
		if frame.journey.key == key then
			return frame
		end
	end
end

---@param menu AGFMenuDescription
---@param text string
---@return AGFMenuDescription?
local function MenuEntry(menu, text)
	for _, entry in ipairs(menu.entries or {}) do
		if entry.text == text then
			return entry
		end
		local found = MenuEntry(entry, text)
		if found then
			return found
		end
	end
end

-- One ready quest, one grey, one ruled out and one the data cannot place.
local function Mixed(extra)
	local options = {
		log = {
			{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
			{ id = 843, title = "Gann's Reclamation", level = 5, complete = false },
			{ id = 999999, title = "Mystery", level = 18, complete = false },
			{ id = 844, title = "Plainstrider Menace", level = 12, complete = false, map = 1413 },
		},
		completed = {},
		db = { autoStart = false },
		charDB = { journey = "carry", notInterested = { ["quest:844"] = { title = "Plainstrider Menace" } } },
	}
	for key, value in pairs(extra or {}) do
		options[key] = value
	end
	return harness.load(options)
end

-- A mixed log: the summary counts each quest once, and the carry card draws it.
do
	local h = Mixed()
	local ns = h.ns
	local carry = Carry(ns)
	check(carry ~= nil, "the carry card is offered")
	local cleanup = carry.cleanup
	check(cleanup ~= nil, "there is something to report")
	check(cleanup.ready == 1, "one complete quest to hand in")
	check(cleanup.grey == 1, "one unfinished quest gone grey")
	check(cleanup.elsewhere == 2, "the ruled-out and unplaced quests can't be finished here")
	check(table.concat(cleanup.readyIDs, ",") == "845", "the ready quest's ID")
	check(table.concat(cleanup.greyIDs, ",") == "843", "the grey quest's ID")
	check(table.concat(cleanup.elsewhereIDs, ",") == "844,999999", "the elsewhere quests' IDs, stably sorted")
	check(ns.Overview.CleanupLine(carry) == "Clean up: 1 to hand in, 1 grey, 2 elsewhere", "the card's line")

	-- Its tooltip lists each group's titles under its heading, in the same order, and says how to act on them.
	ns.Overview.CardTooltip({ journey = carry, state = "shown" })
	local text = table.concat(h.tooltip, "\n")
	check(text:find(ns.L.CLEANUP_READY_HEADING, 1, true) ~= nil, "the ready heading")
	check(text:find("The Zhevra", 1, true) ~= nil, "the ready quest's title")
	check(text:find(ns.L.CLEANUP_GREY_HEADING, 1, true) ~= nil, "the grey heading")
	check(text:find("Gann's Reclamation", 1, true) ~= nil, "the grey quest's title")
	check(text:find(ns.L.CLEANUP_ELSEWHERE_HEADING, 1, true) ~= nil, "the elsewhere heading")
	check(text:find("Plainstrider Menace", 1, true) ~= nil, "the ruled-out quest's title")
	check(text:find("Mystery", 1, true) ~= nil, "the unplaced quest's title")
	check(text:find(ns.L.CLEANUP_RIGHT_CLICK, 1, true) ~= nil, "and the right-click instruction")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

-- Nothing to report: a placed, level-appropriate quest in progress leaves no summary at all, and the card's
-- right-click still does nothing.
do
	local h = harness.load({
		db = { autoStart = false },
		planned = true,
		panelHeight = 1200,
		log = { { id = 843, title = "Gann's Reclamation", level = 23, complete = false } },
	})
	local carry = Carry(h.ns)
	check(carry ~= nil, "the carry card still shows")
	check(carry.cleanup == nil, "no cleanup summary")
	check(h.ns.Overview.CleanupLine(carry) == nil, "and no line")
	local owner = h.tracker
	owner.journey, owner.state = carry, "shown"
	h.menu = nil
	h.ns.Overview.CardClick(owner, "RightButton")
	check(h.menu == nil, "with nothing to clean up, right-click opens no menu")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

-- Nearly full: the existing log-full note still says what could go.
do
	local h = harness.load({
		db = { autoStart = false },
		logMax = 3,
		log = { { id = 843, title = "Gann's Reclamation", level = 5, complete = false } },
	})
	local ns = h.ns
	local first = ns.Route().journeys[1]
	check(first.drop ~= nil and #first.drop == 1, "the log-full note still finds a quest to drop")
	local line = ns.Overview.DropLine(first)
	check(line == ns.L.LOG_FULL_ONE or line == ns.L.LOG_FULL:format(#first.drop), "it still says the log is full")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

-- The carry card's right-click menu lists the grey and elsewhere quests under their headings. Choosing one selects
-- it in the game's quest log and opens the map on its zone, but never in combat and never by abandoning it.
do
	local h = Mixed({ planned = true, panelHeight = 1200 })
	local ns = h.ns
	h.flush()
	ns.OpenPanel()
	h.flush()
	local carry = Carry(ns)
	local card = Card(h, carry.key)
	check(card ~= nil, "the carry card is drawn")
	local abandoned, abandonSelected = 0, 0
	h.G.AbandonQuest = function()
		abandoned = abandoned + 1
	end
	h.G.SetAbandonQuest = function()
		abandonSelected = abandonSelected + 1
	end
	h.selectedQuests = {}
	h.Click(card, "RightButton")
	check(h.menu ~= nil, "right-click opens the cleanup menu")
	local expected = table.concat({
		"title: " .. ns.L.CLEANUP_MENU_TITLE,
		"title: " .. ns.L.CLEANUP_GREY_HEADING,
		"button: Gann's Reclamation",
		"title: " .. ns.L.CLEANUP_ELSEWHERE_HEADING,
		"button: Plainstrider Menace",
		"button: Mystery",
	}, "\n")
	check(table.concat(h.MenuLines(h.menu), "\n") == expected, "the menu names each quest under its heading")
	local entry = MenuEntry(h.menu, "Plainstrider Menace")
	check(entry ~= nil, "the elsewhere quest is a menu button")

	h.SetCombat(true)
	local maps = h.counts.SetMapID
	entry.onClick()
	check(#h.selectedQuests == 0, "in combat nothing is selected")
	check(h.counts.SetMapID == maps, "in combat the map does not turn")
	h.SetCombat(false)
	entry.onClick()
	check(h.selectedQuests[#h.selectedQuests] == 844, "the menu selects the quest's log entry")
	-- A MenuUtil callback refuses C_Map.OpenWorldMap (#411), so the open waits for the menu to close.
	h.flush()
	check(h.counts.SetMapID == maps + 1, "and opens the map")
	check(h.map:GetMapID() == 1413, "on the quest's zone")
	check(abandoned == 0, "the guide never abandons a quest")
	check(abandonSelected == 0, "nor marks one to abandon")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

print("cleanup_spec: " .. checks .. " checks passed")
