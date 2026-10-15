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
equal(quest.names[0][1], "Captain Fairmount", "corpus: slot 0's name")
equal(quest.names[1][1], "Cannoneer Whessan", "corpus: slot 1's name")
equal(quest.names[2][1], "Cannoneer Smythe", "corpus: slot 2's name")
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
quest.names = { [0] = { "Defias" }, [1] = { "Defias Pillager" }, [2] = { "Smythe" } }
entry = Entry({ Kill("Defias Pillager slain: 1/1", true), Kill("Defias slain: 0/1", false), Kill("x", false), ITEM })
equal(Model.ObjectiveDone(data, entry, 1), true, "longest: the Pillager's slot")
equal(Model.ObjectiveDone(data, entry, 0), false, "longest: the plain Defias slot open")
quest.names = { [0] = { "Gnoll" }, [1] = { "Gnoll" }, [2] = { "Smythe" } }
entry = Entry({ Kill("Gnoll slain: 0/1", false), Kill("Gnoll slain: 1/1", true), Kill("x", false), ITEM })
equal(Model.ObjectiveDone(data, entry, 1), true, "tie: order decides")
quest.names = saved

-- QuestieObjectives names only slots that share a type: an NPC's name and the objective's own text, read once.
do
	local reads, asked = { Npc = {}, Object = {}, Item = {} }, 0
	local rows = {
		Npc = { [1] = { name = "Kobold Vermin" }, [2] = { name = "Kobold Worker" }, [3] = { name = "Lonely" } },
		Object = { [9] = { name = "Crate" } },
		Item = { [7] = { name = "Candle" } },
	}
	local function Entity(kind)
		return {
			GetAll = function(id, keys)
				local row = rows[kind][id]
				if keys[1] == "name" then
					asked = asked + 1
					return row and { row.name }
				end
				return { {} }
			end,
		}
	end
	local lib = { Npc = Entity("Npc"), Object = Entity("Object"), Item = Entity("Item") }
	local function yield() end
	local objectives = { { { 1, "Vermin slain" }, { 2 } }, { { 9 } }, { { 7 } } }
	local need, _, kinds, unsupported, names = ns.QuestieObjectives(
		lib,
		objectives,
		nil,
		nil,
		data,
		function() end,
		yield,
		1,
		reads
	)
	equal(need[0] ~= nil and need[1] ~= nil and kinds[2] == "object" and kinds[4] == "item", true, "names: slots")
	equal(unsupported, nil, "names: supported")
	equal(names[0][1], "Kobold Vermin", "names: the NPC's name")
	equal(names[0][2], "Vermin slain", "names: and the objective's text")
	equal(names[1][1], "Kobold Worker", "names: the second kill")
	equal(names[2], nil, "names: an object of its own type has none")
	equal(names[4], nil, "names: an item of its own type has none")
	equal(asked, 2, "names: only the shared slots are read")
	ns.QuestieObjectives(lib, objectives, nil, nil, data, function() end, yield, 2, reads)
	equal(asked, 2, "names: read once per build")
	local _, _, _, _, none = ns.QuestieObjectives(lib, { { { 3 } } }, nil, nil, data, function() end, yield, 3, reads)
	equal(none, nil, "names: nil with no shared type")
end

print(("objective_names_spec: %d checks passed"):format(checks))
