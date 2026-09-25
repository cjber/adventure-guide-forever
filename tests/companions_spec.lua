-- Run from the repository root: luajit tests/companions_spec.lua
-- What's new after an update (Core.lua ns.WhatsNew) and the companion hints (Companions.lua) through
-- tests/harness.lua: the chat line's first install, same version, new version, setting off, dev checkout and missing
-- saved variables; each hint's three states (not installed, installed but off, loaded) and its setting.
local harness = dofile("tests/harness.lua")
local checks = 0

local function equal(actual, expected, label)
	checks = checks + 1
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)), 2)
	end
end

local function clean(h, label)
	equal(#h.errors, 0, label .. ": errors\n" .. table.concat(h.errors, "\n"))
end

-- ui_spec's level-18 orc shaman in The Barrens, with a hand-in the route leads to.
local function Load(extra)
	local options = {
		completed = { 844 },
		log = { { id = 845, title = "The Zhevra", level = 13, complete = true, map = 1413, x = 0.5223, y = 0.3101 } },
	}
	for key, value in pairs(extra or {}) do
		options[key] = value
	end
	return harness.load(options)
end

-- The chat lines naming an update.
local function Updates(h)
	local found = {}
	for _, message in ipairs(h.prints) do
		if message:find("updated to", 1, true) then
			found[#found + 1] = message
		end
	end
	return found
end

--[[ What's new ]]

do
	local h = Load({ version = "0.2.0" })
	clean(h, "first install")
	equal(#Updates(h), 0, "first install: silent")
	equal(h.G.AdventureGuideForeverDB.lastVersion, "0.2.0", "first install: the version is kept")
end

do
	local h = Load({ version = "0.2.0", db = { lastVersion = "0.2.0" } })
	equal(#Updates(h), 0, "same version: silent")
	clean(h, "same version")
end

do
	local h = Load({ version = "0.2.0", db = { lastVersion = "0.1.1" } })
	local lines = Updates(h)
	equal(#lines, 1, "new version: one line")
	equal(
		lines[1],
		"|cff33ff99" .. h.ns.TITLE .. "|r " .. h.ns.L.UPDATED_TO:format("0.2.0", h.ns.L.WHATS_NEW),
		"new version: the title, the version and the headline"
	)
	equal(h.G.AdventureGuideForeverDB.lastVersion, "0.2.0", "new version: now seen")
	h.ns.WhatsNew()
	equal(#Updates(h), 1, "new version: only once")
	clean(h, "new version")
end

do
	local h = Load({ version = "0.2.0", db = { lastVersion = "0.1.1", whatsNew = false } })
	equal(#Updates(h), 0, "setting off: silent")
	equal(h.G.AdventureGuideForeverDB.lastVersion, "0.2.0", "setting off: the version is still kept")
	clean(h, "setting off")
end

do
	-- The TOC's version before the packager fills it in; built here so the packager never rewrites this spec.
	local dev = "@" .. "project-version" .. "@"
	local h = Load({ version = dev, db = { lastVersion = "0.1.1" } })
	equal(#Updates(h), 0, "dev checkout: silent")
	equal(h.G.AdventureGuideForeverDB.lastVersion, "0.1.1", "dev checkout: nothing kept")
	clean(h, "dev checkout")
end

do
	-- The Forever beta client can skip loading saved variables: every login is a first install, never an error.
	local h = Load({ version = "0.2.0", db = nil })
	equal(#Updates(h), 0, "no saved variables: silent")
	clean(h, "no saved variables")
end

--[[ Companion hints ]]

for _, case in ipairs({
	{ addon = "ShortestPathForever", missing = "SPF_MISSING", disabled = "SPF_DISABLED", options = { spf = "v1" } },
	{
		addon = "SkillUpForever",
		missing = "SKILLUP_MISSING",
		disabled = "SKILLUP_DISABLED",
		options = { skillup = {} },
	},
	{ addon = "LegacyForever", missing = "LEGACY_MISSING", disabled = "LEGACY_DISABLED", options = { legacy = {} } },
}) do
	local addon = case.addon
	local h = Load()
	local Companions, L = h.ns.Companions, h.ns.L
	equal(Companions.State(addon), "missing", addon .. " not installed: missing")
	equal(Companions.Hint(addon), L[case.missing], addon .. " not installed: says install")

	h = Load({ installed = { [addon] = true } })
	Companions, L = h.ns.Companions, h.ns.L
	equal(Companions.State(addon), "disabled", addon .. " turned off: disabled")
	equal(Companions.Hint(addon), L[case.disabled], addon .. " turned off: says enable")
	h.ns.SetSetting("suggestCompanions", false)
	equal(Companions.Hint(addon), nil, addon .. " turned off, hints off: nothing")

	h = Load(case.options)
	equal(h.ns.Companions.State(addon), "loaded", addon .. " loaded")
	equal(h.ns.Companions.Hint(addon), nil, addon .. " loaded: nothing")
	clean(h, addon)
end

-- The route step's tooltip: the Shortest Path hint last, only while it isn't loaded and never for a wanderer.
local function StepTooltip(h)
	h.ns.OpenPanel()
	h.flush()
	local step = assert(h.ns.Route().steps[1], "a step")
	local row = h.G.CreateFrame("Button", nil, h.G.UIParent)
	row.step, row.index = step, 1
	h.ns.Overview.RowEnter(row)
	return h.tooltip[#h.tooltip]
end

do
	local h = Load()
	equal(StepTooltip(h), "instruction: " .. h.ns.L.SPF_MISSING, "step without Shortest Path: install hint")
	h.ns.SetSetting("wanderer", true)
	equal(StepTooltip(h) ~= "instruction: " .. h.ns.L.SPF_MISSING, true, "step, wanderer: no hint")
	clean(h, "step without Shortest Path")

	h = Load({ installed = { ShortestPathForever = true } })
	equal(StepTooltip(h), "instruction: " .. h.ns.L.SPF_DISABLED, "step, Shortest Path off: enable hint")
	h.ns.SetSetting("suggestCompanions", false)
	equal(StepTooltip(h) ~= "instruction: " .. h.ns.L.SPF_DISABLED, true, "step, hints off: no hint")

	h = Load({ spf = "v1" })
	local last = StepTooltip(h)
	equal(
		last ~= "instruction: " .. h.ns.L.SPF_MISSING and last ~= "instruction: " .. h.ns.L.SPF_DISABLED,
		true,
		"step with Shortest Path: no hint"
	)
	clean(h, "step with Shortest Path")
end

-- The window's Professions and Completion tabs: their calm line is the hint, or a plain one with hints off.
local function TabLine(h, index)
	h.ns.OpenWindow()
	h.flush()
	local window = h.G.AdventureGuideForeverWindow
	h.Click(window.Tabs[index])
	h.flush()
	local texts = {}
	for _, entry in ipairs(h.ns.DumpLayout(window, h.Describe)) do
		if entry.text then
			texts[entry.text] = true
		end
	end
	return texts
end

do
	local h = Load({ installed = { SkillUpForever = true, LegacyForever = true } })
	local L = h.ns.L
	equal(TabLine(h, 2)[L.SKILLUP_DISABLED], true, "Professions, SkillUp off: says enable")
	equal(TabLine(h, 4)[L.LEGACY_DISABLED], true, "Completion, Legacy off: says enable")
	h.ns.SetSetting("suggestCompanions", false)
	equal(TabLine(h, 2)[L.SKILLUP_ABSENT], true, "Professions, hints off: the plain line")
	equal(TabLine(h, 4)[L.LEGACY_ABSENT], true, "Completion, hints off: the plain line")
	clean(h, "tabs")
end

print(("companions_spec: %d checks passed"):format(checks))
