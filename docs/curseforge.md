Where to go next, for your level, as a tab in the world map's own quest log.

Levelling guides tell you exactly what to do, in order, as fast as possible. I wanted something looser. From your level, the quests you have finished and the ones in your log, Adventure Guide Forever offers a few journeys to choose from, each with a reason, and a short route for the one you pick.

It looks like it came with the game: a tab in the quest log beside Quests, cards drawn with retail's Journeys art, the game's own objective tracker, and Blizzard's quest details when you click a quest. With the tab closed it draws nothing on your map. Shift-J opens the same guide in a window of its own. It works with Shortest Path Forever for travel, and loads alongside Questie or RestedXP, though their routes may overlap.

![The Barrens on the world map with the Adventure Guide tab open on its overview: the header reads The Barrens, level 18, under it the class trainer and talent asides, The Barrens story featured with a round map of the zone, 2 ready to hand in and 1 in progress over its first three steps, then Loose ends and Head to Stonetalon Mountains side by side](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/panel.png)

Or in its own window, with a Professions tab when SkillUp Forever is loaded:

![The Adventure Guide window on its Journeys tab: the class trainer and talent lines along the top, The Barrens story featured over a piece of its zone map with Show on Map, its next three steps beside it, then Loose ends and Head to Stonetalon Mountains below](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/window.png)

![The Professions tab with SkillUp Forever loaded: Leatherworking 142 to 150, its next two recipes, three next steps and the reagents to gather, with a picker for Tailoring at the top right](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/window_professions.png)

![The Completion tab with Legacy Forever loaded: The Barrens over its map with areas, flight paths, dungeons, reputations and quests counted, its next three objectives beside it, and Stonetalon Mountains and Durotar as cards below](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/window_completion.png)

![The Barrens story in your own order: the card tagged Your order, Crossroads as step 1 with its quest givers listed under it, Sergra Darkthorn ticked, and Back to suggested order under the steps](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/window_order.png)

The tracker keeps the step you are on in view, above your quests:

![The objective tracker's Adventure Guide section: Crossroads, The Barrens, 1 to hand in, 8 to pick up, Opens the next chapter here, About 6 min away, Next: Regthar Deathgate](https://raw.githubusercontent.com/cjber/adventure-guide-forever/main/docs/screenshots/tracker.png)

## Features

- **Its own window**: `/agf`, Shift-J or the addon compartment. The same journeys and lines as the map tab, and picking a card in one picks it in the other. *Show on Map* takes you to the first step.
- **Professions tab**: with SkillUp Forever, your next recipes, steps and reagents for each crafting profession.
- **PvP tab**: your rank, its next reward, and the battlegrounds open to you with the nearest battlemaster.
- **Completion tab**: with Legacy Forever, how much of your zone you've done and what's next there.
- **Session length**: 15, 30 or 60 minutes, and the route keeps what you can finish in that time.
- **Your order**: drag steps around, or right-click for *Do this next*. The guide greys out moves that would break the route, and a town's step ticks off each quest giver there.
- **Go to entrance**: with Tweaks Forever, a dungeon card takes you to the way in.
- **Journeys**: up to six cards. Tie up the loose ends in your log, follow a zone's story, pick one of the zones that just came into range for your level, or take up your class quests. Until you pick one, the tab shows the suggested card with its first steps and the others two across, each with a round piece of its zone's map; pick one for its full route, up to nine steps.
- **Stories as chapters**: "Chapter 2 of 4" only when the data proves the chain's length. Later chapters are never named.
- **Choose and go**: choosing a card previews its steps on the map and hands the route to Shortest Path Forever, boats and flight paths included, or sets the game's own waypoint. In a quest's area the waypoint steps aside until you're done there, and Shortest Path Forever keeps showing the way on. A setting makes choosing preview only. The back arrow brings back the overview. *Stop* never removes a waypoint you placed yourself.
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

- `/agf`, `/adventureguide` or Shift-J opens the Adventure Guide window; right-click the addon compartment for the world map tab.
- `/agf audit` checks the quest data against the game and says where it came from.
- Options: the cog on the tab, and *Settings > AddOns > Adventure Guide*.

Early days, feedback welcome.

Source and issues: https://github.com/cjber/adventure-guide-forever · GPL-3.0-or-later

Quest data derives from CMaNGOS classic-db (GPL-3.0). World of Warcraft is a trademark of Blizzard Entertainment; this addon is not affiliated with Blizzard.
