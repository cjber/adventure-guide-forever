---@type string, AGFNamespace
local _, ns = ...

if ns.broken then
	return
end

-- Party quests (docs/design.md §4.5): while the player is in a party (not a raid), the planner favours steps for
-- quests someone in the party also has, so the group tends to do them together and a quest another member carries can
-- be shared rather than walked to. The one source is what the client itself shows of the party,
-- C_QuestLog.IsUnitOnQuest for each quest in the player's own log. Nothing is sent to anyone: no addon messages, no
-- prefix, no other player's addon needed. A burst of roster or log events costs one read, never in combat. With the
-- setting off, or out of a party, nothing is read or kept.
---@class AGFPartyModule
local Party = {}
ns.Party = Party

local SETTLE = 2 -- seconds a burst of log, quest or roster events waits, so it costs one read
local MAX_MEMBERS = 4 -- a party is the player and four others

-- The planner's answer (Party.Quests): quest ID -> how many party members have it; nil when there is nothing to favour.
---@type table<integer, integer>?
local known
local signature = ""
local readQueued = false
local afterCombat = CreateFrame("Frame")

-- In a party, not a raid (the client's home group: an instance group of strangers is not a party to share with).
---@return boolean
local function InParty()
	local home = LE_PARTY_CATEGORY_HOME
	if not (IsInGroup and IsInGroup(home)) then
		return false
	end
	return not (IsInRaid and IsInRaid(home))
end

---@return boolean
local function Enabled()
	return InParty() and ns.Setting("partyQuests") == true
end

-- The visible quest IDs in the player's log. Hidden client quests do not occupy log slots.
---@return integer[]
local function OwnQuests()
	local ids = {}
	for index = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(index)
		if info and not info.isHeader and not info.isHidden and info.questID then
			ids[#ids + 1] = info.questID
		end
	end
	return ids
end

-- Reads the party again: for each member the client lists, which of the player's quests it shows them on. When the
-- answer changed the route is rebuilt.
local function Read()
	readQueued = false
	if not Enabled() then
		local was = known
		known, signature = nil, ""
		if was then
			ns.Invalidate()
		end
		return
	end
	local counts, keys = {}, {}
	local onQuest = C_QuestLog.IsUnitOnQuest
	if onQuest then
		local own = OwnQuests()
		for index = 1, MAX_MEMBERS do
			local unit = "party" .. index
			if UnitExists and UnitExists(unit) then
				for _, id in ipairs(own) do
					local ok, on = pcall(onQuest, unit, id)
					if ok and ns.Readable(on) == true then
						counts[id] = (counts[id] or 0) + 1
					end
				end
			end
		end
	end
	for id in pairs(counts) do
		keys[#keys + 1] = id
	end
	table.sort(keys)
	for index, id in ipairs(keys) do
		keys[index] = id .. "=" .. counts[id]
	end
	known = #keys > 0 and counts or nil
	local text = table.concat(keys, ",")
	if text ~= signature then
		signature = text
		ns.Invalidate()
	end
end

-- Queues a read a moment from now: a burst of roster or log events costs one. In combat it waits for the fight's end.
local function QueueRead()
	if readQueued then
		return
	end
	readQueued = true
	C_Timer.After(SETTLE, function()
		if InCombatLockdown() then
			readQueued = false
			afterCombat:RegisterEvent("PLAYER_REGEN_ENABLED")
			return
		end
		Read()
	end)
end

-- The planner's read (State.Player's `party`): quest ID -> how many party members have it, or nil when the setting
-- is off, the player is not in a party or nobody in it shares a quest. Never written to.
---@return table<integer, integer>?
function Party.Quests()
	return known
end

-- The setting changed: start or stop at once.
function Party.Apply()
	if Enabled() then
		QueueRead()
	else
		Read()
	end
end

afterCombat:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	QueueRead()
end)

local events = CreateFrame("Frame")
events:SetScript("OnEvent", function()
	if Enabled() or known then
		QueueRead()
	end
end)
-- By feature detection: a client without one of these just leaves that source out.
for _, event in ipairs({
	"GROUP_ROSTER_UPDATE",
	"PLAYER_ENTERING_WORLD",
	"UNIT_QUEST_LOG_CHANGED",
	"QUEST_ACCEPTED",
	"QUEST_REMOVED",
	"QUEST_TURNED_IN",
}) do
	pcall(events.RegisterEvent, events, event)
end
