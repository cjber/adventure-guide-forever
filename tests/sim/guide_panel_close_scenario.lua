-- luacheck: read globals scenario ADDON
scenario("closing the map with the guide open keeps the gamepad secure", function(sim)
	sim.world.maps[1429] = { name = "Elwynn Forest", parent = 1415, mapType = 3 }
	sim.world.maps[1415] = { name = "Eastern Kingdoms", parent = 947, mapType = 2 }
	sim:login()
	sim:openWorldMap(1429)
	local G = sim.G
	local tab = G.AdventureGuideForeverTab
	assert(tab, "the guide tab exists")
	sim:input(function()
		G.WorldMapFrame:SetQuestLogPanelShown(true)
	end)
	sim:input(function()
		tab:GetScript("OnMouseUp")(tab, "LeftButton", true)
	end)
	sim:advance(0.1)
	local panel = G.AdventureGuideForeverPanel
	assert(panel:IsVisible(), "the guide panel shows")
	-- The simulator does not load QuestFrame, whose function the quest log's OnHide calls.
	G.QuestFrame_HideQuestPortrait = G.QuestFrame_HideQuestPortrait or function() end
	sim:setGamepad(true)
	local seen = { count = 0 }
	G.EventRegistry:RegisterCallback("UIParentPanelManager.HideUIPanel", function()
		seen.count = seen.count + 1
		seen[seen.count] = sim.taint.current
	end, seen)
	sim:closeWorldMap()
	assert(seen.count == 1, "the map close is heard once, heard " .. tostring(seen.count))
	assert(seen[1] == nil, "the close's broadcast is untainted")
	assert(panel:GetScript("OnShow") == nil, "the panel carries no OnShow script")
	assert(panel:GetScript("OnHide") == nil, "the panel carries no OnHide script")
	assert(not panel:IsVisible(), "the guide panel hides with the map")
	sim:openWorldMap(1429)
	assert(panel:IsVisible(), "reopening the map shows the guide again")
	sim:gamepadNavigate()
	sim:expectNoErrors(ADDON)
end)
