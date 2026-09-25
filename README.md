<p align="center"><img src="https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/media/icon-400.png" width="96" alt=""></p>

<h1 align="center">Adventure Guide Forever</h1>

<p align="center">
A few places to go next in WoW: Forever, in a guide that looks like it came with the game.<br>
<a href="https://github.com/cjber/adventure-guide-forever/actions/workflows/ci.yml"><img src="https://github.com/cjber/adventure-guide-forever/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
<a href="https://github.com/cjber/adventure-guide-forever/releases/latest"><img src="https://img.shields.io/github/v/release/cjber/adventure-guide-forever" alt="Latest release"></a>
</p>

I wanted a levelling guide that left me room to wander. From your level, finished quests and quest log, Adventure Guide Forever offers a few journeys, each with a reason, and a short route for the one you pick. It uses the quest log's side tab, retail's Journeys art and the game's own objective tracker. Clicking a quest in your log opens Blizzard's quest details.

Shortest Path Forever handles travel when installed. If you follow Questie or another guide, you can hide AGF's tracker in settings; their routes may overlap.

<p align="center"><img src="https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/panel.png" width="640" alt="Adventure Guide beside The Barrens map"></p>

<p align="center">Choose a journey from the world map's quest log. The rows fit the panel; more choices open in the guide's window.</p>

<p align="center"><img src="https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/map.png" width="640" alt="Shortest Path Forever's route to the first stop"></p>

<p align="center">Pick one and Shortest Path Forever walks you to each stop in turn.</p>

<p align="center"><img src="https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/window.png" width="640" alt="The Adventure Guide window"></p>

<p align="center">The same journeys in their own window, with the next three steps beside the suggested one.</p>

## Features

- **Journeys.** Up to six choices: loose ends from your log, a zone's story, nearby zones suited to your level and class quests. Dungeon and battleground journeys are opt-in. Each card gives a reason to go; choose one to see its route.
- **Choose and go.** Picking a journey starts guidance with Shortest Path Forever, or the game's waypoint without it. A setting makes choosing preview only. Stop and the back arrow remove only the guidance AGF owns, leaving a waypoint you moved yourself alone.
- **A route that stays with you.** The chosen journey survives new quests, travel and a reload. Town stops group pickups and hand-ins, with a checklist of quest givers. The tracker shows the current stop and the next one.
- **Your order.** Drag steps or right-click for *Do this next*, *Do this sooner* or *Do this later*. Moves that break quest order are greyed out. *Back to suggested order* restores the plan.
- **Time to play.** Choose 15, 30 or 60 minutes to shorten the route using rough travel and quest-time estimates. Leave it at *No limit* for the full route.
- **Stories and search.** Stories read as chapters without naming later quests. A chapter total appears only when the data proves it. Type three letters in search to see a quest's requirements and which ones you meet.
- **Other things to do.** Hints cover class trainers, profession training and unspent talents. The PvP tab shows your rank, its next reward and battlegrounds open at your level, with the nearest battlemaster.
- **Professions and completion.** SkillUp Forever fills the Professions tab with recipes, next steps and reagents. Legacy Forever fills Completion with zone progress and nearby objectives. Tweaks Forever supplies class spell hints and dungeon entrance locations.
- **Your say.** Skip a step until your next reload, hide a journey or rule out a quest on this character. *Skipped* brings them back. The guide can suggest quests to drop from a full log, but never abandons anything for you. Map pins and quest-giver marks are off by default.

<p align="center"><img src="https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/window_order.png" width="640" alt="A journey in your chosen order"></p>

<p align="center">The card says Your order, and each town lists the quest givers still to visit.</p>

<p align="center"><img src="https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/tracker.png" width="400" alt="The Adventure Guide tracker section"></p>

<p align="center">Your next stop sits above your quests, with travel time when Shortest Path Forever has an estimate.</p>

## Install

Download the zip from [Releases](https://github.com/cjber/adventure-guide-forever/releases) and extract it into `_classic_beta_/Interface/AddOns/`, so you end up with `AddOns/AdventureGuideForever/AdventureGuideForever.toc`. After an update, `/reload`.

## Usage

| Command | What it does |
|---|---|
| `/agf`, `/adventureguide` | Open the Adventure Guide window |
| `/agf audit` | Compare the quest data with the game and report its source |
| `/agf dump` | Save the drawn layout for a bug report; `/reload`, then attach `SavedVariables/AdventureGuideForever.lua` |

Shift-J opens the window if the key was free at first login; change it under Key Bindings. Left-click the addon compartment for the window, or right-click for the map tab. The guide's cog holds journey filters, map marks and skipped suggestions. Other options live under Settings > AddOns > Adventure Guide, including starting routes on selection and tracking their quests.

Translations are welcome as a pull request, or pasted into an issue, on GitHub: see the [Locales folder](https://github.com/cjber/adventure-guide-forever/tree/main/Locales).

## Where the quests come from

Bundled data comes from CMaNGOS Classic and the Forever client's tables. An installed, compatible QuestieDB supplies quest requirements and givers instead; bundled locations still limit what the guide can offer. Finished quests come from the game.

Forever's new quests are only considered once they are in your log. The guide never recommends a quest whose eligibility it cannot establish or points at a location it does not have. This is not a complete levelling walkthrough.

## Works alongside

All optional: [Shortest Path Forever](https://github.com/cjber/shortest-path-forever) for travel, [Tweaks Forever](https://github.com/cjber/tweaks-forever) for class spells and dungeon entrances, [SkillUp Forever](https://github.com/cjber/skillup-forever) for crafting routes, [Legacy Forever](https://github.com/cjber/legacy-forever) for completion, and [QuestieDB](https://github.com/Questie/QuestieDB) for quest data. QuestieDB works alone or with Questie. AGF's tracker has its own switch when you prefer another guide.

## Development

Run the full gate in [AGENTS.md](AGENTS.md#commands). It needs LuaJIT, luacheck, StyLua, LuaLS 3.19.1, Python and ruff; type checking fetches pinned WoW API annotations on first use.

Screenshots use Pillow and the [wow-mock-screenshots library](https://github.com/cjber/skills/tree/main/wow-mock-screenshots). Set `WOWMOCK` to the directory containing `wowmock.py`, then run `python3 tools/screenshots.py` twice to check reproducibility.

Contributing and security policies are inherited from [cjber/.github](https://github.com/cjber/.github). Read [AGENTS.md](AGENTS.md) before changing code.

## Licence

GPL-3.0-or-later. Quest and trainer data derive from [CMaNGOS classic-db](https://github.com/cmangos/classic-db) (GPL-3.0); client tables come via [wago.tools](https://wago.tools), and zone level ranges from [Warcraft Wiki](https://warcraft.wiki.gg/wiki/Zones_by_level_(original)). No Questie or Wowhead data is bundled.

Made by Cillian Berragan · [cillian.dev](https://cillian.dev) · [GitHub](https://github.com/cjber) · [Twitter](https://twitter.com/cjberragan)
