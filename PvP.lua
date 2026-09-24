---@type string, AGFNamespace
local _, ns = ...
local L = ns.L
local Asides = ns.Asides

--[[ PvP (docs/design.md §2.15): a battleground open to the player (roadmap #12) and the next PvP rank's reward (#28),
     each an aside. The opt-in Battlegrounds card is the planner's (Model.lua). ]]

-- The highest level this character has stood in a battleground at (charDB.battled); 0 when never, or unreadable.
---@return integer
local function Battled()
	local battled = ns.Prefs().battled
	return type(battled) == "number" and battled or 0
end

-- "Warsong Gulch is open to you": the newest open battleground (State.Battlegrounds), until the character has stood in
-- a battleground since it opened; its place is the nearest battlemaster the data has, else it is text only (Darkspear
-- Islands has none in CMaNGOS).
Asides.Register(function()
	local bg = ns.State.Battlegrounds()[1]
	if not bg or bg.level <= Battled() then
		return nil
	end
	local npc = ns.Model.Battlemaster(ns.Data, ns.State.Player(), bg.id)
	return {
		key = "battleground:" .. bg.id,
		text = L.BATTLEGROUND_OPEN:format(bg.name),
		-- The minimap's battlemaster mark (CSV:1319).
		icon = "battlemaster",
		place = npc and npc.place,
	}
end)

-- Standing in a battleground acts on the aside: it goes, and the next battleground to open brings the next one.
-- IsInInstance is the client's; the probe did not reach a battleground, so without it nothing is recorded.
local instance = CreateFrame("Frame")
instance:RegisterEvent("PLAYER_ENTERING_WORLD")
instance:RegisterEvent("ZONE_CHANGED_NEW_AREA")
instance:SetScript("OnEvent", function()
	if not IsInInstance then
		return
	end
	local _, kind = IsInInstance()
	local level = UnitLevel("player")
	if kind == "pvp" and level > Battled() then
		ns.Prefs().battled = level
		Asides.Refresh()
	end
end)

-- Camelot's PvP rank track is major faction 2800 (Blizzard_UIPanels_Game/Camelot/PVPRankFrame.lua).
local RANK_FACTION = 2800

-- "Rank 6 · <reward>": the next rank with rewards, and the first of them with a description, in its own words and
-- with its icon, as the character pane's "next reward" rows show them. Only for a character with rank points, and
-- only where the client has C_MajorFactions' progression calls, which the probe did not reach.
Asides.Register(function()
	local factions = C_MajorFactions
	if not (factions and factions.GetMajorFactionProgressionInfo and factions.GetRenownRewardsForLevel) then
		return nil
	end
	local info = factions.GetMajorFactionProgressionInfo(RANK_FACTION)
	local rank = info and info.renownLevel or 0
	if not info or (rank <= 0 and (info.renownReputationEarned or 0) <= 0) then
		return nil
	end
	for level = rank + 1, info.maxLevel or rank do
		local rewards = factions.GetRenownRewardsForLevel(RANK_FACTION, level) or {}
		for _, reward in ipairs(rewards) do
			if reward.description then
				return {
					key = "pvprank",
					text = L.PVP_RANK_REWARD:format(level, reward.description),
					-- The minimap's battlemaster mark stands in for a reward with no icon.
					icon = "battlemaster",
					texture = reward.icon,
				}
			end
		end
		if #rewards > 0 then
			return nil
		end
	end
end)
Asides.RefreshOn("PLAYER_PVP_RANK_CHANGED")
Asides.RefreshOn("MAJOR_FACTION_RENOWN_LEVEL_CHANGED")
