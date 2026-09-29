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
	assert(module:GetDifficultyByName("NORMAL") == nil)
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
local reloaded = harness.load({ charDB = h.G.AdventureGuideForeverCharDB })
for _, id in ipairs(planned) do
	assert(reloaded.ns.Dungeons.Planned(id), "plans survive reload")
	assert(h.ns.Prefs().plannedDungeons[id], "other dungeon choices must not clear earlier plans")
	h.ns.Dungeons.SetPlanned(id, false)
	assert(not h.ns.Dungeons.Planned(id))
end
assert(#h.errors == 0, table.concat(h.errors, "\n"))
print("dungeon_regression_spec: localized AtlasLoot lookup and whole-catalog planning passed")
