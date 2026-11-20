-- Run from the repository root: luajit tests/deferred_start_spec.lua
-- The bundled ForeverCore activates at PLAYER_LOGIN and the addon's files run then, after the login event the
-- client's own wait would never see again (#892). The quest catalogue still starts, so the tracker leaves its
-- loading line; and whatever Questie does, the catalogue ends in a settled state.
local harness = dofile("tests/harness.lua")

local function Login(api, questiedb)
	local h = harness.load({
		deferred = true,
		questiedb = questiedb,
		setup = function(loaded)
			loaded.G.Questie = { API = api }
			loaded.G.QuestieLoader = {
				ImportModule = function()
					return {
						IsDoable = function()
							return true
						end,
					}
				end,
			}
		end,
	})
	h.flush()
	return h
end
local function Loading(h)
	local loading = h.tracker.liveBlocks.loading
	return loading ~= nil and loading.used == true
end
local function Settled(h, state, label)
	local status = h.ns.QuestieStatus
	assert(status.settled == true, label .. ": the catalogue settles, state " .. tostring(status.state))
	assert(status.state == state, label .. ": expected " .. state .. ", got " .. tostring(status.state))
	assert(not h.ns.QuestieBuilding(), label .. ": nothing is still building")
	assert(not Loading(h), label .. ": the tracker has left the loading line")
	assert(#h.errors == 0, table.concat(h.errors, "\n"))
end

-- Questie ready: the catalogue is built from QuestieDB and a route is planned.
local ready = Login({
	isReady = true,
	RegisterOnReady = function(fn)
		fn()
	end,
}, harness.questieMirror(harness.data()))
Settled(ready, "questie", "Questie ready")
assert(#ready.ns.Route().steps > 0, "a route is planned from the catalogue")

-- Questie never reports ready: the wait runs out and the catalogue is built without its live policy.
Settled(
	Login({ isReady = false, RegisterOnReady = function() end }, harness.questieMirror(harness.data())),
	"questie",
	"Questie never ready"
)

-- Questie installed without QuestieDB: no catalogue, said plainly, and the quest log's route stands.
Settled(
	Login({
		isReady = true,
		RegisterOnReady = function(fn)
			fn()
		end,
	}, false),
	"unavailable",
	"no QuestieDB"
)

-- The same waits at an ordinary load, where every loading event is still to come.
local inline = harness.load({ questiedb = harness.questieMirror(harness.data()) })
inline.flush()
assert(inline.ns.QuestieStatus.settled == true, "an ordinary load settles as before")
print("deferred_start_spec: passed")
