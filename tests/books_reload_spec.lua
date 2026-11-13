-- Run from the repository root: luajit tests/books_reload_spec.lua
-- #756: the books and the item IDs a first login builds are in the saved catalogue, so a second login or a /reload
-- adopts them too. Without them the Library books card has no books to offer, and a collect step loses the item
-- quality colour its ID gives, though the first login after a rebuild shows both.
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

-- Questie's live policy, which the second login brings in over the adopted catalogue.
local function Policy(h)
	h.G.Questie = { API = {
		isReady = true,
		RegisterOnReady = function(fn)
			fn()
		end,
	} }
	h.G.QuestieLoader = {
		ImportModule = function()
			return {
				IsDoable = function()
					return true
				end,
			}
		end,
	}
	-- The book object drops the tome the quest collects, as QuestieDB says in game.
	h.G.LibQuestieDB.Item.objectDrops = function(id)
		return id == 700 and { 900 } or {}
	end
end

-- One ordinary quest, one book the librarian takes, and two collect-item slots so the step names carry IDs.
local function Fake()
	return {
		quests = {
			[900001] = {
				name = "Q",
				questLevel = 20,
				requiredLevel = 18,
				startedBy = { { 197 } },
				finishedBy = { { 197 } },
				zoneOrSort = 12,
				objectives = { { { 800, nil, 0 } } },
			},
			[900002] = {
				name = "Book",
				questLevel = 20,
				requiredLevel = 18,
				startedBy = { nil, { 900 } },
				finishedBy = { { 211033 } },
				zoneOrSort = 12,
				objectives = { [3] = { { 700 }, { 701 } } },
			},
		},
		npcs = {
			[197] = { name = "Giver", spawns = { [12] = { { 49, 42 } } }, zoneID = 12 },
			[800] = { name = "Enemy", spawns = { [12] = { { 50, 50 } } } },
			[211033] = { name = "Librarian", spawns = { [12] = { { 49, 43 } } }, zoneID = 12 },
		},
		items = { [700] = { name = "Tome" }, [701] = { name = "Scroll" } },
		objects = { [900] = { name = "Book", spawns = { [12] = { { 50, 40 } } }, zoneID = 12 } },
		zones = { area = { [12] = 1429 } },
	}
end

-- The first login builds the catalogue from QuestieDB.
local first = harness.load({ version = "1.8.0", questiedb = Fake(), setup = Policy })
first.flush()
equal(#first.ns.Data.books, 1, "the first login builds the book list")
equal(first.ns.Data.books[1].id, 900002, "the book is the librarian's quest")
equal(first.ns.Data.itemIDs and first.ns.Data.itemIDs.tome, 700, "the first login names the tome's item ID")
equal(first.ns.Data.itemIDs and first.ns.Data.itemIDs.scroll, 701, "and the scroll's")
check(first.ns.QuestieStatus.state == "questie", "the first login has the QuestieDB catalogue")

-- The next login adopts the saved catalogue, as a /reload does.
local second = harness.load({
	version = "1.8.0",
	questiedb = Fake(),
	charDB = first.G.AdventureGuideForeverCharDB,
	setup = Policy,
})
second.flush()
equal(second.ns.QuestieStatus.state, "questie", "the second login adopts the saved catalogue")
equal(type(second.ns.Data.books), "table", "the adopted catalogue keeps its book list")
equal(#second.ns.Data.books, 1, "with the book the first login found")
equal(second.ns.Data.books[1].id, 900002, "the same book")
equal(second.ns.Data.itemIDs and second.ns.Data.itemIDs.tome, 700, "the adopted catalogue keeps the tome's item ID")
equal(second.ns.Data.itemIDs and second.ns.Data.itemIDs.scroll, 701, "and the scroll's")

for _, h in ipairs({ first, second }) do
	equal(#h.errors, 0, table.concat(h.errors, "\n"))
end
print(("books_reload_spec: %d checks passed"):format(checks))
