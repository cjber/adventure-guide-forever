<p align="center"><img src="https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/media/icon-400.png" width="96" alt=""></p>

<h1 align="center">Adventure Guide Forever</h1>

<p align="center">
Where to go next, for your level, inside WoW: Forever's world map.<br>
<a href="https://github.com/cjber/adventure-guide-forever/actions/workflows/ci.yml"><img src="https://github.com/cjber/adventure-guide-forever/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
<a href="https://github.com/cjber/adventure-guide-forever/releases/latest"><img src="https://img.shields.io/github/v/release/cjber/adventure-guide-forever" alt="Latest release"></a>
</p>

Levelling guides tell you exactly what to do, in order, as fast as possible. This addon is looser. From your level, the quests you have finished and the ones in your log, it suggests the next few things worth doing and where they are. You steer it: pick the zone, decide whether dungeon quests count, and pin or skip steps.

## Features

- **Adventure Guide tab** on the world map's quest log, beside Quests and Map Legend. It shows your level and rested XP, three zones that suit your level under *Where next?*, and a suggested route of up to nine steps you can scroll and search. Each step says why it is there: `2 quests · continues chain`.
- **Steps** hand in finished quests, pick up clusters of quests you can take now, and finish objectives already in your log. Dungeon and elite quests are included only when you turn on *Dungeons*, and are marked optional.
- **Pin and skip**: a pinned step stays at the top of the route; a skipped one stays hidden until you `/reload`.
- **Map pins** number the route on the world map.
- **Quest givers** show the game's "!" on the world map over everyone with a quest you can take now.
- **Objective tracker section** above your quests showing the current step and the next one. Right-click it to skip a step or change the route.
- **Go** hands the route from that step onward to Shortest Path Forever as one numbered journey, flight paths and boats included; it moves to the next stop as you arrive. Without it, Go sets the game's own waypoint to the step.

## Install

Install it from CurseForge or Wago Addons, or download the zip from [Releases](https://github.com/cjber/adventure-guide-forever/releases). To install the zip by hand, extract it into `_classic_beta_/Interface/AddOns/` so you end up with `AddOns/AdventureGuideForever/AdventureGuideForever.toc`.

## Usage

- `/agf` or `/adventureguide` opens the guide on the world map.
- `/agf audit` compares the bundled quest data with the game.
- `/agf dump` saves the guide's layout for a bug report; `/reload`, then attach `SavedVariables/AdventureGuideForever.lua`.
- Options are under *Settings > AddOns > Adventure Guide Forever*.

## Where the quests come from

Quest givers, levels and prerequisites come from a pinned CMaNGOS Classic database. Quest IDs are checked against the Forever client's own data. Which quests you have finished always comes from the game. A quest the data cannot place, or whose requirements it cannot check, is never suggested. Quests in your log are always used, including Forever's own new ones.

## Works alongside

- **Shortest Path Forever** plans the travel between steps when it is installed.
- **Questie**, **RestedXP** and other guides: the guide still works with them loaded, but the routes may overlap. Use the settings to hide the tracker section if you follow another guide.

## Development

```sh
python3 tools/gen_quests.py        # regenerate Data/Quests.lua
luacheck . && stylua --check .
for s in tests/*_spec.lua; do luajit "$s" || exit 1; done
```

See `AGENTS.md` for the full gate.

## Licence

GPL-3.0-or-later. Quest data derives from [CMaNGOS classic-db](https://github.com/cmangos/classic-db) (GPL-2.0-or-later).
