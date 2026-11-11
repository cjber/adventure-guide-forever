-- ForeverCore, the addon every Forever addon requires, loaded the way the client loads it: the files its TOC lists,
-- in order, from the checkout the FOREVER_CORE environment variable names. Local runs default to the sibling checkout
-- ../forever-core; CI checks the ref in tools/forever-core.txt out into forever-core/.
local ForeverCore = {}

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

-- The Lua files ForeverCore.toc lists, in its order, with forward slashes for loadfile. The client reads the XML
-- the TOC also lists itself, so there is nothing here to hand LuaJIT.
---@param directory string
---@return string[]
function ForeverCore.files(directory)
	local files = {}
	for line in io.lines(directory .. "/ForeverCore.toc") do
		line = line:gsub("\r$", "")
		if not (line:match("^%s*$") or line:match("^%s*#")) and line:match("%.lua%s*$") then
			files[#files + 1] = (line:gsub("\\", "/"))
		end
	end
	return files
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
-- those files (a spec that only exercises one module); with no list every file the TOC names loads.
---@param env table
---@param names? string[]
---@return table
function ForeverCore.load(env, names)
	local directory = ForeverCore.directory()
	local wanted = Wanted(names)
	local ns = {}
	for _, path in ipairs(ForeverCore.files(directory)) do
		if wanted == nil or wanted[path] then
			local chunk = assert(loadfile(directory .. "/" .. path), path)
			setfenv(chunk, env)
			chunk("ForeverCore", ns)
		end
	end
	return ns
end

return ForeverCore
