-- #849: The packager writes a bare Version, matching the release headline.
local harness = dofile("tests/harness.lua")
local h = harness.load({ db = { autoStart = false, lastVersion = "1.0.0" } })
h.flush()

local ns = h.ns
local addon = "AdventureGuideForever"
local version = ns.WHATS_NEW_VERSION
local headline = "|cff33ff99" .. ns.TITLE .. "|r " .. ns.L.UPDATED_TO:format(version, ns.L.WHATS_NEW)
h.metadata[addon].Version = version
local before = #h.prints

ns.WhatsNew()
assert(#h.prints == before + 1 and h.prints[#h.prints] == headline, "the update headline prints")
assert(h.G.AdventureGuideForeverDB.lastVersion == version, "the packaged version is recorded")

ns.WhatsNew()
assert(#h.prints == before + 1, "the headline prints only once")
assert(#h.errors == 0, table.concat(h.errors, "\n"))
print("whats_new_spec: ok")
