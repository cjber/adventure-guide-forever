# Dungeon journeys

QuestieDB supplies dungeon quests, their prerequisite chains and giver locations at runtime.
Questie confirms available pickups. The planner routes only accepted or proven eligible steps;
remaining prerequisites are shown in the full guide as an outline. Completing or accepting a quest
rebuilds the same journey and updates Shortest Path Forever through the existing guidance contract.
Unknown objective positions never become waypoints. A known entrance can serve as an explicitly
labelled destination for unfinished dungeon quests; QuestieDB supplies it, with Tweaks Forever as fallback.

Installed AtlasLoot Classic supplies boss names and drops through `AtlasLoot.ItemDB:Get` and
`GetItemTable` for `AtlasLootClassic_DungeonsAndRaids`. The module loads only when dungeon loot is
requested outside combat. Its selected difficulty and linked loot tables are respected. Trash sections,
non-item headings and duplicate bosses or drops are omitted. Item names, icons and tooltips come from
the client. No database is copied into the addon. Missing data gives a short installation or unavailable hint.

Journey presents the quest route alongside bosses and loot, with no strategy, ability or model pages.
Tweaks Forever owns automatic interior maps using installed Atlas and Atlas Classic WoW.
Legacy Forever owns dungeon completion and collection tracking.
