-- Run from the repository root: luajit tests/locales_spec.lua
--[[ Translations (Locales/README.md): Locales/phrases.txt copied to Locales/<locale>.lua is a working translation
     for that locale only, and every such file in the tree is listed in the TOC after enUS.lua. ]]
local checks = 0

local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %q, got %q"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local function Read(path)
	local file = assert(io.open(path))
	local text = file:read("*a")
	file:close()
	return text
end

local function Load(chunks, locale)
	local ns = {}
	for _, chunk in ipairs(chunks) do
		local run = type(chunk) == "string" and assert(loadstring(chunk)) or chunk
		setfenv(
			run,
			setmetatable({
				GetLocale = function()
					return locale
				end,
			}, { __index = _G })
		)
		run("AdventureGuideForever", ns)
	end
	return ns.L
end

local enUS = assert(loadfile("Locales/enUS.lua"))
local template = Read("Locales/phrases.txt")
-- A translator's copy: the template's guard for their locale, and a line translated.
local french = template:gsub('"deDE"', '"frFR"'):gsub('L%["TITLE"%] = "[^\n]*"', 'L["TITLE"] = "Guide d\'aventure"')

local L = Load({ enUS, french }, "frFR")
equal(L.TITLE, "Guide d'aventure", "a translated line")
equal(L.GO, "Go", "a line left as the template has it reads English")
equal(Load({ enUS, french }, "deDE").TITLE, "Adventure Guide", "another locale ignores the file")
equal(Load({ enUS, french }, "enUS").TITLE, "Adventure Guide", "English ignores it too")

-- The template holds every English line as it is, bar the GlobalStrings the client translates itself.
local english = Load({ enUS }, "enUS")
local ns = { L = {} }
setfenv(assert(loadstring(template)), {
	GetLocale = function()
		return "deDE"
	end,
})("AdventureGuideForever", ns)
local left = { NO_WAYPOINT = true, WHY_CLASSES = true, WHY_RACES = true }
for key, text in pairs(english) do
	equal(ns.L[key], not left[key] and text or nil, key .. ": the template's line")
end
for key in pairs(ns.L) do
	equal(english[key] ~= nil, true, key .. ": the template has no stale line")
end

local listed, order = {}, 0
for line in io.lines("AdventureGuideForever.toc") do
	line = line:gsub("\r", "")
	if line:match("^Locales\\") then
		order = order + 1
		listed[line:match("^Locales\\(.+)$")] = order
	end
end
equal(listed["enUS.lua"], 1, "enUS.lua loads first")
local files = io.popen("ls Locales")
for name in files:lines() do
	if name:match("^%a%a%u%u%.lua$") and name ~= "enUS.lua" then
		checks = checks + 1
		assert(listed[name] and listed[name] > 1, name .. ": listed in the TOC after enUS.lua")
		assert(
			Read("Locales/" .. name):find('if GetLocale%(%) ~= "' .. name:sub(1, 4) .. '" then'),
			name .. ": guarded"
		)
	end
end
files:close()

-- A sample argument for each placeholder in an English line, in order: text for %s, a number for the rest. A
-- positional one (%2$s, which the client's string.format takes) counts once.
local function Samples(text)
	local args = {}
	for conversion in text:gsub("%%%%", ""):gsub("%%%d+%$", "%%"):gmatch("%%[%-+#0]*%d*%.?%d*([a-zA-Z])") do
		args[#args + 1] = conversion == "s" and "Sample" or 7
	end
	return args
end

-- string.format with the client's positional placeholders, which LuaJIT's lacks.
local function Format(text, args)
	if not text:find("%%%d+%$") then
		return string.format(text, unpack(args))
	end
	local ordered = {}
	local plain = text:gsub("%%(%d+)%$", function(position)
		ordered[#ordered + 1] = args[tonumber(position)]
		return "%"
	end)
	return string.format(plain, unpack(ordered))
end
equal(Format("%2$s, %1$d", { 3, "a" }), "a, 3", "positional placeholders reorder their arguments")

-- Every translation the TOC loads, in the client's own way: nothing under another locale, and under its own each line
-- is text that formats with the English line's arguments (Lua ignores a spare argument, so the count is checked too).
local translated = 0
for line in io.lines("AdventureGuideForever.toc") do
	local locale = line:gsub("\r", ""):match("^Locales\\(%a%a%u%u)%.lua$")
	if locale and locale ~= "enUS" then
		translated = translated + 1
		local path = "Locales/" .. locale .. ".lua"
		local source = Read(path)
		-- Every shipped file has machine lines, whole or marked `-- mt` (WFA-34); one that people translate in full
		-- drops the note and its case here.
		equal(
			source:find("^%-%- Machine translated %(%d+%-%d+%-%d+%); corrections welcome: https://") ~= nil,
			true,
			path .. ": says it is machine translated on its first line"
		)
		equal(Load({ enUS, assert(loadfile(path)) }, "enUS").TITLE, english.TITLE, path .. ": English ignores it")
		local strings = Load({ enUS, assert(loadfile(path)) }, locale)
		-- The guide's name stays its own in every language: the client's word for it is Blizzard's dungeon journal.
		equal(strings.TITLE, english.TITLE, path .. ": keeps the name Adventure Guide")
		local count = 0
		for key, text in pairs(strings) do
			local args = Samples(english[key])
			equal(type(text), "string", path .. ": " .. key .. " is text")
			equal(#Samples(text), #args, path .. ": " .. key .. " keeps its placeholders")
			if #args > 0 then
				local ok, result = pcall(Format, text, args)
				equal(ok, true, path .. ": " .. key .. " formats (" .. tostring(result) .. ")")
			end
			count = count + (text ~= english[key] and 1 or 0)
		end
		equal(count > 0, true, path .. ": translates something")
	end
end
equal(translated > 0, true, "the TOC loads the translations")

-- WHATS_NEW is the newest release's news: it opens with the first headline of CHANGELOG.md's top versioned entry, so
-- a release that forgets to rewrite it fails here instead of announcing the last release's features.
local newest = Read("CHANGELOG.md"):match("\n## %[?%d+%.%d+%.%d+%]? %- [^\n]*\n+%- %*%*(.-)%.?%*%*")
equal(english.WHATS_NEW:sub(1, #newest), newest, "WHATS_NEW opens with the newest release's headline")

print(("locales_spec: %d checks passed"):format(checks))
