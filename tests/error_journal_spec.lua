-- Run from the repository root: luajit tests/error_journal_spec.lua
-- ForeverCore's shared error journal and debug log live in the addon's saved table, attached
-- at ADDON_LOADED once the saved variables and their defaults are in, so the report lists earlier sessions' errors and
-- the lines that led to them after a /reload.
local harness = dofile("tests/harness.lua")
local h = harness.load()
local db = h.G.AdventureGuideForeverDB
assert(type(db.errors) == "table", "the saved table has no error journal")

-- An error caught by ns.core.SafeCall is recorded in the saved journal, which is where the next session reads it.
local ok = h.ns.core.SafeCall("error journal spec", function()
	error("error journal spec failure")
end)
assert(ok == false, "the failure was not caught")
local entry
for _, candidate in ipairs(db.errors) do
	if candidate.message:find("error journal spec failure", 1, true) then
		entry = candidate
	end
end
assert(entry, "the caught error did not reach the saved journal")
assert(entry.kind == "error" and entry.count == 1, "the journal entry is not one error")
assert(type(entry.firstSeen) == "number" and type(entry.lastSeen) == "number", "the journal entry has no times")

-- The shared log rides in the same saved table, so the lines that led to a bug survive a /reload too.
assert(type(db.log) == "table", "the saved table has no debug log")
h.ns.core.Log("info", "error journal spec", "a line before the reload")
local logged
for _, line in ipairs(db.log.lines or {}) do
	if line:find("a line before the reload", 1, true) then
		logged = line
	end
end
assert(logged, "the log line did not reach the saved ring")
assert(logged:find("info error journal spec:", 1, true), "the saved line has no level and topic")

-- The journal and the log are the saved tables themselves, so a session that starts from a saved table keeps what it
-- found there and the report reads those earlier sessions back.
local saved = {
	errors = {
		{
			signature = "earlier\n",
			kind = "error",
			message = "error from an earlier session",
			stack = "",
			count = 2,
			firstSeen = 1,
			lastSeen = 2,
		},
	},
	log = {
		lines = { "2026-11-07 09:00:00 +12.0s info earlier: line from an earlier session" },
		pinned = false,
	},
}
local reloaded = harness.load({ db = saved })
assert(reloaded.G.AdventureGuideForeverDB.errors == saved.errors, "the journal is not the saved errors table")
assert(reloaded.G.AdventureGuideForeverDB.log == saved.log, "the log is not the saved log table")
local earlier
for _, candidate in ipairs(reloaded.ns.core.CaughtErrors()) do
	if candidate.message == "error from an earlier session" then
		earlier = candidate
	end
end
assert(earlier and earlier.fromSession == false, "an earlier session's error is missing from the report")
assert(earlier.count == 2, "the earlier session's count was lost")
local kept
for _, line in ipairs(reloaded.ns.core.LogLines(10)) do
	if line:find("line from an earlier session", 1, true) then
		kept = line
	end
end
assert(kept, "an earlier session's log line is missing after the reload")

print("error_journal_spec: ok")
