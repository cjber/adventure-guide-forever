-- Run from the repository root: luajit tests/contract_spec.lua (docs/plan.md §1.6)
-- AGF's mirror of the Shortest Path API (types/Namespace.lua, AGFSPF*) against SPF's own types/API.lua at a pinned sha,
-- read from the vendored tests/fixtures/spf_types_API.lua so it runs offline. CI diffs that copy against upstream.
local SPF_SHA = "1a70828f0f76e664ec601caafd9bec21f20ba121"
local checks = 0

local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local function Read(path)
	local handle = assert(io.open(path))
	local text = handle:read("*a")
	handle:close()
	return text
end

-- AGF class or alias <-> SPF's.
local ALIASES = {
	AGFSPFAPI = "SPFPublicAPI",
	AGFSPFStop = "SPFAPIStop",
	AGFSPFLeg = "SPFAPILeg",
	AGFSPFDetail = "SPFAPIDetail",
	AGFSPFMode = "SPFAPIMode",
	AGFSPFNoRoute = "SPFAPINoRoute",
}
-- AGF reads ShortestPathForever.API through a checked accessor (Integrations.lua SPF()), not a mirror.
local EXCLUDED = { SPFPublicAddon = true }

local function IsAtom(word)
	for part in (word .. "|"):gmatch("(.-)|") do
		if
			not (part:match("^[%a_][%w_%.]*%??$") or part:match("^[%a_][%w_%.]*%[%]%??$") or part:match('^"[^"]*"%??$'))
		then
			return false
		end
	end
	return true
end

-- The longest type prefix of a field's text. SPF writes prose straight after the type, with no `--`, so a function
-- type is its balanced `fun(...)` plus the `: ret` items that are type atoms; the first item with prose ends it.
local function TypeToken(text)
	text = text:gsub("%s+%-%-.*$", "")
	if not text:match("^fun%(") then
		return (text:match("^(%S+)"))
	end
	local depth, close = 0, nil
	for index = 4, #text do
		local char = text:sub(index, index)
		depth = depth + (char == "(" and 1 or 0) - (char == ")" and 1 or 0)
		if depth == 0 then
			close = index
			break
		end
	end
	assert(close, "unbalanced fun( in: " .. text)
	local token, rest = text:sub(1, close), text:sub(close + 1)
	local returns = rest:match("^:%s*(.*)$")
	if not returns then
		return token
	end
	local items = {}
	for item in (returns .. ", "):gmatch("(.-), ") do
		-- A named return (`seconds: number?`) compares by its type alone.
		local word, prose = item:gsub("^[%a_][%w_]*:%s+", ""):match("^(%S+)(.*)$")
		if not (word and IsAtom(word)) then
			break
		end
		items[#items + 1] = word
		if prose:match("%S") then
			break
		end
	end
	return #items > 0 and token .. ": " .. table.concat(items, ", ") or token
end

-- { [class] = { [field name, "?" kept] = type } } from ---@class / ---@field lines; an alias is a class whose one
-- field, "=", is its type.
local function Parse(text)
	local classes, current = {}, nil
	for line in (text .. "\n"):gmatch("(.-)\r?\n") do
		local class = line:match("^%-%-%-@class%s+([%w_]+)")
		local name, rest = line:match("^%-%-%-@field%s+([%w_]+%??)%s+(.*)$")
		local alias, definition = line:match("^%-%-%-@alias%s+([%w_]+)%s+(.*)$")
		if alias then
			classes[alias], current = { ["="] = TypeToken(definition) }, nil
		elseif class then
			current = {}
			classes[class] = current
		elseif name and current then
			current[name] = TypeToken(rest)
		elseif not line:match("^%-%-%-") then
			current = nil
		end
	end
	return classes
end

-- AGF's class names in a type, spelled as SPF spells them.
local function ToSPF(type)
	return (type:gsub("[%w_]+", function(word)
		return ALIASES[word] or word
	end))
end

local function Sorted(set)
	local list = {}
	for key in pairs(set) do
		list[#list + 1] = key
	end
	table.sort(list)
	return list
end

-- Every difference between AGF's mirror and SPF, as readable lines; an empty list means they agree. AGF may mark a
-- field optional that SPF always has (`EstimateDetail?`): AGF also runs on a Shortest Path from before it and checks
-- the member where it uses it. Never the reverse.
local function Compare(agfText, spfText, required)
	local agf, spf, problems = Parse(agfText), Parse(spfText), {}
	local mirrored = {}
	for _, agfClass in ipairs(Sorted(ALIASES)) do
		local spfClass = ALIASES[agfClass]
		mirrored[spfClass] = true
		local ours, theirs = agf[agfClass], spf[spfClass]
		if ours and not theirs then
			problems[#problems + 1] = agfClass .. ": SPF has no " .. spfClass
		elseif theirs and not ours then
			problems[#problems + 1] = spfClass .. ": AGF has no " .. agfClass
		elseif ours then
			for _, name in ipairs(Sorted(ours)) do
				local spfType = theirs[name] or theirs[(name:gsub("%?$", ""))]
				if spfType == nil then
					problems[#problems + 1] = ("%s.%s: not in SPF's %s"):format(agfClass, name, spfClass)
				elseif ToSPF(ours[name]) ~= spfType then
					problems[#problems + 1] = ("%s.%s: AGF %s, SPF %s"):format(agfClass, name, ours[name], spfType)
				end
			end
			for _, name in ipairs(Sorted(theirs)) do
				if ours[name] == nil and ours[name .. "?"] == nil then
					problems[#problems + 1] = ("%s.%s: not mirrored in %s"):format(spfClass, name, agfClass)
				end
			end
		end
	end
	for _, spfClass in ipairs(Sorted(spf)) do
		if not (mirrored[spfClass] or EXCLUDED[spfClass]) then
			problems[#problems + 1] = spfClass .. ": neither mirrored nor excluded"
		end
	end
	-- REQUIRED must be exactly the non-optional function fields.
	local functions = {}
	for name, type in pairs(agf.AGFSPFAPI or {}) do
		if type:match("^fun%(") and not name:match("%?$") then
			functions[name] = true
		end
	end
	local listed = {}
	for _, name in ipairs(required) do
		listed[name] = true
	end
	if table.concat(Sorted(functions), " ") ~= table.concat(Sorted(listed), " ") then
		problems[#problems + 1] = ("REQUIRED is %s; the required functions are %s"):format(
			table.concat(Sorted(listed), " "),
			table.concat(Sorted(functions), " ")
		)
	end
	return problems
end

-- The type-token rule on SPF's prose style and AGF's `--` style.
equal(TypeToken("integer uiMapID"), "integer", "token: a plain type")
equal(
	TypeToken("fun(a: integer, b?: string): number? seconds, nil when unknown"),
	"fun(a: integer, b?: string): number?",
	"token: prose ends the returns"
)
equal(TypeToken("fun(): number?, AGFSPFNoRoute? -- proposed"), "fun(): number?, AGFSPFNoRoute?", "token: two returns")
equal(TypeToken("fun(owner: string) starts guidance"), "fun(owner: string)", "token: no return clause")
equal(TypeToken('"walk"|"flight" -- modes'), '"walk"|"flight"', "token: a literal union")
equal(
	TypeToken("fun(a: integer): seconds: number?, reason: SPFAPINoRoute? -- travel seconds"),
	"fun(a: integer): number?, SPFAPINoRoute?",
	"token: named returns"
)

local vendored = Read("tests/fixtures/spf_types_API.lua")
equal(vendored:match("^([^\n]*)\n"), "-- shortest-path-forever " .. SPF_SHA .. ":types/API.lua", "vendored copy's sha")
local namespace = Read("types/Namespace.lua")
local required = {}
local list = assert(Read("Integrations.lua"):match("\nlocal REQUIRED = (%b{})"), "no REQUIRED in Integrations.lua")
for name in list:gmatch('"([%w_]+)"') do
	required[#required + 1] = name
end

local problems = Compare(namespace, vendored, required)
equal(#problems, 0, "the contract matches SPF " .. SPF_SHA:sub(1, 7) .. "\n" .. table.concat(problems, "\n"))
equal(Parse(namespace).AGFSPFAPI ~= nil and Parse(vendored).SPFPublicAPI ~= nil, true, "both sides were parsed")

-- Negative tests: today's old drift, a missing mirror field, and a stale REQUIRED list each fail.
local function Fails(text, needle, label)
	local found = Compare(text, vendored, required)
	equal(#found, 1, label .. ": one problem\n" .. table.concat(found, "\n"))
	equal(found[1]:find(needle, 1, true) ~= nil, true, label .. ": " .. found[1])
end
local cancel, n = namespace:gsub("(%-%-%-@field Cancel fun%(owner: string%)): boolean", "%1")
equal(n, 1, "negative: Cancel's line found")
Fails(
	cancel,
	"AGFSPFAPI.Cancel: AGF fun(owner: string), SPF fun(owner: string): boolean",
	"negative: Cancel returns nothing"
)
local missing
missing, n = namespace:gsub("\n%-%-%-@field title%? string\n", "\n")
equal(n, 1, "negative: the stop's title found")
Fails(missing, "SPFAPIStop.title?: not mirrored in AGFSPFStop", "negative: a missing mirror field")
required[#required] = nil
Fails(namespace, "REQUIRED is", "negative: REQUIRED misses a function")

print(("contract_spec: %d checks passed; SPF %s"):format(checks, SPF_SHA:sub(1, 7)))
