-- Run from the repository root: luajit tests/sync_spec.lua
-- Sync Together (#617): the cog menu's checklist of party members running the guide, the "Synced with <names>" line
-- under the guide title, the journey planning what any synced player still needs, and every stop's label saying who
-- it is for. The party message carries each player's completed set in versioned pages; an older peer is ignored.
local harness = dofile("tests/harness.lua")
local diff = dofile("tests/dump_diff.lua")
local checks = 0
local function check(condition, label)
	checks = checks + 1
	if not condition then
		error(label, 2)
	end
end
local function equal(actual, expected, label)
	check(actual == expected, ("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)))
end
local function clean(h, label)
	equal(#h.errors, 0, label .. ": no errors (" .. table.concat(h.errors, "\n") .. ")")
end

--[[ The planner's labels and the group's completed set, without a client ]]

do
	local ns = {}
	harness.model(ns)
	local Model, L = ns.Model, ns.L
	check(type(Model.SyncLabel) == "function", "model: SyncLabel is published")
	equal(Model.NameList({ "Ana" }), "Ana", "names: one")
	equal(Model.NameList({ "Ana", "Bo" }), "Ana " .. L.SYNC_AND .. " Bo", "names: two")
	equal(
		Model.NameList({ "Ana", "Bo", "Cy" }),
		"Ana" .. L.LIST_SEPARATOR .. "Bo " .. L.SYNC_AND .. " Cy",
		"names: three"
	)

	local own = { [1] = true, [2] = true, [3] = true }
	local synced = {
		{ key = "Ana-Realm", name = "Ana", completed = { [1] = true } },
		{ key = "Bo-Realm", name = "Bo", completed = {} },
	}
	equal(Model.SyncLabel(own, synced, { 1 }), L.SYNC_FOR:format("Bo"), "label: only a member needs it")
	equal(Model.SyncLabel(own, synced, { 2 }), L.SYNC_FOR:format("Ana and Bo"), "label: two members, joined")
	equal(Model.SyncLabel(own, synced, { 4 }), L.SYNC_EVERYONE, "label: everyone needs it")
	own[4] = nil
	equal(Model.SyncLabel(own, synced, { 1 }), L.SYNC_FOR:format("Bo"), "label: the player's own set decides")
	local anaDone = { key = "Ana-Realm", name = "Ana", completed = { [5] = true } }
	local boDone = { key = "Bo-Realm", name = "Bo", completed = { [5] = true } }
	equal(Model.SyncLabel(own, { anaDone, boDone }, { 5 }), L.SYNC_FOR_YOU, "label: only the player needs it")
	equal(
		Model.SyncLabel(own, { anaDone, { key = "Bo-Realm", name = "Bo", completed = {} } }, { 5 }),
		L.SYNC_FOR_YOU_AND:format("Bo"),
		"label: the player and one member"
	)
	equal(Model.SyncLabel(own, synced, {}), nil, "label: a stop with no quests")
	equal(Model.SyncLabel(own, {}, { 5 }), nil, "label: not synced")

	local group = Model.GroupCompleted({ [1] = true, [2] = true, [6] = true }, {
		{ key = "Ana-Realm", name = "Ana", completed = { [1] = true, [2] = true, [6] = true } },
		{ key = "Bo-Realm", name = "Bo", completed = { [6] = true } },
	})
	check(group[6], "group: a quest every synced player has done is done")
	check(not group[1] and not group[2], "group: a quest one synced player still needs is still needed")
	local none = Model.GroupCompleted({ [1] = true }, {})
	check(none[1], "group: no members means the player's own set")

	-- Planning over the group's set: a quest the player finished but a member has not is open again.
	local data = {
		quests = {
			[1] = {
				title = "Done long ago",
				level = 17,
				min = 10,
				side = 1,
				zone = 1,
				start = { map = 1, x = 0.3, y = 0.2, name = "Giver", hub = 1 },
				finish = { map = 1, x = 0.3, y = 0.2, name = "Giver", hub = 1 },
				xp = 1000,
			},
		},
		zones = { [1] = { name = "Zone", min = 10, max = 25 } },
		maps = { [1] = { name = "Zone", continent = 0, cx = 0, cy = 0, sx = 1000, sy = 1000 } },
		continents = { [0] = { x = 0, y = 0 } },
	}
	local player =
		{ level = 18, side = 1, raceBit = 0, classBit = 0, map = 1, x = 0, y = 0, maxLevel = 60, party = nil }
	local log = {}
	check(
		not Model.Eligible(data, player, { [1] = true }, log, 1),
		"plan: the player's own completed set closes the quest"
	)
	check(
		Model.Eligible(data, player, Model.GroupCompleted({ [1] = true }, synced), log, 1),
		"plan: the group's set opens a quest a member still needs"
	)
end

--[[ The client: members heard from, the checklist, the plan and its labels ]]

local LOG = {
	{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
	{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
}

local function Load(options)
	options = options or {}
	local party = {
		grouped = options.grouped ~= false,
		raid = false,
		members = { party1 = "Ana", party2 = "Bo" },
		on = {},
	}
	local sent = {}
	local h = harness.load({
		log = options.log or LOG,
		charDB = options.charDB,
		completed = options.completed,
		db = options.db,
		setup = function(this)
			local G = this.G
			G.LE_PARTY_CATEGORY_HOME = 1
			G.IsInGroup = function(category)
				return category == 1 and party.grouped or party.grouped
			end
			G.IsInRaid = function()
				return party.raid
			end
			G.GetNormalizedRealmName = function()
				return "Realm"
			end
			G.UnitExists = function(unit)
				return party.grouped and party.members[unit] ~= nil
			end
			G.UnitName = function(unit)
				if unit == "player" then
					return "Me"
				end
				local name = party.members[unit]
				return name, party.realms and party.realms[unit] or nil
			end
			G.C_QuestLog.IsUnitOnQuest = function(unit, questID)
				return party.on[unit] ~= nil and party.on[unit][questID] == true
			end
			G.C_ChatInfo = {
				RegisterAddonMessagePrefix = function()
					return 0
				end,
				SendAddonMessage = function(prefix, text, channel, target)
					sent[#sent + 1] = { prefix = prefix, text = text, channel = channel, target = target }
					return party.result or 0
				end,
			}
			G.Enum = setmetatable({
				SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3, ChannelThrottle = 8 },
			}, { __index = G.Enum })
		end,
	})
	h.party, h.sent = party, sent
	return h
end

-- Feeds one player's whole state to the party, page by page, as another client would send it.
local function Say(h, sender, log, done, generation)
	local pages = assert(h.ns.Party.Encode(log, done, false, generation or 1))
	for _, text in ipairs(pages) do
		h.fire("CHAT_MSG_ADDON", "AGFParty", text, "PARTY", sender)
	end
	h.flush()
	return pages
end

-- The menu's Sync with submenu, built by the real generator as the cog would open it.
local function SyncMenu(h)
	local owner = h.G.CreateFrame("Button", nil, h.G.UIParent)
	h.G.ForeverCore.ContextMenu(owner, h.ns.Menu.Settings)
	local sync
	for _, entry in ipairs(h.menu.entries) do
		if entry.text == h.ns.L.SYNC_WITH then
			sync = entry
		end
	end
	check(sync ~= nil, "menu: the cog offers Sync with")
	return sync
end

local function HasStep(ns, questID)
	for _, step in ipairs(ns.Route().steps) do
		for _, id in ipairs(step.quests or {}) do
			if id == questID then
				return step
			end
		end
	end
end

-- No one heard from: the submenu says so, with no rows to tick.
do
	local h = Load()
	h.fire("GROUP_ROSTER_UPDATE")
	h.flush()
	local sync = SyncMenu(h)
	equal(#h.ns.Party.Members(), 0, "none: no member runs the guide")
	equal(sync.entries[1].kind, "title", "none: the submenu's title")
	equal(sync.entries[1].text, h.ns.L.SYNC_MEMBERS, "none: names the checklist")
	equal(sync.entries[2].kind, "title", "none: says why it is empty")
	equal(sync.entries[2].text, h.ns.L.SYNC_NONE, "none: its line")
	equal(h.ns.State.Player().synced, nil, "none: the planner is not synced")
	clean(h, "none")
end

-- Two members running the guide: the checklist ticks them, the plan follows, and the guide names them.
do
	local h = Load({ charDB = { journey = "zone:1413" }, completed = { 844 } })
	Say(h, "Ana-Realm", { 870 }, {})
	Say(h, "Bo-Realm", { 850 }, {})
	local members = h.ns.Party.Members()
	equal(#members, 2, "members: both are listed")
	equal(members[1].name, "Ana", "members: by name")
	equal(members[2].name, "Bo", "members: and the next")

	local sync = SyncMenu(h)
	equal(#sync.entries, 3, "checklist: a title and one row per member")
	equal(sync.entries[2].kind, "checkbox", "checklist: rows are checkboxes")
	equal(sync.entries[2].text, "Ana", "checklist: named for the member")
	equal(sync.entries[2].isSelected(), false, "checklist: unticked at first")
	sync.entries[2].onClick()
	h.flush()
	check(h.ns.Party.IsSynced("Ana-Realm"), "checklist: a click ticks the member")
	equal(h.ns.State.Player().synced[1].name, "Ana", "plan: the ticked member reaches the planner")
	equal(#h.ns.State.Player().synced[1].completed, 0, "plan: with the completed set she sent")

	-- The old peer is ignored: no version 1 message makes a member or a set.
	h.fire("CHAT_MSG_ADDON", "AGFParty", "1?:nh,o6", "PARTY", "Cy-Realm")
	h.fire("GROUP_ROSTER_UPDATE")
	h.flush()
	for _, name in ipairs(h.ns.Party.Members()) do
		check(name.name ~= "Cy", "old peer: a version 1 member is not listed")
	end

	-- Ana leaves: her tick goes with her.
	h.party.members.party1 = nil
	h.fire("GROUP_ROSTER_UPDATE")
	h.flush()
	check(not h.ns.Party.IsSynced("Ana-Realm"), "leave: the ticked member is unticked")
	equal(h.ns.State.Player().synced, nil, "leave: the planner stops syncing")
	clean(h, "members")
end

-- A tick saved from last session cannot survive a login with no party: the member has left.
do
	local h = Load({ grouped = false, charDB = { sync = { ["Ana-Realm"] = true } } })
	h.flush()
	check(not h.ns.Party.IsSynced("Ana-Realm"), "solo login: a stale tick is cleared")
	equal(h.ns.State.Player().synced, nil, "solo login: and the plan is not synced")
	clean(h, "solo login")
end

-- The journey plans what any synced player still needs: a quest the player finished but the member has not.
do
	local h = Load({
		charDB = { journey = "zone:1413" },
		completed = { 850 },
		log = {
			{ id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 },
			{ id = 843, title = "Gann's Reclamation", level = 23, complete = false },
		},
	})
	h.flush()
	equal(HasStep(h.ns, 850), nil, "unsynced: a quest the player finished is not planned")
	Say(h, "Ana-Realm", {}, {})
	h.ns.Party.Toggle("Ana-Realm")
	h.flush()
	local step = HasStep(h.ns, 850)
	check(step ~= nil, "synced: the quest the member still needs joins the journey")
	equal(step.sync, h.ns.L.SYNC_EVERYONE, "synced: both need it, so every stop says Everyone")

	-- Unticked again: the route is the player's own.
	h.ns.Party.Toggle("Ana-Realm")
	h.flush()
	equal(HasStep(h.ns, 850), nil, "unsynced again: the member's work leaves the journey")
	clean(h, "plan")
end

-- The line under the guide's title names the synced members; the stops carry their labels on their own line.
do
	local h = Load({ charDB = { journey = "zone:1413" }, completed = { 844 } })
	Say(h, "Ana-Realm", {}, {})
	h.ns.Party.Toggle("Ana-Realm")
	h.ns.OpenPanel()
	h.flush()
	local panel = h.G.AdventureGuideForeverPanel
	local dump = h.ns.DumpLayout(panel, h.Describe)
	local subtitle, syncLine = h.ns.L.SYNC_SUBTITLE:format("Ana"), nil
	local found = false
	for _, entry in ipairs(dump) do
		found = found or entry.text == subtitle
	end
	check(found, "title: the line under it reads " .. subtitle)
	for _, step in ipairs(h.ns.Route().steps) do
		check(step.sync ~= nil, "stops: " .. step.title .. " says who it is for")
		syncLine = syncLine or step.sync
	end
	check(syncLine ~= nil, "stops: one of them is labelled")
	-- The tracker's current stop carries the same line.
	local tracked = false
	for _, id in ipairs(h.tracker.layoutOrder or {}) do
		local block = h.tracker.liveBlocks[id]
		for _, key in ipairs(block.order or {}) do
			tracked = tracked or block.lines[key] == h.ns.L.SYNC_EVERYONE
		end
	end
	check(tracked, "tracker: its step says who it is for too")
	-- The line shares the title's span, clear of the back arrow and the compass, and wraps inside it; the header grows
	-- for the extra line instead of cutting the names off.
	local prefix = h.ns.L.SYNC_SUBTITLE:format("")
	local subtitlePath
	for _, entry in ipairs(dump) do
		if entry.type == "FontString" and entry.text:sub(1, #prefix) == prefix then
			subtitlePath = entry.path
		end
	end
	check(subtitlePath ~= nil, "title: the synced line is drawn")
	local problems = diff.HeaderLines(dump, h.ns.L.TITLE)
	check(#problems == 0, "title: its span is clear of the header's art (" .. table.concat(problems, "; ") .. ")")
	local headerPath = subtitlePath and subtitlePath:match("^(.*)%.[^.]+$")
	local function Height(layout, path)
		for _, entry in ipairs(layout) do
			if entry.path == path and entry.size then
				return entry.size[2]
			end
		end
	end
	local function ScrollHeight(layout)
		for _, entry in ipairs(layout) do
			if entry.path:find("%.scrollChild$") and entry.size then
				return entry.size[2]
			end
		end
	end
	-- The headless harness has no layout engine, so the client's wrapped width is fed in as the string's rect.
	local function Wrap(width)
		h.SetRects(panel, { [subtitlePath] = { 0, 0, width, 20 } })
		h.ns.OpenPanel()
		h.flush()
		return h.ns.DumpLayout(panel, h.Describe)
	end
	local narrow, wide = Wrap(70), Wrap(100)
	local narrowHeight, wideHeight = Height(narrow, headerPath), Height(wide, headerPath)
	check(narrowHeight and wideHeight, "title: the header has a height")
	check(narrowHeight > wideHeight, "title: a wrapped line grows the header")
	check(narrowHeight > 34, "title: the header is taller than its one-line height")
	check(
		ScrollHeight(narrow) - ScrollHeight(wide) == narrowHeight - wideHeight,
		"title: the list moves down with the header"
	)
	problems = diff.HeaderLines(narrow, h.ns.L.TITLE)
	check(#problems == 0, "title: the wrapped line keeps the span (" .. table.concat(problems, "; ") .. ")")
	clean(h, "title")
end

-- A completed set past one message arrives in pages: only the whole set counts, and the player's own set is sent too.
do
	local h = Load({ completed = { 844, 845 } })
	Say(h, "Ana-Realm", {}, {})
	h.ns.Party.Toggle("Ana-Realm")
	h.flush()

	local many = {}
	for id = 1, 600, 3 do
		many[#many + 1] = id
	end
	local pages = assert(h.ns.Party.Encode({ 870 }, many, false, 12))
	check(#pages > 1, "pages: the set needs more than one message")
	-- Every page but the first still leaves the ticked member's old set in place.
	for index = 2, #pages do
		h.fire("CHAT_MSG_ADDON", "AGFParty", pages[index], "PARTY", "Ana-Realm")
	end
	h.flush()
	local member = h.ns.State.Player().synced[1]
	equal(#member.completed, 0, "pages: a partial set is not taken")
	-- The first page completes it, in any order.
	h.fire("CHAT_MSG_ADDON", "AGFParty", pages[1], "PARTY", "Ana-Realm")
	h.flush()
	member = h.ns.State.Player().synced[1]
	local expected = {}
	for _, id in ipairs(many) do
		expected[id] = true
	end
	local count = 0
	for id in pairs(member.completed) do
		count = count + 1
		check(expected[id], "pages: every gap landed on one of the sent quests")
	end
	equal(count, #many, "pages: the whole completed set arrived")

	-- The player's own message carries the log and completed set.
	local page1 = h.ns.Party.Decode(h.sent[#h.sent].text)
	check(page1 ~= nil, "send: a page went out")
	local done, id = {}, 0
	for _, gap in ipairs(page1.gaps) do
		id = id + gap
		done[id] = true
	end
	check(done[844] and done[845], "send: the player's completed quests ride the message")
	clean(h, "pages")
end

print(("sync_spec: %d checks passed"):format(checks))
