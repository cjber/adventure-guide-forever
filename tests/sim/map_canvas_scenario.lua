-- luacheck: read globals scenario ADDON
scenario("full addon map keeps gamepad tables native", function(sim)
	sim.world.maps[1454] = { name = "Orgrimmar", parent = 1411 }
	sim.world.maps[1411] = { name = "Durotar", parent = 1414 }
	sim.world.maps[1414] = { name = "Kalimdor", parent = 947, mapType = 2 }
	sim:login({ savedVariables = { AdventureGuideForeverDB = { showMapPins = true, showQuestGivers = true } } })
	sim:openWorldMap(1454)
	local ns
	for _, entry in ipairs(sim.loader.addons) do
		if entry.name == ADDON then
			ns = entry.ns
		end
	end
	assert(ns, "full addon namespace loaded")
	sim:runAs(
		ADDON,
		[[
		local ns = ...
		-- A small synthetic catalogue drives the real giver eligibility and renderer.
		ns.Data = CopyTable(ns.Data)
		ns.Data.quests = {
			[900001] = {
				title = "Map scenario quest", level = ns.State.Level(), min = 1, max = 0, side = 3, zone = 1454,
				start = {name = "Map scenario giver", map = 1454, x = 0.6, y = 0.5},
			},
		}
		local route = ns.Route()
		route.steps = {{
			kind = "town", key = "town:1454:1", hub = 1, title = "Orgrimmar",
			map = 1454, x = 0.5, y = 0.5,
			quests = {}, checklist = {},
		}}
		ns.Pins.Refresh()
		ns.Pins.Reveal(route.steps[1])
	]],
		ns
	)
	sim:advance(0.1)
	assert(#ns.Pins.Active() == 2, "the real route and giver renderers draw private pins")
	local function pingShown()
		for _, pool in ipairs(ns.MapCanvas.Watch(sim.G.WorldMapFrame).pools) do
			for _, pin in ipairs(pool:Active()) do
				if pin.PlayAt ~= nil and pin:IsVisible() then
					return true
				end
			end
		end
		return false
	end
	assert(pingShown(), "reveal plays the native ping on a private frame")
	local revealStep = ns.Route().steps[1]
	sim:closeWorldMap()
	for _, pin in ipairs(ns.Pins.Active()) do
		assert(not pin:IsVisible(), "closing the native map hides private pins")
	end
	assert(not pingShown(), "closing the native map hides its reveal ping")
	sim:runAs(ADDON, "local ns, step = ...; ns.Pins.Reveal(step)", ns, revealStep)
	sim:advance(0.1)
	assert(sim.G.WorldMapFrame:IsVisible(), "reveal opens the closed native map")
	assert(sim.G.WorldMapFrame:GetMapID() == 1454, "reveal reopens the requested map")
	assert(pingShown(), "reveal plays after reopening the same native map")
	sim:setGamepad(true)
	sim:zoomMap(1)
	sim:panMap(0.1, 0)
	sim:gamepadNavigate()
	sim:enterCombat()
	sim:advance(0.1)
	for _, pin in ipairs(ns.Pins.Active()) do
		assert(not pin:IsVisible(), "combat-start event hides pins before lockdown")
	end
	sim:leaveCombat()
	sim:openWorldMap(1411)
	sim:gamepadNavigate()
	sim:expectNoGamepadTaint(ADDON)
	sim:expectNoErrors(ADDON)
end)
