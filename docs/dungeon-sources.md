# Dungeon sources

The Dungeons tab uses instance Map.IDs, never dungeon-name matching. AtlasLoot, the native Encounter
Journal and QuestieDB are optional runtime sources; no third-party guide code, AtlasLoot data or
bundled boss table is shipped.

Boss data comes from AtlasLoot first and the native Encounter Journal second. AtlasLoot's curated
encounter list is authoritative when its dungeon module is installed, and explicit
`C_EncounterJournal` / `EJ_GetEncounterInfoByIndex` records fill the gaps when it is not. Loot comes
from AtlasLoot's curated item rows, with QuestieDB supplying runtime item-to-NPC relations where
AtlasLoot lists none. Neither source is bundled, and when none is installed the tab shows an empty
state instead of failing. QuestieDB can still supply runtime NPC names, item drops, rewards,
objectives and entrance points, but it is not a bundled fallback and never overrides AtlasLoot's
encounter order or localized names.

| Source | Pin / result | Use |
| --- | --- | --- |
| CMaNGOS classic-db | `22b51464f1625f6ef6275771de1f5466c6f5d19e` | `areatrigger_teleport` entrance requirements; `creature_ai_scripts`, `creature_template_spells` and `creature_spell_list` boss ability ids |
| QuestieDB Forever release | `QUESTIEDB_TAG` and `QUESTIEDB_SHA256` in `tools/gen_corpus.py` | The test-only quest corpus, through the addon's own QuestieSource build |
| wago.tools client tables | `BUILD` in `tools/gen_quests.py` | Existing Map / AreaTable joins identify dungeon instances; existing zone map art; the corpus's skill and faction names; `SpellName` and `SpellEffect` gate every generated boss ability id |
| Gethe/wow-ui-source, forever | `bd2470aed543f72697a044e989285b6c83e63f73` | Encounter Journal templates, explicit-instance API reads and square instance icon |
| QuestieDB public API documentation | `365537a340473291f5af3b7a53a5eca94e2a5f1a`, contract 2 | Runtime NPC ranks/spawns, item drops/rewards, quest objectives and entrance points |
| Tweaks Forever | Public API v1 | Outdoor entrance fallback, through the existing Providers adapter |

Boss abilities are the one generated boss table. `tools/gen_abilities.py` reads the pinned CMaNGOS
classic-db (GPL-3.0) `creature_ai_scripts` cast actions, `creature_template_spells` sets and
`creature_spell_list` lists for every elite-or-above creature that spawns on a browsed instance map, and
writes `Data/Abilities.lua` keyed by creature entry (npcID). Forever renumbers Classic spell ids, so every
id is kept only while the pinned wago.tools build names it in `SpellName` (not an obsolete name) and gives
it a real effect in `SpellEffect`; an id that resolves to nothing is dropped, never shipped. The page reads
the name, icon and tooltip from the client at runtime with `C_Spell.GetSpellInfo` and
`GameTooltip:SetSpellByID`, and hides an id this build cannot resolve. Only ids are bundled, no other
addon's ability table is copied, and the gate is `tools/gen_abilities_test.py` plus the regeneration check.

Drop chances come from AtlasLoot's own installed data, read at runtime through
`AtlasLoot.Data.Droprate:GetData(npcID, itemID)` (AtlasLoot's `DungeonsAndRaids/droprate.lua`). Nothing is
bundled and no rate is invented: a boss drop without a registered rate shows no percent. This is the same
curated rate AtlasLoot applies to its own item tooltips, not a claim the client or CMaNGOS can support.

The dungeon pages wear the Encounter Journal's own art and sizes without its frames, which do not load on
this client (`Blizzard_EncounterJournal.toc` gates its files to mainline): a 174x96 instance button, a
325x55 boss button with the default portrait, a 321x45 loot row with a 42x42 icon and the loot border, the
journal's title and body fonts, all cut from `UI-EncounterJournalTextures` at the journal's own texcoords.
Every texture, atlas and font object used was checked against the pinned client build before use.

The QuestieDB adapter owns the runtime quest source. `tools/gen_quests.py` writes the entrance
requirement list on each instance: level, alternative required items, completed quest and an unsupported
condition flag. It also retains the six reachable Classic dungeon instances without bundled quests
filed under their instance area. The catalog contains 19 dungeon instances; unused maps do not enter it.
Raids come from `Integrations/Raids.lua`, a hand-written registry (not the generator): it names the announced Forever
raid tiers first and the client's remaining raid Map.IDs after them. A registered raid enters the catalog only
once the client carries its Map.ID, so the announced 10-player Barrow Deeps and 20-player Hyjal Summit stay
listed in the registry until a build adds their maps, while the returning 40-player Onyxia's Lair (Map.ID 249)
is browsable today. These three are the announced Forever launch tier
([What's Next Panel Recap](https://news.blizzard.com/en-us/article/24303862/world-of-warcraft-forever-whats-next-panel-recap));
launch raids need no attunement and none is claimed. The other raid Map.IDs the client still carries are not
the announced tier and are filed under their own heading. Every raid is level 60; the group sizes and ranges
are the registry's, not a copied Classic attunement page. Blackrock Spire is one Map.ID, so the source does not
split its wings or claim Upper Spire is a five-player run. `tools/gen_quests.py` also writes the recommended
ranges and LFG IDs. The pinned
[LFGDungeons export](https://wago.tools/db2/LFGDungeons/csv?build=1.60.1.69913) contains the Classic names,
but their MapID is zero and it has no MinLevel/MaxLevel/TargetLevel columns. The linked
[ContentTuning export](https://wago.tools/db2/ContentTuning/csv?build=1.60.1.69913) gives identical
MinLevelSquish/MaxLevelSquish values and zero LfgMinLevel/LfgMaxLevel. These are not useful dungeon ranges.
At runtime, GetLFGDungeonInfo's recommended bounds win if positive and non-degenerate. Otherwise the tab
uses the published Classic ranges in [Neryssa's dungeon overview](https://www.wowhead.com/classic/guide/classic-dungeons-overview),
"WoW Classic Instances by Level", updated 2024-11-22 and checked 2026-09-27. This follows tweaks-forever's
published-range approach; its gen_zonelevels.py contains outdoor zones only, so it cannot supply dungeon
ranges directly. No quest levels or entry minima are substituted for those recommendations.

On 2026-09-27, wago.tools returned `{"errors":"Table not found."}` for both
[JournalInstance](https://wago.tools/db2/JournalInstance/csv?build=1.60.1.69913) and
[JournalEncounter](https://wago.tools/db2/JournalEncounter/csv?build=1.60.1.69913).
The [Forever API source](https://github.com/Gethe/wow-ui-source/blob/bd2470aed543f72697a044e989285b6c83e63f73/Interface/AddOns/Blizzard_APIDocumentationGenerated/EncounterJournalDocumentation.lua)
still declares `C_EncounterJournal.GetInstanceForGameMap`. The tab probes it and uses
`EJ_GetEncounterInfoByIndex(index, journalInstanceID)` when it returns a real instance. It never changes the
player's journal selection. Journal loot APIs depend on that shared selection, so the tab's Loot page uses
AtlasLoot's rows, or QuestieDB's explicit item-to-NPC relations, instead.

[LoadingScreens](https://wago.tools/db2/LoadingScreens/csv?build=1.60.1.69913) exists, but the inspected API
surface provides no Map.ID-to-loading-screen texture lookup. Adding an exported art table would exceed
this feature's bundled-data allowance. Instead, a client journal icon is shown when available; otherwise
the header uses existing `Data/ZoneArt.lua` tiles around the known entrance. Both preserve native aspect.

The [QuestieDB API](https://github.com/Questie/QuestieDB/blob/365537a340473291f5af3b7a53a5eca94e2a5f1a/docs/api.md)
provides sorted, shared `GetAllIds` arrays and detached `GetAll` rows. The adapter yields between records,
checks field metadata, and publishes only a complete snapshot. The pinned NPC metadata has creature rank
but no dungeon-boss flag. Only rank 3 proves a boss by itself; ordinary rank-1 elites are not listed as
bosses. Explicit client journal encounters can identify matching local NPCs in journal order. AtlasLoot's
curated encounter list takes precedence when available; otherwise the native journal supplies the
encounter list, and rank-3 Questie NPCs remain the final runtime fallback. Unidentified elites stay out.

Loot is deduplicated by item ID. Every dropper must have known spawns exclusively in the same instance;
unknown, outdoor or multi-instance droppers exclude the item, including when AtlasLoot also lists it.
The client supplies rarity: green and better survive, as do QuestieDB `startQuest` items of any rarity.
Uncached rarity waits for item data. Boss headings follow encounter order (otherwise level), and a final
Trash heading collects remaining local drops. Shared drops appear once, under the first matching boss.
Rewards still come from `questRewards`; the relation cannot establish which rewards are choices.
Icons and item tooltips come from the client. Objectives use runtime `objectivesText`, falling back to
GetQuestLogQuestText for accepted quests. Entrance gates do not establish every locked door's key.

[AtlasLoot Classic Forever 1.1.2](https://www.curseforge.com/wow/addons/atlasloot-forever/files/8984349)
was published for 1.60.1 on 2026-09-26. The publisher lists GPLv2. Its package and
[upstream Classic source](https://github.com/Hoizame/AtlasLootClassic) expose
`AtlasLoot.ItemDB:Get("AtlasLootClassic_DungeonsAndRaids")`: instance tables have `InstanceID`,
`LevelRange` and ordered `items`; encounter groups have `npcID`, `name`, `Level`, and item rows at the
module's `GetDifficultyByName("n")` key. Row slot 2 is the item ID. NPC IDs may be arrays. Wings
sharing an instance merge by recommended level, preserving each wing's encounter order. Only encounter
and localized Trash groups are read; quests, sets and other extra lists are excluded. AGF optionally
loads the installed dungeon module on demand out of combat, and reads again when a fight that held it back
ends or when AtlasLoot loads after the tab was read. It never changes AtlasLoot's selection or
bundles its data. An empty Bosses view names what would fill it: install AtlasLoot, or enable a copy that is
on disk but not running. With AtlasLoot alone, uncached rarity remains hidden and low-quality quest starters
need QuestieDB to establish that exception. The runtime adapter is also compatible with the inspected
Classic/Era layout; future schema changes fall back to the native Encounter Journal, and QuestieDB
still supplies loot relations where AtlasLoot lists none.

QuestieDB's `ZoneDB.private.dungeons` supplies alternate instance area IDs and already-converted Forever
entrance percentages. The adapter uses only points on maps AGF places and validates them before use. It
never applies the Era conversion a second time. The points are read once, before any dungeon details, so the
page, the journey card and the entrance button name the same place from the first draw. Tweaks remains the live
fallback when those points are absent.

The revised controls are the pinned Forever shared XML's
[TabSystemTopButtonTemplate](https://github.com/Gethe/wow-ui-source/blob/bd2470aed543f72697a044e989285b6c83e63f73/Interface/AddOns/Blizzard_SharedXML/Shared/TabSystem/TabSystemTemplates.xml)
and [CollapseButtonTemplate](https://github.com/Gethe/wow-ui-source/blob/bd2470aed543f72697a044e989285b6c83e63f73/Interface/AddOns/Blizzard_SharedXML/ListTemplates.xml),
the latter used by QuestLogHeaderTemplate. AGF centres every sub-tab label on the same baseline.
Screenshot runtime fixtures are independently derived from the pinned CMaNGOS source and client Item icons,
with synthetic instance spawn positions used only for membership. They live under tests, which is never packaged;
no Questie data has been copied. Scenes cover quests, prep, bosses, grouped loot, absent sources, empty data and the owner's Alliance Darkshore state.

The generator resolves unhinted overlapping outdoor maps using terrain area IDs from the same pinned
client build. CMaNGOS spawn rows have world coordinates but no area/zone column. The old smallest-rectangle
fallback projected Nalpak onto Durotar's western edge. `Map.WdtFileDataID` now locates WDT `MAID` root ADTs;
each `MCNK` area ID joins `AreaTable.ParentAreaID` to a candidate UiMap. Capital rectangles retain precedence
because outdoor terrain below Ironforge and Undercity does not identify their indoor WMO. Established
quest/home hints are preserved. If an ambiguous spawn has no unique area match, it has no coordinates.
The binary layout follows the [CMaNGOS extractor](https://github.com/cmangos/mangos-classic/tree/master/contrib/extractor);
terrain downloads are generator cache files and are not packaged.
The rebuild moved 77 NPCs off map edges they had been projected onto, including Nalpak and Ebru at the
Wailing Caverns cave.

AtlasLoot's installed `AtlasLootClassic_DungeonsAndRaids` module supplies encounter order and loot by
`InstanceID`. The reader loads that module outside combat. `ItemDB:AddDifficulty("NORMAL")` stores the
localized display name and the stable short identifier `n`; `GetDifficultyByName("NORMAL")` does not
resolve that registration key. Regression fixtures exercise localized names and the `n` contract.
Dungeon plans are character preferences independent of an eligible quest journey: a dungeon with no
available preparation quests can still be planned. Existing selected dungeon journeys migrate once.

Map reveal uses Forever's stock `MapPinPingTemplate` from SharedMapPoiTemplates.xml, through AGF's
existing data provider and a private inherited template in UI/Panel.xml. It acquires at
`PIN_FRAME_LEVEL_QUEST_PING`, plays two loops at fractional zone coordinates, and releases on refresh.
Explicit destination controls route through Integrations, then C_Map.OpenWorldMap; combat skips the
panel calls. Matching AGF pins flash on click and glow during map-control hover.

## Interior maps

The Maps tab reads `AtlasMaps` registered by Atlas 1.53.00 and Atlas Classic WoW r109. Stable `CL_` map keys connect each Classic instance to its wings and entrances. `DungeonID` is not a reliable join: the provider assigns 35 to both Maraudon and Dire Maul West. Each map uses its provider-owned 512×512 texture at native aspect, its localized title and its coloured legend. No files are copied into the addon, no provider UI is driven, and no map or player position is inferred from modern dungeon layouts.

Sources: [Atlas](https://www.curseforge.com/wow/addons/atlas), [Atlas Classic WoW](https://www.curseforge.com/wow/addons/atlas-classicwow). Enable both for interiors; AtlasLoot supplies loot, not these maps. Read-only validation against the r109 data and image files covered all 19 Classic dungeons. Maps without their provider show an explicit empty state.
