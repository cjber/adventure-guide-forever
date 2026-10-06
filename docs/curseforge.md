Developed with AI assistance; changes are reviewed and checked with automated tests, linting and type checks and performance budgets.

I wanted a levelling guide that left me room to wander. Adventure Guide Forever suggests journeys from your level and quest log, with a route for the one you pick. It looks like it came with the game.

QuestieDB supplies quests; Questie checks pickup availability. You can hide the tracker when following another guide.

![Choosing a journey and following its route](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/demo.gif)

Choose a journey and follow its route.

![Adventure Guide beside The Barrens map](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/panel.png)

Choose a journey without leaving the world map's quest log.

![Shortest Path Forever's route to the first stop](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/map.png)

Pick one and Shortest Path Forever walks you to each stop in turn.

![The Adventure Guide window](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/window.png)

Follow your journey, browse its upcoming steps and quests, or choose another in Activities.

![Professions in Activities](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/window_professions.png)

SkillUp Forever supplies the recipes to make and reagents still needed.

![Progress](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/window_completion.png)

See completed stories here. Legacy Forever supplies collection and zone completion on the map.

![A journey in your chosen order](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/window_order.png)

Move steps around.

![The Adventure Guide tracker section](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/tracker.png)

Your journey heads the tracker, with action icons for the current stop and up to two upcoming stops.

![Bosses and loot beside a dungeon journey](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/dungeons.png)

Check the quests and their earlier steps before heading to the entrance.

![A full quest outline with current steps followed by later Questie quests](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/window_full_guide.png)

The full guide continues across pages. These images are generated previews of the guide UI.

## Features

- **What to do next.** Journeys explains your next action. Activities offers journeys, professions and PvP. Progress records completed stories.
- **Journeys.** Finish loose ends, follow zone stories or pick up class quests. Dungeon and battleground journeys are opt-in.
- **Dungeons.** Check quests and prerequisites, then visit their givers. Tweaks Forever displays Atlas interior maps on the world map. [AtlasLoot Classic](https://www.curseforge.com/wow/addons/atlaslootclassic) supplies bosses and loot.
- **Full guide.** Browse the route and the area's quest outline. Later entries wait for Questie's availability checks.
- **Choose and go.** Use Shortest Path Forever or the game's waypoint. Stop clears only guidance the addon started.
- **Your route.** Your journey survives travel and reloads. Ready hand-ins come first. Towns group quest givers into checklists.
- **Your order.** Drag steps or use their menu. Moves that break quest order are greyed out.
- **Time to play.** Choose 15, 30 or 60 minutes using rough travel and quest-time estimates.
- **Search and hints.** Check quest requirements, talents and battlegrounds. Class spell reminders are optional and off by default.
- **Your say.** Skip steps or hide journeys. Shift-click search results or map quest givers to add quests. Nothing abandons quests for you. Map marks are off by default.

Forever's new quests are only considered once they are in your log, and a missing location stays missing. This is not a complete levelling walkthrough.

## Usage

`/agf` or `/adventureguide` opens the window. Shift-J does too if that key was free at first login. Left-click the addon compartment for the window; right-click for the map tab. Options are in the guide's cog and Settings > AddOns > Adventure Guide.

Translations are welcome on GitHub: see the [Locales folder](https://github.com/cjber/adventure-guide-forever/tree/main/Locales).

For a missing quest, include `/agf audit` output in a bug report. Early days, feedback welcome.

Works alongside [Shortest Path Forever](https://www.curseforge.com/wow/addons/shortest-path-forever) for travel, [Tweaks Forever](https://www.curseforge.com/wow/addons/tweaks-forever) for class spells and dungeon entrances, [SkillUp Forever](https://www.curseforge.com/wow/addons/skillup-forever) for crafting routes and [Legacy Forever](https://www.curseforge.com/wow/addons/legacy-forever) for completion. All optional.

Source code and issues: [github.com/cjber/adventure-guide-forever](https://github.com/cjber/adventure-guide-forever). Licence: GPL-3.0-or-later.

Choose the highest recommended quest level relative to yours in Route settings. The default, +2, avoids orange and red pickups. Quests already in your log remain visible.
