-- Run from the repository root: luajit tests/stats_spec.lua
-- Adventure Guide's adapter over the shared peer stats (Core/Stats.lua): the saved-layout migration, the cumulative
-- snapshot it offers, the opt-out across a reload, and the leaderboard the API and /agf print. The protocol itself
-- (bounds, malformed and stale rows, caps, several addons together) is tests/peer_stats_spec.lua's.
local harness = dofile("tests/harness.lua")
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local now = os.time()
local sent
-- Loads the addon over `db` and `charDB` with the chat, guild and clock the transport needs.
local function boot(db, charDB)
	sent = {}
	-- Set before the load: the shared module reads the clock and the player's name the first time it sees the table.
	_G.GetServerTime = function()
		return now
	end
	_G.UnitName = function()
		return "Me"
	end
	_G.GetNormalizedRealmName = function()
		return "MyRealm"
	end
	_G.IsInGuild = function()
		return true
	end
	_G.C_ChatInfo = {
		SendAddonMessage = function(_, payload, channel)
			sent[#sent + 1] = channel .. ":" .. payload
			return true
		end,
	}
	local h = harness.load({ db = db, charDB = charDB })
	return h, h.G.AdventureGuideForever.API
end

local function hear(h, sender, total)
	h.fire("CHAT_MSG_ADDON", "WFAStats", ("1|agf|quest_turn_ins|all|%d|%d"):format(total, now - 60), "GUILD", sender)
end

local function printed(h, needle)
	for _, line in ipairs(h.prints) do
		if line:find(needle, 1, true) then
			return true
		end
	end
	return false
end

--[[ Migration: only this addon's validated total moves; the old table stays ]]
local old = {
	Bob = {
		agf = {
			quest_turn_ins = { all = { value = 12, eventUnix = now - 500 } },
			quest_turn_in = { ["5"] = { value = 3 } },
		},
		fieldguide = { creature_kills = { all = { value = 99, eventUnix = now - 400 } } },
	},
	Bad = { agf = { quest_turn_ins = { all = { value = -5, eventUnix = now } } } },
	Foreign = { skillup = { recipes_observed_learned = { all = { value = 4, eventUnix = now } } } },
}
local h, api = boot({ sharedStats = old }, {})
equal(api.Leaderboard().sharing, true, "sharing defaults on for a new user")
local db = h.G.AdventureGuideForeverDB
equal(db.peerStats.Bob.quest_turn_ins.all.value, 12, "Bob's total migrated")
equal(db.peerStats.Bob.fieldguide, nil, "foreign metrics are not guessed")
equal(db.peerStats.Bad, nil, "an invalid total is dropped")
equal(db.peerStats.Foreign, nil, "a sender with no total of ours is dropped")
equal(db.sharedStats.Bob.fieldguide.creature_kills.all.value, 99, "the original history is kept")
equal(db.sharedStats.Bad.agf.quest_turn_ins.all.value, -5, "the old table is untouched")

--[[ Cumulative snapshots ]]
h.fire("QUEST_TURNED_IN", 1001)
h.flush()
equal(#sent, 1, "first turn-in is offered once")
equal(sent[1]:match("^GUILD:1|agf|quest_turn_ins|all|1|%d+$") ~= nil, true, "cumulative total on the wire")
h.fire("QUEST_TURNED_IN", 1002)
h.flush()
equal(#sent, 2, "a second turn-in is a new offer")
equal(sent[2]:match("|all|2|") ~= nil, true, "the snapshot is the running total")
for _, line in ipairs(sent) do
	equal(line:find("quest_turn_in|", 1, true), nil, "per-quest rows are not shared")
end

--[[ Leaderboard, API copies, deterministic order ]]
hear(h, "Alice-MyRealm", 20)
hear(h, "Zed", 12)
local board = api.Leaderboard()
equal(board.scope, "guild_group", "scope is guild and group")
equal(board.total, 4, "own row and three peers")
equal(board.rows[1].name, "Alice", "highest first")
equal(board.rows[2].name, "Bob", "ties fall to the name (bob before zed)")
equal(board.rows[3].name, "Zed", "tie, second")
equal(board.rows[4].self, true, "own row present")
equal(board.rows[4].value, 2, "own cumulative total")
local top = api.Leaderboard(1)
equal(#top.rows, 2, "a top list plus the own row outside it")
equal(top.rows[2].rank, 4, "the own row keeps its rank")
equal(api.Leaderboard(-1), nil, "a bad limit is nil")
equal(api.Leaderboard(2.5), nil, "a fractional limit is nil")
board.rows[1].value = -1
equal(api.Leaderboard().rows[1].value, 20, "API result is a copy")
local shared = db.peerStats
equal(shared.Alice.quest_turn_ins.all.value, 20, "heard rows land in the canonical table")

--[[ Command ]]
h.Slash("leaderboard")
equal(printed(h, "Quest turn-ins observed for this character"), true, "title names the observed metric")
equal(printed(h, "player-reported, not verified"), true, "peer values are labelled player-reported")
equal(printed(h, "1. Alice: 20"), true, "ranked peer row")
equal(printed(h, "4. Me (you): 2"), true, "own row")
equal(printed(h, "/agf share off"), true, "opt-out is stated")
local before = #h.prints
h.Slash("stats")
equal(#h.prints > before, true, "stats is an alias")

--[[ Opt-out: send, receive and rows stop at once; the local row stays ]]
h.fire("QUEST_TURNED_IN", 1003)
h.Slash("share off")
equal(db.statsShare, false, "the setting is saved")
h.flush()
equal(#sent, 2, "a queued offer is cancelled")
hear(h, "Carol", 50)
local off = api.Leaderboard()
equal(off.sharing, false, "sharing reported off")
equal(#off.rows, 1, "peers are hidden")
equal(off.rows[1].self, true, "own row remains")
equal(off.rows[1].value, 3, "own total still counts")
h.prints = {}
h.Slash("leaderboard")
equal(printed(h, "1. Me (you): 3"), true, "personal progress shows with sharing off")
equal(printed(h, "hidden while sharing is off"), true, "hidden peers are said to be hidden")
equal(printed(h, "/agf share on"), true, "how to turn it back on")
equal(printed(h, "Alice"), false, "no peer row")

--[[ Reload keeps the opt-out and the local history ]]
local saved, savedChar = h.G.AdventureGuideForeverDB, h.G.AdventureGuideForeverCharDB
h, api = boot(saved, savedChar)
h.flush()
equal(#sent, 0, "nothing is sent after a reload while off")
hear(h, "Dave", 70)
local reloaded = api.Leaderboard()
equal(reloaded.sharing, false, "still off after reload")
equal(#reloaded.rows, 1, "no peers while off")
equal(reloaded.rows[1].value, 3, "local history survives")
equal(saved.peerStats.Dave, nil, "a report is not kept while off")
equal(saved.peerStats.Alice.quest_turn_ins.all.value, 20, "cached peers are kept, only hidden")
equal(saved.sharedStats.Bob.fieldguide.creature_kills.all.value, 99, "the old table survives a reload")

--[[ Re-enable ]]
h.Slash("share on")
h.flush()
equal(#sent, 1, "re-enabling offers the total again")
equal(sent[1]:match("|all|3|") ~= nil, true, "with the current total")
equal(api.Leaderboard().rows[1].name, "Alice", "cached peers return")
equal(api.Leaderboard().sharing, true, "sharing on")

print(("stats_spec: %d checks passed"):format(checks))
