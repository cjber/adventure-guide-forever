# Adventure Guide navigation

The guide helps a player choose an adventure and follow it from preparation to completion. Use the native journal frame, readable quest rows and restrained destination art.

| Tab | Contents |
| --- | --- |
| Journey, default | Current adventure, progress, upcoming steps, quest checklist and travel actions |
| Activities | Choose journeys, professions or PvP |
| Progress | Completed story milestones and a link to Legacy Forever on the map |

Journey has a compact heading and two columns. The left column shows ordered steps with action icons; the right shows related quests. Start, Resume, Show on map, Stop and Full guide act on the displayed journey. Manual ordering stays available. Full guide adds later quests without turning locked prerequisites into active route steps.

Dungeon journeys retain faction and class checks, prerequisite pickups, accepted quests and end-to-end Shortest Path routing. Their right column shows bosses and drops supplied by AtlasLoot Classic through its public item database. Show item icons and native item tooltips. Do not duplicate encounter strategies, models or an independent dungeon journal. Missing AtlasLoot explains how to install it without blocking quest guidance.

Tweaks Forever owns automatic dungeon interior maps on the main world map, using installed Atlas data. Adventure Guide does not install map overlays or entrance pins. Its entrance action uses the existing Tweaks entrance provider or QuestieDB coordinates.

Activities makes choosing another adventure explicit. Opening the page alone keeps the active route. Profession and PvP empty states describe their own data requirements. Training reminders remain off by default.

Progress records completed stories. Collection, exploration and zone completion belong to Legacy Forever. Use the same persisted story record for the completion popup and list; never infer completion from an empty route.

The tracker uses the active journey title as its single heading, followed by the current action and up to two upcoming steps. Live counts agree with the main window and Shortest Path. Hearthstone and teleport instructions use the travel provider's visible action prompt.

## Verification

- Three tabs work with all optional companions missing.
- Choosing a journey preserves quest prerequisites and route ownership.
- Dungeon full guides include incomplete preparation quests; bosses and loot load independently.
- Completed stories persist across reloads without replaying historical popups.
- Combat defers restricted travel and module loading; passive browsing remains usable.
- Main-page controls, long names, scroll lists and item tooltips remain readable at the player's UI scale.
- Tweaks opens the correct dungeon floor on the world map, supports floor selection and returning to the outdoor map, and hides stale interiors when changing maps.
