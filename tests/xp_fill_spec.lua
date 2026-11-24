-- Issue #950: the bundled XP fills (Data/XPFills.lua, from forever-db) answer only what the provider has no XP
-- for, and a provider value always wins. The plain load gives the bundled fills beside the model fixture; the
-- mirror build composes the whole corpus through QuestieSource, with a QuestXP module the spec supplies, so the
-- assertions run over the composed catalogue a player's game carries.
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

-- forever-db quests the pinned QuestieDB release lacks (its GetAllIds has no row for them), so their fills sit
-- unused until a provider release carries the quests. Kept exact: a data refresh that changes the set updates
-- this list from the new data.
local OUTSIDE = { 785, 908, 909, 3366, 3911, 5101, 5659, 7681, 7682, 7908, 7961, 7962 }

-- The bundled fills beside the model fixture: every fill names a catalogue quest, but the quests the pinned
-- provider lacks.
local plain = harness.load()
equal(#plain.errors, 0, "plain load errors\n" .. table.concat(plain.errors, "\n"))
local fills = plain.ns.Data.xpfills
equal(type(fills), "table", "the bundled fills are loaded")
local missing = {}
for id in pairs(fills) do
	if not plain.ns.Data.quests[id] then
		missing[#missing + 1] = id
	end
end
table.sort(missing)
equal(#missing, #OUTSIDE, "the fills the catalogue lacks")
for index, id in ipairs(OUTSIDE) do
	equal(missing[index], id, "a fill the catalogue lacks " .. index)
end

-- The provider rows the spec gives QuestieDB's QuestXP module: 4606 also has a fill, with a different value, so
-- the composition must keep the provider's; 16 and 117 have no fill.
local providerXP = {
	[4606] = { 40, 2524 },
	[16] = { 5, 220 },
	[117] = { 8, 340 },
}
local built = harness.load({
	questiedb = harness.questieMirror(harness.data()),
	setup = function(loaded)
		local lib = loaded.G.LibQuestieDB
		local get = lib.Support.Get
		lib.Support.Get = function(name)
			if name == "QuestXP" then
				return { db = providerXP }
			end
			return get(name)
		end
	end,
})
equal(#built.errors, 0, "mirror build errors\n" .. table.concat(built.errors, "\n"))
local quests = built.ns.Data.quests

-- A provider value is kept exactly, never the fill.
equal(quests[4606] ~= nil, true, "4606 composed")
equal(quests[4606].xp, 2524, "the provider's XP wins where it has one")
equal(quests[4606].xp ~= fills[4606], true, "the provider's XP is not the fill's")
equal(quests[16] ~= nil and quests[117] ~= nil, true, "16 and 117 composed")
equal(quests[16].xp, 220, "a provider row where no fill exists: 16")
equal(quests[117].xp, 340, "a provider row where no fill exists: 117")

-- Over the whole catalogue: every XP is exactly its provider row or exactly its fill, and no quest gains one
-- from nowhere.
local expected = 0
for id in pairs(fills) do
	if quests[id] and not providerXP[id] then
		expected = expected + 1
	end
end
for id in pairs(providerXP) do
	if quests[id] then
		expected = expected + 1
	end
end
local filled = 0
for id, quest in pairs(quests) do
	if quest.xp then
		filled = filled + 1
		local provider = providerXP[id]
		if provider then
			equal(quest.xp, provider[2], "a provider value kept: " .. id)
		else
			equal(quest.xp, fills[id], "the fill carried exactly: " .. id)
		end
	end
end
equal(filled, expected, "no quest gained an XP from nowhere")

-- Two exact fills, by id and value, beside the bundled rows they came from.
equal(quests[5640] ~= nil, true, "5640 composed")
equal(quests[5887] ~= nil, true, "5887 composed")
equal(quests[5640].xp, 210, "the exact fill 5640")
equal(quests[5887].xp, 4200, "the exact fill 5887")
equal(quests[5640].xp, fills[5640], "the exact fill 5640 is its bundled row")
equal(quests[5887].xp, fills[5887], "the exact fill 5887 is its bundled row")

print(("xp_fill_spec: %d checks passed"):format(checks))
