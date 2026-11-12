---@type string, AGFNamespace
local _, ns = ...

if ns.broken then
	return
end

-- Party quests and Sync Together (docs/design.md §4.5): while the player is in a party (not a raid), the planner
-- favours steps for quests someone in the party also has, so the group tends to do them together and a quest another
-- member carries can be shared rather than walked to. Two sources, both read only:
--   * what the client shows of the party: C_QuestLog.IsUnitOnQuest for each quest in the player's own log;
--   * what party members running Adventure Guide say: hidden addon messages to the party carrying the quest IDs in
--     their log and every quest they have completed, so a quest the player has not taken yet counts too and a synced
--     member's completed set can plan the journey for the whole group.
-- A message carries numbers only (base 36), never text. Version 2 adds the completed set; a version 1 peer's message
-- is ignored, as version 1 peers ignore ours. A completed set does not fit in one message, so it is cut into pages,
-- each within the client's 255-byte limit, all carrying the same generation and page count; only a whole set counts.
-- Messages go out a moment after the log, the completed set or the party changes, at most once every SEND_GAP
-- seconds, never in combat and never on a timer of its own; a page the client throttles is tried again shortly after,
-- and a member who just joined asks the others for theirs once. With the setting off, or out of a party, nothing is
-- sent or kept.
---@class AGFPartyModule
local Party = {}
ns.Party = Party

local PREFIX = "AGFParty"
local VERSION = "2"
local SETTLE = 2 -- seconds a burst of log, quest or roster events waits, so it costs one read and one message
local SEND_GAP = 15 -- seconds between two messages, whatever asks for them
local PAGE_GAP = 1 -- seconds between two pages of one set, while the client's own throttle clears
local PAGE_TRIES = 3 -- a page the client throttles is tried this many times before the set waits for the next change
local MAX_BYTES = 255 -- the client's limit for one addon message
local MAX_LOG = 40 -- a full log (Forever's holds 40), so a longer message is not ours
local MAX_DONE = 6000 -- more than the catalogue holds; a larger set is not ours
local MAX_ID = 1679615 -- four base-36 digits, well above any quest ID
local MAX_PAGES = 1295 -- two base-36 digits
local MAX_MEMBERS = 4 -- a party is the player and four others
local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

-- What each party member running the guide last said: "Name-Realm" -> { log = set of quest IDs, done = set of
-- completed quest IDs, name = the name without its realm, version = its last message set }. Kept while in a party, so
-- a message that lands before the client knows the sender's name still counts once it does.
---@class AGFPartyHeard
---@field log table<integer, true>
---@field done? table<integer, true>
---@field name string
---@field version integer

---@type table<string, AGFPartyHeard>
local heard = {}
-- Pages of a message set still arriving, by sender: "Name-Realm" -> what has landed so far.
---@class AGFPartyArriving
---@field gen integer
---@field pages integer
---@field got table<integer, number[]>
---@field count integer
---@field log? table<integer, true>

---@type table<string, AGFPartyArriving>
local arriving = {}
-- The members the last read found, by key; nil names stay unknown rather than leaving.
---@type table<string, true>
local roster = {}
-- The planner's answer (Party.Quests): quest ID -> how many party members have it; nil when there is nothing to favour.
---@type table<integer, integer>?
local known
-- The ticked members present with a completed set heard (Party.Synced): who the journey plans for.
---@type AGFPartyMember[]?
local synced
local signature = ""
local grouped = false
-- Sending: one message set queued at a time, `ask` when it also asks the others for theirs, `force` when it goes even
-- though it says what the last one said (someone asked, or someone joined).
local lastSent = -math.huge
---@type string?
local sentSignature
---@type {pages: string[], index: integer, signature: string, tries: integer}?
local sending
local queued, ask, force, deferred = false, false, false, false
local readQueued = false
local gen = 0
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

-- `value` in base 36, zero-padded to `width`, so a field has one size in every message.
---@param value integer
---@param width integer
---@return string
local function Fixed36(value, width)
	local text = Base36(value)
	return #text >= width and text or string.rep("0", width - #text) .. text
end

-- The message head: version, whether it asks for theirs, the set's generation and this page of it.
---@param asks boolean
---@param generation integer
---@param page integer
---@param pages integer
---@return string
local function Head(asks, generation, page, pages)
	return VERSION
		.. (asks and "?" or "")
		.. Fixed36(generation, 3)
		.. ":"
		.. Fixed36(page, 2)
		.. "/"
		.. Fixed36(pages, 2)
		.. ":"
end

-- The quest IDs in `ids` as absolute base-36 tokens, ascending (or nil when one cannot be written in four digits).
---@param ids integer[]
---@return string?
local function Absolute(ids)
	local parts = {}
	for index, id in ipairs(ids) do
		if type(id) ~= "number" or id < 1 or id > MAX_ID or id % 1 ~= 0 then
			return nil
		end
		parts[index] = Base36(id)
	end
	return table.concat(parts, ",")
end

-- The completed quests as gaps from the one before, so a set costs about two characters a quest rather than five.
---@param ids integer[]
---@return string[]?
local function Gaps(ids)
	local parts, previous = {}, 0
	for index, id in ipairs(ids) do
		if type(id) ~= "number" or id < 1 or id > MAX_ID or id % 1 ~= 0 or id <= previous then
			return nil
		end
		parts[index] = Base36(id - previous)
		previous = id
	end
	return parts
end

-- Cuts `tokens` into pages whose joined text stays within `budget` bytes. Every page but the first has the whole
-- message for its gaps; the first also carries the log.
---@param tokens string[]
---@param budget fun(page: integer): integer
---@return string[]?
local function Chunk(tokens, budget)
	local chunks, chunk, used = {}, {}, 0
	for _, token in ipairs(tokens) do
		local room = budget(#chunks + 1)
		local cost = #token + (#chunk > 0 and 1 or 0)
		if used + cost > room then
			if #chunk == 0 or #token > budget(#chunks + 2) then
				return nil
			end
			chunks[#chunks + 1], chunk, used = table.concat(chunk, ","), { token }, #token
		else
			chunk[#chunk + 1] = token
			used = used + cost
		end
	end
	chunks[#chunks + 1] = table.concat(chunk, ",")
	return chunks
end

-- The messages for one player's state: their log's quest IDs and their completed set, ascending. `asks` also asks
-- the others for theirs; `generation` tells one set from the next. Nil when the state cannot be written in messages
-- the client will carry (a log longer than a full one, a set past MAX_PAGES).
---@param log integer[]
---@param done integer[]
---@param asks? boolean
---@param generation? integer
---@return string[]?
function Party.Encode(log, done, asks, generation)
	if #log > MAX_LOG or #done > MAX_DONE then
		return nil
	end
	local logText = Absolute(log)
	local gaps = Gaps(done)
	if not logText or not gaps then
		return nil
	end
	generation = (generation or 0) % 46656
	-- The first page carries the log too; every later one has the gaps alone.
	local function Budget(page)
		local fixed = #Head(asks == true, generation, page, page) + 1 -- the head and the "|" before the gaps
		return MAX_BYTES - fixed - (page == 1 and #logText or 0)
	end
	local chunks = Chunk(gaps, Budget)
	if not chunks or #chunks > MAX_PAGES or #Head(asks == true, generation, 1, #chunks) + 1 + #logText > MAX_BYTES then
		return nil
	end
	local pages = {}
	for index, chunk in ipairs(chunks) do
		pages[index] = Head(asks == true, generation, index, #chunks) .. (index == 1 and logText or "") .. "|" .. chunk
	end
	return pages
end

-- One message's page: the quest IDs in its log (page 1 only), its completed set's gaps, and the set it belongs to.
---@class AGFPartyPage
---@field log table<integer, true>
---@field gaps integer[] gaps from the previous completed quest, the first from 0
---@field asks boolean
---@field gen integer
---@field page integer
---@field pages integer

-- A message's page; nil for anything malformed, of another version, or larger than the client allows.
---@param text any
---@return AGFPartyPage?
function Party.Decode(text)
	if type(text) ~= "string" or text == "" or #text > MAX_BYTES then
		return nil
	end
	local version, asks, generation, page, pages, logText, gapsText = text:match(
		"^(%d)(%??)([0-9a-z][0-9a-z][0-9a-z]):([0-9a-z][0-9a-z])/([0-9a-z][0-9a-z]):([0-9a-z,]*)|([0-9a-z,]*)$"
	)
	if version ~= VERSION then
		return nil
	end
	local function Field(value, width)
		return #value <= width and value ~= "" and tonumber(value, 36) or nil
	end
	local generationValue, pageValue, pagesValue = Field(generation, 3), Field(page, 2), Field(pages, 2)
	if
		not (generationValue and pageValue and pagesValue)
		or pagesValue < 1
		or pageValue < 1
		or pageValue > pagesValue
	then
		return nil
	end
	local function Tokens(body, limit, ascending)
		local values, count, previous = {}, 0, 0
		if body ~= "" then
			if body:sub(1, 1) == "," or body:sub(-1) == "," or body:find(",,", 1, true) then
				return nil
			end
			for part in body:gmatch("[^,]+") do
				local value = Field(part, 4)
				if not value or value < 1 or (ascending and value <= previous) then
					return nil
				end
				count = count + 1
				if count > limit then
					return nil
				end
				values[count], previous = value, value
			end
		end
		return values
	end
	local logIDs = Tokens(logText, MAX_LOG, true)
	local gaps = Tokens(gapsText, MAX_DONE, false)
	if not logIDs or not gaps or (pageValue ~= 1 and logText ~= "") then
		return nil
	end
	local log = {}
	for _, id in ipairs(logIDs) do
		log[id] = true
	end
	return { log = log, gaps = gaps, asks = asks == "?", gen = generationValue, page = pageValue, pages = pagesValue }
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

-- Whether the player asked to sync with anyone in the party: a tick is explicit, so it keeps the messages going even
-- with the party-quests setting off, until the member leaves or is unticked.
---@return boolean
local function WantsSync()
	return next(ns.Prefs().sync or {}) ~= nil
end

---@return boolean
local function Enabled()
	return InParty() and (ns.Setting("partyQuests") == true or WantsSync())
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

-- Every completed quest the client has answered with (State's one seam), ascending. A quest is only ever added, so a
-- turn-in the client's list has not caught up with yet still counts.
---@return integer[]
local function OwnCompleted()
	local ids = {}
	for id in pairs(ns.State.Completed()) do
		if type(id) == "number" and id >= 1 and id <= MAX_ID and id % 1 == 0 then
			ids[#ids + 1] = id
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

-- The name a member is shown by: without its realm.
---@param key string
---@return string
local function Name(key)
	return key:match("^([^%-]+)") or key
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

-- Rebuilds the members the journey plans for: ticked, still in the party, and heard from with a completed set. A
-- ticked member whose set has not arrived yet is left out rather than planned for as if they had done nothing.
local function RefreshSynced()
	local list = {}
	local prefs = ns.Prefs().sync or {}
	for key in pairs(prefs) do
		local entry = roster[key] and heard[key] or nil
		if entry and entry.done then
			list[#list + 1] = { key = key, name = entry.name, completed = entry.done }
		end
	end
	table.sort(list, function(a, b)
		if a.name ~= b.name then
			return a.name < b.name
		end
		return a.key < b.key
	end)
	synced = #list > 0 and list or nil
end

-- What the ticked members say changed: the keys, and each member's last message set.
---@return string
local function SyncSignature()
	local keys = {}
	for key in pairs(ns.Prefs().sync or {}) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	for index, key in ipairs(keys) do
		local entry = heard[key]
		keys[index] = key .. ":" .. tostring(entry and entry.version or 0)
	end
	return table.concat(keys, ",")
end

-- The party members running the guide: heard from, still in the party, by name then key. For the Sync with checklist.
---@return {key: string, name: string}[]
function Party.Members()
	local list, seen = {}, {}
	for key in pairs(roster) do
		local entry = heard[key] and heard[key].done and heard[key]
		if entry then
			list[#list + 1] = { key = key, name = entry.name }
			seen[entry.name] = (seen[entry.name] or 0) + 1
		end
	end
	for _, member in ipairs(list) do
		-- Two members of one name from different realms: show each one's key so the checklist can tell them apart.
		if seen[member.name] > 1 then
			member.name = member.key
		end
	end
	table.sort(list, function(a, b)
		if a.name ~= b.name then
			return a.name < b.name
		end
		return a.key < b.key
	end)
	return list
end

-- Whether `key` is ticked under Sync with.
---@param key string
---@return boolean
function Party.IsSynced(key)
	return (ns.Prefs().sync or {})[key] == true
end

-- The ticked members the journey plans for (State.Player's `synced`): key, name and completed set, by name then key;
-- nil when none is ticked, present and heard from.
---@return AGFPartyMember[]?
function Party.Synced()
	return synced
end

-- Ticks or unticks a member under Sync with; the route rebuilds, and ticking asks them for their completed set.
---@param key string
function Party.Toggle(key)
	local prefs = ns.Prefs()
	prefs.sync = prefs.sync or {}
	prefs.sync[key] = not prefs.sync[key] and true or nil
	RefreshSynced()
	ns.Invalidate()
	if prefs.sync[key] then
		Party.Send(true)
	end
end

-- Reads the party again: who is in it, what the client shows of their logs, what their last messages said and which
-- ticked members are still here. When the answer changed the route is rebuilt; when someone new is in the party, they
-- are told what this player has.
local function Read()
	readQueued = false
	if not Enabled() then
		local was = known or synced
		known, signature, heard, arriving, roster, grouped = nil, "", {}, {}, {}, false
		sending, sentSignature, ask, force, deferred = nil, nil, false, false, false
		-- Out of the party every ticked member has left, so none stays ticked.
		local prefs = ns.Prefs()
		if not InParty() and next(prefs.sync or {}) ~= nil then
			prefs.sync = {}
		end
		RefreshSynced()
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
	for name, entry in pairs(heard) do
		if now[name] then
			for id in pairs(entry.log) do
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
	-- Once every member's name is known, a message from someone no longer here is forgotten, as is their tick.
	if settled then
		for name in pairs(heard) do
			if not now[name] then
				heard[name], arriving[name] = nil, nil
			end
		end
		local prefs = ns.Prefs()
		prefs.sync = prefs.sync or {}
		local unticked = false
		for key in pairs(prefs.sync) do
			if not now[key] then
				prefs.sync[key] = nil
				unticked = true
			end
		end
		if unticked then
			ns.Invalidate()
		end
	end
	roster, grouped = now, true
	known = #keys > 0 and counts or nil
	RefreshSynced()
	local text = table.concat(keys, ",") .. "|" .. SyncSignature()
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

-- Merges one page into the sender's set and, once every page is here, remembers the whole of it: their log and
-- completed quests. Nil or malformed pages were refused before this. A page from a new generation starts the set over.
---@param name string sender's key
---@param page AGFPartyPage
local function Merge(name, page)
	local state = arriving[name]
	if not state or state.gen ~= page.gen then
		state = { gen = page.gen, pages = page.pages, got = {}, count = 0, log = page.page == 1 and page.log or nil }
		arriving[name] = state
	end
	if state.pages ~= page.pages then
		arriving[name] = nil
		return
	end
	if page.page == 1 then
		state.log = page.log
	end
	if not state.got[page.page] then
		state.got[page.page] = page.gaps
		state.count = state.count + 1
	end
	if state.count < state.pages or not state.log then
		return
	end
	-- The gaps are relative across pages, so read them in page order.
	local done, id, count = {}, 0, 0
	for index = 1, state.pages do
		for _, gap in ipairs(state.got[index]) do
			id = id + gap
			count = count + 1
			if id > MAX_ID or count > MAX_DONE then
				arriving[name] = nil
				return
			end
			done[id] = true
		end
	end
	arriving[name] = nil
	local previous = heard[name]
	heard[name] = {
		log = state.log,
		done = done,
		name = Name(name),
		version = (previous and previous.version or 0) + 1,
	}
	QueueRead()
end

-- Sends the queued set a page at a time: the player's quest IDs and completed set, to the party only. Combat puts it
-- off until the fight ends; a set saying what the last one said is not sent again unless someone asked or joined. A
-- page the client throttles goes again a moment later; one still refused after PAGE_TRIES waits for the next change.
local function Flush()
	queued = false
	if not Enabled() or not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then
		sending, ask, force = nil, false, false
		return
	end
	if InCombatLockdown() then
		deferred = true
		afterCombat:RegisterEvent("PLAYER_REGEN_ENABLED")
		return
	end
	if not sending then
		local own, completed = OwnQuests(), OwnCompleted()
		local setSignature = table.concat(own, ",") .. "|" .. table.concat(completed, ",")
		if setSignature == sentSignature and not force and not ask then
			ask, force = false, false
			return
		end
		gen = gen + 1
		local pages = Party.Encode(own, completed, ask, gen)
		if not pages then
			ask, force = false, false
			return
		end
		sending = { pages = pages, index = 1, signature = setSignature, tries = 0 }
	end
	local results = Enum and Enum.SendAddonMessageResult
	local function Outcome(result)
		-- An older client answers true or nothing; a newer one Enum.SendAddonMessageResult, where only Success is sent.
		local success = result == nil or result == true or (results ~= nil and result == results.Success)
		local throttled = results and (result == results.AddonMessageThrottle or result == results.ChannelThrottle)
		return success, throttled
	end
	while sending and sending.index <= #sending.pages do
		lastSent = GetTime()
		local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, sending.pages[sending.index], "PARTY")
		local success, throttled = false, false
		if ok then
			success, throttled = Outcome(result)
		end
		if success then
			sending.index, sending.tries = sending.index + 1, 0
			if sending.index <= #sending.pages then
				-- One page a second, the rate the client's own channel allows, so a long set is not throttled.
				C_Timer.After(PAGE_GAP, Flush)
				return
			end
		elseif throttled and sending.tries + 1 < PAGE_TRIES then
			sending.tries = sending.tries + 1
			C_Timer.After(PAGE_GAP, Flush)
			return
		else
			sending, sentSignature = nil, nil
			break
		end
	end
	if sending and sending.index > #sending.pages then
		sentSignature, sending = sending.signature, nil
	end
	ask, force = false, false
end

-- Asks for the player's state to go to the party, SETTLE seconds from now at the earliest and SEND_GAP seconds
-- after the last message: never more often, however often it is asked.
---@param asks? boolean the set also asks the others for theirs
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

-- A party message: our own echo, a secret sender and another prefix or channel were filtered by the caller.
---@param sender any
---@param text any
function Party.Heard(sender, text)
	local name = ns.Readable(sender)
	if type(name) ~= "string" then
		return
	end
	name = Key(name)
	local me = Key(UnitName("player"))
	if name == me then
		return
	end
	local page = Party.Decode(ns.Readable(text))
	if not page then
		return
	end
	Merge(name, page)
	if page.page == 1 and page.asks then
		Party.Send(false, true)
	end
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
		if prefix == PREFIX and channel == "PARTY" and Enabled() then
			ns.core.SafeCall("party message", Party.Heard, sender, text)
		end
	elseif ns.Setting("partyQuests") == true or WantsSync() then
		if InParty() or grouped then
			QueueRead()
		elseif event == "PLAYER_ENTERING_WORLD" or event == "GROUP_ROSTER_UPDATE" then
			-- Logged in alone with a member still ticked from last session: no party, so the tick goes.
			Read()
		end
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

-- The completed set grew (a turn-in the client reports late, or the first answer after a login): tell the party, so
-- a synced member plans with it. The send is deduped and throttled like any other.
local completedSeen = ns.State.CompletedVersion and ns.State.CompletedVersion() or 0
ns.State.OnChange(function()
	local version = ns.State.CompletedVersion and ns.State.CompletedVersion() or 0
	if version ~= completedSeen then
		completedSeen = version
		Party.Send()
	end
end)
