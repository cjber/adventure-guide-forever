-- Run from the repository root: luajit tests/party_spec.lua
-- Party quests (docs/design.md §4.5, Core/Party.lua): in a party, a step for a quest someone in the party also has
-- counts as nearer (Model.PartyCost), never a fixed order; a pickup the party has says so. The party's quests come
-- from what the client shows (C_QuestLog.IsUnitOnQuest) and from party members' hidden addon messages, which go out
-- throttled, never in combat, to the party only, and only with the setting on.
local harness = dofile("tests/harness.lua")
local checks = 0
local function check(condition, label)
	checks = checks + 1
	if not condition then
		error(label, 2)
	end
end
local function equal(actual, expected, label)
	check(actual == expected, ("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)))
end

--[[ The planner: Model.PartyCost and the route it leans ]]

do
	local ns = {}
	harness.model(ns)
	local Model = ns.Model

	equal(Model.PartyCost(nil, { 1 }, 400), 400, "cost: out of a party nothing changes")
	equal(Model.PartyCost({ [2] = 1 }, { 1 }, 400), 400, "cost: a step the party doesn't share keeps its cost")
	equal(Model.PartyCost({ [1] = 1 }, { 1 }, 400), 200, "cost: a shared step costs half")
	equal(Model.PartyCost({ [1] = 2 }, { 3, 1 }, 2000), 1700, "cost: but never more than 300 yards less")
	equal(Model.PartyCost({ [1] = 1 }, nil, 400), 400, "cost: a step with no quests keeps its cost")

	-- Model.Nearest takes the party too: the shared stop leads while it is within reach of the nearest.
	local function Stop(key, x, quest)
		return { key = key, x = x, y = 0, continent = 1, known = true, r = 0, quests = { quest } }
	end
	local from = { x = 0, y = 0, continent = 1, known = true }
	local function At(step)
		return step
	end
	local function Keys(path)
		local keys = {}
		for _, step in ipairs(path) do
			keys[#keys + 1] = step.key
		end
		return table.concat(keys, " ")
	end
	equal(Keys(Model.Nearest(from, { Stop("a", 100, 1), Stop("b", 180, 2) }, At)), "a b", "nearest: alone, a leads")
	equal(
		Keys(Model.Nearest(from, { Stop("a", 100, 1), Stop("b", 180, 2) }, At, nil, { [2] = 1 })),
		"b a",
		"nearest: the party's stop leads when it is not much farther"
	)
	equal(
		Keys(Model.Nearest(from, { Stop("a", 100, 1), Stop("b", 900, 2) }, At, nil, { [2] = 1 })),
		"a b",
		"nearest: a party stop far beyond the nearest still waits"
	)

	-- Model.Plan over two carried quests' areas and one pickup.
	local data = {
		quests = {},
		zones = { [1] = { name = "Zone", min = 10, max = 25 } },
		maps = { [1] = { name = "Zone", continent = 0, cx = 0, cy = 0, sx = 1000, sy = 1000 } },
		continents = { [0] = { x = 0, y = 0 } },
	}
	for id, x in ipairs({ 0.3, 0.7, 0.5 }) do
		data.quests[id] = {
			title = "Quest " .. id,
			level = 17,
			min = 10,
			side = 1,
			zone = 1,
			start = { map = 1, x = x, y = 0.2, name = "Giver " .. id, hub = id },
			finish = { map = 1, x = x, y = 0.2, name = "Giver " .. id, hub = id },
			need = { [0] = 10 },
			obj = { { 0, x * 1000, 500, 10 } },
			xp = 1000,
		}
	end
	local log = {}
	for id = 1, 2 do
		log[id] = {
			id = id,
			title = "Quest " .. id,
			level = 17,
			complete = false,
			objectives = { { type = "monster", done = false, have = 0, need = 10 } },
		}
	end
	local player = { level = 19, maxLevel = 60, side = 1, raceBit = 1, classBit = 2, map = 1, x = 0.45, y = 0.5 }
	local prefs = { quests = true, dungeons = false, skipped = {}, journey = "zone:1" }
	local function Route()
		return Model.Plan(data, player, {}, log, prefs).steps
	end
	local function FirstArea()
		for _, step in ipairs(Route()) do
			if step.kind == "area" then
				return step.quests[1]
			end
		end
	end
	equal(FirstArea(), 1, "plan: alone, the nearer area leads")
	player.party = { [2] = 1 }
	equal(FirstArea(), 2, "plan: the area of a quest the party shares leads when it is a little farther")
	player.x = 0.32
	equal(FirstArea(), 1, "plan: standing beside the other area, the nearest still leads (never a fixed order)")
	player.x, player.party = 0.45, nil
	equal(FirstArea(), 1, "plan: the party gone, the order is the plain nearest again")

	-- A pickup someone in the party has says so; the same pickup alone keeps its own reason.
	local function PickupReason()
		for _, step in ipairs(Route()) do
			if step.kind == "town" and step.pickups and step.pickups[1] == 3 and #step.quests == 1 then
				return step.reason
			end
		end
	end
	local alone = PickupReason()
	check(alone ~= nil and alone ~= ns.L.PARTY_HAS, "plan: the pickup alone gives its usual reason")
	player.party = { [3] = 1 }
	equal(PickupReason(), ns.L.PARTY_HAS, "plan: a pickup the party has says someone in the party has it")
	player.party = nil
end

--[[ The message format ]]

do
	local h = harness.load({})
	local Party = h.ns.Party
	local text = Party.Encode({ 1, 35, 36, 845, 12345 })
	equal(text, "1:1,z,10,nh,9ix", "encode: quest IDs in base 36")
	equal(Party.Encode({ 7 }, true), "1?:7", "encode: a message asking for theirs")
	local ids, asks = Party.Decode(text)
	check(ids and ids[1] and ids[35] and ids[36] and ids[845] and ids[12345], "decode: the IDs come back")
	equal(asks, false, "decode: a plain message asks nothing")
	ids, asks = Party.Decode("1?:")
	check(ids and next(ids) == nil and asks == true, "decode: an empty log that asks")
	local many = {}
	for id = 1, 51 do
		many[id] = id
	end
	equal(Party.Encode(many), nil, "encode: more than a log holds is not sent")
	for _, bad in ipairs({
		"2:1",
		"1:0",
		"1:ZZ",
		"1:12345",
		"1:a,,b",
		"1;a",
		"hello",
		("1:" .. ("1,"):rep(60) .. "1"),
		("1:" .. ("a"):rep(300)),
	}) do
		equal(Party.Decode(bad), nil, "decode: refuses " .. bad:sub(1, 20))
	end
	equal(Party.Decode(nil), nil, "decode: refuses nil")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

--[[ The client: what is read, what is sent, and when ]]

local LOG = {
	{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
	{ id = 870, title = "The Forgotten Pools", level = 14, complete = false },
}

-- A party of the player and Ana (or nobody), a client that answers IsUnitOnQuest from `on`, and a chat that records
-- each addon message and timer delay.
local function Load(options)
	options = options or {}
	local party = { grouped = options.grouped ~= false, raid = false, members = { party1 = "Ana" }, on = {} }
	local sent, delays = {}, {}
	local h = harness.load({
		log = LOG,
		db = options.db,
		setup = function(h)
			local G = h.G
			G.IsInGroup = function()
				return party.grouped
			end
			G.IsInRaid = function()
				return party.raid
			end
			G.UnitExists = function(unit)
				return party.grouped and party.members[unit] ~= nil
			end
			G.UnitName = function(unit)
				if unit == "player" then
					return "Me"
				end
				return party.members[unit], "Realm"
			end
			G.C_QuestLog.IsUnitOnQuest = function(unit, questID)
				return party.on[unit] ~= nil and party.on[unit][questID] == true
			end
			G.C_ChatInfo = {
				RegisterAddonMessagePrefix = function(prefix)
					party.prefix = prefix
					return 0
				end,
				SendAddonMessage = function(prefix, text, channel, target)
					sent[#sent + 1] = { prefix = prefix, text = text, channel = channel, target = target }
					return party.result or 0
				end,
			}
			G.Enum = setmetatable({
				SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3, ChannelThrottle = 8 },
			}, { __index = G.Enum })
			local after = G.C_Timer.After
			G.C_Timer.After = function(delay, fn)
				delays[#delays + 1] = delay
				return after(delay, fn)
			end
		end,
	})
	h.party, h.sent, h.delays = party, sent, delays
	return h
end

-- Not in a party: nothing is read or sent, and the planner favours nothing.
do
	local h = Load({ grouped = false })
	h.fire("GROUP_ROSTER_UPDATE")
	h.fire("QUEST_ACCEPTED", 870)
	h.flush()
	equal(#h.sent, 0, "alone: no message is sent")
	equal(h.ns.Party.Quests(), nil, "alone: no party quests")
	equal(h.ns.State.Player().party, nil, "alone: the planner sees no party")
	equal(h.party.prefix, "AGFParty", "the addon message prefix is registered once at load")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

-- In a party: Ana's log, as the client shows it, makes a shared quest, and one message asks for hers.
do
	local h = Load()
	h.party.on.party1 = { [870] = true }
	h.fire("GROUP_ROSTER_UPDATE")
	h.flush()
	local quests = h.ns.Party.Quests()
	check(quests and quests[870] == 1 and quests[845] == nil, "party: the quest Ana has too is shared")
	equal(h.ns.State.Player().party, quests, "party: the planner reads the same answer")
	equal(#h.sent, 1, "party: one message on joining")
	check(table.concat(h.ns.ReportLines(), "\n"):find("Party quests shared: 1", 1, true), "party: /agf report says so")
	local message = h.sent[1]
	equal(message.prefix, "AGFParty", "party: under the addon's prefix")
	equal(message.channel, "PARTY", "party: to the party only")
	equal(message.target, nil, "party: whispering nobody")
	equal(message.text, "1?:nh,o6", "party: the log's quest IDs, asking for theirs")

	-- A second change straight after waits for the gap: never more often than once every 15 seconds.
	local before = #h.delays
	h.fire("QUEST_REMOVED", 845)
	local waited = 0
	for index = before + 1, #h.delays do
		waited = math.max(waited, h.delays[index])
	end
	check(waited >= 15, "throttle: the next message waits the full gap, waited " .. waited)
	-- Nothing changed in the log, so nothing more is said.
	h.flush()
	equal(#h.sent, 1, "throttle: a message saying the same is not sent again")

	-- Ana's message: a quest the player hasn't taken counts too; her asking gets a reply even with nothing new.
	h.time = h.time + 30
	h.fire("CHAT_MSG_ADDON", "AGFParty", "1?:" .. "nh,o6,1kf", "PARTY", "Ana-Realm")
	h.flush()
	quests = h.ns.Party.Quests()
	check(quests and quests[2031] == 1 and quests[870] == 1, "heard: Ana's own log counts, without counting her twice")
	equal(#h.sent, 2, "heard: asking for ours gets one reply")
	equal(h.sent[2].text, "1:nh,o6", "heard: the reply does not ask again")

	-- Ignored: our own echo, another prefix, a raid's channel, a secret sender, a malformed message.
	h.time = h.time + 30
	h.fire("CHAT_MSG_ADDON", "AGFParty", "1?:1", "PARTY", "Me-Realm")
	h.fire("CHAT_MSG_ADDON", "Other", "1?:1", "PARTY", "Ana-Realm")
	h.fire("CHAT_MSG_ADDON", "AGFParty", "1?:1", "RAID", "Ana-Realm")
	h.fire("CHAT_MSG_ADDON", "AGFParty", "1?:1", "PARTY", h.Secret())
	h.fire("CHAT_MSG_ADDON", "AGFParty", "1?:!!", "PARTY", "Ana-Realm")
	h.flush()
	equal(#h.sent, 2, "ignored: none of those asks for a reply")
	check(h.ns.Party.Quests()[1] == nil, "ignored: none of those adds a quest")

	-- Combat: the message waits for the fight's end.
	h.time = h.time + 30
	h.SetCombat(true)
	h.fire("CHAT_MSG_ADDON", "AGFParty", "1?:nh", "PARTY", "Ana-Realm")
	h.flush()
	equal(#h.sent, 2, "combat: nothing is sent in a fight")
	h.SetCombat(false)
	h.flush()
	equal(#h.sent, 3, "combat: the reply goes once the fight ends")

	-- A throttled message is tried once more, then left for the next change.
	h.time = h.time + 30
	h.party.result = 3
	h.fire("CHAT_MSG_ADDON", "AGFParty", "1?:nh", "PARTY", "Ana-Realm")
	h.flush()
	equal(#h.sent, 5, "throttled: tried once more")
	h.flush()
	equal(#h.sent, 5, "throttled: and then left")
	h.party.result = nil

	-- Ana leaves: her message is forgotten with her.
	h.time = h.time + 30
	h.party.members.party1 = nil
	h.party.grouped = false
	h.fire("GROUP_ROSTER_UPDATE")
	h.flush()
	equal(h.ns.Party.Quests(), nil, "left: no party quests once the party is gone")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

-- The setting off: nothing is read, sent or heard; turning it on starts at once.
do
	local h = Load({ db = { partyQuests = false } })
	h.party.on.party1 = { [870] = true }
	h.fire("GROUP_ROSTER_UPDATE")
	h.fire("CHAT_MSG_ADDON", "AGFParty", "1?:1kf", "PARTY", "Ana-Realm")
	h.flush()
	equal(#h.sent, 0, "off: no message is sent")
	equal(h.ns.Party.Quests(), nil, "off: no party quests")
	h.ns.SetSetting("partyQuests", true)
	h.flush()
	check(h.ns.Party.Quests() and h.ns.Party.Quests()[870] == 1, "on: the party is read at once")
	equal(#h.sent, 1, "on: and one message asks for theirs")
	h.time = h.time + 30
	h.ns.SetSetting("partyQuests", false)
	h.flush()
	equal(h.ns.Party.Quests(), nil, "off again: the party's quests are dropped")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

print(("party_spec: %d checks passed"):format(checks))
