<p align="center"><img src="https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/media/icon-400.png" width="96" alt=""></p>

<h1 align="center">Adventure Guide Forever</h1>

<p align="center">
A few places to go next in WoW: Forever, in a guide that looks like it came with the game.<br>
<a href="https://github.com/cjber/adventure-guide-forever/actions/workflows/ci.yml"><img src="https://github.com/cjber/adventure-guide-forever/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
<a href="https://github.com/cjber/adventure-guide-forever/releases/latest"><img src="https://img.shields.io/github/v/release/cjber/adventure-guide-forever" alt="Latest release"></a>
</p>

I wanted a levelling guide that left me room to wander. From your level, finished quests and quest log, Adventure Guide Forever offers a few journeys, each with a reason, and a short route for the one you pick. It uses the quest log's side tab, retail's Journeys art and the game's own objective tracker. Clicking a quest in your log opens Blizzard's quest details.

Shortest Path Forever handles travel when installed. QuestieDB supplies the full quest catalogue; Questie checks which pickups are currently available. Questie owns background quest markers; the guide adds route rings. If you'd rather follow another guide's route, you can hide the guide's tracker in settings.

<p align="center"><img src="https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/demo.gif" width="640" alt="Choosing a journey and following its route"></p>

<p align="center">Choose a journey, see its steps on the map and follow the route, check off its quests as you go.</p>

<p align="center"><img src="https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/panel.png" width="640" alt="Adventure Guide beside The Barrens map"></p>

<p align="center">Choose a journey from the world map's quest log. Continue shows two cards; other sections show one. Expand a header for more choices.</p>

<p align="center"><img src="https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/map.png" width="640" alt="Shortest Path Forever's route to the first stop"></p>

<p align="center">Pick one and Shortest Path Forever walks you to each stop in turn.</p>

<p align="center"><img src="https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/story_complete.png" width="400" alt="Story completion popup"></p>

## Features

- **Map guide.** Continue shows two journeys; other sections show one each. Expand a section for more choices. Quests in your log is the default suggestion.

- **Quest difficulty.** Choose the highest recommended quest level relative to yours in Route settings. The default, +2, avoids orange and red pickups. Accepted quests remain visible.

- **Dungeon journeys.** Follow quest pickups, preparation chains and hand-ins with Shortest Path Forever. Preparation steps include prerequisites available now. Tweaks Forever handles automatic dungeon maps.
- **Journeys.** Finish loose ends, follow a zone's story, find nearby zones suited to your level or take class quests. Journey choices explain why each fits. Dungeon and battleground journeys are opt-in.
- **Full guide.** Expand the map guide to see the current route followed by the area's Questie outline. Later entries stay outline-only until Questie confirms they are available.
- **Choose and go.** Pick a journey on the map to start guidance with Shortest Path Forever, or the game's waypoint without it. A setting makes choosing preview only. Stop clears only guidance the addon started.
- **A route that stays with you.** Your choice survives new quests, travel and a reload. Ready hand-ins and nearby pickups come first. Town stops group quest givers into a checklist. The tracker uses your journey as its heading and shows action icons for the current stop and up to two upcoming stops.
- **Your order.** Drag steps or right-click to move them earlier or later. Moves that break quest order are greyed out. *Back to suggested order* restores the plan.
- **Story milestones.** Completing a proven quest chain earns a brief story-complete popup, recorded once for that character.
- **Stories and search.** Stories read as chapters without naming later quests. Totals appear only when the data proves them. Search shows a quest's requirements and which ones you meet.
- **Other things to do.** Hints cover professions, unspent talents, hearths and unexplored areas. Class spell reminders and automatic trainer visits are off by default; enable them under Settings > AddOns > Adventure Guide Forever > Route. PvP shows your rank, its next reward and available battlegrounds, with the nearest battlemaster.
- **Your say.** Skip a step until your next reload, hide a journey or rule out a quest on this character. Shift-click a search result or map quest giver to add quests. *Skipped* restores hidden suggestions. The guide never abandons quests for you. Map marks are off by default.

<p align="center"><img src="https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/tracker.png" width="400" alt="The Adventure Guide tracker section"></p>

<p align="center">Your next stop sits beside your quests, with travel time when Shortest Path Forever has an estimate.</p>

## Install

Install from [CurseForge](https://www.curseforge.com/wow/addons/adventure-guide-forever) or [Wago Addons](https://addons.wago.io/addons/adventure-guide-forever), or download the zip from [Releases](https://github.com/cjber/adventure-guide-forever/releases) and extract it into `_classic_beta_/Interface/AddOns/`, so you end up with `AddOns/AdventureGuideForever/AdventureGuideForever.toc`. After an update, `/reload`.

## Usage

| Command | What it does |
|---|---|
| `/agf`, `/adventureguide` | Open the guide on the world map |
| `/agf travel` | Print guidance state for a travel report |
| `/agf tracker` | Print the tracker anchors for an overlap report |
| `/agf audit` | Compare the quest data with the game and report its source |
| `/agf dump` | Save the drawn layout for a bug report; `/reload`, then attach `SavedVariables/AdventureGuideForever.lua` |

Open the guide from its world-map tab, the addon compartment or `/agf`. The guide's cog holds journey filters, map marks and skipped suggestions. Other options live under Settings > AddOns > Adventure Guide, including starting routes on selection, tracking their quests and detaching the shared Forever tracker so you can drag it elsewhere.

Translations are welcome as a pull request, or pasted into an issue, on GitHub: see the [Locales folder](https://github.com/cjber/adventure-guide-forever/tree/main/Locales).

## Where the quests come from

The installed Forever edition of QuestieDB supplies quests and locations. Questie checks pickup availability; the game supplies finished quests and objective progress. The catalogue is kept between logins. Missing QuestieDB is shown explicitly.

Forever's new quests are only considered once they are in your log. The guide recommends only quests whose eligibility it can establish and never invents a location. This is not a complete levelling walkthrough.

## Works alongside

QuestieDB and Questie are needed for pickup recommendations. Optional companions are [AtlasLoot Classic](https://www.curseforge.com/wow/addons/atlaslootclassic) for bosses and loot, [Shortest Path Forever](https://www.curseforge.com/wow/addons/shortest-path-forever) for travel, [Tweaks Forever](https://www.curseforge.com/wow/addons/tweaks-forever) for class spells and dungeon entrances, [SkillUp Forever](https://www.curseforge.com/wow/addons/skillup-forever) for crafting and [Legacy Forever](https://www.curseforge.com/wow/addons/legacy-forever) for completion. The guide's tracker has its own switch when you prefer another guide.

## Development

Developed with AI assistance; changes are reviewed and checked with automated tests, linting and type checks and performance budgets.

Run the full gate in [AGENTS.md](AGENTS.md#commands). It needs LuaJIT, luacheck, StyLua, LuaLS 3.19.1, Python and ruff; type checking fetches pinned WoW API annotations on first use.

Screenshots use Pillow and the [wow-mock-screenshots library](https://github.com/cjber/skills/tree/main/wow-mock-screenshots). Set `WOWMOCK` to the directory containing `wowmock.py`, then run `python3 tools/screenshots.py` twice to check reproducibility.

Contributing and security policies are inherited from [cjber/.github](https://github.com/cjber/.github). Read [AGENTS.md](AGENTS.md) before changing code.

## Licence

GPL-3.0-or-later. What trainers teach, dungeon entrance requirements and boat routes derive from [CMaNGOS classic-db](https://github.com/cmangos/classic-db) (GPL-3.0); client tables come via [wago.tools](https://wago.tools), and zone level ranges from [Warcraft Wiki](https://warcraft.wiki.gg/wiki/Zones_by_level_(original)). No Questie or Wowhead data is bundled.

Made by Cillian Berragan · [cillian.dev](https://cillian.dev) · [GitHub](https://github.com/cjber) · [Twitter](https://twitter.com/cjberragan)
