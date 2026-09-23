-- Usage, from the repository root: luajit tests/dump_diff.lua <WTF/.../SavedVariables/AdventureGuideForever.lua>
-- Compares the layout /agf dump saved in game with tests/golden/layout.json: the region paths, atlases and
-- explicitly set sizes. Font metrics and stock-template sizes legitimately differ, so they are not compared, and
-- the regions only the game draws (stock-template chrome the harness stubs) are counted, not failed.
local diff = {}

local function Size(entry)
	return entry.size and ("%.2fx%.2f"):format(entry.size[1], entry.size[2]) or "none"
end

-- Returns the differences as lines, and how many regions only the game has.
function diff.Compare(golden, game)
	local byPath, differences, onlyInGame = {}, {}, 0
	for _, entry in ipairs(game) do
		byPath[entry.path] = entry
	end
	local seen = {}
	for _, entry in ipairs(golden) do
		seen[entry.path] = true
		local other = byPath[entry.path]
		if not other then
			differences[#differences + 1] = entry.path .. ": missing in game"
		else
			if entry.atlas ~= other.atlas then
				differences[#differences + 1] = ("%s: atlas %s in golden, %s in game"):format(
					entry.path,
					tostring(entry.atlas),
					tostring(other.atlas)
				)
			end
			if Size(entry) ~= Size(other) then
				differences[#differences + 1] = ("%s: size %s in golden, %s in game"):format(
					entry.path,
					Size(entry),
					Size(other)
				)
			end
		end
	end
	for _, entry in ipairs(game) do
		onlyInGame = onlyInGame + (seen[entry.path] and 0 or 1)
	end
	return differences, onlyInGame
end

local function Main(savedVariables)
	local json = dofile("tests/json.lua")
	local handle = assert(io.open("tests/golden/layout.json"))
	local golden = json.decode(handle:read("*a"))
	handle:close()
	local env = {}
	setfenv(assert(loadfile(savedVariables)), env)()
	local dump = assert(env.AdventureGuideForeverDB and env.AdventureGuideForeverDB.dump, "no dump: run /agf dump")
	local differences, onlyInGame = diff.Compare(golden.layout, dump.layout or {})
	print(("build %s; %d regions only in game"):format(tostring(dump.build), onlyInGame))
	for _, line in ipairs(differences) do
		print(line)
	end
	print(("%d differences"):format(#differences))
	os.exit(#differences == 0 and 0 or 1)
end

-- Run as a script only: ui_spec loads this file for Compare.
if arg and arg[0] and arg[0]:match("dump_diff%.lua$") then
	Main(assert(arg[1], "usage: luajit tests/dump_diff.lua <AdventureGuideForever.lua>"))
end

return diff
