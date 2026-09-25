-- Run from the repository root: luajit tests/locales_spec.lua
--[[ Locales/Translations.lua as the packager leaves it: each @localization line replaced by that locale's
     L["KEY"] = "text" lines. A translation lands on its key, only for its own locale, and a line nobody
     translated keeps its English. ]]
local checks = 0

local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %q, got %q"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local file = assert(io.open("Locales/Translations.lua"))
local source = file:read("*a")
file:close()

local seen = 0
local packaged = source:gsub('([ \t]*)%-%-@localization%(locale="(%a+)"[^\n]*%)@', function(indent, locale)
	seen = seen + 1
	return ('%sL["TITLE"] = "%s guide"\n%sL["SKIP"] = "%s skip"'):format(indent, locale, indent, locale)
end)
equal(seen, 10, "a line for each locale CurseForge translates")

local function Load(chunk, locale)
	local ns = {}
	assert(loadfile("Locales/enUS.lua"))("AdventureGuideForever", ns)
	local run = assert(loadstring(chunk, "Translations.lua"))
	setfenv(
		run,
		setmetatable({
			GetLocale = function()
				return locale
			end,
		}, { __index = _G })
	)
	run("AdventureGuideForever", ns)
	return ns.L
end

for _, locale in ipairs({ "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "zhCN", "zhTW" }) do
	local L = Load(packaged, locale)
	equal(L.TITLE, locale .. " guide", locale .. ": its translation")
	equal(L.SKIP, locale .. " skip", locale .. ": each line it has")
	equal(L.GO, "Go", locale .. ": an untranslated line stays English")
end
equal(Load(packaged, "enUS").TITLE, "Adventure Guide", "English is the table itself")
equal(Load(packaged, "enGB").TITLE, "Adventure Guide", "a locale CurseForge doesn't list reads English")
equal(Load(source, "deDE").TITLE, "Adventure Guide", "a git checkout, before the packager, reads English")

print(("locales_spec: %d checks passed"):format(checks))
