-- luacheck: read globals scenario ADDON
-- The upgrade arrow on a quest giver's reward choices (UI/Upgrades.lua), drawn on Blizzard's own QuestInfo reward
-- buttons: the better helm is marked, the mail one a level 18 shaman can't wear and the weaker one are not; it holds
-- through combat and the gamepad interface, and Pawn loaded or the setting off clears it.
scenario("quest reward upgrades mark Blizzard's reward buttons", function(sim)
	-- The quest giver window, which the sim does not boot by default.
	sim:loadBlizzard("Blizzard_UIPanels_Game:FriendshipStatusBar|QuestFrame|QuestInfo")
	sim:login({ savedVariables = { AdventureGuideForeverDB = {} } })
	local G = sim.G
	-- Three helms on offer (item level, armour subclass: 2 leather, 3 mail) and the worn one, 101.
	local items = { { 20, 2 }, { 20, 3 }, { 12, 2 }, [101] = { 15, 2 } }
	for id in pairs(items) do
		sim.world.items[id] = { name = "Helm " .. id }
	end
	G.C_Item.GetItemInfo = function(item)
		local id = tonumber(tostring(item):match("%d+"))
		local row = items[id]
		if row then
			return "Helm " .. id, "item:" .. id, 2, row[1], 1, "Armor", "", 1, "INVTYPE_HEAD", 134400, 100, 4, row[2]
		end
	end
	G.C_Item.GetItemStats = function()
		return {}
	end
	G.GetNumQuestChoices = function()
		return 3
	end
	G.GetQuestItemLink = function(_, index)
		return "item:" .. index
	end
	G.GetQuestItemInfo = function(_, index)
		return "Helm " .. index, 134400, 1, 2, true, index
	end
	G.GetQuestItemInfoLootType = function()
		return 0
	end
	G.GetInventoryItemID = function(_, slot)
		return slot == 1 and 101 or nil
	end
	G.UnitClassBase = function()
		return "SHAMAN", 7
	end
	G.UnitLevel = function()
		return 18
	end
	-- Client natives the quest window reads that the sim lacks, and the new-player tutorial it checks for.
	G.TutorialFrame = { id = 0 }
	G.GetQuestBackgroundMaterial = function() end
	G.GetQuestPortraitTurnIn = function()
		return 0
	end
	G.GetRewardTitle = function() end
	G.GetRewardHonor = function()
		return 0
	end
	G.GetRewardArtifactXP = function()
		return 0
	end
	G.GetRewardXP = function()
		return 0
	end
	G.GetRewardSkillPoints = function() end
	G.GetRewardMoney = function()
		return 0
	end
	G.GetNumQuestRewards = function()
		return 0
	end
	G.GetRewardText = function()
		return ""
	end
	G.GetTitleText = function()
		return "Quest"
	end
	G.GetQuestID = function()
		return 1
	end
	-- The client opens the giver's window through the interaction manager, then sends QUEST_COMPLETE.
	G.ShowUIPanel(G.QuestFrame)
	sim:event("QUEST_COMPLETE")
	sim:advance(0.1)
	local function arrows()
		local shown = {}
		for index, button in ipairs(G.QuestInfoRewardsFrame.RewardButtons) do
			if button:IsShown() and button.type == "choice" then
				for _, region in ipairs({ button:GetRegions() }) do
					if region.GetAtlas and region:GetAtlas() == "bags-greenarrow" and region:IsShown() then
						shown[#shown + 1] = index
					end
				end
			end
		end
		return table.concat(shown, ",")
	end
	assert(G.QuestFrameRewardPanel:IsVisible(), "the reward panel is open")
	assert(arrows() == "1", "only the better leather helm is marked, got " .. arrows())
	sim:setGamepad(true)
	sim:enterCombat()
	sim:event("QUEST_ITEM_UPDATE")
	sim:advance(0.1)
	assert(arrows() == "1", "the mark holds in combat and with a gamepad")
	sim:leaveCombat()
	sim:setGamepad(false)
	local ns
	for _, entry in ipairs(sim.loader.addons) do
		if entry.name == ADDON then
			ns = entry.ns
		end
	end
	sim:runAs(ADDON, [[ (...).SetSetting("markUpgrades", false) ]], ns)
	assert(arrows() == "", "turning the setting off clears the mark")
	sim:runAs(ADDON, [[ (...).SetSetting("markUpgrades", true) ]], ns)
	assert(arrows() == "1", "and on draws it again")
	local loaded = G.C_AddOns.IsAddOnLoaded
	G.C_AddOns.IsAddOnLoaded = function(name)
		return name == "Pawn" or loaded(name)
	end
	sim:event("QUEST_COMPLETE")
	sim:advance(0.1)
	assert(arrows() == "", "with Pawn loaded Pawn marks the rewards instead")
	G.C_AddOns.IsAddOnLoaded = loaded
	sim:event("QUEST_FINISHED")
	sim:advance(0.1)
	assert(arrows() == "", "closing the window clears the mark")
	sim:expectNoErrors(ADDON)
end)
