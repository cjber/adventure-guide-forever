**Where to go next, for your level, inside WoW: Forever's world map.**

Levelling guides tell you exactly what to do, in order. I wanted something looser. From your level, the quests you have finished and the ones in your log, Adventure Guide Forever offers a few journeys to choose from, each with a reason, and a short route for the one you pick.

It looks like it came with the game: a tab in the quest log beside Quests, cards drawn with retail's Journeys art, the game's own objective tracker, and Blizzard's quest details when you click a quest. With the tab closed it draws nothing on your map. It works with Shortest Path Forever for travel, and loads alongside Questie or RestedXP, though their routes may overlap.

![The Barrens on the world map with the Adventure Guide tab open: the chosen Barrens story card with its seven stops listed and ringed on the map, towns such as Crossroads with their counts (1 to hand in, 8 to pick up, 6 min), and the other journeys folded to one-line rows above it](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/panel.png)

![The objective tracker's Adventure Guide section: Crossroads, The Barrens, 1 to hand in, 8 to pick up, Opens the next chapter here, About 6 min away, Next: Regthar Deathgate](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/tracker.png)

## Features

- **Journeys**: up to three cards. Finish the quests you carry, follow a zone's story, or head to the next zone once it has enough quests near your level. Pick one and it shows its steps, up to nine.
- **Stories as chapters**: "Chapter 2 of 4" only when the data proves the chain's length. Later chapters are never named.
- **Choose and go**: choosing a card previews its steps on the map and hands the route to Shortest Path Forever, boats and flight paths included, or sets the game's own waypoint. A setting makes choosing preview only. *Stop* never removes a waypoint you placed yourself.
- **Routes by distance** cross the sea at most once; a turn-in on the other continent waits until you are there.
- **Why not?**: search a quest and see what it needs, ticked when you meet it.
- **Objective tracker section** above your quests with the current step, how you'll get there, and the next one. Click the title to start the route; right-click to skip a step or pick another journey.
- **Dungeons when you ask**: a card for the dungeon with the most quests you can take, routed to their givers. Raids are never suggested.
- **Class trainer**: with Tweaks Forever, a line tells you when you have new spells to train.
- **Map pins and quest givers** are off by default. Turn them on in the guide's settings menu.

A quest the data can't check is never suggested, so Forever's own new quests only show once they are in your log.

## Usage

- `/agf` or `/adventureguide` opens the guide on the world map.
- `/agf audit` checks the bundled quest data against the game.
- Options: the cog on the tab, and *Settings > AddOns > Adventure Guide*.

Early days, feedback welcome.

Source and issues: https://github.com/cjber/adventure-guide-forever · GPL-3.0-or-later

Quest data derives from CMaNGOS classic-db (GPL-3.0). World of Warcraft is a trademark of Blizzard Entertainment; this addon is not affiliated with Blizzard.
