-- Run from the repository root: luajit tests/giver_offers_spec.lua
-- What a giver really offers (Core/Offers.lua, docs/design.md §2.25): a route pickup its giver's gossip or greeting
-- window leaves out is marked not offered at the player's level, unproven with its own Why line, said once in chat,
-- and off the route; a listed quest is never marked; a level-up or a turn-in clears the marks.
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local function Load()
	local h = harness.load({
		charDB = { journey = "zone:1413" },
		planned = true,
		completed = { 844 },
		log = {
			{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
		},
	})
	h.flush()
	return h
end

local function Creature(entry)
	return ("Creature-0-5250-0-17-%d-00004A2B3C"):format(entry)
end

-- The route's first pickup with a giver, its giver and the giver's other pickups.
local function Pickup(h)
	for _, step in ipairs(h.ns.Route().steps) do
		for _, id in ipairs(step.pickups or {}) do
			local spot = step.spots and step.spots[id]
			if spot and spot.npc then
				local others = {}
				for _, other in ipairs(step.pickups) do
					if other ~= id and step.spots[other] and step.spots[other].npc == spot.npc then
						others[#others + 1] = other
					end
				end
				return id, spot.npc, others
			end
		end
	end
end

local function OnRoute(h, id)
	for _, step in ipairs(h.ns.Route().steps) do
		for _, pickup in ipairs(step.pickups or {}) do
			if pickup == id then
				return true
			end
		end
	end
	return false
end

local function Said(h, text)
	local count = 0
	for _, line in ipairs(h.prints) do
		count = count + (line:find(text, 1, true) and 1 or 0)
	end
	return count
end

local function Why(h, id)
	local state = h.ns.State
	for _, line in ipairs(h.ns.Model.Why(h.ns.Data, state.Player(), state.Completed(), state.Log(), id)) do
		if line.text == h.ns.L.WHY_NOT_OFFERED then
			return line.met
		end
	end
end

-- A gossip window without the quest: marked, said once, off the route, with the Why line unmet.
do
	local h = Load()
	local id, npc, others = Pickup(h)
	assert(id, "a route pickup with a giver")
	local title = h.ns.Data.quests[id].title
	local offered = {}
	for _, other in ipairs(others) do
		offered[#offered + 1] = { questID = other, title = h.ns.Data.quests[other].title }
	end
	h.Talk(Creature(npc), "GOSSIP_SHOW", offered)
	h.flush()
	equal(h.ns.Prefs().notOffered[id], h.player.level, "gossip: marked at the player's level")
	equal(Said(h, h.ns.L.NOT_OFFERED:format(title)), 1, "gossip: said once")
	equal(OnRoute(h, id), false, "gossip: off the route")
	equal(Why(h, id), false, "gossip: the Why line, unmet")
	for _, other in ipairs(others) do
		equal(h.ns.Prefs().notOffered[other], nil, "gossip: a listed quest is never marked")
	end
	h.Talk(Creature(npc), "GOSSIP_SHOW", offered)
	h.flush()
	equal(Said(h, h.ns.L.NOT_OFFERED:format(title)), 1, "gossip: not said again")
	-- A turn-in clears the marks: the giver may offer it now.
	h.fire("QUEST_TURNED_IN", 845)
	h.flush()
	equal(next(h.ns.Prefs().notOffered), nil, "turn-in: cleared")
	equal(#h.errors, 0, "gossip: errors\n" .. table.concat(h.errors, "\n"))
end

-- A window that lists it marks nothing; nor does another NPC's, a secret GUID's or an unreadable greeting.
do
	local h = Load()
	local id, npc = Pickup(h)
	local title = h.ns.Data.quests[id].title
	h.Talk(Creature(npc), "GOSSIP_SHOW", { { questID = id, title = title } })
	h.flush()
	equal(h.ns.Prefs().notOffered[id], nil, "listed: not marked")
	h.Talk(Creature(npc + 100000), "GOSSIP_SHOW", {})
	h.flush()
	equal(h.ns.Prefs().notOffered[id], nil, "another NPC: not marked")
	h.Talk(h.Secret(), "GOSSIP_SHOW", {})
	h.flush()
	equal(h.ns.Prefs().notOffered[id], nil, "secret GUID: not marked")
	h.Talk(Creature(npc), "QUEST_GREETING", { title })
	h.flush()
	equal(h.ns.Prefs().notOffered[id], nil, "greeting: listed by title, not marked")
	h.Talk(Creature(npc), "QUEST_GREETING", { "" })
	h.flush()
	equal(h.ns.Prefs().notOffered[id], nil, "greeting: an untitled list proves nothing")
	-- A greeting that lists only something else marks it.
	h.Talk(Creature(npc), "QUEST_GREETING", { "Some Other Quest" })
	h.flush()
	equal(h.ns.Prefs().notOffered[id], h.player.level, "greeting: marked")
	-- A level-up clears it.
	h.player.level = h.player.level + 1
	h.fire("PLAYER_LEVEL_UP", h.player.level)
	h.flush()
	equal(next(h.ns.Prefs().notOffered), nil, "level-up: cleared")
	equal(#h.errors, 0, "listed: errors\n" .. table.concat(h.errors, "\n"))
end

-- A mark from another level doesn't count: the planner's player carries only this level's.
do
	local h = Load()
	local id = Pickup(h)
	h.ns.Prefs().notOffered[id] = h.player.level - 1
	h.ns.Invalidate()
	h.flush()
	equal(h.ns.State.Player().notOffered[id], nil, "another level: not counted")
	equal(OnRoute(h, id), true, "another level: still on the route")
end

print(("giver_offers_spec: %d checks passed"):format(checks))
