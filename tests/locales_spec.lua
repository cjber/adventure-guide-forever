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

print(("locales_spec: %d checks passed"):format(checks))
