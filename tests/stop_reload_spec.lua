-- Run from the repository root: luajit tests/stop_reload_spec.lua
-- #757: Stop survives a /reload. The player's Stop is kept on the character, so a reload no longer starts the offered
-- journey again; choosing a journey, including pressing Go, asks for one to start again.
local harness = dofile("tests/harness.lua")
local checks = 0

local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local LOG = { { id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 } }

-- A login the autoStart starts, as a returning character has it.
local function Login(charDB)
	local h = harness.load({ spf = "v1", completed = { 844 }, log = LOG, charDB = charDB })
	h.flush()
	return h
end

local first = Login()
equal(first.spf.NavigateRoute >= 1, true, "the offered journey starts on login")
local key = first.ns.Prefs().journey
equal(type(key), "string", "a journey was chosen and started")

-- The player's Stop clears the route and keeps that choice off the character.
first.ns.Stop()
first.flush()
equal(first.ns.Prefs().autoStartBlocked, true, "Stop is kept on the character")
equal(first.ns.Prefs().journey, nil, "Stop clears the chosen journey")

-- The same character logs in again: no route starts itself.
local reload = Login(first.G.AdventureGuideForeverCharDB)
equal(reload.ns.Prefs().autoStartBlocked, true, "the reload reads the stopped character")
equal(reload.spf.NavigateRoute or 0, 0, "no route starts after a reload")
equal(reload.ns.Prefs().guided, nil, "and no journey is recorded as guided")

-- Choosing a journey again clears the Stop and starts its route.
reload.ns.Choose(key, true)
reload.flush()
equal(reload.ns.Prefs().autoStartBlocked, nil, "choosing a journey clears the Stop")
equal(reload.ns.Prefs().guided, key, "and the chosen journey starts")

-- Pressing Go after a Stop does the same: it is choosing the offered journey.
local go = Login(first.G.AdventureGuideForeverCharDB)
go.ns.StartRoute()
go.flush()
equal(go.ns.Prefs().autoStartBlocked, nil, "Go clears the Stop")
equal(go.ns.Prefs().guided, go.ns.Route().journey, "and starts the offered journey")

for _, h in ipairs({ first, reload, go }) do
	equal(#h.errors, 0, table.concat(h.errors, "\n"))
end
print(("stop_reload_spec: %d checks passed"):format(checks))
