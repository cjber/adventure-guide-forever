<p align="center"><img src="https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/media/icon-400.png" width="96" alt=""></p>

<h1 align="center">Adventure Guide Forever</h1>

<p align="center">
Where to go next, for your level, inside WoW: Forever's world map.<br>
<a href="https://github.com/cjber/adventure-guide-forever/actions/workflows/ci.yml"><img src="https://github.com/cjber/adventure-guide-forever/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
<a href="https://github.com/cjber/adventure-guide-forever/releases/latest"><img src="https://img.shields.io/github/v/release/cjber/adventure-guide-forever" alt="Latest release"></a>
</p>

Levelling guides tell you exactly what to do, in order. I wanted something looser. From your level, the quests you have finished and the ones in your log, this addon offers a few journeys to choose from, each with a reason, and a short route for the one you pick.

It looks like it came with the game: a tab in the quest log beside Quests, cards drawn with retail's Journeys art, the game's own map pins and objective tracker, and Blizzard's quest details when you click a quest. With the tab closed it draws nothing on your map.

<p align="center"><img src="https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/panel.png" width="640" alt="The Barrens on the world map with the Adventure Guide tab open: the chosen card for the quests you carry with its two steps listed and ringed on the map, and the zone story and next zone folded to one-line rows above it"></p>

## Features

- **Journeys**: up to three cards on the Adventure Guide tab. *Finish what you carry* counts what is ready to hand in and in progress; *Westfall story* follows the zone's quest chain; *Head to Darkshore* ("For level 14") suggests the next zone once it has at least five quests near your level. Pick one and it shows its steps, up to nine.
- **Stories as chapters**: a chain reads "Chapter 2 of 4" only when the quest data proves its length, and "Chapter 2" otherwise. Later chapters are never named. Finishing a story of known length glows the tracker once and plays the game's stage-end sound.
- **Select, then Go**: choosing a card turns the map to its zone and previews its numbered steps, but starts nothing. *Go* hands the steps from there on to Shortest Path Forever as one journey, or sets the game's own waypoint without it. *Stop* only removes what the guide set, so a waypoint you moved yourself stays.
- **Routes by distance**: steps are ordered by where they are, cross the sea at most once, and a turn-in on the other continent waits at the end with "Hand in when you're in Stormwind City".
- **Why not?**: type three letters or more in *Search quests* and each match lists what the data says it needs (level, earlier quests, race, class, faction), ticked when you meet it.
- **Objective tracker section** above your quests: the current step, how you'll get there with Shortest Path Forever ("Fly to Sentinel Hill · 6 min"), and the step after. Click the title to start the route and track its quests; right-click for *Go*, *Show quest*, *Skip for now* or another journey. After a login, when step 1 is still the step you stopped on, it says "Where you left off".
- **Quest details**: clicking a quest from your log, in the guide or the tracker, opens Blizzard's own quest page. Nothing opens in combat.
- **Dungeons when you ask**: turn on *Dungeons* in the guide's settings menu and a card offers the dungeon with the most quests you can take, routed to their quest givers. Raids are never suggested. Quests in your log always show, whatever the filters.
- **Class trainer**: with Tweaks Forever loaded, "Visit your class trainer · 3 new spells" appears above the steps when you have spells to train. It has no map mark, because the data has no trainer locations.
- **Map pins and quest givers**, off by default: numbered route pins, and the game's "!" over everyone with a quest you can take now. Turn them on under *Show map pins* and *Show quest givers*.
- **Skip for now** hides a step until your next `/reload`; *Skipped (n)* under the steps brings one back.

<p align="center"><img src="https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/tracker.png" width="400" alt="The objective tracker's Adventure Guide section: Turn in: The Zhevra, About 6 min away, Next: Gann's Reclamation"></p>

## Install

Install it from CurseForge or Wago Addons, or download the zip from [Releases](https://github.com/cjber/adventure-guide-forever/releases). To install the zip by hand, extract it into `_classic_beta_/Interface/AddOns/` so you end up with `AddOns/AdventureGuideForever/AdventureGuideForever.toc`.

## Usage

- `/agf` or `/adventureguide` opens the guide on the world map, as does the addon compartment on the minimap.
- `/agf audit` compares the bundled quest data with the game.
- `/agf dump` saves the guide's layout for a bug report; `/reload`, then attach `SavedVariables/AdventureGuideForever.lua`.
- The cog on the tab holds *Quests*, *Dungeons*, the map pins and the tracker. The rest is under *Settings > AddOns > Adventure Guide*, including what clicking the tracker title does.

## Where the quests come from

Quest givers, levels and prerequisites come from a pinned CMaNGOS Classic database, and dungeons from the Forever client's own map tables. Quest IDs are checked against the Forever client's data. Which quests you have finished always comes from the game, and quest and zone names come from the game in your language.

A quest the data cannot place, or whose requirements it cannot check, is never suggested, and a step never points at a place the data does not have. So Forever's own new quests are not suggested until they are in your log; once they are, they are used like any other.

## Works alongside

- **Shortest Path Forever** plans the travel for *Go* and gives the tracker its travel line. Without it, *Go* sets a waypoint and there is no travel line.
- **Tweaks Forever** tells the guide when you have class spells to train.
- **Questie**, **RestedXP** and other guides: the guide still works with them loaded, but the routes may overlap. Turn off *Show tracker section* in the settings if you follow another guide.

## Development

```sh
python3 tools/gen_quests.py        # regenerate Data/Quests.lua
python3 tools/screenshots.py       # regenerate docs/screenshots/
luacheck . && stylua --check .
for s in tests/*_spec.lua; do luajit "$s" || exit 1; done
```

See `AGENTS.md` for the full gate.

## Licence

GPL-3.0-or-later. Quest data derives from [CMaNGOS classic-db](https://github.com/cmangos/classic-db) (GPL-2.0-or-later).
