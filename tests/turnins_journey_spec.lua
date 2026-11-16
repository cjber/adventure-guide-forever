-- #772: turn-ins are a separate journey; Clean up my log still includes work and pickups.
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function Card(h, kind)
	for _, card in ipairs(h.ns.Route().journeys) do
		if card.kind == kind then
			return card
		end
	end
end
local function Holds(card, id)
	for _, step in ipairs(card and card.steps or {}) do
		for _, quest in ipairs(step.quests) do
			if quest == id then
				return true
			end
		end
	end
	return false
end
local function Load(planned)
	return harness.load({
		planned = planned,
		db = { autoStart = false },
		completed = { 844 },
		logMax = 40,
		log = {
			{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
			{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
			{ id = 900001, title = "Unplaced hand-in", level = 18, complete = true },
			{
				id = 900002,
				title = "Live hand-in",
				level = 18,
				complete = true,
				poi = { map = 1413, x = 0.6, y = 0.4 },
			},
			{ id = 900003, title = "Invalid hand-in", level = 18, complete = true, map = 1413, x = 2, y = 0.4 },
			{
				id = 900004,
				title = "Failed quest",
				level = 18,
				complete = true,
				failed = true,
				map = 1413,
				x = 0.6,
				y = 0.4,
			},
		},
	})
end
for _, planned in ipairs({ false, true }) do
	local h = Load(planned)
	h.flush()
	local card = Card(h, "turnins")
	equal(card ~= nil, true, "turn-ins journey is offered")
	equal(card.title, h.ns.L.JOURNEY_TURNINS, "separate title")
	equal(card.section, "continue", "Continue contains the subset")
	equal(card.ready, 2, "only placed completed quests count")
	equal(Holds(card, 845), true, "known hand-in included")
	equal(Holds(card, 900002), true, "live POI hand-in included without inventing an NPC")
	for _, id in ipairs({ 843, 900001, 900003, 900004 }) do
		equal(Holds(card, id), false, "unfinished, unplaced, invalid or failed quest excluded: " .. id)
	end
	for _, step in ipairs(card.steps) do
		equal(step.kind == "turnin" or step.kind == "town", true, "only hand-in stops")
		equal(#(step.pickups or {}), 0, "no pickups")
		equal(step.kind == "town" or step.place == nil, true, "live-only point names no guessed NPC")
	end
	local carry = Card(h, "carry")
	equal(Holds(carry, 843), true, "ordinary cleanup keeps objectives")
	local pickups = 0
	for _, step in ipairs(carry.steps) do
		pickups = pickups + #(step.pickups or {})
	end
	equal(pickups > 0, true, "ordinary cleanup keeps pickups on the way")
	h.ns.Choose("turnins", false)
	h.flush()
	equal(h.ns.Route().journey, "turnins", "subset can be chosen")
	h.log[4].timer = { total = 600, elapsed = 0 }
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	equal(h.ns.Route().steps[1].quests[1], 900002, "urgent completed hand-in leads the subset")
	-- Completion may be revoked or a hand-in removed while combat permits only the cheap rebuild.
	h.combat = true
	h.log[1].complete = false
	h.log[4].map, h.log[4].poi = nil, nil
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	equal(Card(h, "turnins"), nil, "no completed placed quests leaves no stale subset in combat")
	equal(#h.errors, 0, "no harness errors: " .. table.concat(h.errors, "\n"))
end
do
	local h = Load(true)
	h.flush()
	local card = Card(h, "turnins")
	for _, step in ipairs(card.steps) do
		h.ns.Prefs().skipped[step.key] = true
	end
	h.ns.Invalidate()
	h.flush()
	equal(Card(h, "turnins"), nil, "skipped hand-ins are not offered again")
end
do
	local h = Load(true)
	h.flush()
	h.ns.NotInterested("turnins", h.ns.L.JOURNEY_TURNINS)
	h.flush()
	equal(Card(h, "turnins"), nil, "the card's ordinary dismiss menu is respected")
end
print(("turnins_journey_spec: %d checks passed"):format(checks))
