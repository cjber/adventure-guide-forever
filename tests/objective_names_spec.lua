-- Run from the repository root: luajit tests/objective_names_spec.lua
-- Same-type objectives match by name (Planning/Steps.lua OpenSlots, Integrations/QuestieObjectives.lua): when two
-- slots of a quest share a type, each client objective goes to the slot whose NPC or item name its words hold, so a
-- log that lists them in another order than QuestieDB keeps the finished one off the route; without a name, order.
local ns = {}
local harness = dofile("tests/harness.lua")
harness.model(ns)
ns.QuestieFields = { spawns = { "spawns" }, drops = { "npcDrops", "objectDrops", "itemDrops" } }
assert(loadfile("Integrations/QuestieObjectives.lua"))("AdventureGuideForever", ns)
local Model, data, checks = ns.Model, { quests = harness.fixtureQuests(), maps = {} }, 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

-- The Guns of Northwatch (891): Captain Fairmount, Cannoneer Whessan and Cannoneer Smythe, slots 0-2, all kills,
-- named from QuestieDB; the corpus carries the names because the three slots share a type.
local GUNS = 891
local quest = data.quests[GUNS]
equal(quest.names[0], "captain fairmount", "corpus: slot 0's name, lower-cased")
equal(quest.names[1], "cannoneer whessan", "corpus: slot 1's name")
equal(quest.names[2], "cannoneer smythe", "corpus: slot 2's name")
equal(quest.names[4], nil, "corpus: the one collect slot carries no name")

local function Entry(objectives)
	return { id = GUNS, objectives = objectives }
end
local function Kill(text, done)
	return { type = "monster", text = text, done = done, have = done and 1 or 0, need = 1 }
end
local ITEM = { type = "item", text = "Item: 0/1", done = false, have = 0, need = 1 }

-- The client lists Smythe first and has him dead; Fairmount and Whessan are still to do.
local entry = Entry({
	Kill("Cannoneer Smythe slain: 1/1", true),
	Kill("Captain Fairmount slain: 0/1", false),
	Kill("Cannoneer Whessan slain: 0/1", false),
	ITEM,
})
equal(Model.ObjectiveDone(data, entry, 2), true, "by name: Smythe's slot is done")
equal(Model.ObjectiveDone(data, entry, 0), false, "by name: Fairmount's slot is open")
equal(Model.ObjectiveDone(data, entry, 1), false, "by name: Whessan's slot is open")
equal(Model.ObjectiveDone(data, entry, 4), false, "by name: the collect slot is open")

-- Case does not matter; text with no name falls back to order among the slots left.
entry = Entry({
	Kill("cannoneer whessan slain: 1/1", true),
	Kill("Slain: 0/1", false),
	Kill("Slain: 0/1", false),
	ITEM,
})
equal(Model.ObjectiveDone(data, entry, 1), true, "case: Whessan matched in lower case")
equal(Model.ObjectiveDone(data, entry, 0), false, "fallback: the first free slot")
equal(Model.ObjectiveDone(data, entry, 2), false, "fallback: the next free slot")

-- No names at all (one slot per type): order, as before.
entry = Entry({ Kill("A: 1/1", true), Kill("B: 0/1", false), Kill("C: 0/1", false), ITEM })
equal(Model.ObjectiveDone(data, entry, 0), true, "order: the first slot")
equal(Model.ObjectiveDone(data, entry, 1), false, "order: the second slot")

-- The longest name found wins: "Defias Pillager" over "Defias"; a tie on the same length falls back to order.
local saved = quest.names
quest.names = { [0] = "defias", [1] = "defias pillager", [2] = "smythe" }
entry = Entry({ Kill("Defias Pillager slain: 1/1", true), Kill("Defias slain: 0/1", false), Kill("x", false), ITEM })
equal(Model.ObjectiveDone(data, entry, 1), true, "longest: the Pillager's slot")
equal(Model.ObjectiveDone(data, entry, 0), false, "longest: the plain Defias slot open")
quest.names = { [0] = "gnoll", [1] = "gnoll", [2] = "smythe" }
entry = Entry({ Kill("Gnoll slain: 0/1", false), Kill("Gnoll slain: 1/1", true), Kill("x", false), ITEM })
equal(Model.ObjectiveDone(data, entry, 1), true, "tie: order decides")
-- A name the client's words for another objective also hold: the objective whose words are shortest takes it, so the
-- partial match can't steal it ("Riverpaw Gnoll Mystic" holds "gnoll", but not the data's "riverpaw mystic").
quest.names = { [0] = "gnoll", [1] = "riverpaw mystic", [2] = "smythe" }
entry = Entry({
	Kill("Riverpaw Gnoll Mystic slain: 0/1", false),
	Kill("Gnoll slain: 1/1", true),
	Kill("x", false),
	ITEM,
})
equal(Model.ObjectiveDone(data, entry, 0), true, "steal: the Gnoll slot goes to the plain Gnoll objective")
equal(Model.ObjectiveDone(data, entry, 1), false, "steal: the Mystic's slot open")
quest.names = saved

-- QuestieObjectives names only slots that share a type: NPC names (a kill credit's root NPC), item names, lower-cased,
-- each read once per build; English objective text overrides are left out; a failing name read leaves the slot unnamed.
do
	local reads, asked =
		{ Npc = {}, Object = {}, Item = {}, levels = {}, names = { Npc = {}, Object = {}, Item = {} } }, 0
	local rows = {
		Npc = {
			[1] = { name = "Kobold Vermin" },
			[2] = { name = "Kobold Worker" },
			[3] = { name = "Lonely" },
			[5] = { name = "Credit Root" },
		},
		Object = { [9] = { name = "Crate" } },
		Item = { [7] = { name = "Candle" }, [8] = { name = "Wick" } },
	}
	local function Entity(kind)
		return {
			GetAll = function(id, keys)
				if keys[1] == "name" then
					asked = asked + 1
					if id == 666 then
						error("no name field")
					end
					local row = rows[kind][id]
					return row and { row.name }
				end
				return { {} }
			end,
		}
	end
	local lib = { Npc = Entity("Npc"), Object = Entity("Object"), Item = Entity("Item") }
	local function yield() end
	local function Map() end
	local objectives = {
		{ { 1, "Vermin slain" }, { 2 } },
		{ { 9 } },
		{ { 7, "Candles" }, { 8 } },
		nil,
		{ { { 4, 6 }, 5, "Credit given" } },
	}
	local _, _, kinds, unsupported, names = ns.QuestieObjectives(lib, objectives, nil, nil, data, Map, yield, 1, reads)
	-- Kills 0-1, the object 2, the kill credit after them at 3, the collects at 4-5.
	equal(
		kinds[2] == "object" and kinds[3] == "monster" and kinds[4] == "item" and kinds[5] == "item",
		true,
		"names: slots"
	)
	equal(unsupported, nil, "names: supported")
	equal(names[0], "kobold vermin", "names: the NPC's name, lower-cased, no override text")
	equal(names[1], "kobold worker", "names: the second kill")
	equal(names[2], nil, "names: an object of its own type has none")
	equal(names[3], "credit root", "names: a kill credit by its root NPC")
	equal(names[4], "candle", "names: a collect slot")
	equal(names[5], "wick", "names: the second collect slot")
	equal(asked, 5, "names: only the shared slots are read")
	ns.QuestieObjectives(lib, objectives, nil, nil, data, Map, yield, 2, reads)
	equal(asked, 5, "names: read once per build")
	local _, _, _, _, none = ns.QuestieObjectives(lib, { { { 3 } } }, nil, nil, data, Map, yield, 3, reads)
	equal(none, nil, "names: nil with no shared type")
	local _, _, _, _, failed = ns.QuestieObjectives(lib, { { { 666 }, { 1 } } }, nil, nil, data, Map, yield, 4, reads)
	equal(failed[0], nil, "names: a failing read leaves its slot unnamed")
	equal(failed[1], "kobold vermin", "names: the other slot still named")
end

print(("objective_names_spec: %d checks passed"):format(checks))
