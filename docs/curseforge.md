I wanted a levelling guide that left me room to wander. Adventure Guide Forever offers a few journeys from your level and quest log, with a short route for the one you pick. It looks like it came with the game: a tab beside Quests, retail's Journeys cards and the game's own objective tracker.

Shortest Path Forever handles travel when installed. QuestieDB is the guide's quest catalogue and Questie applies its live availability rules; Questie owns its background map markers while Adventure Guide adds route markers. Atlas and Atlas Classic WoW optionally provide dungeon interiors and legends, and AtlasLoot optionally provides encounter and loot tables. If you'd rather follow another guide's route, you can hide the guide's tracker in settings.

![Choosing a journey and following its route](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/demo.gif)

Choose a journey, see its steps on the map and follow the route, then the window's Professions and Completion tabs.

![Adventure Guide beside The Barrens map](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/panel.png)

Choose a journey without leaving the world map's quest log.

![Shortest Path Forever's route to the first stop](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/map.png)

Pick one and Shortest Path Forever walks you to each stop in turn.

![The Adventure Guide window](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/window.png)

The same journeys have their own window, the featured one with its next steps beside it.

![The Professions tab](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/window_professions.png)

SkillUp Forever supplies the recipes to make and reagents still needed.

![The Completion tab](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/window_completion.png)

Legacy Forever supplies your zone's progress and the next things to do there.

![A journey in your chosen order](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/window_order.png)

Move steps around; quest givers tick off as you finish with them.

![The Adventure Guide tracker section](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/tracker.png)

Your current stop and the one after it sit beside your quests.

![The Dungeons tab](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/dungeons.png)

Check the quests and their earlier steps before heading to the entrance.

![A full quest outline with current steps followed by later Questie quests](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/window_full_guide.png)

The full guide shows ten rows per page, with current route actions first and later outline entries after them. This is a generated preview of the guide UI; the dungeon map preview is intentionally omitted because maps depend on the optional Atlas providers.

## Features

- **Dungeons.** Browse dungeon quests, check what needs picking up before you go and plan a journey to their givers. AtlasLoot supplies optional encounter and loot tables, while QuestieDB and the client journal fill confirmed records when available. Without the relevant provider, the affected details show an explicit missing-data state. Atlas and Atlas Classic WoW optionally supply dungeon interiors, legends and entrances; no provider artwork or data is bundled.
- **Full guide.** Open a journey's full guide to page through the current route followed by the area's Questie outline. Ten rows are shown per page; later entries show their level and difficulty and remain outline-only until Questie confirms that they are available.

- **Journeys.** Finish loose ends, follow a zone's story, head somewhere suited to your level or pick up class quests. Each card says why it fits. Dungeon and battleground journeys are opt-in.
- **Choose and go.** Picking a journey starts its route with Shortest Path Forever, or the game's waypoint without it. A setting makes choosing preview only. Stop clears only the route the guide started; a waypoint you set yourself stays.
- **Your order.** Drag steps or use their right-click menu. Moves that put a hand-in before its pickup are greyed out. Towns list their quest givers, ticked as you finish with them.
- **Time to play.** Pick 15, 30 or 60 minutes to shorten the route using rough travel and quest-time estimates.
- **Stories and search.** Chapters show their length only when the data proves it. Search a quest to see which requirements you meet and what is missing.
- **Other things to do.** Hints cover trainers, professions and unspent talents. The PvP tab shows your rank, its next reward and available battlegrounds. Tweaks Forever supplies class spell hints and dungeon entrances.
- **Your say.** Skip a step for this session, hide a journey or rule out a quest. The guide never abandons quests for you. Map pins and quest-giver marks are off by default.

The bundled quest data covers Classic quests. Forever's new quests are only considered once they are in your log, and a missing location stays missing. This is not a complete levelling walkthrough.

## Usage

`/agf` or `/adventureguide` opens the window. Shift-J does too if that key was free at first login. Left-click the addon compartment for the window; right-click for the map tab. Options are in the guide's cog and Settings > AddOns > Adventure Guide.

Translations are welcome on GitHub: see the [Locales folder](https://github.com/cjber/adventure-guide-forever/tree/main/Locales).

For a missing quest, include `/agf audit` output in a bug report. Early days, feedback welcome.

Works alongside [Shortest Path Forever](https://www.curseforge.com/wow/addons/shortest-path-forever) for travel, [Tweaks Forever](https://www.curseforge.com/wow/addons/tweaks-forever) for class spells and dungeon entrances, [SkillUp Forever](https://www.curseforge.com/wow/addons/skillup-forever) for crafting routes and [Legacy Forever](https://www.curseforge.com/wow/addons/legacy-forever) for completion. All optional.

Source code and issues: [github.com/cjber/adventure-guide-forever](https://github.com/cjber/adventure-guide-forever). Licence: GPL-3.0-or-later.
