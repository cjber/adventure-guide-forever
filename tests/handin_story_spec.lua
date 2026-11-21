-- Run from the repository root: luajit tests/handin_story_spec.lua
-- Handing a quest in does not end the chosen story while Questie's live policy has yet to hear of it. The client's
-- turn-in reaches this addon before Questie's, so the next quest of the chain is not doable to Questie for a build; the
-- story then has no step, and the choice and its guidance were cleared, so nothing routed until a /reload.
local harness = dofile("tests/harness.lua")
local checks = 0
local function check(value, label)
	assert(value, label)
	checks = checks + 1
end

local data = harness.data()

-- Grelin Whitebeard takes The Stolen Journal (218) and gives Senir's Observations (282), which Thalos takes. Questie
-- finds only what `doable` lists; `reports` is its update callback.
local function Load()
	local list, doable, state = { 182 }, { [218] = true }, {}
	local h = harness.load({
		spf = "subscribe",
		questiedb = harness.questieMirror(data),
		charDB = { journey = "zone:1426", guided = "zone:1426", lead = 1426, quests = true },
		player = { level = 5, faction = "Alliance", raceID = 7, classID = 3, map = 1426, x = 0.2508, y = 0.7571 },
		completed = list,
		log = {
			{ id = 218, title = "The Stolen Journal", level = 5, complete = true, map = 1426, x = 0.2508, y = 0.7571 },
		},
		setup = function(loaded)
			loaded.G.Questie = {
				API = {
					isReady = true,
					RegisterOnReady = function(fn)
						fn()
					end,
					RegisterForQuestUpdates = function(fn)
						state.reports = fn
					end,
				},
			}
			loaded.G.QuestieLoader = {
				ImportModule = function()
					return {
						IsDoable = function(id)
							return doable[id] == true
						end,
					}
				end,
			}
		end,
	})
	h.flush()
	check(h.ns.StartRoute(), "the story starts")
	h.flush()
	check(h.spfRoute, "Shortest Path holds the story's route")
	-- The hand-in, as the client tells it, before Questie has.
	table.remove(h.log, 1)
	list[#list + 1] = 218
	h.fire("QUEST_TURNED_IN", 218)
	h.fire("QUEST_REMOVED", 218)
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	check(h.ns.Prefs().journey == "zone:1426", "still chosen before Questie has heard of the turn-in")
	check(h.ns.Prefs().guided == "zone:1426", "and still guided")
	return h, doable, state
end

-- The chain goes on: Questie opens 282, the player takes it, and Shortest Path is handed its step.
do
	local h, doable, state = Load()
	doable[282] = true
	state.reports(218, 1, 2)
	table.insert(
		h.log,
		{ id = 282, title = "Senir's Observations", level = 5, complete = true, map = 1426, x = 0.3348, y = 0.7184 }
	)
	h.fire("QUEST_ACCEPTED", 282)
	h.fire("QUEST_LOG_UPDATE")
	h.flush()
	local route = h.ns.Route()
	check(route.chosen and route.journey == "zone:1426", "the story carries on")
	check(h.ns.Prefs().guided == "zone:1426", "and stays guided")
	check(h.spfRoute and h.spfRoute.stops[1].x ~= 0.2508, "Shortest Path is handed the next step")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

-- The story really is done: once Questie has reported, the plan is judged and the choice ends.
do
	local h, _, state = Load()
	state.reports(218, 1, 2)
	h.flush()
	check(h.ns.Prefs().journey == nil, "a finished story ends once Questie has caught up")
	check(h.ns.Prefs().guided == nil and h.spfRoute == nil, "and its guidance with it")
	check(#h.errors == 0, table.concat(h.errors, "\n"))
end

print("handin_story_spec: " .. checks .. " checks passed")
