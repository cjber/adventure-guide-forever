# Dungeon sources

The Dungeons tab uses instance Map.IDs, never dungeon-name matching. QuestieDB and AtlasLoot are optional runtime sources; no third-party guide code or AtlasLoot data is bundled.

`Data/DungeonBosses.lua` is generated from the same pinned GPL-3.0 CMaNGOS database as the quests.
Its 167 encounters cover all 19 Classic dungeons. `instance_dungeon_encounters` supplies instance,
normal difficulty and order; `instance_encounters` must identify a creature-kill credit; the matching
`creature_template` supplies the NPC ID and levels. This is a baseline, not a complete rare-spawn list
or a claim that Classic data includes every Forever addition. AtlasLoot's curated list takes priority;
native journal records and Questie NPC records provide runtime names and additional confirmed bosses.

| Source | Pin / result | Use |
| --- | --- | --- |
| CMaNGOS classic-db | `22b51464f1625f6ef6275771de1f5466c6f5d19e` | Existing quest baseline and `areatrigger_teleport` entrance requirements |
| wago.tools client tables | `1.60.1.69913` | Existing Map / AreaTable joins identify dungeon instances; existing zone map art |
| Gethe/wow-ui-source, forever | `bd2470aed543f72697a044e989285b6c83e63f73` | Encounter Journal templates, explicit-instance API reads and square instance icon |
| QuestieDB public API documentation | `365537a340473291f5af3b7a53a5eca94e2a5f1a`, contract 2 | Runtime NPC ranks/spawns, item drops/rewards, quest objectives and entrance points |
| Tweaks Forever | Public API v1 | Outdoor entrance fallback, through the existing Providers adapter |

`tools/gen_quests.py` still owns all bundled quest data. Its entrance
requirement list on each instance contains: level, alternative required items, completed quest and an unsupported
condition flag. This also retains the six reachable Classic dungeon instances without bundled quests
filed under their instance area. The catalog contains 19 dungeon instances; raids and unused maps do not
enter it. Blackrock Spire is one Map.ID, so the source does not split its wings or claim Upper Spire is a
five-player run. The revision adds recommended ranges and LFG IDs through that generator. The pinned
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
QuestieDB's explicit item-to-NPC relations instead.

[LoadingScreens](https://wago.tools/db2/LoadingScreens/csv?build=1.60.1.69913) exists, but the inspected API
surface provides no Map.ID-to-loading-screen texture lookup. Adding an exported art table would exceed
this feature's bundled-data allowance. Instead, a client journal icon is shown when available; otherwise
the header uses existing `Data/ZoneArt.lua` tiles around the known entrance. Both preserve native aspect.

The [QuestieDB API](https://github.com/Questie/QuestieDB/blob/365537a340473291f5af3b7a53a5eca94e2a5f1a/docs/api.md)
provides sorted, shared `GetAllIds` arrays and detached `GetAll` rows. The adapter yields between records,
checks field metadata, and publishes only a complete snapshot. The pinned NPC metadata has creature rank
but no dungeon-boss flag. Only rank 3 proves a boss by itself; ordinary rank-1 elites are not listed as
bosses. Explicit client journal encounters can identify matching local NPCs in journal order. AtlasLoot's
curated encounter list takes precedence when available. Otherwise the generated encounter baseline
identifies Classic bosses even when their creature rank is only elite. Unidentified elites stay out.

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
module's `GetDifficultyByName("NORMAL")` key. Row slot 2 is the item ID. NPC IDs may be arrays. Wings
sharing an instance merge by recommended level, preserving each wing's encounter order. Only encounter
and localized Trash groups are read; quests, sets and other extra lists are excluded. AGF optionally
loads the installed dungeon module on demand out of combat. It never changes AtlasLoot's selection or
bundles its data. With AtlasLoot alone, uncached rarity remains hidden and low-quality quest starters
need QuestieDB to establish that exception. The runtime adapter is also compatible with the inspected
Classic/Era layout; future schema changes fall back to QuestieDB.

QuestieDB's `ZoneDB.private.dungeons` supplies alternate instance area IDs and already-converted Forever
entrance percentages. The adapter uses only points on maps AGF places and validates them before use. It
never applies the Era conversion a second time. Tweaks remains the live fallback when those points are absent.

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
existing data provider and a private inherited template in Panel.xml. It acquires at
`PIN_FRAME_LEVEL_QUEST_PING`, plays two loops at fractional zone coordinates, and releases on refresh.
Explicit destination controls route through Integrations, then OpenWorldMap/SetMapID; combat skips the
panel calls. Matching AGF pins flash on click and glow during map-control hover.

## Interior maps

The Maps tab reads `AtlasMaps` registered by Atlas 1.53.00 and Atlas Classic WoW r109. Stable `CL_` map keys connect each Classic instance to its wings and entrances. `DungeonID` is not a reliable join: the provider assigns 35 to both Maraudon and Dire Maul West. Each map uses its provider-owned 512×512 texture at native aspect, its localized title and its coloured legend. No files are copied into the addon, no provider UI is driven, and no map or player position is inferred from modern dungeon layouts.

Sources: [Atlas](https://www.curseforge.com/wow/addons/atlas), [Atlas Classic WoW](https://www.curseforge.com/wow/addons/atlas-classicwow). Enable both for interiors; AtlasLoot supplies loot, not these maps. Read-only validation against the r109 data and image files covered all 19 Classic dungeons. Maps without their provider show an explicit empty state.
