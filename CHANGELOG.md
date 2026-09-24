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
- **Stop only removes what the guide set.** A waypoint you placed or moved yourself survives Stop, even after a `/reload`.
- **Routes cross the sea at most once.** Steps are ordered by distance, a far turn-in never pushes out a nearby pickup, and a quest to hand in on another continent waits at the end with "Hand in when you're in Stormwind City".
- **Search shows why a quest isn't offered.** Type three letters or more and each match lists what the data says it needs, ticked when you meet it: level, earlier quests, race, class or faction.
- **An Adventure Guide section in the objective tracker** shows the current step, how you'll travel there with Shortest Path Forever ("Fly to Sentinel Hill · 6 min"), and the step after. Click its title to start the route and track the route's quests; right-click for Go, Skip for now or another journey. After a login, when step 1 is still the step you stopped on, it says "Where you left off".
- **Clicking a quest from your log** in the guide or the tracker opens Blizzard's own quest details, never in combat.
- **Dungeon quests only when you ask.** Turn on *Dungeons* in the guide's settings menu and a card offers the dungeon with the most quests you can take, routed to their quest givers. Raids are never suggested. Quests already in your log always show, whatever the filters.
- **Visit your class trainer** appears above the steps when Tweaks Forever says you have new spells to train. It has no map mark, because the data has no trainer locations.
- **The map stays yours.** With the tab closed the guide draws nothing on the world map. Route pins and a "!" over every quest giver with a quest you can take now are opt-in under *Show map pins* and *Show quest givers*.
- **Skip for now** hides a step until your next `/reload`; *Skipped (n)* under the steps brings one back.
- **A quest the data can't check is never suggested,** and a step never points at a place the data doesn't have. Quest and zone names come from the game, in your language.
