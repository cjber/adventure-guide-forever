-- luacheck: read globals scenario ADDON
local core = dofile("tests/sim/forever_core.lua")

scenario("completed hand-ins draw in the native guide panel", { addons = core }, function(sim)
	sim.world.maps[1413] = { name = "The Barrens", parent = 1414, mapType = 3 }
	sim.world.maps[1414] = { name = "Kalimdor", parent = 947, mapType = 2 }
	sim:login({ savedVariables = { AdventureGuideForeverDB = { autoStart = false } } })
	local ns
	for _, entry in ipairs(sim.loader.addons) do
		if entry.name == ADDON then
			ns = entry.ns
		end
	end
	assert(ns, "the addon loaded")
	sim:advance(0.3)
	sim:runAs(
		ADDON,
		[[
		local ns = ...
		-- A live-only hand-in exercises the planner and card without inventing a catalogue NPC.
		local log = {
			[900001] = { id = 900001, title = "Completed quest", level = 18, complete = true,
				map = 1413, x = 0.5, y = 0.5, objectives = {} },
			[900002] = { id = 900002, title = "Unfinished quest", level = 18, complete = false, objectives = {} },
		}
		local player = ns.State.Player()
		player.map, player.x, player.y = 1413, 0.4, 0.4
		local card = assert(ns.Planner.Journeys.Turnins(ns.Data, player, {}, log, {}, ns.Prefs(), ns.State.MapName))
		ns.Planner.Journeys.Summarise(card)
		assert(#card.steps == 1 and card.steps[1].quests[1] == 900001, "only the completed quest is planned")
		local route = { journey = "turnins", chosen = true, journeys = { card }, steps = card.steps }
		ns.Route = function() return route end
		ns.Prefs().journey = "turnins"
	]],
		ns
	)
	sim:openWorldMap(1413)
	sim:input(function()
		sim.G.WorldMapFrame:SetQuestLogPanelShown(true)
	end)
	sim:input(function()
		local tab = sim.G.AdventureGuideForeverTab
		tab:GetScript("OnMouseUp")(tab, "LeftButton", true)
	end)
	sim:advance(0.2)
	local panel = sim.G.AdventureGuideForeverPanel
	assert(panel:IsVisible(), "the native guide panel shows")
	assert(ns.CurrentJourney().kind == "turnins", "the chosen hand-in card reaches the UI")
	sim:setGamepad(true)
	sim:gamepadNavigate()
	sim:expectNoErrors(ADDON)
end)
