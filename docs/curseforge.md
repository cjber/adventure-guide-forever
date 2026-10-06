Developed with AI assistance; changes are reviewed and checked with automated tests, linting and type checks and performance budgets.

I wanted a levelling guide that left me room to wander. Adventure Guide Forever suggests journeys from your level and quest log, with a route for the one you pick. It looks like it came with the game.

QuestieDB supplies quests; Questie checks pickup availability. You can hide the tracker when following another guide.

![Choosing a journey and following its route](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/demo.gif)

Choose a journey and follow its route.

![Adventure Guide beside The Barrens map](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/panel.png)

Choose a journey without leaving the world map's quest log.

![Shortest Path Forever's route to the first stop](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/map.png)

Pick one and Shortest Path Forever walks you to each stop in turn.

![The Adventure Guide tracker section](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/tracker.png)

Your journey heads the tracker, with action icons for the current stop and up to two upcoming stops.

These images are generated previews of the guide UI.

## Features

- **What to do next.** The map guide offers two Continue cards and one per other section. Expand a header to see more. Quests in your log is the default suggestion.
- **Journeys.** Finish loose ends, follow zone stories or pick up class quests. Dungeon and battleground journeys are opt-in.
- **Dungeons.** Check quests and prerequisites, then visit their givers. Tweaks Forever displays Atlas interior maps on the world map. [AtlasLoot Classic](https://www.curseforge.com/wow/addons/atlaslootclassic) supplies bosses and loot.
- **Full guide.** Browse the route and the area's quest outline. Later entries wait for Questie's availability checks.
- **Choose and go.** Use Shortest Path Forever or the game's waypoint. Stop clears only guidance the addon started.
- **Your route.** Your journey survives travel and reloads. Ready hand-ins come first. Towns group quest givers into checklists.
- **Your order.** Drag steps or use their menu. Moves that break quest order are greyed out.
- **Search and hints.** Check quest requirements, talents and battlegrounds. Class spell reminders are optional and off by default.
- **Your say.** Skip steps or hide journeys. Shift-click search results or map quest givers to add quests. Nothing abandons quests for you. Map marks are off by default.

Forever's new quests are only considered once they are in your log, and a missing location stays missing. This is not a complete levelling walkthrough.

## Usage

`/agf`, `/adventureguide` or the addon compartment opens the guide on the world map. Options are in the guide's cog and Settings > AddOns > Adventure Guide.

Translations are welcome on GitHub: see the [Locales folder](https://github.com/cjber/adventure-guide-forever/tree/main/Locales).

For a missing quest, include `/agf audit` output in a bug report. Early days, feedback welcome.

Works alongside [Shortest Path Forever](https://www.curseforge.com/wow/addons/shortest-path-forever) for travel, [Tweaks Forever](https://www.curseforge.com/wow/addons/tweaks-forever) for class spells and dungeon entrances, [SkillUp Forever](https://www.curseforge.com/wow/addons/skillup-forever) for crafting routes and [Legacy Forever](https://www.curseforge.com/wow/addons/legacy-forever) for completion. All optional.

Source code and issues: [github.com/cjber/adventure-guide-forever](https://github.com/cjber/adventure-guide-forever). Licence: GPL-3.0-or-later.

Choose the highest recommended quest level relative to yours in Route settings. The default, +2, avoids orange and red pickups. Quests already in your log remain visible.
