-- Run from the repository root: luajit tests/companions_spec.lua
-- What's new after an update (Core.lua ns.WhatsNew) and the companion hints (Companions.lua) through
-- tests/harness.lua: the chat line's first install, same version, new version, setting off, dev checkout and missing
-- saved variables; each companion hint's three states (not installed, installed but off, loaded), the shared
-- suggestions setting and "Don't suggest this again", and each place a hint shows.
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

--[[ Companion hints, through the shared Forever addons rules (UI/ForeverFamily.lua) ]]

-- The three states, the way the client tells them: not on disk, on disk but not loaded, loaded.
local function State(h, addon, state)
	h.installed[addon] = state == "off" or nil
	h.metadata[addon] = state == "on" and {} or nil
end

-- Each companion's line: missing suggests it (grey), installed but off says "Enable" where it has such a line,
-- loaded says nothing; the suggestions setting hides all of them, and "Don't suggest this again" the suggestion only.
for _, case in ipairs({
	{
		addon = "ShortestPathForever",
		key = "AdventureGuideForever.step",
		missing = "SPF_MISSING",
		off = "SPF_DISABLED",
	},
	{
		addon = "TweaksForever",
		key = "AdventureGuideForever.entrance",
		missing = "TWEAKS_MISSING",
		off = "TWEAKS_DISABLED",
	},
	{ addon = "SkillUpForever", key = "AdventureGuideForever.professionTrainer", missing = "SKILLUP_FAMILY" },
}) do
	local h = Load()
	local Companions, L, db, addon = h.ns.Companions, h.ns.L, h.G.AdventureGuideForeverDB, case.addon
	State(h, addon, "missing")
	local line, suggestion = Companions.Line(addon)
	equal(line, L[case.missing], addon .. " missing: suggests it")
	equal(suggestion, true, addon .. " missing: as a suggestion")
	db.suggestFamily = false
	equal(Companions.Line(addon), nil, addon .. " missing, suggestions off: nothing")
	db.suggestFamily = nil
	db.familyDismissed = { [case.key] = true }
	equal(Companions.Line(addon), nil, addon .. " missing, dismissed: nothing")
	State(h, addon, "off")
	line, suggestion = Companions.Line(addon)
	equal(line, case.off and L[case.off] or nil, addon .. " turned off: its Enable line, dismissed or not")
	equal(suggestion == true, false, addon .. " turned off: not a suggestion")
	db.suggestFamily = false
	equal(Companions.Line(addon), nil, addon .. " turned off, suggestions off: nothing")
	db.suggestFamily, db.familyDismissed = nil, nil
	State(h, addon, "on")
	equal(Companions.Line(addon), nil, addon .. " loaded: nothing")
	clean(h, addon)
end

-- The shared module looks its words up by English phrase: every one it asks for maps to our line of the same words,
-- which a translation of its FAMILY_ key replaces.
do
	local h = Load()
	local file = assert(io.open("UI/ForeverFamily.lua", "rb"))
	local source = file:read("*a")
	file:close()
	local asked = 0
	for phrase in source:gmatch('L%["([^"]+)"%]') do
		asked = asked + 1
		equal(h.ns.FamilyL[phrase], phrase, "the module's phrase has our line: " .. phrase)
	end
	equal(asked >= 16, true, "the module's phrases were found")
	clean(h, "phrases")
end

-- The old "Suggest companion addons" setting carries over: off stays off, and the old key goes.
do
	local h = Load({ db = { suggestCompanions = false } })
	equal(h.G.AdventureGuideForeverDB.suggestFamily, false, "migration: off stays off")
	equal(h.G.AdventureGuideForeverDB.suggestCompanions, nil, "migration: the old key goes")
	h = Load({ db = { suggestCompanions = true } })
	equal(h.G.AdventureGuideForeverDB.suggestFamily, nil, "migration: on is the default, so nothing is saved")
	h = Load({ db = { suggestCompanions = false, suggestFamily = true } })
	equal(h.G.AdventureGuideForeverDB.suggestFamily, true, "migration: a choice on the new page wins")
	clean(h, "migration")
end

-- The route step's tooltip: the Shortest Path line last, only while it isn't loaded and never for a wanderer.
local function StepTooltip(h)
	h.ns.OpenPanel()
	h.flush()
	local step = assert(h.ns.Route().steps[1], "a step")
	local row = h.G.CreateFrame("Button", nil, h.G.UIParent)
	row.step, row.index = step, 1
	h.ns.Overview.RowEnter(row)
	return h.tooltip[#h.tooltip], h.tooltipColors[#h.tooltip]
end

do
	local h = Load()
	local last, color = StepTooltip(h)
	equal(last, "colored: " .. h.ns.L.SPF_MISSING, "step without Shortest Path: its suggestion")
	equal(color and color[1], 0.5, "step without Shortest Path: grey")
	h.ns.SetSetting("wanderer", true)
	equal(StepTooltip(h) ~= "colored: " .. h.ns.L.SPF_MISSING, true, "step, wanderer: no suggestion")
	h.ns.SetSetting("wanderer", false)
	h.G.AdventureGuideForeverDB.familyDismissed = { ["AdventureGuideForever.step"] = true }
	equal(StepTooltip(h) ~= "colored: " .. h.ns.L.SPF_MISSING, true, "step, dismissed: no suggestion")
	clean(h, "step without Shortest Path")

	h = Load({ installed = { ShortestPathForever = true } })
	equal(StepTooltip(h), "instruction: " .. h.ns.L.SPF_DISABLED, "step, Shortest Path off: enable line")
	h.G.AdventureGuideForeverDB.suggestFamily = false
	equal(StepTooltip(h) ~= "instruction: " .. h.ns.L.SPF_DISABLED, true, "step, suggestions off: no line")

	h = Load({ spf = "v1" })
	last = StepTooltip(h)
	equal(
		last ~= "colored: " .. h.ns.L.SPF_MISSING and last ~= "instruction: " .. h.ns.L.SPF_DISABLED,
		true,
		"step with Shortest Path: no line"
	)
	clean(h, "step with Shortest Path")
end

-- A menu description that records its buttons, as Blizzard's builds them.
local function Recorder()
	local root = { buttons = {} }
	function root:CreateTitle() end
	function root:CreateButton(text, onClick)
		local button = { text = text, onClick = onClick }
		function button.SetTooltip() end
		function button.CreateButton(_, ...)
			return root:CreateButton(...)
		end
		self.buttons[#self.buttons + 1] = button
		return button
	end
	return root
end

local function Find(root, text)
	for _, button in ipairs(root.buttons) do
		if button.text:find(text, 1, true) then
			return button
		end
	end
end

-- The step's menu: a grey entry that shows Shortest Path's address, behind the same rules as the tooltip line.
do
	local h = Load()
	h.flush()
	local step = assert(h.ns.Route().steps[1])
	local root = Recorder()
	h.ns.Menu.Step(root, step)
	local entry = assert(Find(root, h.ns.L.SPF_FAMILY_MENU), "step menu without Shortest Path: the grey entry")
	equal(entry.text, "|cff7f7f7f" .. h.ns.L.SPF_FAMILY_MENU .. "|r", "step menu: grey")
	entry.onClick()
	local window = assert(h.G.ForeverFamilyLink, "the entry opens the address window")
	equal(window:IsShown(), true, "the address window shows")
	window:Hide()
	h.combat = true
	entry.onClick()
	equal(window:IsShown(), false, "never in combat")
	h.combat = false
	h.G.AdventureGuideForeverDB.familyDismissed = { ["AdventureGuideForever.step"] = true }
	root = Recorder()
	h.ns.Menu.Step(root, step)
	equal(Find(root, h.ns.L.SPF_FAMILY_MENU), nil, "step menu, dismissed: no entry")
	clean(h, "step menu")

	h = Load({ installed = { ShortestPathForever = true } })
	h.flush()
	root = Recorder()
	h.ns.Menu.Step(root, assert(h.ns.Route().steps[1]))
	equal(Find(root, h.ns.L.SPF_FAMILY_MENU), nil, "step menu, Shortest Path off: no entry")
end

-- A profession trainer (the professions aside): SkillUp's grey line on its tooltip and an entry in its menu, while
-- SkillUp isn't installed; another aside gets neither.
do
	local h = Load()
	local L, owner = h.ns.L, h.G.CreateFrame("Button", nil, h.G.UIParent)
	local trainer = { key = "profession:slot", text = "A free profession slot", category = "professions" }
	local other = { key = "talents", text = "Unspent talent points", category = "talents" }
	h.ns.Asides.Enter(owner, trainer)
	equal(h.tooltip[#h.tooltip], "colored: " .. L.SKILLUP_FAMILY, "trainer without SkillUp: its line")
	equal(h.tooltipColors[#h.tooltip][1], 0.5, "trainer without SkillUp: grey")
	h.ns.Asides.Enter(owner, other)
	equal(h.tooltip[#h.tooltip] ~= "colored: " .. L.SKILLUP_FAMILY, true, "another aside: no line")
	h.ns.Asides.Open(owner, trainer)
	local lines = table.concat(h.MenuLines(), "\n")
	equal(lines:find(L.SKILLUP_FAMILY_MENU, 1, true) ~= nil, true, "trainer's menu without SkillUp: the entry")
	h.ns.Asides.Open(owner, other)
	equal(table.concat(h.MenuLines(), "\n"):find(L.SKILLUP_FAMILY_MENU, 1, true), nil, "another aside's menu: none")
	h.G.AdventureGuideForeverDB.suggestFamily = false
	h.ns.Asides.Enter(owner, trainer)
	equal(h.tooltip[#h.tooltip] ~= "colored: " .. L.SKILLUP_FAMILY, true, "trainer, suggestions off: no line")
	h.G.AdventureGuideForeverDB.suggestFamily = nil
	State(h, "SkillUpForever", "off")
	h.ns.Asides.Enter(owner, trainer)
	equal(h.tooltip[#h.tooltip] ~= "colored: " .. L.SKILLUP_FAMILY, true, "trainer, SkillUp off: no line")
	State(h, "SkillUpForever", "on")
	h.ns.Asides.Open(owner, trainer)
	equal(table.concat(h.MenuLines(), "\n"):find(L.SKILLUP_FAMILY_MENU, 1, true), nil, "trainer, SkillUp on: none")
	clean(h, "profession trainer")
end

-- A dungeon card with no entrance: Tweaks Forever's line while it is missing or off, else that the entrance is unknown.
do
	local h = Load()
	local L, journey = h.ns.L, { kind = "dungeon", instance = 999999 }
	local function Note()
		local _, _, note = h.ns.Overview.Entrance(journey)
		return note
	end
	equal(Note(), L.TWEAKS_MISSING, "entrance without Tweaks: its line")
	h.G.AdventureGuideForeverDB.familyDismissed = { ["AdventureGuideForever.entrance"] = true }
	equal(Note(), L.ENTRANCE_UNKNOWN, "entrance, dismissed: unknown")
	h.G.AdventureGuideForeverDB.familyDismissed = nil
	State(h, "TweaksForever", "off")
	equal(Note(), L.TWEAKS_DISABLED, "entrance, Tweaks off: enable line")
	h.G.AdventureGuideForeverDB.suggestFamily = false
	equal(Note(), L.ENTRANCE_UNKNOWN, "entrance, Tweaks off and suggestions off: unknown")
	clean(h, "entrance")
end

print(("companions_spec: %d checks passed"):format(checks))
