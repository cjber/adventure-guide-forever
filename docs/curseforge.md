Where to go next, for your level, as a tab in the world map's own quest log.

Levelling guides tell you exactly what to do, in order, as fast as possible. I wanted something looser. From your level, the quests you have finished and the ones in your log, Adventure Guide Forever offers a few journeys to choose from, each with a reason, and a short route for the one you pick.

It looks like it came with the game: a tab in the quest log beside Quests, cards drawn with retail's Journeys art, the game's own objective tracker, and Blizzard's quest details when you click a quest. With the tab closed it draws nothing on your map. It works with Shortest Path Forever for travel, and loads alongside Questie or RestedXP, though their routes may overlap.

![The Barrens on the world map with the Adventure Guide tab open: the chosen Barrens story card with its seven stops listed and ringed on the map, towns such as Crossroads with their counts (1 to hand in, 8 to pick up, 6 min), and the other journeys folded to one-line rows above it](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/panel.png)

The tracker keeps the step you are on in view, above your quests:

![The objective tracker's Adventure Guide section: Crossroads, The Barrens, 1 to hand in, 8 to pick up, Opens the next chapter here, About 6 min away, Next: Regthar Deathgate](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/tracker.png)

## Features

- **Journeys**: up to six cards. Tie up the loose ends in your log, follow a zone's story, pick one of the zones that just came into range for your level, or take up your class quests. The first card's steps show until you pick another, up to nine.
- **Stories as chapters**: "Chapter 2 of 4" only when the data proves the chain's length. Later chapters are never named.
- **Choose and go**: choosing a card previews its steps on the map and hands the route to Shortest Path Forever, boats and flight paths included, or sets the game's own waypoint. In a quest's area the waypoint steps aside until you're done there. A setting makes choosing preview only. The back arrow brings back all suggestions. *Stop* never removes a waypoint you placed yourself.
- **Routes by distance** cross the sea at most once; a turn-in on the other continent waits until you are there.
- **Why not?**: search a quest and see what it needs, ticked when you meet it.
- **Objective tracker section** above your quests: the current step, how you'll get there, and the next one. Click the title to start the route; right-click to skip a step or pick another journey. Right-click a card if you are not interested in it.
- **Your say**: right-click a step for *Not this quest* and it stays off your routes, though not out of your log. Shift-click a quest giver's "!" or a search result to add a quest to your route.
- **A nearly full log**: the first card counts the quests you could drop, and its tooltip names them. It never abandons anything for you.
- **Dungeons when you ask**: a card for the dungeon with the most quests you can take, routed to their givers. Outdoor elite quests stay on the zone cards, marked optional. Raids are never suggested.
- **Class trainer**: with Tweaks Forever, a line tells you when you have new spells to train and names the town of your nearest trainer. Click it to go there. A chosen journey through that town stops there to train. Skip it for now, or say you're not interested.
- **Professions**: when a profession reaches its cap, a line names the town of your nearest trainer of the next rank. It also tells you when a profession slot is free, or First Aid, Cooking or Fishing is still to learn. Click it to go there.
- **Talent points**: a line while you have talent points to spend.
- **Battlegrounds**: a line when a battleground opens to you, routed to a battlemaster; turn on *Battlegrounds* for a card. With PvP rank points, your next rank's reward.
- **Something new**: when a level or a new zone brings a journey you haven't seen, the tracker says so once and the Adventure tab gets an alert pip. Nothing opens by itself.
- **Map pins and quest givers** are off by default. Turn them on in the guide's settings menu.

Uses QuestieDB (installed with Questie) for its quest data when present, shortly after login; otherwise its own bundled data. A quest the data can't check is never suggested, so Forever's own new quests only show once they are in your log.

## Usage

- `/agf` or `/adventureguide` opens the guide on the world map.
- `/agf audit` checks the quest data against the game and says where it came from.
- Options: the cog on the tab, and *Settings > AddOns > Adventure Guide*.

Early days, feedback welcome.

Source and issues: https://github.com/cjber/adventure-guide-forever · GPL-3.0-or-later

Quest data derives from CMaNGOS classic-db (GPL-3.0). World of Warcraft is a trademark of Blizzard Entertainment; this addon is not affiliated with Blizzard.
