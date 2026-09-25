<p align="center"><img src="https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/media/icon-400.png" width="96" alt=""></p>

<h1 align="center">Adventure Guide Forever</h1>

<p align="center">
Where to go next, for your level, inside WoW: Forever's world map.<br>
<a href="https://github.com/cjber/adventure-guide-forever/actions/workflows/ci.yml"><img src="https://github.com/cjber/adventure-guide-forever/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
<a href="https://github.com/cjber/adventure-guide-forever/releases/latest"><img src="https://img.shields.io/github/v/release/cjber/adventure-guide-forever" alt="Latest release"></a>
</p>

Levelling guides tell you exactly what to do, in order, as fast as possible. I wanted something looser. From your level, the quests you have finished and the ones in your log, this addon offers a few journeys to choose from, each with a reason, and a short route for the one you pick.

It looks like it came with the game: a tab in the quest log beside Quests, cards drawn with retail's Journeys art, the game's own map pins and objective tracker, and Blizzard's quest details when you click a quest. With the tab closed it draws nothing on your map.

<p align="center"><img src="https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/panel.png" width="640" alt="The Barrens on the world map with the Adventure Guide tab open on its overview: The Barrens story (Chapter 1 of 4, 2 min, 2 quests will soon turn grey) and Head to Stonetalon Mountains (7 quests near your level, 11 min, For level 20), each card whole with its first three steps under it"></p>

## Features

- **Journeys**: up to six cards on the Adventure Guide tab. *Loose ends* counts what is ready to hand in, what is in progress and anything you added yourself; *Westfall story* follows the zone's quest chain; *Head to Duskwood* ("For level 21") and up to two more suggest the zones you've just come into range for, nearest first, once they have enough quests near your level; *Your calling* gathers your class quests ("Your class trainer has a task: The Hunter's Path"). A dungeon and your calling take the slots left, the one whose quests opened most recently first. Each card gives one reason from the quest data, such as "A chain begins with Gryan Stoutmantle", "Sentinel Hill needs hands" or "3 quests will soon turn grey". Until you pick one, the tab is an overview: every card whole, with its counts, its minutes and its first three steps under it. Click a card to pick it, and its steps show in full, up to nine, with the other cards folded above it.
- **Stories as chapters**: a chain reads "Chapter 2 of 4" only when the quest data proves its length, and "Chapter 2" otherwise. Later chapters are never named. Finishing a story of known length glows the tracker once and plays the game's stage-end sound.
- **Choose and go**: choosing a card turns the map to its zone, previews its numbered steps and hands them to Shortest Path Forever as one journey, or sets the game's own waypoint without it. In combat it starts once the fight ends. The back arrow above the cards (or a right-click on the guide's title) brings back the overview. *Stop*, or going back, removes only what the guide set, so a waypoint you moved yourself stays. Once you're in a quest's area the waypoint steps aside until you're done there, and Shortest Path Forever keeps showing the way on to the next stops. A setting turns this off, so choosing only previews.
- **Routes by distance**: steps are ordered by where they are, cross the sea at most once, and a turn-in on the other continent waits at the end with "Hand in when you're in Stormwind City".
- **Why not?**: type three letters or more in *Search quests* and each match lists what the data says it needs (level, earlier quests, race, class, faction), ticked when you meet it.
- **Objective tracker section** above your quests: the current step of the journey the guide shows, how you'll get there with Shortest Path Forever ("Fly to Sentinel Hill · 6 min"), and the step after. Click the title to choose that journey and start the route (and, with the setting on, track its quests); right-click for *Go*, *Show quest*, *Skip for now*, *Not this quest* or another journey. After a login, when step 1 is still the step you stopped on, it says "Where you left off".
- **Quest details**: clicking a quest from your log, in the guide or the tracker, opens Blizzard's own quest page. Nothing opens in combat.
- **Dungeons when you ask**: turn on *Dungeons* in the guide's settings menu and a card offers the dungeon with the most quests you can take, routed to their quest givers. Outdoor elite quests stay on the zone cards, marked optional with the group badge. Raids are never suggested. Quests in your log always show, whatever the filters.
- **Class trainer**: with Tweaks Forever loaded, "Visit your class trainer in Orgrimmar · 3 new spells" appears above the cards and in the tracker when you have spells to train. It names the town of the nearest trainer of your class and faction who teaches them, and clicking it routes there. A chosen journey that passes that town adds a "Train in Orgrimmar" stop. The line's red X skips it for the session. Right-click it for *Not interested*, which *Skipped* in the cog can undo. Hunter pet trainers and riding are not covered.
- **Professions**: when a profession reaches its rank's cap and you can train the next rank, "Your Mining has reached 75 of 75 · Journeyman training in Ironforge" appears the same way, naming the town of the nearest trainer of that rank for your faction; clicking it routes there. It also says when a profession slot is free, and when you haven't learned First Aid, Cooking or Fishing. Recipes and skill-ups stay with SkillUp Forever.
- **Talent points**: "You have 1 talent point to spend" shows above the cards and in the tracker while points wait. Skipping it holds until you gain the next point.
- **Battlegrounds**: when a battleground opens to you, a line says so ("Warsong Gulch is open to you") and clicking it routes to the nearest battlemaster of your side. It goes once you have played a battleground. Turn on *Battlegrounds* in the cog for a card that routes to the battlemaster.
- **PvP rank**: with rank points, a line shows your next rank's reward with its icon, as the character pane does.
- **Something new**: when a level or a new zone brings a journey you haven't been offered, the tracker says so once ("Duskwood is now for your level"); new spells at your trainer light up its line the same way. The Adventure tab and the addon compartment get Blizzard's alert pip, and the new card is marked. Opening the tab clears them; nothing opens by itself.
- **Map pins and quest givers**, off by default: numbered route pins, and the game's "!" over everyone with a quest you can take now. Turn them on under *Show map pins* and *Show quest givers*.
- **Your say in the route**: right-click a step for *Not this quest* and that quest stays off every route on this character. It stays in your log. Shift-click a quest giver's "!" on the map, or a quest in the search, to add it to your route (not one marked orange or red), and a star marks it in the search. A quest you add in another zone goes on *Loose ends*.
- **A nearly full log**: with two slots or fewer left, the first card says how many quests you could drop ("Log nearly full: 3 you could drop"), and its tooltip names them: grey ones, ones you said no to, and ones on another continent or nowhere the data can place. It never abandons anything for you.
- **Skip for now** hides a step until your next `/reload`. Right-click a journey card for *Not interested*, which hides it on this character. *Skipped (n)*, under the steps and in the cog, brings any of these back.

<p align="center"><img src="https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/tracker.png" width="400" alt="The objective tracker's Adventure Guide section: Crossroads, The Barrens, 1 to hand in, 8 to pick up, Opens the next chapter here, About 6 min away, Next: Regthar Deathgate"></p>

## Install

Install it from CurseForge or Wago Addons, or download the zip from [Releases](https://github.com/cjber/adventure-guide-forever/releases). To install the zip by hand, extract it into `_classic_beta_/Interface/AddOns/` so you end up with `AddOns/AdventureGuideForever/AdventureGuideForever.toc`.

## Usage

- `/agf` or `/adventureguide` opens the guide on the world map, as does the addon compartment on the minimap.
- `/agf audit` compares the quest data with the game and says where it came from.
- `/agf dump` saves the guide's layout for a bug report; `/reload`, then attach `SavedVariables/AdventureGuideForever.lua`.
- The cog on the tab holds *Quests*, *Dungeons*, *Battlegrounds*, the map pins, the tracker and anything skipped. The rest is under *Settings > AddOns > Adventure Guide*, including whether choosing a journey or clicking the tracker title starts the route.

## Where the quests come from

Quest givers, levels and prerequisites come from a pinned CMaNGOS Classic database, and dungeons from the Forever client's own map tables. Quest IDs are checked against the Forever client's data. Which quests you have finished always comes from the game, and quest and zone names come from the game in your language.

With **QuestieDB** loaded (it comes with Questie, or on its own), the guide reads each quest's givers, spawns, levels, prerequisites and gates from it shortly after login, and the bundled data serves until then. Towns, maps, trainers and dungeons still come from the bundled data, and a quest is only offered where the bundled data has a start for it too. If QuestieDB is missing or a version the guide can't read, the bundled data is used, and `/agf audit` says why.

A quest the data cannot place, or whose requirements it cannot check, is never suggested, and a step never points at a place the data does not have. So Forever's own new quests are not suggested until they are in your log; once they are, they are used like any other.

## Works alongside

- **Shortest Path Forever** plans the travel when you choose a journey and gives the tracker its travel line. Without it, choosing sets a waypoint and there is no travel line.
- **Tweaks Forever** tells the guide when you have class spells to train.
- **QuestieDB** (with Questie, or alone) supplies the quest data when loaded; see above.
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

GPL-3.0-or-later. Quest data derives from [CMaNGOS classic-db](https://github.com/cmangos/classic-db) (GPL-3.0),
map, flight and dungeon tables from the Forever client's own data via [wago.tools](https://wago.tools), and zone level
ranges from [Warcraft Wiki](https://warcraft.wiki.gg/wiki/Zones_by_level_(original)). The addon bundles no data from
Questie or Wowhead; it reads an installed QuestieDB at runtime only.

World of Warcraft and its content are trademarks and copyrights of Blizzard Entertainment. This addon is free, and
is not affiliated with or endorsed by Blizzard.
