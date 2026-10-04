-- The dungeon pages' Encounter Journal layout, curated drop chances and boss abilities.
local harness = dofile("tests/harness.lua")
local Button = dofile("tests/ui_helpers.lua").Button
local checks = 0
local function equal(actual, expected, label)
	checks = checks + 1
	assert(actual == expected, ("%s: expected %s, got %s"):format(label, tostring(expected), tostring(actual)))
end

-- A synthetic AtlasLoot shape, with one curated boss, one drop it rates and one it does not.
local h = harness.load({
	items = {
		[999904] = { name = "Rated drop", quality = 3, icon = 134400 },
		[999905] = { name = "Unrated drop", quality = 3, icon = 134401 },
	},
})
h.G.AtlasLoot = {
	Locales = { Trash = "Trash" },
	ItemDB = {
		Get = function()
			return {
				GetDifficultyByName = function(_, name)
					return name == "n" and 1
				end,
				Test = {
					InstanceID = 43,
					LevelRange = { 10, 25 },
					items = {
						{ name = "Test boss", npcID = 999901, Level = 21, [1] = { { 1, 999904 }, { 2, 999905 } } },
					},
				},
			}
		end,
	},
	Data = {
		Droprate = {
			GetData = function(_, npc, item)
				if npc == 999901 and item == 999904 then
					return 23.1
				end
			end,
		},
	},
}
-- A creature entry's bundled ids, resolved by the client the way the page reads them at runtime.
h.ns.Data.bossAbilities[999901] = { 12345, 12346 }
h.G.C_Spell.GetSpellInfo = function(id)
	return { name = "Ability " .. id, iconID = 100000 + id }
end

h.ns.Window.OpenDungeon(43)
h.flush()
equal(#h.errors, 0, "open dungeon UI")

-- The instance select page is the journal's tile grid; Back leaves the instance page for it.
h.Click(Button(h, h.ns.L.MENU_BACK))
local tiles = h.Find(function(frame)
	return frame:IsVisible() and frame.Range ~= nil and frame.value ~= nil and frame.value.id == 43
end)
assert(#tiles >= 1, "the selected dungeon's tile is drawn")
local tile = tiles[1]
equal(tile.Up.file, 522972, "instance tile uses the journal sheet")
equal(tile.Up.width, 174, "instance tile width")
equal(tile.Up.height, 96, "instance tile height")
equal(tile.Title.font, "QuestTitleFontBlackShadow", "instance title uses the journal font")
equal(tile.Range.font, "GameFontNormal", "instance range uses the journal font")
equal(tile.Range:GetText(), h.ns.L.DUNGEON_QUEST_LEVELS:format(15, 25), "instance tile shows its level range")

-- Picking a tile opens the instance page again.
h.Click(tile)
h.flush()
equal(#h.errors, 0, "select a dungeon from the grid")

-- Bosses are the journal's 325x55 buttons with the default portrait.
h.Click(Button(h, h.ns.L.DUNGEON_BOSSES_TAB))
local bossRows = h.Find(function(frame)
	return frame:IsVisible() and frame.value ~= nil and frame.value.boss and frame.value.title == "Test boss"
end)
equal(#bossRows, 1, "one boss button")
local boss = bossRows[1]
equal(boss.Up.file, 522972, "boss button uses the journal sheet")
equal(boss.Up.width, 325, "boss button width")
equal(boss.Up.height, 55, "boss button height")
equal(boss.Portrait.file, nil, "no per-encounter portrait source leaves the boss plate")
equal(boss.Title.font, "GameFontNormalMed3", "boss name uses the journal font")

-- Each boss's abilities sit under it as a spell icon and name, with the client's own spell tooltip.
local abilityRows = h.Find(function(frame)
	return frame:IsVisible() and frame.value ~= nil and frame.value.ability == 12345
end)
equal(#abilityRows, 1, "one ability row under the boss")
equal(abilityRows[1].Title:GetText(), "Ability 12345", "ability name comes from the client")
equal(abilityRows[1].AbilityIcon.file, 112345, "ability icon comes from the client")
h.Hover(abilityRows[1])
equal(h.tooltip[1], "spell: 12345", "ability hover uses the client spell tooltip")

-- Loot rows are the journal's 321x45 rows with a 42x42 icon and the loot border, rated only where AtlasLoot has one.
h.Click(Button(h, h.ns.L.DUNGEON_LOOT_TAB))
local lootRows = h.Find(function(frame)
	return frame:IsVisible() and frame.value ~= nil and frame.value.item ~= nil
end)
local rated, unrated
for _, row in ipairs(lootRows) do
	rated = rated or (row.value.item == 999904 and row)
	unrated = unrated or (row.value.item == 999905 and row)
end
assert(rated and unrated, "both drops are drawn")
equal(rated.ItemIcon.width, 45, "loot icon width")
equal(rated.ItemIcon.height, 45, "loot icon height")
equal(rated.LootFrame.file, 522972, "loot row uses the journal loot border")
equal(
	rated.Percent:GetText(),
	h.ns.L.DUNGEON_DROP_RATE:format(23.1) .. "%",
	"curated drop chance shown beside the drop"
)
equal(unrated.Percent:IsShown(), false, "a drop without a rate shows no percent")
equal(unrated.Percent:GetText(), "", "a drop without a rate shows no text")

-- The reader answers only where AtlasLoot registered a rate: nothing is bundled and nothing is invented.
equal(h.ns.Dungeons.DropRate(999901, 999904), 23.1, "curated rate read through AtlasLoot")
equal(h.ns.Dungeons.DropRate(999901, 999905), nil, "absent rate stays absent")
h.G.AtlasLoot.Data.Droprate = nil
equal(h.ns.Dungeons.DropRate(999901, 999904), nil, "no AtlasLoot droprate leaves the row unrated")
equal(#h.errors, 0, "journal layout, drop chances and abilities have no errors")

-- A spell id this build cannot resolve never becomes a row: the capability is the client's, not the table's.
local missing = harness.load()
missing.ns.Data.bossAbilities[639] = { 111111 }
missing.G.C_Spell.GetSpellInfo = function()
	return nil
end
equal(#missing.ns.Dungeons.Abilities(639), 0, "an unresolvable id is dropped")
equal(missing.ns.Dungeons.DropRate(639, 1), nil, "no droprate module reads as absent")

-- Two ids the client names the same are one ability row, never a repeated name.
local dedupe = harness.load()
dedupe.ns.Data.bossAbilities[639] = { 111, 222 }
dedupe.G.C_Spell.GetSpellInfo = function()
	return { name = "Cleave", iconID = 134400 }
end
equal(#dedupe.ns.Dungeons.Abilities(639), 1, "one row per ability name")

print(("dungeon_journal_spec: %d checks passed"):format(checks))
