-- Times a login's catalogue work over a real QuestieDB release, offline in LuaJIT (-joff for the client's plain Lua):
-- the cold build QuestieSource.lua slices across frames, the saved catalogue it writes (its size in the
-- SavedVariables file and the client's parse of it) and the warm adoption that reads it back. Never shipped.
--
--   python3 tools/gen_corpus.py   # downloads the pinned QuestieDB release into tools/.cache
--   AGF_QUESTIEDB=tools/.cache/questiedb-<QUESTIEDB_TAG>/QuestieDB luajit -joff tools/login_bench.lua
--
-- The build runs here in one go (the harness clock stands still, so no slice yields) and its frames are its work over
-- the build's slice (SLICE_MS); seconds assume 60 fps, since each frame gives the build its slice and the rest goes to
-- the game.
local root = assert(os.getenv("AGF_QUESTIEDB"), "AGF_QUESTIEDB is not set")
local FPS, SLICE_MS = 60, 2

local function Now()
	return os.clock() * 1000
end

local loadStarted = Now()
local lib = assert(loadfile("tools/questiedb_load.lua"))()(root, "QuestieDB_Forever.toc")
local loadMs = Now() - loadStarted
local harness = dofile("tests/harness.lua")

-- One login: QuestieDB loaded, Questie absent (so the build starts at once), every QuestieSource timer timed as the
-- frame that runs it.
local function Login(charDB)
	local slices, work = 0, 0
	local h = harness.load({
		questiedb = {},
		clientFacts = false,
		charDB = charDB,
		setup = function(loaded)
			loaded.G.LibQuestieDB = lib
			loaded.metadata.QuestieDB = { Version = "bench", ["X-Flavor"] = "Forever" }
			loaded.metadata.AdventureGuideForever.Version = "bench"
			local after = loaded.G.C_Timer.After
			loaded.G.C_Timer.After = function(delay, fn)
				local source = debug.getinfo(fn, "S").source
				after(delay, function()
					local started = Now()
					fn()
					if source:find("QuestieSource") then
						slices, work = slices + 1, work + Now() - started
					end
				end)
			end
		end,
	})
	assert(h.ns.QuestieStatus.state == "questie", "catalogue not built: " .. tostring(h.ns.QuestieStatus.reason))
	return h, slices, work
end

-- The saved catalogue as the client writes it into SavedVariables: one `[key] = value,` line per entry.
local function Serialise(value, out, depth)
	local kind = type(value)
	if kind == "string" then
		out[#out + 1] = ("%q"):format(value)
	elseif kind ~= "table" then
		out[#out + 1] = tostring(value)
	else
		out[#out + 1] = "{\n"
		local indent = ("\t"):rep(depth + 1)
		for key, item in pairs(value) do
			out[#out + 1] = indent
			out[#out + 1] = type(key) == "string" and ("[%q] = "):format(key) or ("[" .. key .. "] = ")
			Serialise(item, out, depth + 1)
			out[#out + 1] = ",\n"
		end
		out[#out + 1] = ("\t"):rep(depth) .. "}"
	end
	return out
end

local h, _, work = Login({})
local saved = h.G.AdventureGuideForeverCharDB.catalogue
assert(saved, "no saved catalogue")
local source = "AdventureGuideForeverCharDB = " .. table.concat(Serialise({ catalogue = saved }, {}, 0))
local parseStarted = Now()
local chunk = assert(loadstring(source))
local env = {}
setfenv(chunk, env)
chunk()
local parseMs = Now() - parseStarted

local adoptStarted = Now()
local warm, warmSlices = Login(env.AdventureGuideForeverCharDB)
local adoptMs = Now() - adoptStarted
assert(warmSlices == 0, "the warm login built instead of adopting")
assert(warm.ns.Data.quests ~= nil and next(warm.ns.Data.quests) ~= nil, "the warm login has no quests")

print(("QuestieDB load %.0f ms (before PLAYER_LOGIN)"):format(loadMs))
print(
	("cold build %.0f ms of work, %d frames at %d ms: %.1f s at %d fps"):format(
		work,
		work / SLICE_MS,
		SLICE_MS,
		work / SLICE_MS / FPS,
		FPS
	)
)
print(("saved catalogue %.2f MB, client parse %.0f ms"):format(#source / 1048576, parseMs))
print(("warm login (adopt and first route) %.0f ms"):format(adoptMs))
