# Design contract

These are the rules referenced by the source and headless specs. The numbered topics remain stable.

## 1. Intent

Offer a few places to go, with reasons, and let the player choose. Use the game's frames and art.
Never recommend a quest with unproven eligibility or invent a destination. The guide never accepts or
abandons quests.

## 2. Surfaces

- **2.1 Map tab.** The overview scrolls; the expand button opens the window. Chosen steps and
  search can scroll. Quest-giver marks and route pins are opt-in.
- **2.2 Journey cards.** Offer every eligible journey for the current level; the home view scrolls and the window grid pages through them. Prefer useful green/yellow quests; exclude orange/red pickups. A choice shows up to ten route actions, followed by upcoming quest entries when fewer actions are available. The active route appears above alternative destinations.
  Give each card a reason and only known travel estimates.
- **2.3 Chapters.** Show a total only for a proven chain. A quest tooltip may name its proven next chapter with its level.
- **2.4 Search.** Share eligibility checks with the planner. Explain missing requirements; locked
  quests offer no destination.
- **2.5 Tracker.** Show the current and next step beside quests. Leave the stock quest order alone.
  Quest tracking is opt-in; a step's quest opens on the map only outside combat.
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
- **2.14 QuestieDB.** Enumerate the compatible provider's complete composed quest catalogue after
  Questie's ready callback (policy corrections precede reads). No bundled-ID, giver or objective whitelist;
  provider absence/failure publishes no partial or fallback quest list. The game owns progress and live POIs;
  QuestieDB owns records, spawns and XP; the live log owns objective counts. Provider objective icon fields are never treated as counts. Questie's IsDoable policy, plus minimum/maximum
  level and guide difficulty preferences, gates pickups. Without live policy, logged quests remain browsable
  but new pickups are not recommended. Route geometry and transport metadata are separate data sources.
  Questie owns background markers whenever loaded, including its visibility toggle; AGF owns route markers.
- **2.15 PvP.** Offer only battlegrounds open at the player's level; journey cards are opt-in.
- **2.16 Professions.** Suggest only training the player qualifies for. Crafting routes come from SkillUp.
- **2.17 Pacing.** Rest and hearth hints advise. Wanderer mode chooses without starting guidance.
- **2.18 Choices.** Dropped quests stay in the log. Added quests still pass eligibility checks.
  Skips are reversible; a full log gets advice only.
- **2.19 Window.** Share the map's choices. Optional tabs use sibling public APIs and explain missing
  providers. Assign Shift-J once, only if neither it nor the window already has a binding.
- **2.20 Your order.** Reordering must preserve quest dependencies. Suggested order remains recoverable.

- **2.21 Dungeons.** A window tab below the shared Today strip, with a level-sorted dungeon list, featured
  header and Quests / Prep / Bosses / Loot pages. The list groups dungeons, the announced Forever raids, then
  the client's other raid instances, each raid row tagged with its group size; the raid tier and sizes come from
  `Integrations/Raids.lua` (docs/dungeon-sources.md), never from a copied Classic attunement page. Remember the instance Map.ID in window state. Plan to run
  selects the existing dungeon journey and enables the existing dungeon preference; no parallel plan state.
  Journey cards link back to the dungeon page. Build on first show, slice source reads at 1 ms, cancel on hide,
  reuse visible rows, and cache a complete optional-source snapshot until the quest data changes.

  Quest statuses use `Model.Eligible`; completed and accepted quests are identified separately. Known faction, race and class exclusions are omitted from quests, Prep and expanded prerequisites.
  A faction-only empty page explains why. Other unproven requirements remain visible as Locked, without a
  pickup recommendation. Expanded steps show prerequisites, including
  alternatives, with no claim that every alternative is required. Only proven giver coordinates are navigable,
  revalidated on click through Integrations. Explicit map actions set the existing SPF/native route, open the
  destination zone with C_Map.OpenWorldMap and play the stock map ping twice. Combat skips opening or
  changing the map but retains navigation. Journey/step map actions and other explicit place buttons share
  the reveal helper; automatic route maintenance never opens panels. Matching AGF pins flash on click and
  glow on map-control hover, with the corresponding row highlighted. Explicit giver navigation is available for locked and earlier quests;
  Map controls are hidden without coordinates. Wanderer mode disables them with an explanatory tooltip. Quest experience uses the planner's level adjustment, counting
  accepted quests and chains provable at the current level, excluding completed quests and counting exclusive
  alternatives once. Unknown experience contributes nothing. Recommended levels use a valid client LFG range, falling back to
  the generator's published Classic dungeon ranges; sorting and every list subtitle use that same range.
  Entry requirements stay in the header and Prep. Enemy-capital entrances remain browsable, marked Hostile and excluded from automatic level-fit selection.
  Other range text uses the client's quest difficulty colour for the
  nearest level in the range, with a tooltip explaining yellow, orange/red and green/grey. Titles remain white.

  Prep derives outside pickups and prerequisite chains from quest records. Each generated entrance keeps its
  level, alternative items, completed-quest gate and unsupported-condition flag. Teleport destinations are inside
  the instance and are never used as outdoor waypoints. QuestieDB's Forever entrance points supply those,
  with Tweaks Forever as the fallback. Door keys absent from
  these sources are not invented or described as unnecessary.

  QuestieDB is read only through QuestieSource's contract-checked runtime layer. Nothing derived from it is
  shipped. Bosses lists only rank-3 NPCs or explicit AtlasLoot/client journal encounters, never every elite.
  AtlasLoot's installed normal-difficulty pages supply curated encounter order and drops; wings merge by level.
  QuestieDB is the fallback. Loot has one row per item ID, boss headings with known levels, and final Trash.
  Any outside/unknown dropper excludes an item. Client rarity excludes grey/white items except proven quest
  starters; uncached rarity waits for item data. Shared drops belong to the first matching boss.
  `questRewards` supplies reward icons without claiming which are choices. Neither optional source present
  shows Needs QuestieDB or AtlasLoot; known empty data shows the empty state. Runtime reads bundle no data.
  Objective text comes from that snapshot, then the accepted quest's client log; otherwise it is omitted.
  Place names use the hub, client map name or bundled map name; an unknown place leaves the NPC alone.
  Experience uses BreakUpLargeNumbers. No internal IDs or missing-value placeholders enter player text.

  Top sub-tabs use TabSystemTopButtonTemplate on a common baseline; chains use the quest log's
  CollapseButtonTemplate. The header has title, location and a single meta line (entry level and positive remaining XP),
  with a stock Plan to run checkbox and padded action row inside its border. It does not repeat the list's range.
  Sub-tabs meet the content inset. Quest rows are a uniform 38 units: expand at left, title and short status
  in separate columns, giver/place below. Full titles, alternative prerequisites and unmet requirements live in
  the row tooltip; rewards and giver navigation live in the detail inset, with compact Map controls on expanded chain steps.
  Details use a header font, an Objectives heading, spaced wrapping text without an objective line cap, start/end
  NPCs (one line when identical), a Rewards heading and a proven linear chain position. The scrollable body keeps the giver button fixed at the bottom. Item icons remain square,
  tooltips use GameTooltip, and the stock divider keeps its atlas aspect.

  Client journal instance IDs and encounters win when available, queried with an explicit instance ID so the
  player's journal selection is untouched. Client dungeon icons are square, as the EJ instance button draws
  them; otherwise the header uses the entrance zone's existing map art at native aspect. Source findings and
  pins are recorded in [dungeon-sources.md](dungeon-sources.md). The layout is included in `/agf dump` and
  `docs/screenshots/dungeons*.png`, including the owner's Alliance level 19 Darkshore/Ragefire regression.
  The shared Today strip shows two wide hints, with the rest in a small stock-font More menu control on every tab.
- **2.22 Addon API.** `AdventureGuideForever.API` (docs/api.md) is read-only and versioned. It copies the
  tracker's step from the committed route and answers nil while a route is due, never building one for a caller.
  Fields are added, never renamed or repurposed, within a version.

## 3. Copy

Use short, plain player language and the game's names. Unknown values stay absent. Public descriptions
follow the shared family voice.

## 4. Routes

- **4.1 Selection.** Take the nearest action at every step: the nearest town pickup, the nearest area of
  a quest the town handed out or the player carries, or the nearest ready hand-in. Group town visits and cross
  the sea at most once. This nearest order is the default; the opt-in `optimisedRoute` beta instead keeps the
  older heuristics (the story's chapter lead, a town's-own look-ahead and the committed order), which the
  player turns on from the Add-ons page.
- **4.2 Laps.** A quest's objectives follow its pickup and its hand-in all of them. Respect quest-log capacity.
  Rebuild on events;
  movement changes focus without shuffling the route. Proximity never hides or truncates guidance. Plan a bounded lookahead, then verify and merge visits before limiting the displayed actions. Keep work bounded per frame.
  An area step's point is the objective node nearest the player (a spawn group's medoid, or the generator's point
  inside the shape), so the marker sits on the work rather than on the shape's border; when the player is already
  inside the area the point stays the area's ring (its middle). Standing in the area step 1 leads to is "you're here":
  its in-progress quest is selected, its travel line and numbered pin go, and the route stays on it until its
  objectives are done (a merged visit takes only the objectives the player can work on now).
- **4.3 Committed order.** Preserve the chosen sequence and visit identities across rebuilds.
  Session limits use rough estimates and retain complete planned work and returns.

The guide uses `ShowUIPanel` / `HideUIPanel` by default, with `UIPanelLayout-*` attributes on its own frame only. It never registers in Blizzard's shared `UIPanelWindows` table. `floatWindow` opts into independent placement and dragging; saved floating positions remain available when switching back. Opening and mode changes defer during combat.

Tweaks can request hidden, lazy creation through `AdventureGuideForever.EnsureWindow`. The guide emits `AdventureGuideForever.WindowCreated` after building and `AdventureGuideForever.WindowLayoutChanged` after switching modes. Tweaks owns layout overrides and scale; the guide retains normal panel occupancy or floating behavior.

### Full guide outline

The Journeys card opens `UI/WindowGuide.lua`, a ten-row paged view of the active lap and the zone's remaining QuestieDB catalogue. Active route steps remain the planner's responsibility. Outline entries never become navigation targets or claim pickup eligibility. Race, class, faction, completion and dungeon/repeatable filters apply; active-chain successors and useful quest levels sort first, with prerequisites before dependents. This is an adaptive zone outline, not a fixed 1–60 walkthrough. Hiding the Journeys page closes the outline.
