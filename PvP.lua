---@type string, AGFNamespace
local _, ns = ...
local L = ns.L
local Asides = ns.Asides

--[[ PvP (docs/design.md §2.15): a battleground open to the player (roadmap #12), as an
     aside. The opt-in Battlegrounds card is the planner's (Model.lua). ]]

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
