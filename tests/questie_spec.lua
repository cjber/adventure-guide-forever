-- Run from the repository root: luajit tests/questie_spec.lua
-- QuestieDB as a quest source (QuestieSource.lua, docs/design.md §2.14) through tests/harness.lua's synthetic
-- QuestieDB: the checks that keep the bundled data, the mapping against a mirror of the bundled data, the starts it
-- withholds, and the build's frame slices and swap.
local harness = dofile("tests/harness.lua")
local checks = 0

local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local function same(a, b)
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for key, value in pairs(a) do
		if not same(value, b[key]) then
			return false
		end
	end
	for key in pairs(b) do
		if a[key] == nil then
			return false
		end
	end
	return true
end

local bundled = {}
assert(loadfile("Data/Quests.lua"))("AdventureGuideForever", bundled)
bundled = bundled.Data

local function Audit(h)
	local from = #h.prints + 1
	h.G.SlashCmdList.ADVENTUREGUIDEFOREVER("audit")
	return table.concat(h.prints, "\n", from)
end

-- Every check that fails keeps the bundled data and says why in /agf audit.
for _, case in ipairs({
	{ nil, "QUESTIE_ABSENT" },
	{ { contract = 1 }, "QUESTIE_CONTRACT" },
	{ { flavor = "Vanilla" }, "QUESTIE_FLAVOUR" },
	{ { missing = "questLevel" }, "QUESTIE_FIELD", "questLevel" },
	{ { noZones = true }, "QUESTIE_ZONES" },
}) do
	local fake, key, arg = case[1], case[2], case[3]
	local h = harness.load({ questiedb = fake })
	local L = h.ns.L
	local reason = arg and L[key]:format(arg) or L[key]
	equal(#h.errors, 0, key .. ": errors")
	equal(h.ns.QuestieStatus.state, "bundled", key .. ": state")
	equal(h.ns.QuestieStatus.reason, reason, key .. ": reason")
	equal(h.ns.Data.source:find("^CMaNGOS") ~= nil, true, key .. ": the bundled data stays")
	local audit = Audit(h)
	equal(audit:find(L.AUDIT_SOURCE_BUNDLED, 1, true) ~= nil, true, key .. ": audit names the bundled data")
	equal(audit:find(L.AUDIT_QUESTIE_UNUSED:format(reason), 1, true) ~= nil, true, key .. ": audit says why")
end

-- A read that raises keeps the bundled data too.
do
	local fake = harness.questieMirror(bundled)
	fake.quests = setmetatable({}, {
		__index = function()
			error("unreadable")
		end,
	})
	local h = harness.load({ questiedb = fake })
	equal(h.ns.QuestieStatus.state, "bundled", "a failed read: state")
	equal(h.ns.QuestieStatus.reason:find("unreadable") ~= nil, true, "a failed read: reason")
	equal(h.ns.Data.source:find("^CMaNGOS") ~= nil, true, "a failed read: the bundled data stays")
end

-- A mirror of the bundled data converts back to it: every field of every quest. Only a quest whose bundled start was
-- withheld may differ in its zone (the generator files it by the start it then withholds), and an exclusive group of
-- one (its other members aren't Forever's) closes nothing either way.
do
	local h = harness.load({ questiedb = harness.questieMirror(bundled) })
	local data = h.ns.Data
	equal(#h.errors, 0, "mirror: errors")
	equal(h.ns.QuestieStatus.state, "questie", "mirror: state")
	equal(data.source, "QuestieDB 0.0-test", "mirror: source")
	equal(Audit(h):find(h.ns.L.AUDIT_SOURCE_QUESTIE:format("0.0-test"), 1, true) ~= nil, true, "mirror: audit")
	local sizes = {}
	for _, quest in pairs(bundled.quests) do
		sizes[quest.group or 0] = (sizes[quest.group or 0] or 0) + 1
	end
	local count, members = 0, {}
	for id, quest in pairs(bundled.quests) do
		count = count + 1
		local built = data.quests[id]
		for _, field in ipairs({ "title", "level", "min", "side", "races", "classes", "start", "finish", "pre" }) do
			equal(same(built[field], quest[field]), true, id .. " " .. field)
		end
		for _, field in ipairs({ "preAny", "next", "repeatable", "elite", "dungeon", "raid", "skill", "rep" }) do
			equal(same(built[field], quest[field]), true, id .. " " .. field)
		end
		if quest.start or bundled.zones[quest.zone] then
			equal(built.zone, quest.zone, id .. " zone")
		end
		if quest.group and sizes[quest.group] > 1 then
			members[quest.group] = members[quest.group] or built.group
			equal(built.group ~= nil and built.group == members[quest.group], true, id .. " group")
		end
	end
	for id in pairs(data.quests) do
		equal(bundled.quests[id] ~= nil, true, id .. " only the bundled data's quests")
	end
	equal(count > 3000, true, "mirror: quest count")
end

-- One mirror, changed quest by quest: what QuestieDB says wins, and a start is withheld whenever it names a
-- requirement the planner can't check. Kobold Camp Cleanup (7) starts with Marshal McBride (197) in Northshire.
local fake = harness.questieMirror(bundled)
local mcBride = fake.npcs[197]
-- A subzone (a synthetic area 90001 inside Elwynn Forest's) files the quest under its parent zone.
fake.zones.parent = { [90001] = 1429 }
fake.quests[7].zoneOrSort = 90001
-- A spawn on a map the data doesn't place is dropped; McBride's other spawn stands.
mcBride.spawns[90002] = { { 10, 10 } }
fake.zones.area[90002] = 99999
-- A new giver 25 yards from McBride's door joins his town; one in Elwynn's far corner joins none.
fake.npcs[900001] = { name = "Near", spawns = { [1429] = { { 49.2, 41.8 } } }, zoneID = 1429 }
fake.npcs[900002] = { name = "Far", spawns = { [1429] = { { 2, 97 } } }, zoneID = 1429 }
fake.quests[33].startedBy = { { 900001 } }
fake.quests[18].finishedBy = { { 900002 } }
-- An item starts it: no start, as the bundled data.
fake.quests[783].startedBy = { nil, nil, { 12345 } }
-- Exclusive quests, joined through a middle one, are one group named by the lowest ID.
fake.quests[33].exclusiveTo = { 18 }
fake.quests[6].exclusiveTo = { 18 }
-- Requirements the planner has no state for withhold the start; the finish stays for the log.
local GATED = {
	{ 5, "requiredSpell", 1234 },
	{ 15, "requiredMaxLevel", 20 },
	{ 21, "parentQuest", 20 },
	{ 22, "breadcrumbForQuestId", 38 },
	{ 35, "exclusiveTo", { 999999 } },
	{ 37, "preQuestGroup", { 999999 } },
	{ 39, "preQuestSingle", { -40 } },
	{ 40, "requiredMinRep", { 99999, 3000 } },
	{ 46, "questFlags", 1024 },
}
for _, case in ipairs(GATED) do
	assert(bundled.quests[case[1]].start, case[1] .. " has a bundled start")
	fake.quests[case[1]][case[2]] = case[3]
end
-- The level cap as a maximum is none.
fake.quests[47].requiredMaxLevel = 255
-- A start only where the bundled data has one (its lack is a gate or an event-only giver), whatever giver QuestieDB
-- names.
local startless
for id, quest in pairs(bundled.quests) do
	startless = startless or (not quest.start and fake.quests[id] and id) or nil
end
fake.quests[startless].startedBy = { { 197 } }
-- What QuestieDB leaves out stays bundled: a level that scales with the player (-1), a minimum level, a dungeon it
-- files elsewhere, and a giver it can't place (every spawn on an area no map has).
fake.quests[33].questLevel = -1
fake.quests[33].requiredLevel = nil
local dungeonQuest
for id, quest in pairs(bundled.quests) do
	dungeonQuest = dungeonQuest or (quest.dungeon and fake.quests[id] and id) or nil
end
fake.quests[dungeonQuest].zoneOrSort = 1429
local unplaced
for id, quest in pairs(bundled.quests) do
	local finish = quest.finish and quest.finish.npc
	unplaced = unplaced or (finish and finish ~= 197 and fake.quests[id] and fake.npcs[finish] and id) or nil
end
fake.npcs[bundled.quests[unplaced].finish.npc].spawns = { [90003] = { { 50, 50 } } }
-- A quest typed Raid (Paragons of Power, filed outdoors in the bundled data) stays a raid's though QuestieDB files it
-- under a party instance (the Deadmines, 36).
assert(bundled.quests[8053].raid and not bundled.quests[8053].dungeon and not bundled.instances[36].raid)
fake.quests[8053].zoneOrSort = fake.zones.instances[36]
-- A quest the bundled data lacks is left out: nothing says what else gates it.
fake.quests[999998] = { name = "Unknown", questLevel = 5, requiredLevel = 1, startedBy = { { 197 } } }

local h = harness.load({ questiedb = fake })
local quests = h.ns.Data.quests
equal(#h.errors, 0, "changed mirror: errors")
equal(quests[7].zone, 1429, "a subzone's quest is its parent zone's")
equal(same(quests[7].start, bundled.quests[7].start), true, "McBride's placed spawn")
equal(quests[33].start.name, "Near", "the new giver")
equal(quests[33].start.hub, bundled.quests[7].start.hub, "a giver near a town joins it")
equal(quests[18].finish.name, "Far", "the far ender")
equal(quests[18].finish.hub, nil, "a giver far from any town joins none")
equal(quests[783].start, nil, "an item-started quest has no start")
equal(quests[6].group, 6, "an exclusive group: 6")
equal(quests[18].group, 6, "an exclusive group: 18")
equal(quests[33].group, 6, "an exclusive group: 33")
for _, case in ipairs(GATED) do
	equal(quests[case[1]].start, nil, case[1] .. " " .. case[2] .. " withholds the start")
	equal(same(quests[case[1]].finish, bundled.quests[case[1]].finish), true, case[1] .. " keeps its finish")
end
equal(quests[47].start ~= nil, true, "the level cap as a maximum keeps the start")
equal(quests[startless].start, nil, "no start where the bundled data has none")
equal(quests[33].level, bundled.quests[33].level, "a scaling level: the bundled one")
equal(quests[33].min, bundled.quests[33].min, "no minimum: the bundled one")
equal(quests[dungeonQuest].dungeon, bundled.quests[dungeonQuest].dungeon, "a dungeon QuestieDB files elsewhere")
equal(same(quests[unplaced].finish, bundled.quests[unplaced].finish), true, "an unplaced giver keeps the bundled place")
equal(quests[unplaced].finish ~= bundled.quests[unplaced].finish, true, "a copy of the bundled place")
equal(quests[999998], nil, "a quest the bundled data lacks")
equal(quests[8053].dungeon, 36, "a raid's quest QuestieDB files in a party instance: that instance")
equal(quests[8053].raid, true, "and still a raid's")

-- The build runs a slice a frame from login, 2 ms each, on the bundled data until the swap; then one rebuild.
do
	local frames, perFrame, during, invalidated = 0, {}, true, 0
	local h2 = harness.load({
		questiedb = harness.questieMirror(bundled),
		setup = function(h2)
			h2.clockStep = 0.01
			local after = h2.G.C_Timer.After
			h2.G.C_Timer.After = function(delay, fn)
				frames = frames + 1
				return after(delay, fn)
			end
			local getAll = h2.G.LibQuestieDB.Quest.GetAll
			h2.G.LibQuestieDB.Quest.GetAll = function(...)
				perFrame[frames] = (perFrame[frames] or 0) + 1
				during = during and h2.ns.Data.source:find("^CMaNGOS") ~= nil
				during = during and h2.ns.QuestieStatus.state == "building"
				return getAll(...) -- multi-value: the wrapper is transparent
			end
			local invalidate = h2.ns.Invalidate
			h2.ns.Invalidate = function()
				invalidated = invalidated + (h2.ns.QuestieStatus.state == "questie" and 1 or 0)
				invalidate()
			end
		end,
	})
	local slices, most = 0, 0
	for _, count in pairs(perFrame) do
		slices, most = slices + 1, math.max(most, count)
	end
	equal(#h2.errors, 0, "slices: errors")
	equal(slices > 10, true, "slices: the build spans frames (" .. slices .. ")")
	equal(most <= 201, true, "slices: at most 2 ms of quests a frame (" .. most .. ")")
	equal(during, true, "slices: the bundled data serves while it builds")
	equal(h2.ns.QuestieStatus.state, "questie", "slices: swapped")
	equal(invalidated, 1, "slices: one invalidation after the swap")
end

print(("questie_spec: %d checks passed"):format(checks))
