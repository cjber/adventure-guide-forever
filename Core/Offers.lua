---@type string, AGFNamespace
local _, ns = ...

-- What a giver really offers (docs/design.md §2.25). When the player talks to an NPC, its gossip or greeting window
-- lists the quests it offers. A quest the route sends the player there to pick up that the window leaves out, and
-- that isn't grey for them, is one Forever removed or changed, so it is marked not offered at the player's level:
-- the planner treats it as unproven with its own Why line ("The giver didn't offer it") and the route stops sending
-- the player back. Only ever a tightening: a quest the window lists is never marked, a window that lists nothing
-- the guide can match (an untitled or unreadable list) marks nothing, and a single quest's detail window, which may
-- be one choice from a longer list, only confirms. The marks clear on a level-up (they hold at the level they were
-- made at) and on any turn-in, which can open what a giver offers.

local L = ns.L
---@class AGFOffersModule
local Offers = {}
ns.Offers = Offers

-- The giver's creature entry from the "npc" unit's GUID; nil for an object, an item, a player or a secret GUID.
---@return integer?
local function Giver()
	local guid = ns.Readable(UnitGUID("npc"))
	if type(guid) ~= "string" then
		return nil
	end
	local kind, entry = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$")
	return (kind == "Creature" or kind == "Vehicle") and tonumber(entry) or nil
end

-- The quests the open gossip or greeting window offers, as IDs and as titles; nil when it can't be read.
---@param event string
---@return table<integer, true>?, table<string, true>?
local function Offered(event)
	local ids, titles = {}, {}
	if event == "GOSSIP_SHOW" then
		if not (C_GossipInfo and C_GossipInfo.GetAvailableQuests) then
			return nil
		end
		for _, info in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
			local id = ns.Readable(info.questID)
			local title = ns.Readable(info.title)
			if type(id) == "number" then
				ids[id] = true
			end
			if type(title) == "string" and title ~= "" then
				titles[title] = true
			end
		end
	elseif event == "QUEST_GREETING" then
		if not (GetNumAvailableQuests and GetAvailableTitle) then
			return nil
		end
		for index = 1, ns.Readable(GetNumAvailableQuests()) or 0 do
			local title = ns.Readable(GetAvailableTitle(index))
			if type(title) ~= "string" or title == "" then
				return nil -- a list the guide can't read whole proves nothing
			end
			titles[title] = true
			local id = GetAvailableQuestInfo and ns.Readable(select(5, GetAvailableQuestInfo(index)))
			if type(id) == "number" then
				ids[id] = true
			end
		end
	end
	return ids, titles
end

-- The current route's pickups at `entry`, and whether each one's place is that giver's.
---@param entry integer
---@return integer[]
local function Wanted(entry)
	local wanted = {}
	if not ns.RouteSettled() then
		return wanted
	end
	for _, step in ipairs(ns.Route().steps) do
		for _, id in ipairs(step.pickups or {}) do
			local spot = step.spots and step.spots[id]
			if spot and spot.npc == entry then
				wanted[#wanted + 1] = id
			end
		end
	end
	return wanted
end

---@param event string
local function Look(event)
	local entry = Giver()
	if not entry then
		return
	end
	local wanted = Wanted(entry)
	if not wanted[1] then
		return
	end
	local ids, titles = Offered(event)
	if not ids then
		return
	end
	local prefs, data, state = ns.Prefs(), ns.Data, ns.State
	local level = state.Level and state.Level() or UnitLevel("player")
	local marked = false
	for _, id in ipairs(wanted) do
		local quest = data.quests[id]
		local title = state.QuestTitle(id) or (quest and quest.title)
		local listed = ids[id] or (title and titles[title])
		local grey = quest and quest.level > 0 and ns.Model.IsGray(quest.level, level)
		if quest and not listed and not grey and prefs.notOffered[id] ~= level then
			prefs.notOffered[id] = level
			marked = true
			ns.Print(L.NOT_OFFERED:format(title or ""))
		end
	end
	if marked then
		ns.Invalidate()
	end
end

-- The quests marked not offered at `level`: quest ID -> true, for the planner's player (State.Player).
---@param level integer
---@return table<integer, true>
function Offers.NotOffered(level)
	local marks = {}
	for id, at in pairs(ns.Prefs().notOffered) do
		if at == level then
			marks[id] = true
		end
	end
	return marks
end

local events = CreateFrame("Frame")
events:RegisterEvent("GOSSIP_SHOW")
events:RegisterEvent("QUEST_GREETING")
events:RegisterEvent("QUEST_TURNED_IN")
events:RegisterEvent("PLAYER_LEVEL_UP")
events:SetScript("OnEvent", function(_, event)
	if event == "QUEST_TURNED_IN" or event == "PLAYER_LEVEL_UP" then
		if next(ns.Prefs().notOffered) then
			ns.Prefs().notOffered = {}
		end
		return
	end
	ns.SafeCall("giver window", Look, event)
end)
