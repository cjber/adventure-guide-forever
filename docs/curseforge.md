Adventure Guide Forever is a levelling guide for WoW: Forever. Zone story journeys read as chapters, with your progress through each chapter kept per character, and Quests in your log finishes what you already carry so the log empties instead of growing. Then a short route joins the rest of your level's quests, and Shortest Path Forever walks you to each stop; without it, the game's waypoint does.

QuestieDB supplies quests; Questie checks pickup availability. With RestedXP installed, a one-time prompt lets you keep its display or follow its guides here.

Free, with nothing locked behind it. If it saves you time, you can [buy me a coffee on Ko-fi](https://ko-fi.com/cjber).

![The Barrens story chosen: chapter 1 of 8, its numbered stops in the panel and on the map, with the route drawn from the first](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/chosen.png)

A zone story journey, read as chapters: every stop numbered and the route drawn from the first.

![A journey's quest stops numbered on The Barrens map, with Shortest Path Forever's route to the first](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/map.png)

Each number is a stop on the route: a pickup, an objective or a hand-in.

![Choosing a journey and following its route](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/demo.gif)

Choose a journey and follow its route.

![Adventure Guide beside The Barrens map](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/panel.png)

Choose a journey from the world map's quest log.

![The Adventure Guide tracker section](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/tracker.png)

Your journey heads the tracker: the story chapter you are on, then your current and next two stops.

![RestedXP instructions in the Adventure tab](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/restedxp.png)

These images are generated previews of the guide UI.

## Features

- **Zone stories.** Each zone's quest chains read as chapters, such as *Chapter 3 of 7*, on the journey card, the map guide and the tracker, without naming later quests. Finishing a story shows a short popup, once per character. Finishing a zone moves on to the next zone for your level, and starts walking there when it was guiding you.

- **RestedXP guides.** Read RestedXP's instructions and objectives in the Adventure tab and tracker. Choose a guide from the Continue cards and move between its steps. While you follow one, the tracker lists only the quests its steps name, and your own tracked quests come back when you stop. While it steers a RestedXP guide, Adventure Guide shows its own item and target buttons for the current step. Turn off *Use RestedXP guides* to return to Adventure Guide recommendations.


- **Works alongside Polestar.** While Polestar guides, the route and map marks pause; click the tracker line to take over, or turn this off in Route settings.

- **Journeys.** Find nearby zones for your level or pick up class quests. Dungeon and battleground journeys are opt-in.
- **Dungeons.** Check quests and prerequisites, then visit their givers. [AtlasLoot Classic Forever](https://www.curseforge.com/wow/addons/atlasloot-forever) supplies bosses and loot.
- **Full guide.** Browse the route and the area's quest outline.
- **Choose and go.** Use Shortest Path Forever or the game's waypoint. Stop clears only guidance the addon started.
- **A button on the minimap.** Drag it around the rim to choose its place, press Alt-G or use `/agf`, and hide it in Settings if you prefer the map tab or the addon compartment.
- **Your route.** Your journey survives travel and reloads. Ready hand-ins come first. Towns group quest givers into checklists. A quest missing from its giver's list drops off, with a line in chat.
- **Where to do objectives.** A place with mobs 3 or more levels above you gives way to a lower one on its map. *Next spot* picks another camp, even where you stand.
- **Quest givers stand out.** While a step talks to an NPC, a pair of small arrows bounces either side of their nameplate and a target button selects them and, when you play solo, stars them if they carry no mark of their own. Friendly nameplates must be on; the tracker says so once.
- **Quest difficulty.** Set the highest quest level relative to yours in Route settings. The default, +2, avoids orange and red pickups.
- **Your order.** Drag steps or use their menu. Moves that break quest order are greyed out.
- **Search and hints.** Search puts the best match first, with each quest's requirements and, for a locked one, the first quest in its chain you can take. Hints cover talents and battlegrounds.
- **Your say.** Skip steps or hide journeys. Shift-click search results or map quest givers to add quests. Nothing abandons quests for you. Map marks are off by default.

Forever's new quests are only considered once they are in your log, and a missing location stays missing. This is not a complete levelling walkthrough.

![Dungeon boss drops](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/loot.png)

Right-click a dungeon card for AtlasLoot bosses and drops, with native item tooltips.

## Usage

`/agf`, `/adventureguide`, the minimap button or the addon compartment opens the guide on the world map. Options are in the guide's cog and Settings > AddOns > Adventure Guide, whose Forever addons page lists all five Forever addons.
`/agf leaderboard` ranks your quest turn-ins against the totals your guild and group members running the addon report; their numbers are player-reported, not verified. Sharing is on by default and `/agf share off`, or the checkbox under Settings > AddOns > Adventure Guide, stops it.

Translated into German, French, Spanish, Brazilian Portuguese, Russian, Korean and Chinese (machine translated; corrections welcome through the [translation form](https://github.com/cjber/adventure-guide-forever/issues/new?template=translation.yml)).

For a bug report, paste what `/agf report` shows. For a wrong stop, paste `/agf where`. For a missing quest, add `/agf audit`. To report a bug or request a feature, `/agf issue` opens a ready-made GitHub issue link.

<!-- forever-family:start -->

## The Forever addons

Each one works on its own, and they work together when you install more than one.

| Addon | What it does | Issues |
|---|---|---|
| [Shortest Path Forever](https://www.curseforge.com/wow/addons/shortest-path-forever) | Plans journeys on foot, by air, by sea and through portals, with directions in the tracker. | [Issues](https://github.com/cjber/shortest-path-forever/issues) |
| [Adventure Guide Forever](https://www.curseforge.com/wow/addons/adventure-guide-forever) | Suggests quests for your level and routes you from one to the next. | [Issues](https://github.com/cjber/adventure-guide-forever/issues) |
| [SkillUp Forever](https://www.curseforge.com/wow/addons/skillup-forever) | Shows skill-up chances, recipe costs and levelling routes in the Professions window. | [Issues](https://github.com/cjber/skillup-forever/issues) |
| [Legacy Forever](https://www.curseforge.com/wow/addons/legacy-forever) | Shows your unfinished Legacy challenges on the world map and tracks the ones you choose. | [Issues](https://github.com/cjber/legacy-forever/issues) |
| [Tweaks Forever](https://www.curseforge.com/wow/addons/tweaks-forever) | Adds quest automation, rare alerts and merchant options to the game's settings. | [Issues](https://github.com/cjber/tweaks-forever/issues) |

Bug reports, feature requests and pull requests are welcome on each addon's GitHub. Everyone whose report or idea ships is thanked by name in the addon's credits and changelog.

<!-- forever-family:end -->

Installed together, Shortest Path Forever plans the way to every stop. SkillUp Forever fills the Professions tab, and Legacy Forever adds your zone completion. Tweaks Forever supplies class trainer locations and dungeon entrances, and lets you move the guide window.

The guide's tracker section shares one column with the other Forever sections, above your quests. Empty, it leaves your quests where Edit Mode or your UI addon put them.

Source code and issues: [github.com/cjber/adventure-guide-forever](https://github.com/cjber/adventure-guide-forever). Licence: GPL-3.0-or-later.

Built with AI assistance.
