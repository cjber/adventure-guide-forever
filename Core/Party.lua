---@type string, AGFNamespace
local _, ns = ...

-- Party quests (docs/design.md §4.5): while the player is in a party (not a raid), the planner favours steps for
-- quests someone in the party also has, so the group tends to do them together and a quest another member carries can
-- be shared rather than walked to. Two sources, both read only:
--   * what the client shows of the party: C_QuestLog.IsUnitOnQuest for each quest in the player's own log;
--   * what party members running Adventure Guide say: one hidden addon message to the party with the quest IDs in
--     their log, so a quest the player has not taken yet counts too.
-- A message carries quest IDs only (base 36, comma separated), never text. It goes out a moment after the log or the
-- party changes, at most once every SEND_GAP seconds, never in combat and never on a timer of its own; a member who
-- just joined asks the others for theirs once. With the setting off, or out of a party, nothing is sent or kept.
---@class AGFPartyModule
local Party = {}
ns.Party = Party

local PREFIX = "AGFParty"
local VERSION = "1"
local SETTLE = 2 -- seconds a burst of log or roster events waits, so it costs one read and one message
local SEND_GAP = 15 -- seconds between two messages, whatever asks for them
local MAX_BYTES = 255 -- the client's limit for one addon message
local MAX_IDS = 50 -- more than a full log (Forever's holds 40), so a longer message is not ours
local MAX_MEMBERS = 4 -- a party is the player and four others
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

-- What each party member's last message said: "Name-Realm" -> set of quest IDs. Kept while in a party, so a message
-- that lands before the client knows the sender's name still counts once it does.
---@type table<string, table<integer, true>>
local heard = {}
-- The planner's answer (Party.Quests): quest ID -> how many party members have it; nil when there is nothing to favour.
---@type table<integer, integer>?
local known
local signature = ""
-- The roster at the last read, so a newcomer is told what this player has.
---@type table<string, true>
local roster = {}
local grouped = false
-- Sending: one message queued at a time, `ask` when it also asks the others for theirs, `force` when it goes even
-- though it says what the last one said (someone asked, or someone joined).
local lastSent = -math.huge
---@type string?
local sentText
local queued, ask, force, deferred, retried = false, false, false, false, false
local readQueued = false
local afterCombat = CreateFrame("Frame")

-- `id` in base 36.
---@param id integer
---@return string
local function Base36(id)
	local out = ""
	repeat
		local digit = id % 36
		out = DIGITS:sub(digit + 1, digit + 1) .. out
		id = (id - digit) / 36
	until id == 0
	return out
end

-- The message for `ids` (ascending quest IDs): "1:a3,1kf" or, asking the others for theirs, "1?:a3,1kf". Nil for
-- more IDs than a message may hold.
---@param ids integer[]
---@param asks? boolean
---@return string?
function Party.Encode(ids, asks)
	if #ids > MAX_IDS then
		return nil
	end
	local parts = {}
	for index, id in ipairs(ids) do
		parts[index] = Base36(id)
	end
	local text = VERSION .. (asks and "?" or "") .. ":" .. table.concat(parts, ",")
	return #text <= MAX_BYTES and text or nil
end

-- A message's quest IDs (a set) and whether it asks for ours; nil for anything malformed or of another version.
---@param text any
---@return table<integer, true>?, boolean?
function Party.Decode(text)
	if type(text) ~= "string" or #text > MAX_BYTES then
		return nil
	end
	local version, asks, body = text:match("^(%d+)(%??):([0-9a-z,]*)$")
	if version ~= VERSION or body:find(",,", 1, true) or body:sub(1, 1) == "," or body:sub(-1) == "," then
		return nil
	end
	local ids, count = {}, 0
	for part in body:gmatch("[^,]+") do
		-- Four base-36 digits at most: well above any quest ID.
		local id = #part <= 4 and tonumber(part, 36)
		if not id or id < 1 then
			return nil
		end
		count = count + 1
		if count > MAX_IDS then
			return nil
		end
		ids[id] = true
	end
	return ids, asks == "?"
end

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
	return ns.Setting("partyQuests") == true and InParty()
end

-- The quest IDs in the player's log, ascending.
---@return integer[]
local function OwnQuests()
	local ids = {}
	for index = 1, C_QuestLog.GetNumQuestLogEntries() do
		local info = C_QuestLog.GetInfo(index)
		if info and not info.isHeader and info.questID then
			ids[#ids + 1] = info.questID
		end
	end
	table.sort(ids)
	return ids
end

-- A character's key, "Name-Realm" as a sender's name arrives: `realm` (spaces dropped) when given, else the player's
-- own realm, so two members of one name from different realms stay apart.
---@param name string
---@param realm? string
---@return string
local function Key(name, realm)
	if name:find("-", 1, true) then
		return name
	end
	realm = (type(realm) == "string" and realm ~= "") and realm:gsub("%s", "")
		or (GetNormalizedRealmName and GetNormalizedRealmName())
	return realm and realm ~= "" and (name .. "-" .. realm) or name
end

-- The party members the client lists now: unit token -> key, false where the name is secret or not known yet.
---@return table<string, string|false>
local function Members()
	local members = {}
	for index = 1, MAX_MEMBERS do
		local unit = "party" .. index
		if UnitExists and UnitExists(unit) then
			local name = ns.Readable(UnitName(unit))
			-- secret-ok: the realm, UnitName's second value, goes straight through ns.Readable as the name does
			local realm = ns.Readable((select(2, UnitName(unit))))
			local named = type(name) == "string" and name ~= "" and name ~= UNKNOWNOBJECT
			members[unit] = named and Key(name, realm) or false
		end
	end
	return members
end

-- Reads the party again: who is in it, what the client shows of their logs and what their last messages said. When
-- the answer changed the route is rebuilt; when someone new is in the party, they are told what this player has.
local function Read()
	readQueued = false
	if not Enabled() then
		local was = known
		known, signature, heard, roster, grouped = nil, "", {}, {}, false
		sentText, ask, force, deferred, retried = nil, false, false, false, false
		if was then
			ns.Invalidate()
		end
		return
	end
	local members, carriers, now = Members(), {}, {}
	local function Carry(id, who)
		carriers[id] = carriers[id] or {}
		carriers[id][who] = true
	end
	local onQuest = C_QuestLog.IsUnitOnQuest
	local own = OwnQuests()
	for unit, name in pairs(members) do
		local who = name or unit
		now[who] = true
		if onQuest then
			for _, id in ipairs(own) do
				local ok, on = pcall(onQuest, unit, id)
				if ok and ns.Readable(on) == true then
					Carry(id, who)
				end
			end
		end
	end
	for name, ids in pairs(heard) do
		if now[name] then
			for id in pairs(ids) do
				Carry(id, name)
			end
		end
	end
	local counts, keys = {}, {}
	for id, who in pairs(carriers) do
		local n = 0
		for _ in pairs(who) do
			n = n + 1
		end
		counts[id], keys[#keys + 1] = n, id
	end
	table.sort(keys)
	for index, id in ipairs(keys) do
		keys[index] = id .. "=" .. counts[id]
	end
	local joined = not grouped
	local newcomer, settled = false, true
	for unit, name in pairs(members) do
		newcomer = newcomer or not roster[name or unit]
		settled = settled and name ~= false
	end
	-- Once every member's name is known, a message from someone no longer here is forgotten.
	if settled then
		for name in pairs(heard) do
			heard[name] = now[name] and heard[name] or nil
		end
	end
	roster, grouped = now, true
	known = #keys > 0 and counts or nil
	local text = table.concat(keys, ",")
	if text ~= signature then
		signature = text
		ns.Invalidate()
	end
	-- Joining, or someone new in the party: tell them, and ask for theirs.
	if joined or newcomer then
		Party.Send(true)
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

-- Sends the queued message: the player's quest IDs, to the party only. Combat puts it off until the fight ends; a
-- message saying what the last one said is not sent again unless someone asked or joined. One the client throttles
-- is tried once more after the gap, then left for the next change.
local function Flush()
	queued = false
	if not Enabled() or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then
		ask, force = false, false
		return
	end
	if InCombatLockdown() then
		deferred = true
		afterCombat:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	local own = OwnQuests()
	local text, plain = Party.Encode(own, ask), Party.Encode(own)
	if not text or (plain == sentText and not force and not ask) then
		ask, force = false, false
		return
	end
	lastSent = GetTime()
	local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, text, "PARTY")
	local results = Enum and Enum.SendAddonMessageResult
	local throttled = results and (result == results.AddonMessageThrottle or result == results.ChannelThrottle)
	-- An older client answers true or nothing; a newer one Enum.SendAddonMessageResult, where only Success is sent.
	local success = result == nil or result == true or (results ~= nil and result == results.Success)
	if ok and success then
		sentText, ask, force, retried = plain, false, false, false
	elseif ok and throttled and not retried then
		retried = true
		Party.Send(ask, force)
	else
		sentText, ask, force, retried = nil, false, false, false
	end
end

-- Asks for the player's quest IDs to go to the party, SETTLE seconds from now at the earliest and SEND_GAP seconds
-- after the last message: never more often, however often it is asked.
---@param asks? boolean the message also asks the others for theirs
---@param forced? boolean it goes even if it says what the last one said
function Party.Send(asks, forced)
	ask, force = ask or asks == true, force or forced == true
	if queued then
		return
	end
	queued = true
	C_Timer.After(math.max(SETTLE, lastSent + SEND_GAP - GetTime()), Flush)
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
		grouped = false
		QueueRead()
	else
		Read()
	end
end

---@param sender any
---@param text any
local function Heard(sender, text)
	local name = ns.Readable(sender)
	if type(name) ~= "string" then
		return
	end
	name = Key(name)
	local me = Key(UnitName("player"))
	if name == me then
		return
	end
	local ids, asks = Party.Decode(ns.Readable(text))
	if not ids then
		return
	end
	heard[name] = ids
	if asks then
		Party.Send(false, true)
	end
	QueueRead()
end

afterCombat:SetScript("OnEvent", function(self)
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	QueueRead()
	if deferred then
		deferred = false
		Party.Send(ask, force)
	end
end)

local events = CreateFrame("Frame")
local registered = false
events:SetScript("OnEvent", function(_, event, prefix, text, channel, sender)
	-- The prefix is registered with the first event (a login's PLAYER_ENTERING_WORLD), before any party message.
	if not registered and C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
		registered = true
		pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
	end
	if event == "CHAT_MSG_ADDON" then
		if prefix == PREFIX and channel == "PARTY" and ns.Setting("partyQuests") == true then
			ns.SafeCall("party message", Heard, sender, text)
		end
	elseif ns.Setting("partyQuests") == true and (grouped or InParty()) then
		QueueRead()
		if event == "QUEST_ACCEPTED" or event == "QUEST_REMOVED" or event == "QUEST_TURNED_IN" then
			Party.Send()
		end
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
	"CHAT_MSG_ADDON",
}) do
	pcall(events.RegisterEvent, events, event)
end
