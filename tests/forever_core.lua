-- ForeverCore, the addon every Forever addon requires, loaded the way the client loads it: the files its TOC lists,
-- in order, from the checkout the FOREVER_CORE environment variable names. Local runs default to the sibling checkout
-- ../forever-core; CI checks the ref in tools/forever-core.txt out into forever-core/.
--
-- The TOC reader is ForeverCore's own (tools/forever_sim/toc.lua, vendored byte for byte): it expands the TOC the way
-- the client does, each XML in its place and the virtual templates that XML declares.
local ForeverCore = {}

local Toc = dofile("tools/forever_sim/toc.lua")

local DEFAULT_DIRECTORY = "../forever-core"

local function Exists(path)
	local file = io.open(path .. "/ForeverCore.toc", "r")
	if file then
		file:close()
		return true
	end
	return false
end

-- The checkout, as FOREVER_CORE names it. A relative path is read from the working directory first, then from
-- GITHUB_WORKSPACE, because the packaged specs run from a scratch folder rather than the repository root.
---@return string
function ForeverCore.directory()
	local configured = os.getenv("FOREVER_CORE")
	local candidates = {}
	if configured and configured ~= "" then
		candidates[#candidates + 1] = configured
		if configured:sub(1, 1) ~= "/" then
			local workspace = os.getenv("GITHUB_WORKSPACE")
			if workspace and workspace ~= "" then
				candidates[#candidates + 1] = workspace .. "/" .. configured
			end
		end
	else
		candidates[#candidates + 1] = DEFAULT_DIRECTORY
	end
	for _, path in ipairs(candidates) do
		local cleaned = path:gsub("/+$", "")
		if cleaned ~= "" and Exists(cleaned) then
			return cleaned
		end
	end
	error(
		"ForeverCore's checkout is not at "
			.. table.concat(candidates, " or ")
			.. "; set FOREVER_CORE to it (tools/forever-core.txt names the ref)"
	)
end

-- The TOC's entries, in its order, under `directory`: `{ path, kind }`, where `kind` is "lua" or "xml". The reader
-- joins `directory` to each TOC line, so a path is what the client would load, not the line as written.
---@param directory string
---@return { path: string, kind: "lua"|"xml" }[]
function ForeverCore.files(directory)
	return Toc.files(directory, "ForeverCore.toc")
end

-- Every file, or only `names` plus enUS (the phrases every core module reads).
---@param names? string[]
---@return table<string, boolean>?
local function Wanted(names)
	if names == nil then
		return nil
	end
	local wanted = { ["Locales/enUS.lua"] = true }
	for _, name in ipairs(names) do
		wanted[name] = true
	end
	return wanted
end

-- Load ForeverCore into `env`, each file with its own namespace, and return that namespace. `names` narrows the load to
-- those files (a spec that only exercises one module); with no list every file the TOC names loads. `templates` is
-- where the environment keeps the virtual templates a frame is built from by name: each XML entry hands it what it
-- declares (`{ name, type, inherits }`), so ForeverTrackerInteractiveLineTemplate resolves to the stock line it
-- inherits. An environment that draws no frames passes none, and its XML entries then declare nothing anyone builds.
---@param env table
---@param names? string[]
---@param templates? fun(template: {name: string, type: string, inherits: string?})
---@return table
function ForeverCore.load(env, names, templates)
	local directory = ForeverCore.directory()
	local wanted = Wanted(names)
	local ns = {}
	for _, entry in ipairs(ForeverCore.files(directory)) do
		-- The reader joins `directory` to each TOC line, so this is the name the TOC wrote.
		if wanted == nil or wanted[entry.path:sub(#directory + 2)] then
			if entry.kind == "lua" then
				local chunk = assert(loadfile(entry.path), entry.path)
				setfenv(chunk, env)
				chunk("ForeverCore", ns)
			elseif templates then
				for _, template in ipairs(Toc.templates(entry.path)) do
					templates(template)
				end
			end
		end
	end
	return ns
end

return ForeverCore
