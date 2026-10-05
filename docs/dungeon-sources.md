# Dungeon sources

The Dungeons tab uses instance Map.IDs, never dungeon-name matching. QuestieDB is the optional runtime
source for a dungeon's quests and their details, and Atlas is the optional source for its interior maps;
no third-party guide code or data is shipped. Dungeon and raid bosses and loot belong to
[Adventure Guide for Classic](https://www.curseforge.com/wow/addons/adventure-guide-for-classic), this
addon's recommended companion for them. The tab keeps one control, Bosses and loot, that opens that
addon's window where its own Bosses and Loot pages were.

| Source | Pin / result | Use |
| --- | --- | --- |
| CMaNGOS classic-db | `22b51464f1625f6ef6275771de1f5466c6f5d19e` | `areatrigger_teleport` entrance requirements, and the test-only quest corpus |
| QuestieDB Forever release | `QUESTIEDB_TAG` and `QUESTIEDB_SHA256` in `tools/gen_corpus.py` | The test-only quest corpus, through the addon's own QuestieSource build |
| wago.tools client tables | `BUILD` in `tools/gen_quests.py` | Existing Map / AreaTable joins identify dungeon instances; existing zone map art; the corpus's skill and faction names |
| Gethe/wow-ui-source, forever | `bd2470aed543f72697a044e989285b6c83e63f73` | Shared tab and list templates |
| QuestieDB public API documentation | `365537a340473291f5af3b7a53a5eca94e2a5f1a`, contract 2 | Runtime NPC ranks/spawns, item rewards, quest objectives and entrance points |
| Tweaks Forever | Public API v1 | Outdoor entrance fallback, through the existing Providers adapter |

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
[JournalEncounter](https://wago.tools/db2/JournalEncounter/csv?build=1.60.1.69913). The build carries no
client encounter table, which is why a dungeon's bosses and loot are not listed here and the Bosses and loot
control hands them to Adventure Guide for Classic instead.

[LoadingScreens](https://wago.tools/db2/LoadingScreens/csv?build=1.60.1.69913) exists, but the inspected API
surface provides no Map.ID-to-loading-screen texture lookup. Adding an exported art table would exceed
this feature's bundled-data allowance. The page's ring icon is the Adventure Guide's own dungeon atlas, drawn
at native aspect, and the header uses existing `Data/ZoneArt.lua` tiles around the known entrance.

The [QuestieDB API](https://github.com/Questie/QuestieDB/blob/365537a340473291f5af3b7a53a5eca94e2a5f1a/docs/api.md)
provides sorted, shared `GetAllIds` arrays and detached `GetAll` rows. The adapter yields between records,
checks field metadata, and publishes only a complete snapshot. It reads item `questRewards` to place reward
icons on a dungeon quest and `objectivesText` for its objective line; a quest with no catalogue text falls
back to GetQuestLogQuestText for accepted quests. The relation cannot establish which rewards are choices.
Icons and item tooltips come from the client. Entrance gates do not establish every locked door's key.

QuestieDB's `ZoneDB.private.dungeons` supplies alternate instance area IDs and already-converted Forever
entrance percentages. The adapter uses only points on maps AGF places and validates them before use. It
never applies the Era conversion a second time. The points are read once, before any dungeon details, so the
page, the journey card and the entrance button name the same place from the first draw. Tweaks remains the live
fallback when those points are absent.

Adventure Guide for Classic registers one public entry point, the slash command `/agc`, whose handler toggles
its encounter journal window. It exposes no public way to open a specific instance, and its journal, navigation
and component tables sit inside a private global facade rather than `_G`. The Bosses and loot control therefore
calls that handler to open the companion's own window, names it in a tooltip, and is disabled with an install
hint when the addon is absent or disabled. Nothing reaches into the companion's tables.

The revised controls are the pinned Forever shared XML's
[TabSystemTopButtonTemplate](https://github.com/Gethe/wow-ui-source/blob/bd2470aed543f72697a044e989285b6c83e63f73/Interface/AddOns/Blizzard_SharedXML/Shared/TabSystem/TabSystemTemplates.xml)
and [CollapseButtonTemplate](https://github.com/Gethe/wow-ui-source/blob/bd2470aed543f72697a044e989285b6c83e63f73/Interface/AddOns/Blizzard_SharedXML/ListTemplates.xml),
the latter used by QuestLogHeaderTemplate. AGF centres every sub-tab label on the same baseline.
Screenshot runtime fixtures are independently derived from the pinned CMaNGOS source and client Item icons,
with synthetic instance spawn positions used only for membership. They live under tests, which is never packaged;
no Questie data has been copied. Scenes cover quests, prep, empty data and the owner's Alliance Darkshore state.

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

Dungeon plans are character preferences independent of an eligible quest journey: a dungeon with no
available preparation quests can still be planned. Existing selected dungeon journeys migrate once.

Map reveal uses Forever's stock `MapPinPingTemplate` from SharedMapPoiTemplates.xml, through AGF's
existing data provider and a private inherited template in UI/Panel.xml. It acquires at
`PIN_FRAME_LEVEL_QUEST_PING`, plays two loops at fractional zone coordinates, and releases on refresh.
Explicit destination controls route through Integrations, then C_Map.OpenWorldMap; combat skips the
panel calls. Matching AGF pins flash on click and glow during map-control hover.

## Interior maps

The Maps tab reads `AtlasMaps` registered by Atlas 1.53.00 and Atlas Classic WoW r109. Stable `CL_` map keys connect each Classic instance to its wings and entrances. `DungeonID` is not a reliable join: the provider assigns 35 to both Maraudon and Dire Maul West. Each map uses its provider-owned 512×512 texture at native aspect, its localized title and its coloured legend. No files are copied into the addon, no provider UI is driven, and no map or player position is inferred from modern dungeon layouts.

The Maps tab and the world map share one view. A dungeon the guide offers is pinned at its entrance on the world map, and the pin opens that instance's interior without going there first. An instance with several Atlas maps carries the game's own floor dropdown, on the map and in the tab, which returns to the floor last chosen in the session. Both controls are absent without Atlas and its Classic module, and nothing errors.

Sources: [Atlas](https://www.curseforge.com/wow/addons/atlas), [Atlas Classic WoW](https://www.curseforge.com/wow/addons/atlas-classicwow). Enable both for interiors; Adventure Guide for Classic supplies bosses and loot, not these maps. Read-only validation against the r109 data and image files covered all 19 Classic dungeons. Maps without their provider show an explicit empty state.
