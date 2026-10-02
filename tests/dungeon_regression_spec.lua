-- Contract matches AtlasLoot ItemDB:AddDifficulty: NORMAL registers a localized name and short key n.
local harness = dofile("tests/harness.lua")
local function noop() end
for _, locale in ipairs({ "Normal", "Normalmodus", "Обычный" }) do
	local h = harness.load()
	local module = {
		GetDifficultyByName = function(_, name)
			return ({ n = 1, [locale] = 1 })[name]
		end,
	}
	for _, id in ipairs({ 36, 43, 48, 389 }) do
		module["Instance" .. id] = {
			InstanceID = id,
			items = {
				{ name = "Encounter " .. id, npcID = id, Level = 20, [1] = { { 1, 999900 } } },
			},
		}
	end
	h.G.AtlasLoot = { ItemDB = {
		Get = function()
			return module
		end,
	}, Locales = {} }
	local source = assert(h.ns.Dungeons.Source(noop))
	for _, id in ipairs({ 36, 43, 48, 389 }) do
		assert(source.bosses[id][1].name == "Encounter " .. id)
		assert(source.loot[id][1].droppers[1].id == id)
	end
end
-- Empty eligibility is intentional: planning must survive the full route rebuild anyway.
local h = harness.load()
for _, quest in pairs(h.ns.Data.quests) do
	quest.min = 99
end
local old = harness.load({ charDB = { journey = "dungeon:43" } })
assert(old.ns.Dungeons.Planned(43), "migrate previously selected dungeon")
local planned = {}
for id, instance in pairs(h.ns.Data.instances) do
	if not instance.raid then
		h.ns.Window.OpenDungeon(id)
		h.flush()
		local button
		for _, frame in ipairs(h.frames) do
			if
				frame:IsObjectType("Button")
				and frame:IsVisible()
				and (
					frame:GetText() == h.ns.L.DUNGEON_PLAN
					or frame.Text and frame.Text:GetText() == h.ns.L.DUNGEON_PLAN
				)
			then
				button = frame
			end
		end
		assert(button, "plan button for " .. id)
		h.Click(button)
		h.flush()
		assert(h.ns.Dungeons.Planned(id), "planning must persist for " .. id)
		local bosses = h.ns.Dungeons.Bosses(nil, id)
		-- Bosses now come from AtlasLoot/native EJ only; with neither installed the list is empty, never nil.
		assert(type(bosses) == "table", "boss list is a table for " .. id)
		for _, frame in ipairs(h.frames) do
			if
				frame:IsObjectType("Button")
				and frame:IsVisible()
				and (
					frame:GetText() == h.ns.L.DUNGEON_BOSSES_TAB
					or frame.Text and frame.Text:GetText() == h.ns.L.DUNGEON_BOSSES_TAB
				)
			then
				h.Click(frame)
				break
			end
		end
		h.flush()
		if bosses[1] then
			local visible = false
			for _, entry in ipairs(h.ns.DumpLayout(h.G.AdventureGuideForeverWindow, h.Describe)) do
				visible = visible or entry.text == bosses[1].name
			end
			assert(visible, "standalone boss panel for " .. id)
		end
		planned[#planned + 1] = id
	end
end
assert(#planned > 15, "exercise the whole Classic catalog")
-- Raids page through the same window; with no optional source their boss list is a table, never a bundled baseline.
for _, raid in ipairs(h.ns.Raids) do
	if raid.map then
		h.ns.Window.OpenDungeon(raid.map)
		h.flush()
		for _, frame in ipairs(h.frames) do
			if
				frame:IsObjectType("Button")
				and frame:IsVisible()
				and (
					frame:GetText() == h.ns.L.DUNGEON_BOSSES_TAB
					or frame.Text and frame.Text:GetText() == h.ns.L.DUNGEON_BOSSES_TAB
				)
			then
				h.Click(frame)
				break
			end
		end
		h.flush()
		assert(type(h.ns.Dungeons.Bosses(nil, raid.map)) == "table", "raid boss list is a table for " .. raid.map)
	end
end
local reloaded = harness.load({ charDB = h.G.AdventureGuideForeverCharDB })
for _, id in ipairs(planned) do
	assert(reloaded.ns.Dungeons.Planned(id), "plans survive reload")
	assert(h.ns.Prefs().plannedDungeons[id], "other dungeon choices must not clear earlier plans")
	h.ns.Dungeons.SetPlanned(id, false)
	assert(not h.ns.Dungeons.Planned(id))
end
assert(#h.errors == 0, table.concat(h.errors, "\n"))
-- Hand off to the optional guide's public command without importing its data.
local classic = harness.load()
classic.ns.Window.OpenDungeon(43)
classic.flush()
local launch
for _, frame in ipairs(classic.frames) do
	if frame:IsObjectType("Button") and frame:GetText() == classic.ns.L.DUNGEON_CLASSIC_GUIDE then
		launch = frame
	end
end
assert(launch, "optional guide button is built")
assert(not launch:IsShown(), "guide button stays hidden without the dependency")
assert(not classic.ns.Integrations.OpenClassicGuide(), "absent dependency cannot launch")
classic.metadata.AdventureGuideClassic = {}
classic.ns.Window.OpenDungeon(43)
classic.flush()
assert(not launch:IsShown(), "loaded dependency without its command cannot launch")
local calls = 0
classic.G.SlashCmdList.ADVENTUREGUIDECLASSIC = function(message)
	assert(message == "", "public command receives its normal home argument")
	calls = calls + 1
end
classic.ns.Window.OpenDungeon(43)
classic.flush()
assert(launch:IsVisible(), "available dependency exposes the launch button")
classic.Click(launch)
assert(calls == 1, "one click invokes the public guide command once")
assert(#classic.errors == 0, "public handoff does not raise errors")
print("dungeon_regression_spec: localized AtlasLoot lookup, raid pages and whole-catalog planning passed")
