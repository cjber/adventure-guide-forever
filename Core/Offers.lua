---@type string, AGFNamespace
local _, ns = ...

-- What a giver really offers (docs/design.md §2.25). When the player talks to an NPC, its gossip or greeting window
-- lists the quests it offers. A quest the route sends the player there to pick up that the window leaves out, and
-- that isn't grey for them, is one Forever removed or changed, so it is marked not offered at the player's level:
-- the planner treats it as unproven with its own Why line ("The giver didn't offer it") and the route stops sending
-- the player back. Only ever a tightening: a quest the window lists is never marked; a window the guide can't read
-- whole (a secret or untitled entry, or titles only for a quest whose client title isn't known yet) marks nothing; a
-- quest already taken or done is never marked; a single quest's detail window, which may be one choice from a longer
-- list, is not read. A mark holds at the level it was made at, and a hand-in clears the marks it could open: quests
-- that need the quest handed in, and quests the same NPC gives.

local L = ns.L
---@class AGFOffersModule
local Offers = {}
ns.Offers = Offers

-- The quests the open gossip or greeting window offers, as IDs and as titles; nil when it can't be read whole.
---@param event string
---@return table<integer, true>?, table<string, true>?
local function Offered(event)
	local ids, titles = {}, {}
	if event == "GOSSIP_SHOW" then
		if not (C_GossipInfo and C_GossipInfo.GetAvailableQuests) then
			return nil
		end
		for _, info in ipairs(C_GossipInfo.GetAvailableQuests() or {}) do
			local id, title = ns.Readable(info.questID), ns.Readable(info.title)
			local known = false
			if type(id) == "number" then
				ids[id], known = true, true
			end
			if type(title) == "string" and title ~= "" then
				titles[title], known = true, true
			end
			if not known then
				return nil -- an entry the guide can't read proves nothing about the rest
			end
		end
	elseif event == "QUEST_GREETING" then
		if not (GetNumAvailableQuests and GetAvailableTitle) then
			return nil
		end
		for index = 1, ns.Readable(GetNumAvailableQuests()) or 0 do
			local title = ns.Readable(GetAvailableTitle(index))
			if type(title) ~= "string" or title == "" then
				return nil
			end
			titles[title] = true
			local id = GetAvailableQuestInfo and ns.Readable((select(5, GetAvailableQuestInfo(index))))
			if type(id) == "number" then
				ids[id] = true
			end
		end
	end
	return ids, titles
end

-- The current route's pickups whose place is the giver `entry`.
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
	local entry = ns.CreatureEntry(ns.Readable(UnitGUID("npc")))
	if not entry then
		return
	end
	local wanted = Wanted(entry)
	if not wanted[1] then
		return
	end
	local ids, titles = Offered(event)
	if not (ids and titles) then
		return
	end
	local prefs, data, state = ns.Prefs(), ns.Data, ns.State
	local level, completed = UnitLevel("player"), state.Completed()
	local marked = false
	for _, id in ipairs(wanted) do
		local quest = data.quests[id]
		-- A greeting gives titles only: match by the client's own title, and prove nothing without one.
		local title = state.QuestTitle(id)
		local listed = ids[id] or (title and titles[title]) or (not title and not next(ids) and event ~= "GOSSIP_SHOW")
		local taken = completed[id] or C_QuestLog.IsOnQuest(id)
		if
			quest
			and not listed
			and not taken
			and not ns.Model.IsGray(quest.level, level)
			and prefs.notOffered[id] ~= level
		then
			prefs.notOffered[id] = level
			marked = true
			ns.Print(L.NOT_OFFERED:format(title or quest.title))
		end
	end
	if marked then
		ns.Invalidate()
	end
end

-- A hand-in of `turned` clears the marks it could open: a quest that needs it, and any quest its ender gives.
---@param turned integer
local function TurnedIn(turned)
	local marks, data = ns.Prefs().notOffered, ns.Data
	local done = data.quests[turned]
	local ender = done and done.finish and done.finish.npc
	for id in pairs(marks) do
		local quest = data.quests[id]
		local opens = false
		for _, list in ipairs({ quest and quest.pre or {}, quest and quest.preAny or {} }) do
			for _, pre in ipairs(list) do
				opens = opens or pre == turned
			end
		end
		if not quest or opens or (ender and quest.start and quest.start.npc == ender) then
			marks[id] = nil
		end
	end
end

local events = CreateFrame("Frame")
events:RegisterEvent("GOSSIP_SHOW")
events:RegisterEvent("QUEST_GREETING")
events:RegisterEvent("QUEST_TURNED_IN")
events:SetScript("OnEvent", function(_, event, arg)
	if event == "QUEST_TURNED_IN" then
		if type(arg) == "number" then
			ns.SafeCall("giver window", TurnedIn, arg)
		end
		return
	end
	ns.SafeCall("giver window", Look, event)
end)
