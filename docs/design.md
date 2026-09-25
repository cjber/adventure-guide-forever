# Design contract

These are the rules referenced by the source and headless specs. The numbered topics remain stable.

## 1. Intent

Offer a few places to go, with reasons, and let the player choose. Use the game's frames and art.
Never recommend a quest with unproven eligibility or invent a destination. The guide never accepts or
abandons quests.

## 2. Surfaces

- **2.1 Map tab.** The overview fits without scrolling; overflow opens the window. Chosen steps and
  search can scroll. Quest-giver marks and route pins are opt-in.
- **2.2 Journey cards.** Offer up to six eligible journeys. A choice shows at most nine steps.
  Give each card a reason and only known travel estimates.
- **2.3 Chapters.** Show a total only for a proven chain. Never reveal later chapter titles.
- **2.4 Search.** Share eligibility checks with the planner. Explain missing requirements; locked
  quests offer no destination.
- **2.5 Tracker.** Show the current and next step above quests. Leave the stock quest order alone.
  Quest tracking is opt-in; quest details open only outside combat.
- **2.6 Pins.** Draw only known locations and step aside while Shortest Path supplies guidance.
- **2.7 Completion.** Announce a proven story ending once, using the game's tracker glow and sound.
- **2.8 Menus.** Share step actions between the guide and tracker.
- **2.9 Tooltips.** Explain visits and quest difficulty. Town checklists tick completed givers;
  repeated visits share a map ring.
- **2.10 Lifecycle.** Keep the chosen journey through rebuilds, travel and reloads. Resume paused
  guidance explicitly. Stop clears only owned guidance; a moved waypoint survives.
- **2.11 Asides.** Keep hints separate from routes. Unknown locations remain text only.
- **2.12 Trainers.** Use known spells and trainer locations; add a stop only when the route passes.
- **2.13 New suggestions.** Announce new offers quietly after a level or zone change, never by opening UI.
- **2.14 QuestieDB.** Use a compatible installed source, with bundled data as fallback and location limit.
- **2.15 PvP.** Offer only battlegrounds open at the player's level; journey cards are opt-in.
- **2.16 Professions.** Suggest only training the player qualifies for. Crafting routes come from SkillUp.
- **2.17 Pacing.** Rest and hearth hints advise. Wanderer mode chooses without starting guidance.
- **2.18 Choices.** Dropped quests stay in the log. Added quests still pass eligibility checks.
  Skips are reversible; a full log gets advice only.
- **2.19 Window.** Share the map's choices. Optional tabs use sibling public APIs and explain missing
  providers. Assign Shift-J once, only if neither it nor the window already has a binding.
- **2.20 Your order.** Reordering must preserve quest dependencies. Suggested order remains recoverable.

## 3. Copy

Use short, plain player language and the game's names. Unknown values stay absent. Public descriptions
follow the shared family voice.

## 4. Routes

- **4.1 Selection.** Prefer nearby useful work, group town visits, and cross the sea at most once.
  Keep distant hand-ins from displacing nearby pickups.
- **4.2 Laps.** Pickups precede objectives and hand-ins. Respect quest-log capacity. Rebuild on events;
  movement changes focus without shuffling the route. Keep work bounded per frame.
- **4.3 Committed order.** Preserve the chosen sequence and visit identities across rebuilds.
  Session limits use rough estimates and retain complete planned work and returns.
