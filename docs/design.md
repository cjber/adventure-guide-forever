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

- **2.21 Dungeons.** A window tab below the shared Today strip, with a level-sorted dungeon list, featured
  header and Quests / Prep / Bosses / Loot pages. Remember the instance Map.ID in window state. Plan to run
  selects the existing dungeon journey and enables the existing dungeon preference; no parallel plan state.
  Journey cards link back to the dungeon page. Build on first show, slice source reads at 1 ms, cancel on hide,
  reuse visible rows, and cache a complete optional-source snapshot until the quest data changes.

  Quest statuses use `Model.Eligible`; completed and accepted quests are identified separately. Unproven
  requirements remain visible without a pickup recommendation. Expanded steps show prerequisites, including
  alternatives, with no claim that every alternative is required. Only proven giver coordinates are navigable,
  revalidated on click through Integrations. Explicit giver navigation is available for locked and earlier quests;
  Map controls are hidden without coordinates. Wanderer mode disables them with an explanatory tooltip. Quest experience uses the planner's level adjustment, counting
  accepted quests and chains provable at the current level, excluding completed quests and counting exclusive
  alternatives once. Unknown experience contributes nothing. Recommended levels use a valid client LFG range, falling back to
  the generator's published Classic dungeon ranges; sorting and every list subtitle use that same range.
  Entry requirements stay in the header and Prep. Range text uses the client's quest difficulty colour for the
  nearest level in the range, with a tooltip explaining yellow, orange/red and green/grey. Titles remain white.

  Prep derives outside pickups and prerequisite chains from quest records. Each generated entrance keeps its
  level, alternative items, completed-quest gate and unsupported-condition flag. Teleport destinations are inside
  the instance and are never used as outdoor waypoints. QuestieDB's Forever entrance points supply those,
  with Tweaks Forever as the fallback. Door keys absent from
  these sources are not invented or described as unnecessary.

  QuestieDB is read only through QuestieSource's contract-checked runtime layer. Nothing derived from it is
  shipped. NPC rank and instance-area spawns identify the fallback enemy list; ordinary elites are labelled
  explicitly, not promoted to bosses. That fallback tab is titled Elites because creature rank does not identify
  dungeon bosses; client journal encounters retain Bosses. Item `npcDrops` supplies loot, names known droppers
  in that instance and puts rank-3 boss drops first. `questRewards` supplies reward icons;
  that inverse relation does not distinguish choices from guaranteed rewards, so the UI says Rewards.
  Missing optional data greys its page with Needs QuestieDB. The standalone addon suffices.
  Objective text comes from that snapshot, then the accepted quest's client log; otherwise it is omitted.
  Place names use the hub, client map name or bundled map name; an unknown place leaves the NPC alone.
  Experience uses BreakUpLargeNumbers. No internal IDs or missing-value placeholders enter player text.

  Top sub-tabs use TabSystemTopButtonTemplate on a common baseline; chains use the quest log's
  CollapseButtonTemplate. Quest statuses occupy a right-aligned column; known reward icons have their own row.
  Details flow from title and level/experience through objective, start/end NPCs, rewards and a proven linear
  chain position. The scrollable body keeps the giver button fixed at the bottom. Item icons remain square,
  tooltips use GameTooltip, and the stock divider keeps its atlas aspect.

  Client journal instance IDs and encounters win when available, queried with an explicit instance ID so the
  player's journal selection is untouched. Client dungeon icons are square, as the EJ instance button draws
  them; otherwise the header uses the entrance zone's existing map art at native aspect. Source findings and
  pins are recorded in [dungeon-sources.md](dungeon-sources.md). The layout is included in `/agf dump` and
  `docs/screenshots/dungeons.png`.

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
