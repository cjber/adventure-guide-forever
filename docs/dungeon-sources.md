# Dungeon sources

The Dungeons tab uses instance Map.IDs, never dungeon-name matching. No third-party guide code,
text or data is used. QuestieDB is an optional runtime source; none of its data is bundled.

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
but no dungeon-boss flag. Rank 3 is labelled Boss, 1 Elite and 2 Rare elite; dungeon bosses can share rank 1
with ordinary elites. The fallback tab is therefore titled Elites, with no explanatory footnote. Client
journal results retain Bosses. Loot comes from `npcDrops` with spawns in the instance area, names those
NPCs and sorts known rank-3 boss drops first; rewards come from item `questRewards`. That relation cannot establish which rewards
are choices. Icons and item tooltips come from the client by item ID. Objective text is Questie's runtime
`objectivesText`; accepted quests fall back to GetQuestLogQuestText and absent text is omitted. Entrance gates do not establish every locked door's key.

QuestieDB's `ZoneDB.private.dungeons` supplies alternate instance area IDs and already-converted Forever
entrance percentages. The adapter uses only points on maps AGF places and validates them before use. It
never applies the Era conversion a second time. Tweaks remains the live fallback when those points are absent.

The revised controls are the pinned Forever shared XML's
[TabSystemTopButtonTemplate](https://github.com/Gethe/wow-ui-source/blob/bd2470aed543f72697a044e989285b6c83e63f73/Interface/AddOns/Blizzard_SharedXML/Shared/TabSystem/TabSystemTemplates.xml)
and [CollapseButtonTemplate](https://github.com/Gethe/wow-ui-source/blob/bd2470aed543f72697a044e989285b6c83e63f73/Interface/AddOns/Blizzard_SharedXML/ListTemplates.xml),
the latter used by QuestLogHeaderTemplate. AGF centres every sub-tab label on the same baseline.
Screenshot runtime fixtures are independently derived from the pinned CMaNGOS source and client Item icons,
with synthetic instance spawn positions used only for membership. They live under tests, which is never packaged;
no Questie data has been copied. The five scenes cover quests, prep, ranked enemies, loot and missing QuestieDB.

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
