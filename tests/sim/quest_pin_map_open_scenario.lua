-- luacheck: read globals scenario ADDON
-- #534: opening the map as the player does, with quests in the log, after the guide turned it. Blizzard's quest
-- data provider reads WorldMapFrame.mapID while it acquires its pins, and a map id an addon wrote taints that walk,
-- so the client blocks the pin's protected SetPassThroughButtons. The guide must only ever ask C_Map.OpenWorldMap.
--
-- forever_sim does not model taint on a frame's own fields, so it cannot raise the client's ADDON_ACTION_BLOCKED
-- here. The scenario instead watches the write that produces it: WorldMapFrame:SetMapID while Adventure Guide's code
-- is running. On the old code the guide's turn runs Blizzard's Lua OpenWorldMap (Blizzard_WorldMap.lua:1329), which
-- calls SetMapID as the addon; the assertion below fails at that seam.
scenario("player opens the map with quests in the log after the guide turned it", function(sim)
	sim.world.maps[1429] = { name = "Elwynn Forest", parent = 1415, mapType = 3 }
	sim.world.maps[1415] = { name = "Eastern Kingdoms", parent = 947, mapType = 2 }
	sim.world.maps[1413] = { name = "Northern Barrens", parent = 1414, mapType = 3 }
	sim.world.maps[1414] = { name = "Kalimdor", parent = 947, mapType = 2 }
	sim.world.maps[947] = { name = "Azeroth", parent = 0, mapType = 1 }
	sim.world.player.map = 1429
	sim.cvars.questPOI = "1"
	sim:login()
	local G = sim.G
	local ns
	for _, entry in ipairs(sim.loader.addons) do
		if entry.name == ADDON then
			ns = entry.ns
		end
	end
	assert(ns, "the addon namespace is loaded")
	-- One quest on the player's map, so Blizzard's QuestDataProvider acquires a quest pin whenever the map opens.
	sim.impl["C_QuestLog.GetQuestsOnMap"] = function(mapID)
		if mapID == 1429 then
			return { { questID = 900001, x = 0.5, y = 0.5, isMapIndicatorQuest = false } }
		end
		return nil
	end
	G.HaveQuestData = function()
		return true
	end
	-- Watch the field the client's quest pins read: who writes WorldMapFrame.mapID.
	local writtenByAddon = false
	local setMapID = G.WorldMapFrame.SetMapID
	G.WorldMapFrame.SetMapID = function(self, mapID)
		if sim.taint.current == ADDON then
			writtenByAddon = true
		end
		return setMapID(self, mapID)
	end

	-- The player opens the map out of combat; Blizzard acquires its quest pin with no blocked action.
	sim:input(function()
		G.ToggleWorldMap()
	end)
	sim:advance(0.3)
	assert(G.WorldMapFrame:IsShown(), "the player's map opens")
	assert(not writtenByAddon, "the player's own open writes the map id securely")
	local pins = 0
	for _ in G.WorldMapFrame:EnumeratePinsByTemplate("QuestPinTemplate") do
		pins = pins + 1
	end
	assert(pins > 0, "the map acquired a quest pin")

	-- The guide turns the shown map, as a card or a step reveal does: through the client, never by writing its id.
	sim:runAs(ADDON, "local ns, map = ...; ns.OpenMap(map)", ns, 1413)
	sim:advance(0.3)
	assert(not writtenByAddon, "the guide asks the client to retarget the map")

	-- The player follows it, closes and reopens the map there: the field the pins read was never written as the addon.
	sim:closeWorldMap()
	sim.world.player.map = 1413
	sim:input(function()
		G.ToggleWorldMap()
	end)
	sim:advance(0.3)
	assert(G.WorldMapFrame:IsShown(), "the player's map reopens on the new zone")
	assert(not writtenByAddon, "reopening the map keeps its id secure")

	-- In combat the refreshed quest pins still take their protected pass-through call without a blocked action.
	sim:enterCombat()
	sim.events.fire("QUEST_POI_UPDATE")
	sim:advance(0.2)
	sim:leaveCombat()
	sim:advance(0.2)
	for _, action in ipairs(sim.actions) do
		if action.addon == ADDON then
			error(string.format("%s: %s", action.event, action.func))
		end
	end
	sim:expectNoErrors(ADDON)
	sim:expectNoGamepadTaint(ADDON)
end)
