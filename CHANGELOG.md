# Changelog

What changed in each release, in the terms someone levelling a character would notice. Dates are UTC.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). The entries are prose rather than bare
Added/Fixed lists.

Each version's entry is also its release notes on GitHub, CurseForge and Wago.

## [Unreleased]

The first release: a few journeys to choose from on the world map, each with a reason, and a short route for the one you pick.

- **An Adventure Guide tab on the world map's quest log** offers up to three journeys: finish the quests you carry, follow a zone's story, or head to the next zone with enough quests for your level. Only the journey you pick shows its steps, up to nine, so you choose where to go rather than being handed a list.
- **Zone stories read as chapters.** A chain shows "Chapter 2 of 4" only when the quest data proves how long it is, and never names a later chapter, so the story is not spoiled. Finishing a story of known length glows the tracker once and plays the game's stage-end sound.
- **Choosing a journey starts nothing until you press Go.** The map turns to the journey's zone and previews its numbered steps. Go hands the steps from there on to Shortest Path Forever as one journey, or sets the game's own waypoint without it, or when Shortest Path can't plan the trip. Go warns you first if it would replace another addon's journey.
- **A stop is a town.** Everything to hand in and pick up in one place is one step, "Lakeshire, Redridge" with "2 to hand in, 4 to pick up", and Shortest Path takes you to the giver nearest the stop before. Its tooltip lists each NPC's quests with their level, in the quest log's difficulty colours. Hand-ins come first, then quests about to turn grey, then those nearest your level.
- **Cards tell you the cost of a choice.** With Shortest Path Forever each card shows the minutes to its first stop ("11 min", or "11 min by boat" where it fits), its first town and how many stops follow, and a group tag when any of its quests needs a group. Hover a card for all of it. The guide asks for one estimate a frame, and none in combat.
- **Stop only removes what the guide set.** A waypoint you placed or moved yourself survives Stop, even after a `/reload`. The Stop button goes as soon as Shortest Path ends the journey or you clear the waypoint yourself.
- **A journey lasts until you finish it.** The card you chose stays through a new quest, a level-up or travel: head to Redridge and it becomes the Redridge story on arrival. The route follows the journey as towns empty or you're taken elsewhere, comes back after a `/reload` or login, and says "Journey complete" in the tracker when your last hand-in ends it. If you clear the route in Shortest Path or another journey replaces it, the footer says so, and a click on the card or the tracker title resumes it.
- **Routes cross the sea at most once.** Steps are ordered by distance, a far turn-in never pushes out a nearby pickup, and a quest to hand in on another continent waits at the end with "Hand in when you're in Stormwind City".
- **Search shows why a quest isn't offered.** Type three letters or more and each match lists what the data says it needs, ticked when you meet it: level, earlier quests, race, class or faction.
- **An Adventure Guide section in the objective tracker** shows the current step, how you'll travel there with Shortest Path Forever ("Fly to Sentinel Hill · 6 min"), and the step after. Click its title to start the route and track the route's quests; right-click for Go, Skip for now or another journey. After a login, when step 1 is still the step you stopped on, it says "Where you left off".
- **Clicking a quest from your log** in the guide or the tracker opens Blizzard's own quest details, never in combat.
- **Dungeon quests only when you ask.** Turn on *Dungeons* in the guide's settings menu and a card offers the dungeon with the most quests you can take, routed to their quest givers. Raids are never suggested. Quests already in your log always show, whatever the filters.
- **Visit your class trainer** appears above the steps when Tweaks Forever says you have new spells to train. It has no map mark, because the data has no trainer locations.
- **The map stays yours.** With the tab closed the guide draws nothing on the world map. Route pins and a "!" over every quest giver with a quest you can take now are opt-in under *Show map pins* and *Show quest givers*.
- **Skip for now** hides a step until your next `/reload`; *Skipped (n)* under the steps brings one back.
- **The window has PvP and Completion tabs.** PvP shows your rank, the points to the next and its reward, and the battlegrounds open at your level with the nearest battlemaster. Completion reads Legacy Forever: how much of your zone and the next ones you've done, and the next three things to do there. Without Legacy the tab greys and says so.
- **Pick how long you've got.** A dropdown over the steps takes No limit, 15, 30 or 60 minutes, and the route keeps only what you can finish in that time, with "About 25 min" under it.
- **Put the steps in your own order.** Drag one onto another, or right-click for *Do this next*, *Do this sooner* or *Do this later*. Moves that would break the route are greyed out, the card says "Your order", and *Back to suggested order* undoes it.
- **A town lists its quest givers** under its step, ticked as you finish with each; right-click the town to skip one. Each step's ring shows what it is: a "!" to pick up, a "?" to hand in, the objective mark, a trainer or a battlemaster. A town the route comes back to keeps one map ring with "+1".
- **Go to entrance** on a dungeon card takes you to the way in when Tweaks Forever knows it. The window's Today line shows three and "+2 more" when there's more, including setting your hearth.
- **A quest the data can't check is never suggested,** and a step never points at a place the data doesn't have. Quest and zone names come from the game, in your language.
