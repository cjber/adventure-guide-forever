-- Run from the repository root: luajit tests/books_spec.lua
-- #706: the Library books card. QuestieDB's 40 book quests (tools/gen_corpus.py's pinned corpus) are filtered to a
-- territory's own zones and the contested ones, with the player's own faction first; a class-restricted book waits for
-- that class, a completed one is gone, and a book QuestieDB places nowhere says so. Stops run smaller zones first and
-- the card ends at the librarian.
local harness = dofile("tests/harness.lua")
local checks = 0

local function check(value, label)
	assert(value, label)
	checks = checks + 1
end

local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local function Load(options)
	local load = {
		planned = true,
		panelHeight = 1600,
		db = { autoStart = false },
		charDB = { journey = "library" },
		completed = { 844 },
	}
	for key, value in pairs(options or {}) do
		load[key] = value
	end
	local h = harness.load(load)
	h.flush()
	return h
end

local function Library(h)
	for _, journey in ipairs(h.ns.Route().journeys) do
		if journey.kind == "library" then
			return journey
		end
	end
end

local function Steps(journey)
	return journey and journey.steps or {}
end

-- The first step for a quest ID, or nil.
local function StepOf(journey, id)
	for _, step in ipairs(Steps(journey)) do
		for _, quest in ipairs(step.quests or {}) do
			if quest == id then
				return step
			end
		end
	end
end

do
	-- A Horde character: the card lists their own territory and the contested zones, never an Alliance-only one.
	local h = Load()
	local ns, journey = h.ns, Library(h)
	check(journey ~= nil, "horde: the card is offered")
	equal(journey.title, ns.L.BOOKS_HORDE, "horde: the player's own faction is the default")
	equal(journey.reason, ns.L.BOOKS_SMALLER_FIRST, "horde: smaller zones first")
	equal(journey.level, ns.Data.quests[78150].level, "horde: the next goal's level is the card's gate")
	local horde, alliance, contested = 0, 0, 0
	for _, step in ipairs(Steps(journey)) do
		if step.kind == "book" then
			local mask = step.map and ns.Data.territory[step.map]
			check(mask ~= 2, "horde: no book in an Alliance zone")
			horde = horde + (mask == 4 and 1 or 0)
			contested = contested + (mask == 0 and 1 or 0)
			alliance = alliance + (mask == 2 and 1 or 0)
		end
	end
	equal(alliance, 0, "horde: no Alliance-only stop")
	check(horde > 0, "horde: the territory's own zones are included")
	check(contested > 0, "horde: contested zones are included")
	equal(StepOf(journey, 79094) ~= nil, true, "horde: Orgrimmar's book is on the route")
	equal(StepOf(journey, 79091), nil, "horde: Ironforge's book is not")
	equal(#Steps(journey) <= ns.Model.MAX_STEPS, true, "horde: the route fits the guide")

	-- The same character choosing the Alliance territory.
	ns.Prefs().booksTerritory = 1
	ns.Invalidate()
	h.flush()
	journey = Library(h)
	equal(journey.title, ns.L.BOOKS_ALLIANCE, "alliance: the chosen territory titles the card")
	equal(StepOf(journey, 79091) ~= nil, true, "alliance: Ironforge's book is on the route")
	for _, step in ipairs(Steps(journey)) do
		if step.kind == "book" then
			check(step.map == nil or ns.Data.territory[step.map] ~= 4, "alliance: no book in a Horde zone")
		end
	end
	equal(#h.errors, 0, "territory: errors\n" .. table.concat(h.errors, "\n"))

	local a = Load({ player = { faction = "Alliance", raceID = 1, classID = 1 } })
	equal(Library(a).title, a.ns.L.BOOKS_ALLIANCE, "alliance: an Alliance character defaults to its own territory")
	equal(#a.errors, 0, "alliance: errors\n" .. table.concat(a.errors, "\n"))
end

do
	-- A book the player has completed is not offered again; the next one takes its place.
	local h = Load({ completed = { 844, 79091 }, charDB = { journey = "library", booksTerritory = 1 } })
	local journey = Library(h)
	equal(StepOf(journey, 79091), nil, "completed: the done book is gone")
	check(#Steps(journey) > 0, "completed: the card still offers the rest")
	equal(#h.errors, 0, "completed: errors\n" .. table.concat(h.errors, "\n"))
end

do
	-- A class-restricted book waits for that class: make Ironforge's mage-only and a shaman sees the next one.
	local h = Load({ charDB = { journey = "library", booksTerritory = 1 } })
	local ns = h.ns
	ns.Data.quests[79091].classes = 128
	ns.Invalidate()
	h.flush()
	local journey = Library(h)
	equal(StepOf(journey, 79091), nil, "class: a mage-only book is not a shaman's")
	check(#Steps(journey) > 0, "class: the card keeps the books anyone may take")

	h = Load({ player = { classID = 8 }, charDB = { journey = "library", booksTerritory = 1 } })
	ns = h.ns
	ns.Data.quests[79091].classes = 128
	ns.Invalidate()
	h.flush()
	journey = Library(h)
	equal(StepOf(journey, 79091) ~= nil, true, "class: the mage sees it")
	equal(#h.errors, 0, "class: errors\n" .. table.concat(h.errors, "\n"))
end

do
	-- A book QuestieDB places nowhere (79953 in 1.0.16) is a row that says so instead of a stop: no waypoint, and no
	-- hand-in promising a book nobody can collect.
	local h = Load({ completed = { 844 }, charDB = { journey = "library", booksTerritory = 1 } })
	local ns = h.ns
	local only
	for _, book in ipairs(ns.Data.books) do
		if book.id == 79953 then
			book.spots = {}
			only = book
		end
	end
	ns.Data.books = { only }
	ns.Invalidate()
	h.flush()
	local journey = Library(h)
	local steps = Steps(journey)
	local step = StepOf(journey, 79953)
	check(step ~= nil, "unlocated: the book is still offered")
	equal(step.detail, ns.L.BOOKS_UNLOCATED, "unlocated: it says the place is unknown")
	equal(step.unlocated, true, "unlocated: it is marked as unlocated")
	equal(step.map, nil, "unlocated: and has no waypoint")
	equal(#steps, 1, "unlocated: it is the card's only row")
	equal(#h.errors, 0, "unlocated: errors\n" .. table.concat(h.errors, "\n"))
end

do
	-- Stops run smaller zones first: the width of the zone's level range, then its lower level and name. The
	-- librarian's hand-in comes after every book.
	local h = Load()
	local ns, journey = h.ns, Library(h)
	local steps, lastBook, firstHandin = Steps(journey), 0, nil
	for index, step in ipairs(steps) do
		if step.kind == "book" then
			lastBook = index
		elseif step.kind == "bookhandin" and not firstHandin then
			firstHandin = index
		end
	end
	check(lastBook > 0, "order: the card has books")
	check(firstHandin ~= nil, "order: the card has a hand-in")
	check(lastBook < firstHandin, "order: every book comes before the hand-in")
	-- A city map has no level range, so it is the narrowest zone of all: its span and lower level are zero.
	local function Key(step)
		local zone = ns.Data.zones[step.map]
		if zone then
			return { zone.max - zone.min, zone.min, zone.name }
		end
		return { 0, 0, ns.Data.maps[step.map].name }
	end
	local function BeforeZone(previous, key)
		if previous[1] ~= key[1] then
			return previous[1] < key[1]
		elseif previous[2] ~= key[2] then
			return previous[2] < key[2]
		end
		return previous[3] <= key[3]
	end
	local previous
	for _, step in ipairs(steps) do
		if step.kind == "book" and step.map then
			local key = Key(step)
			if previous then
				check(BeforeZone(previous, key), "order: " .. previous[3] .. " comes before " .. key[3])
			end
			previous = key
		end
	end
	equal(steps[#steps].kind, "bookhandin", "order: the card ends at the librarian")
	equal(#h.errors, 0, "order: errors\n" .. table.concat(h.errors, "\n"))
end

do
	-- The card's right-click menu: Horde and Alliance territory radio buttons, the player's own faction selected
	-- until they pick the other. Picking it rebuilds the one card for that territory.
	local h = Load()
	local ns, journey = h.ns, Library(h)
	local owner = h.G.CreateFrame("Button", nil, h.G.UIParent)
	ns.Menu.Journey(owner, journey)
	local radios = {}
	for _, entry in ipairs(h.menu.entries) do
		if entry.kind == "radio" then
			radios[#radios + 1] = entry
		end
	end
	equal(#radios, 2, "menu: the two territories")
	equal(radios[1].isSelected(), false, "menu: Alliance is not the Horde character's")
	equal(radios[2].isSelected(), true, "menu: Horde is")
	radios[1].onClick()
	h.flush()
	equal(ns.Prefs().booksTerritory, 1, "menu: the pick is the character's")
	equal(Library(h).title, ns.L.BOOKS_ALLIANCE, "menu: and the card follows it")
	equal(#h.errors, 0, "menu: errors\n" .. table.concat(h.errors, "\n"))
end

do
	-- Skip for now and Not this quest both take a book off the card, as they do on any other stop, and hand-in counts
	-- shrink with it.
	local h = Load()
	local ns = h.ns
	local journey = Library(h)
	local first = nil
	for _, step in ipairs(Steps(journey)) do
		if step.kind == "book" and step.map then
			first = step
			break
		end
	end
	check(first ~= nil, "skip: the card has a placed book")
	ns.Skip(first.key, first.title)
	ns.Invalidate()
	h.flush()
	equal(StepOf(Library(h), first.quests[1]), nil, "skip: the book waits behind Show again")

	ns.Unskip(first.key)
	ns.NotThisQuest(first.quests[1], first.title)
	ns.Invalidate()
	h.flush()
	equal(StepOf(Library(h), first.quests[1]), nil, "not this quest: the book is dropped")
	equal(#h.errors, 0, "skip: errors\n" .. table.concat(h.errors, "\n"))
end

print(("books_spec: %d checks passed"):format(checks))
