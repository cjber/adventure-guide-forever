<p align="center"><img src="https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/media/icon-400.png" width="96" alt=""></p>

<h1 align="center">Adventure Guide Forever</h1>

<p align="center">
Picks quests for your level in WoW: Forever and, with Shortest Path Forever, walks you to each one.<br>
<a href="https://github.com/cjber/adventure-guide-forever/actions/workflows/ci.yml"><img src="https://github.com/cjber/adventure-guide-forever/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
<a href="https://github.com/cjber/adventure-guide-forever/releases/latest"><img src="https://img.shields.io/github/v/release/cjber/adventure-guide-forever" alt="Latest release"></a>
<a href="https://ko-fi.com/cjber59408"><img src="https://img.shields.io/badge/Ko--fi-tip-ff5e5b?logo=ko-fi&logoColor=white" alt="Ko-fi"></a>
</p>

Adventure Guide Forever suggests quests for your level and quest log, in a short route. Shortest Path Forever walks you to each stop; without it, the game's waypoint does.

Questie draws the quest markers; the guide adds route rings. With RestedXP installed, a one-time prompt lets you keep its display or follow its guides in Adventure Guide.

<p align="center"><img src="https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/map.png" width="640" alt="A journey's quest stops numbered on The Barrens map, with Shortest Path Forever's route to the first"></p>

<p align="center">Each number is a stop on the route: a pickup, an objective or a hand-in.</p>

<p align="center"><img src="https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/demo.gif" width="640" alt="Choosing a journey and following its route"></p>

<p align="center">Choose a journey and follow its route, checking off its quests as you go.</p>

<p align="center"><img src="https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/panel.png" width="640" alt="Adventure Guide beside The Barrens map"></p>

<p align="center">Choose a journey from the world map's quest log. Expand a header for more choices.</p>

<p align="center"><img src="https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/story_complete.png" width="400" alt="Story completion popup"></p>

<p align="center">Finished stories are recorded once for this character.</p>

<p align="center"><img src="https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/restedxp.png" width="640" alt="RestedXP instructions in the Adventure tab"></p>

<p align="center">Follow a RestedXP guide in the Adventure tab, with its engine handling progress.</p>

## Features

- **RestedXP guides.** Read the active guide in the journey cards, step rows and tracker, with about ten steps on the map. Choose a guide from the Continue cards, move between steps or skip one. RestedXP handles completion; Shortest Path Forever handles travel. Turn off *Use RestedXP guides* to return to Adventure Guide's suggestions.

- **Map guide.** The active RestedXP guide comes first while *Use RestedXP guides* is on; otherwise Quests in your log.

- **Quest difficulty.** Choose the highest recommended quest level relative to yours in Route settings. The default, +2, avoids orange and red pickups. Accepted quests remain visible.

- **Dungeon journeys.** Follow quest pickups, preparation chains and hand-ins with Shortest Path Forever. Right-click a dungeon card for AtlasLoot bosses, drops and native item tooltips. Tweaks Forever handles automatic dungeon maps.
- **Journeys.** Finish loose ends, follow a zone's story, find nearby zones suited to your level or take class quests. Journey choices explain why each fits. Dungeon and battleground journeys are opt-in.
- **Full guide.** Expand the map guide for the whole route, then the area's Questie outline. Later entries stay as outline until Questie confirms them.
- **Choose and go.** Pick a journey on the map to start guidance with Shortest Path Forever, or the game's waypoint. A setting makes choosing preview only. Stop clears only guidance the addon started.
- **A route that stays with you.** Your choice survives new quests, travel and reloads. Ready hand-ins and nearby pickups come first. Town stops group quest givers into a checklist.
- **Playing in a party.** Quests someone in your party also has count as a little nearer, so you tend to do them together, and a pickup a party member already has says so. Party members with the guide tell each other which quests they have through hidden addon messages, at most one every 15 seconds and never in combat. Turn off *Favour quests your party has* in Route settings to stop it.
- **Your order.** Drag steps or right-click to move them earlier or later. Moves that break quest order are greyed out. *Back to suggested order* restores the plan.
- **Where to do an objective.** The guide skips a place whose mobs are 3 or more levels above you for a lower one on the same map. *Next spot* in the step's menu moves the arrow to the nearest other camp, even where you stand.
- **Givers that don't offer a quest.** If a giver doesn't offer the quest the guide sent you for, the guide says so once in chat and drops it, trying again after a level-up or a hand-in that could open it up.
- **Story milestones.** Finishing a proven quest chain shows a short popup, once per character.
- **Stories and search.** Stories read as chapters without naming later quests. Search puts the best match first and shows which of a quest's requirements you meet. For a locked quest it names the earliest quest in its chain you can take, and a shift-click adds that one.
- **Other things to do.** Hints cover professions, unspent talents, hearths and unexplored areas. Class spell reminders and trainer visits are off by default (Route settings). PvP shows your rank, its next reward and the nearest battlemaster.
- **Your say.** Skip a step until your next reload, hide a journey or rule out a quest on this character. Shift-click a search result or map quest giver to add quests. *Skipped* restores hidden suggestions. The guide never abandons quests for you. Map marks are off by default.

<p align="center"><img src="https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/tracker.png" width="400" alt="The Adventure Guide tracker section"></p>

<p align="center">Your next stop sits beside your quests, with travel time when Shortest Path Forever has an estimate.</p>

<p align="center"><img src="https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/loot.png" width="300" alt="Dungeon boss drops in the map card menu"></p>

<p align="center">Right-click a dungeon card for its bosses and loot. Hover a drop for the game's item tooltip.</p>

## Install

Install from [CurseForge](https://www.curseforge.com/wow/addons/adventure-guide-forever) or [Wago Addons](https://addons.wago.io/addons/adventure-guide-forever), or download the zip from [Releases](https://github.com/cjber/adventure-guide-forever/releases) and extract it into `_classic_beta_/Interface/AddOns/`, so you end up with `AddOns/AdventureGuideForever/AdventureGuideForever.toc`. After an update, `/reload`.

## Usage

| Command | What it does |
|---|---|
| `/agf`, `/adventureguide` | Open the guide on the world map |
| `/agf report` | Show a report to copy into a bug report: versions, your current stop and why, recent errors |
| `/agf issue` | Open a ready-made GitHub issue link to report a bug or request a feature |
| `/agf where` | Show the stop the guide is on, for a wrong-stop report |
| `/agf travel` | Print guidance state for a travel report |
| `/agf tracker` | Print the tracker anchors for an overlap report |
| `/agf audit` | Compare the quest data with the game and report its source |
| `/agf stats` | Show local quest turn-ins and the number of addon users reporting activity |
| `/agf dump` | Save the drawn layout; `/reload`, then attach `SavedVariables/AdventureGuideForever.lua` |

Open the guide from its world-map tab or the addon compartment. The guide's cog holds journey filters, map marks and skipped suggestions. Other options live under Settings > AddOns > Adventure Guide, including tracking route quests and detaching the shared Forever tracker. Its Forever addons page lists all five Forever addons, with a box to turn off suggestions.

## Where the quests come from

The installed Forever edition of QuestieDB supplies quests and locations. Questie checks pickup availability; the game supplies finished quests and objective progress. Missing QuestieDB is shown explicitly.

Forever's new quests are only considered once they are in your log. The guide recommends only quests whose eligibility it can establish and never invents a location. This is not a complete levelling walkthrough.

## Works alongside

QuestieDB and Questie are needed for pickup recommendations. [AtlasLoot Classic Forever](https://www.curseforge.com/wow/addons/atlasloot-forever) is an optional companion for bosses and loot. While Polestar has a guide running, the guide starts no route and draws no map marks until you click its tracker line; *Step aside while Polestar is guiding* turns that off. The guide's tracker section shares one column with the other Forever sections, above your quests, and has its own switch when you prefer another guide. An empty column leaves your quests where Edit Mode or your UI addon put them.

<!-- forever-family:start -->

## The Forever addons

Each one works on its own, and they work together when you install more than one.

| Addon | What it does |
|---|---|
| [Shortest Path Forever](https://www.curseforge.com/wow/addons/shortest-path-forever) | Plans journeys on foot, by air, by sea and through portals, with directions in the tracker. |
| [Adventure Guide Forever](https://www.curseforge.com/wow/addons/adventure-guide-forever) | Suggests quests for your level and routes you from one to the next. |
| [SkillUp Forever](https://www.curseforge.com/wow/addons/skillup-forever) | Shows skill-up chances, recipe costs and levelling routes in the Professions window. |
| [Legacy Forever](https://www.curseforge.com/wow/addons/legacy-forever) | Shows your unfinished Legacy challenges on the world map and tracks the ones you choose. |
| [Tweaks Forever](https://www.curseforge.com/wow/addons/tweaks-forever) | Adds quest automation, rare alerts and merchant options to the game's settings. |

<!-- forever-family:end -->

Installed together, Shortest Path Forever plans the way to every stop, SkillUp Forever fills the Professions tab, and Legacy Forever adds your zone completion. Tweaks Forever supplies class trainer locations and dungeon entrances, and its Windows option moves the guide window.

## Ways to help

No code needed:

- **Wrong stop:** paste `/agf where` into a [Wrong stop issue](https://github.com/cjber/adventure-guide-forever/issues/new?template=wrong_stop.yml).
- **An error:** paste `/agf report` into a [bug report](https://github.com/cjber/adventure-guide-forever/issues/new?template=bug_report.yml).
- **A translation:** it's machine translated into German, French, Spanish, Brazilian Portuguese, Russian, Korean and Chinese; send corrections through the [translation form](https://github.com/cjber/adventure-guide-forever/issues/new?template=translation.yml).

## Development

Run the full gate in [AGENTS.md](AGENTS.md#commands). `python3 tools/doctor.py` lists the tools it needs, with a fix for each problem.

Screenshots use Pillow and the [wow-mock-screenshots library](https://github.com/cjber/skills/tree/main/wow-mock-screenshots): set `WOWMOCK` to its directory and run `python3 tools/screenshots.py` twice; both runs must match.

[tests/README.md](tests/README.md) describes the test layers and the harness. Contributing and security policies are inherited from [cjber/.github](https://github.com/cjber/.github). Read [AGENTS.md](AGENTS.md) before changing code.

## Support

The addon is free and stays GPL-3.0. If it saves you time, you can [buy me a coffee on Ko-fi](https://ko-fi.com/cjber59408); nothing is locked behind it and there is no paid version.

## Credits

Data comes from [wago.tools](https://wago.tools), [CMaNGOS classic-db](https://github.com/cmangos/classic-db) (GPL-3.0) and [Warcraft Wiki](https://warcraft.wiki.gg/wiki/Zones_by_level_(original)). Some features were inspired by [Polestar](https://github.com/fitzforge/polestar) by Fitz; no code was copied. Fitz is welcome to use our code. Thanks to rhednak, deathmvp1, berserkerlxl and everyone in [THIRD_PARTY.md](THIRD_PARTY.md).

## Licence

GPL-3.0-or-later; [THIRD_PARTY.md](THIRD_PARTY.md) lists inputs. No Questie or Wowhead data is bundled.

Made by Cillian Berragan · [cillian.dev](https://cillian.dev) · [GitHub](https://github.com/cjber) · [Twitter](https://twitter.com/cjberragan)

Built with AI assistance.
