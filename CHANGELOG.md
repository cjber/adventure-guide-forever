# Changelog

What changed in each release, in the terms someone levelling a character would notice. Dates are UTC.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). The entries are prose rather than bare
Added/Fixed lists: what matters about a release is why the guide now sends you somewhere different.

Each version's entry is also its release notes on GitHub, CurseForge and Wago. Older entries are kept
verbatim rather than rewritten as the addon moves. API changes other addons' authors need go under an
optional `### For addon authors` subsection after a version's player bullets.

## [Unreleased]

- **Quest, geometry, zone-art and Forever data regenerated for client build 1.60.1.70630, on QuestieDB v1.0.9 and Classic Era 1.15.9.70576.** The generators now read the newest Forever build from wago.tools' `wowf` product as well as `wow_classic_beta`: wago lists 1.60.1.70630 only under `wowf`, and the pin check had been reading only `wow_classic_beta`, so the daily refresh reported itself already current and skipped regeneration. This build adds 14 flight points and 15 map areas to Forever; the guide's zones, town areas and routes follow them. QuestieDB v1.0.9 also corrects quest text the guide shows.

## [0.22.9] - 2026-10-26

- **The guide now ships the suite's dead-code gate, and an internal build hook nothing called is gone.**
  `tools/deadcode.py` scans the addon for namespace members no code reads, Lua files no TOC loads and media
  nothing references, and runs as its own CI job; adopting it removed `ns.Rebuilding()`, the leftover accessor
  the rebuild benchmark used to read. Nothing changes in game.

## [0.22.8] - 2026-10-26

- **The guide's search now runs on the same shared text matching as every other Forever addon.** It folds and ranks search text through Forever Core's one shared fold (`Core/Text.lua`, `ns.Text.Fold` and `ns.Text.Rank`) instead of its own copy, so an accented quest title is found the same way wherever you search in the suite. Nothing changes in game. Forever Core's settings-page chrome (`UI/SettingsPage.lua`) is vendored byte for byte for the shared-code drift gate; the guide keeps its own settings page.

## [0.22.7] - 2026-10-25

- **An Adventure Guide button now sits on the micro menu bar.** It opens the guide with a click or Alt-G, can take over Blizzard's own tome so the old
  button opens this guide, and follows the placement choice in the addon's settings.

## [0.22.6] - 2026-10-24

- The report keeps the same error details, now captured by Forever Core alongside the other shared report code.

## [0.22.5] - 2026-10-24

- **Report and issue text selects when focused.** Ctrl+C now copies the full report or issue link from either text box.

## [0.22.4] - 2026-10-24

- **The optimised route stays put when your log is nearly full.** A town's quest the log had no room for no longer holds back the visit to hand in that town's other quests, so the route no longer switches between two versions on every rebuild.

## [0.22.3] - 2026-10-23

- **The Forever addons link box selects its address without a Lua error.** Focusing the read-only box handed the client's own `isUserInput` flag to `HighlightText` as its start argument, so it raised *bad argument #2 to '?' (outside of expected range -2147483648 to 2147483647)* and left the address unselected. It now selects the whole address the way the game asks, from the shared link box the Forever addons all carry (#269).

## [0.22.2] - 2026-10-23

- **Report a bug or request a feature from the game.** `/agf issue` (also `/agf bug` and `/agf feature`) opens a composer: write what went wrong, pick Bug or Feature request, and the window hands you a ready-made GitHub issue link, selected so Ctrl+C and a paste opens the new issue with your words and the addon's system report already filled in. Copy report still puts the same text in your hands for Discord.

## [0.22.1] - 2026-10-23

- **The objective tracker hands itself back cleanly in Edit Mode.** Entering Edit Mode now releases the native objective frame anchor and detaches the guide column before Blizzard moves the tracker, and leaving Edit Mode puts the column back. Previously the two fought over the anchor and the tracker could end up clamped in the wrong place.

## [0.22.0] - 2026-10-22

- **Quest activity totals record correctly and can be shared.** The sharing setting now appears, and quest turn-ins are recorded for your character.

### For addon authors

- **Addon authors can read local quest activity totals.** Version 1 minor 3 of the API reports turn-ins observed for this character, with an aggregate row and per-quest rows for personal journals and milestones. These SavedVariables stay local; the addon does not broadcast them or call them realm-first records.

## [0.21.5] - 2026-10-22

- **A quest item in your bags clicks normally while the tracker is loaded.** The guide's tracker sections used to be handed to the game's own tracker manager, which marked the bag item click path insecure, and a click on an item in your bags could be turned into a blocked action while the Forever column was up. Each addon now parents its own sections and never calls the native manager, so the click path stays secure. Already released in SkillUp Forever 0.18.12 and Shortest Path Forever 1.21.10.

## [0.21.4] - 2026-10-21

- **The guide spends less time loading your character.** Its saved Questie catalogue used to repeat the same field names in every quest, town and NPC record; it now stores those names once and uses compact numeric keys, rebuilding the expanded tables after loading. Existing saves are rebuilt once. Thanks to jechten, Jechten and Naburiel for the reports on CurseForge and GitHub issue #166.

## [0.21.3] - 2026-10-21

- **The game's All Objectives header stays in its own frame.** The guide's tracker column used to lift Blizzard's *All Objectives* header out of the objective tracker and hang it above the Forever rows; the game re-anchors it on every tracker update, so the two fought and left a stranded header with a blank band under it. Nothing of ours touches that header any more - no re-anchor, no show or hide, no reserved gap - so the column starts cleanly under the header and stays there through refreshes. Already released in Shortest Path Forever 1.21.8.

## [0.21.2] - 2026-10-21

- **The tracker no longer errors out when another Forever addon adds its own section.** With SkillUp Forever loaded, the two addons' tracker sections are sorted together, and a section that carries no ordering of its own was compared against ones that do, so the layout pass died with `attempt to compare nil with number` on every refresh. Sections that carry an order keep it, sections without one follow them in the order they were added, and the column draws every time. Found in the shared tracker host, reported against Shortest Path Forever by Torpdotorgx on CurseForge.

## [0.21.1] - 2026-10-21

- **Sections that grow in combat no longer get cut off.** While you were in combat, a section that gained lines, such as a new quest objective or a scenario step, was drawn inside the height the column had before it grew, so the new lines stayed clipped until the fight ended. The column now measures the taller content and keeps that height for the rest of the fight, and a collapsed native tracker header no longer leaves a blank gap at the top of the column.

## [0.21.0] - 2026-10-20

- **Lock the tracker where you put it.** Detach the Forever column, drag it where you want it, then tick *Settings*, *Objective tracker*, *Lock the tracker*: the grip stops moving the column and hovering it says the tracker is locked instead of offering to move it. It is off by default, it only ever suppresses our own drag handler, so turning it on or off in combat cannot taint or move anything, and an existing character's settings gain the switch without losing their place. Thanks to Alex21xx for the request.

## [0.20.2] - 2026-10-20

- **A RestedXP guide no longer breaks the route.** With the RestedXP guide loaded, the guide's own card had no overview header to sit under, so every rebuild failed with *guide has no overview header* and the guide stopped keeping up with your progress. That card now sits under Continue with the rest of your route, and a card of a kind the guide does not know falls back there rather than taking the rebuild down with it. Thanks to CodeHoax for the report and the error text.

## [0.20.1] - 2026-10-20

- **Questie's quest tracker can be moved again.** With a Forever section in the tracker, Questie's quest list and the game's own quest tracker could no longer be dragged, and could vanish. A frame of ours sat between UIParent and Questie's list, and Questie's own drag code reads the list's corners and then clears its points mid-gesture, so a layout pass of ours landing in that window left it nothing to read. Nothing of ours is anchored to the list any more: it is watched through its own show, hide, drag-stop and size calls, the column holds its place while you drag or resize it, and it reflows once when you let go. Thanks to procque and Fareed on CurseForge, and to the Questie team for the report that named the cause in Questie/Questie#8076.

## [0.20.0] - 2026-10-20

- **Objectives send you to the main camp of normal mobs.** When an objective's mobs or drops can be found in more than one place, the guide now sends you to the biggest camp rather than a lone spawn or a small cluster nearby, with the marker in the middle of the camp. It passes over a camp of elites for one of normal mobs on the same map, even if those are a few levels higher, and keeps the elites only when there's nothing else. "Next spot" moves between separate camps. Thanks to Polestar for the idea.

## [0.19.0] - 2026-10-20

- **Quest items that run out go first.** Some quest items vanish from your bags after a while, like the Rendered Spores Apothecary Zamah wants in Thunder Bluff within 45 minutes. While you carry one, the guide puts that quest's hand-in (or its objectives, if it isn't done yet) at the top of the route and says *before Rendered Spores runs out*. Thanks to Polestar for the idea.

## [0.18.1] - 2026-10-19

- **Steps say when you'll want a group.** A step's tooltip and its lines in the objective tracker now say why it needs company: *Dungeon:* or *Raid:* with the instance's name, *Group of 3* when your quest log suggests a group size, or *Elite: group advised* for other elite quests. The group icon on the step stays as it was. The idea came from Polestar.
- **A warning before a quest closes another.** Some quests shut others off for good once you take them. When a giver offers one, the guide now says in chat which quests you'd lose, before you click Accept, once per quest. Turn off *Warn before a quest closes another* in Route settings if you'd rather not hear it. If Polestar's own warning is on, the guide leaves it to Polestar. The idea came from Polestar.

## [0.18.0] - 2026-10-18

- **Plays better in a party.** When you're grouped, quests someone in your party also has count as a little nearer, so the route leans towards what you can do together without locking you into an order, and a pickup a party member already has says *someone in your party has it* so you can ask for a share. Party members running Adventure Guide tell each other which quests they have through a hidden addon message, at most once every 15 seconds and never in combat. It's on by default; turn off *Favour quests your party has* in Route settings to stop it. The idea came from Polestar.

## [0.17.1] - 2026-10-17

- **The tracker sections now move clear of Questie's quest list.** With Questie's tracker on, its list was drawn over the Forever sections. They now sit below Questie's list, or above or beside it when there isn't room, and follow it when it moves, grows or hides; your quest tracker keeps its own place. Thanks to deathmvp1 for the report and berserkerlxl for finding the cause.

## [0.17.0] - 2026-10-17

- **Steps aside while Polestar is guiding.** If you have Polestar installed and one of its guides running, Adventure Guide no longer starts its own route or draws map marks over it. The tracker says *Polestar is guiding you*; click that line, or Go on a journey, to take over again. Turn off *Step aside while Polestar is guiding* in Route settings to keep both running.

## [0.16.1] - 2026-10-17

- **Data checked against Forever 1.60.1.70450.** The bundled maps, zones and quest data are unchanged apart from the build they name, so the quest catalogue is rebuilt once at your next login.

## [0.16.0] - 2026-10-16

- **In your language.** The guide is now in German, French, Spanish (Spain and Latin America), Brazilian Portuguese, Russian, Korean and Chinese (simplified and traditional), using the game's own words for the quest log, quest givers, flight paths and the objective tracker. It's machine translated, and corrections are welcome through the translation issue form. Quest, NPC and place names come from the game or QuestieDB as before, and a few town names from the guide's own data stay in English.

## [0.15.0] - 2026-10-16

- **A Forever addons page in the settings.** Settings > AddOns > Adventure Guide has a new *Forever addons* page. It lists my five Forever addons and, for each of the others, says whether it's on, turned off or not installed, with a *Copy link* button that shows its address to copy. Its *Suggest my other Forever addons* box replaces *Suggest companion addons*; if you had that turned off, it stays off.

- **Suggestions for my other addons are quieter.** They are grey now and show only for an addon you don't have, where it would help: a route step for Shortest Path Forever, a trainer for your next profession rank for SkillUp Forever, which plans the cheapest route there, and a dungeon card with no known entrance for Tweaks Forever. Each one's menu offers the address, with *Don't suggest this again* (never in combat). While suggestions are on, a dungeon card still says to enable Tweaks Forever when it's installed but turned off; with them off, no suggestion shows anywhere.

- **The README credits the people and addons behind Adventure Guide Forever.** The players who reported bugs or asked for features, and Polestar, which inspired some features, are named, and THIRD_PARTY.md has the full list.

### For addon authors

- **`AdventureGuideForever.API.Suggestions(limit)` and `API.StartSuggestion(id)`** let another addon list the guide's cards (up to five, in the panel's order, as `{id, title, level, kind, map, x, y}`) and start one as the guide's own Start does. `API.minor` is 2; `version` stays 1. See docs/api.md.

## [0.14.1] - 2026-10-16

- **"Next spot" moves between an objective's camps.** When a step's objective can be done at more than one camp on the map, right-click the step and choose "Next spot" to go to the nearest camp you haven't passed over, including from a camp someone has just cleared. Before, it only moved between the different objectives of one step, so a quest with a single kill or collect objective never offered it. Standing at any of the camps of the step you're on now counts as being in its area. A step that groups objectives done in different places still moves between those places.

## [0.14.0] - 2026-10-16

- **Objectives send you to mobs nearer your level.** When an objective can be done in more than one place and the first place's mobs are 3 or more levels above you, the guide sends you to the next place on the same map whose mobs aren't. If there's no such place, it keeps the first.

- **"Next spot" works while you're standing in the area.** When a step covers objectives in more than one spot nearby, right-click it where you stand and choose "Next spot": the arrow leads you to the nearest spot you haven't passed over, and the area is yours again once you get there. Walk back to a spot you passed over and the arrow leads on again. After the last spot it goes round again.

- **The quest tracker goes back to its own place when the guide has nothing to show in it.** With nothing in the Forever section, or All Objectives collapsed, the quest tracker returns to where Edit Mode (or your UI addon) put it, and you can move it again. Before, it could stay stuck mid-screen or over the minimap.

- **The guide's tracker section stays current in combat.** Collapsing All Objectives mid-fight hides it straight away, and its steps keep updating until combat ends.

- **Data checked against Forever 1.60.1.70425.** The patch adds two areas, Hyjal Crater and Sunken Hollow, and nothing else in the bundled data changed. The quest catalogue is rebuilt once at your next login.

## [0.13.0] - 2026-10-16

- **The guide learns when a quest giver doesn't have a quest.** If the guide sends you to pick up a quest and the NPC's quest list doesn't include it (Forever removed or changed some quests), the guide says so in chat, drops it from the route, and its search explains "The giver didn't offer it". It tries again after your next level-up, or after a hand-in that could open the quest up.

- **"Next spot" for objectives with more than one camp.** Right-click an objective step that has more than one place to do it, and "Next spot" moves the arrow to the nearest place you haven't passed over yet. It isn't offered while you're standing in the area, and it forgets the places you passed over when you /reload.

- **Start a locked quest's chain from the search.** When a quest you search for is locked behind others, its tooltip now names the earliest quest in its chain that you can take now, and a shift-click adds that quest to your route.

- **The guide's quest search puts the best match first.** It used to list every title containing what you typed in alphabetical order and stop at ten, so the quest you meant could be cut off. Now an exact title comes first, then titles that start with your words, then titles with a word starting that way, then the rest; within those, quests you can take now come first, then those that best suit your level. You can type the words in any order, and "dun garok" finds "Dûn Garok".

- **`/agf report` gives you something to paste into a bug report.** It opens a small window with the text already selected: your addon and game versions, your character, the stop the guide is showing and why, the quest data version, your other addons, and the last few errors the guide caught this session. Press Ctrl+C and paste it. It fits in one message, and you don't need a /reload or a saved-variables file.

- **`/agf where` for reporting a wrong stop.** It shows the stop the guide is on, with its quest IDs and why it was chosen, ready to copy. The GitHub issue page now has a "Wrong stop" form that asks for it, plus a form for pasting a translation, and the README says how to help without writing code.

- **The guide follows Shortest Path the moment its journey changes.** With a Shortest Path new enough to announce its changes, the guide hears straight away when a journey ends, moves on or is replaced, instead of waiting for the game's waypoint events. Older Shortest Path versions work as before.

- **The arrow stops flipping between two quest givers standing near each other.** In a town visit the arrow always pointed at whichever giver was nearest, so walking between two of them could swap the Shortest Path waypoint back and forth. It now stays on the giver it's pointing at until another one is about 35 yards closer, or you've finished with the first.

- **Suggestions right after a level-up use your new level.** The game can briefly report your old level after the level-up, and the guide sometimes rebuilt in that gap, so the new suggestions were a level behind until something else changed. It now goes by the level the level-up itself reported.

- **Quests with two kill or two collect objectives keep the right one on the route.** When the quest log listed them in a different order from the quest data (The Guns of Northwatch, for one), the guide paired them up by position. Kill Smythe first and his area stayed on the route while Fairmount's dropped off. It now matches each objective by the NPC or item it names, and only uses position when there's no name to go on.

- **Hovering an NPC in combat or an instance can no longer raise an error.** The "Adventure guide" line on a unit's tooltip read the unit's ID straight away, but the game can keep that ID hidden from addons. The guide now checks first and quietly leaves its line out when it can't read the ID, and it leaves protected tooltips alone.

- **Killing and looting for a quest costs less.** Every kill or quest item used to re-plan the whole route, even when all that changed was a count like 3/10. Now a count-only change just updates the numbers, and the full re-plan waits for something that matters: an objective finishing, a quest completing, or a quest added or dropped.

### For addon authors

- **`AdventureGuideForever.API.Subscribe(callback)`** calls back the frame after the current stop or the followed journey changes, once per burst, with `{stop = true, journey = true}` as they apply. `API.minor` is 1; `version` stays 1. See docs/api.md.

## [0.12.2] - 2026-10-15

- **Finished quests catch up without a /reload.** The guide read your finished quests once per session and then only counted the ones you handed in, so a quest the game closed some other way (a breadcrumb or the other branch of a chain) stayed on the route until you reloaded. It now reads them again after each hand-in and at every loading screen, and if the game has no answer at login it keeps asking instead of staying on "Loading".

- **Your quests stay below the Forever tracker with EllesmereUI and other UI suites.** When the game, Edit Mode or a UI addon put the quest tracker back in its saved spot, the Forever sections waited for the next quest event to restack, so your quests sat over them until then. The column now follows the quest tracker as soon as it moves, still without touching the game's own tracker code.

- **A detached tracker with nothing to show leaves the screen.** Its "Forever tracker" title hides with the empty column and comes back, where you left it, as soon as a section has something to show.

- **Less work while looting and on the map.** Picking up coins no longer asks for your trainable spells once per coin, and refreshing the world map's quest-giver pins reuses the quest log the route was planned from.

- **Data checked against Forever 1.60.1.70374.** The bundled maps, zones and quest data are unchanged apart from the build they name, so the quest catalogue is rebuilt once at your next login.

## [0.12.1] - 2026-10-13

- **Tracker stays put when Edit Mode places it by its centre or bottom.** Attaching to the quest tracker no longer pushes it down the screen when it has been moved away from the default top-anchored spot.

- **How the Forever addons work together.** The README and store page list each of the other Forever addons and what it adds when installed alongside this one.

- **Current Forever client data.** The guide is built against Forever build 1.60.1.70338 and rebuilds its quest catalogue for QuestieDB 1.0.6, which adds the new Deadmines and Scarlet Monastery quests.

## [0.12.0] - 2026-10-09

- **Resume RestedXP from Shortest Path.** Its Resume guide action returns to the active RestedXP journey through Adventure Guide when integrated navigation is enabled.

- **Keep Blizzard's tracker methods intact.** The shared Forever tracker responds to objective and player events without wrapping native layout methods.

- **Keep route updates smooth during quest-log changes.** A queued route rebuild now stays frame-sliced while the tracker refreshes, so the current route remains visible until the new one is ready.

- **Current quest and map data.** The guide includes the latest Forever client data for newly added quests and map areas.

## [0.11.1] - 2026-10-08

- **Quest text stays on screen when the Forever tracker is smaller.** The native quest column and its header keep their full width at the edge of the screen.

- **Shorter addon descriptions.** The README and store pages explain the features directly and keep the author and licence credits.

- **Shared tracker scaling.** Adventure Guide follows the tracker scale selected in Shortest Path Forever.

## [0.11.0] - 2026-10-07

- **Choose where to display RestedXP guides.** A one-time prompt explains which windows and markers Adventure Guide replaces. Keep RestedXP or use Adventure Guide, and change the choice later in AddOns settings.

- **Quest objectives stay below the Forever tracker after reload.** The shared tracker no longer resizes Blizzard's quest container, which could move it over the addon sections.

- **Compact step menus.** Step actions use small menu rows instead of a column of red buttons. Nearby map stops share stacked rings on the world map and minimap.

- **RestedXP guides in the Adventure tab.** Read guide instructions and objectives in the map sidebar and tracker, select guides and control their steps. RestedXP handles progression while Shortest Path Forever handles travel. The guide shares existing journey cards, steps and map pins with Adventure Guide recommendations. The map previews ten steps with grouped markers, while the quest tracker shows the current step, the next step and ongoing objectives.

## [0.10.2] - 2026-10-07

- **Data checked against Forever 1.60.1.70245.** The bundled game data is unchanged.
- **Data updates keep the saved catalogue in sync.** The refresh workflow updates its revision and checks it before opening a pull request.

## [0.10.1] - 2026-10-06

- **Shared quest stops show all their work.** Nearby objectives share a visit with each quest's current progress shown beneath it in the tracker and map tooltip. Counts update during combat, completed work drops out, and quests placed by the client stay in the visit. Objectives on different maps remain separate.

## [0.10.0] - 2026-10-06

- **Bosses and loot on the map.** Right-click a dungeon card to browse AtlasLoot bosses and their drops with native item tooltips.

- **Useful dungeon order.** Level suitability comes first, then quests in your log and travel to the first stop. Recently unlocked quests no longer push high-level dungeons ahead.

- **Journeys keep their full route.** Time-limit controls and estimated session budgets are removed. Saved time limits no longer hide quest steps.

- **One map guide.** The standalone window and its key binding are removed. Continue shows two choices and other sections one until expanded. Quests in your log includes the current story and is the default suggestion.
- **Steady quest-log routes.** Accepting another quest keeps the current first stop while adding the new work to your route.
- **Quicker reloads.** Reuse the Questie catalogue when addon source and data are unchanged.
- **Dungeon information stays with the quest route.** Dungeon journeys include available prerequisite chains. Automatic interior maps live in Tweaks Forever.

- **Readable map badges.** Quest marks return to their original size. Kill objectives use the native skull instead of the long attack cursor.

- **Choose your quest difficulty.** A level slider defaults to quests no more than two levels above yours, avoiding orange and red recommendations. Accepted quests stay visible.
- **Keep preparing for your dungeon.** Accepting its quests no longer removes the dungeon journey. It includes available preparation quests and uses a known entrance when an accepted objective has no location.

- **More useful choices.** Suitable dungeons appear together, including Deadmines and Wailing Caverns. A quest visit in a zone above your level follows normal questing zones and explains the level range.
- **Smoother rebuilds.** Route planning checks its frame budget between adventure cards and presents only the finished result. The cold QuestieDB catalogue also uses shorter slices; completed routes remain atomic.
- **Three guide pages.** Journeys holds your adventure and useful suggestions, Activities groups dungeon, profession and PvP browsing, and Progress shows completion. Old page selections carry across.
- **Stories worth finishing.** A proven final story hand-in shows a named completion popup once per character, including with the tracker hidden.
- **A clearer story tracker.** Your chosen journey is the section heading, with action icons for the current stop and up to two upcoming stops. The preview follows your current route position, and a ready hand-in no longer repeats its status beneath the action.
- **Class spell training is optional.** Spell reminders and automatic trainer visits are off by default. Enable them in the Route settings when you want them; talent and profession hints keep working independently.
- **Useful suggestions beside your journey.** Journeys brings your adventure, training and profession hints together. See why each suggestion fits, start its route or browse other things you can do. Browsing leaves your current journey intact.
- **Training hints follow you around town.** Moving between city districts refreshes the trainer and profession hints without rebuilding your quest route. A hint dismissed or moved since it was drawn cannot start navigation to its old destination.
- **Game data for Forever build 1.60.1.70235, tested against QuestieDB 1.0.5.** The new QuestieDB lists Forever's added quests in Westfall, Moonglade's Great Cat Spirit and more, and when your quest log is full a route that leaves out a town's quest no longer drops the walk back to hand in the rest.

## [0.9.0] - 2026-10-05

- **Quest progress stays in step with Shortest Path.** An objective count changing at the current stop refreshes the journey's text, without sending you back to an earlier stop.

- **See what to do next.** The guide leads with your next task and its reason, offers a Start action, and keeps other adventures underneath.

- **An objective area shared by several quests shows the game's own quest area.** Shortest Path Forever now draws the client's quest area on the map for a stop, and the guide names every quest an area covers, not only an area with a single quest, so a merged area gets the same outline and the same arrival check.
- **Every header of the guide's overview fits the panel, and a group turns pages.** With a few zones open to you the list ran off the bottom of the map panel, and Dungeons and Battlegrounds sat below the fold. Each group now shows as many cards as the panel has room for and its header carries the spellbook's page arrows for the rest, so Continue, Zones, Dungeons and Battlegrounds are all in sight at once.
- **A card says what level its place is.** A zone or dungeon card shows its level range at the right of its title, and a battleground the level it opens at, in the colour the game gives a quest of that level: yellow suits you, green is easy, orange is a stretch.
- **Icons keep their shape.** A note above the cards, a step's badge and a profession's icon could show a cropped corner of their picture after the same slot had drawn a different kind of icon, and a few rings and marks were a pixel off square. Every icon is now drawn at its own shape, and the overview's spacing is even: a card's icon sits centred, and each group has room above its header.
- **Following a zone's story no longer breaks the panel for some characters.** On a character whose race the quest data has no entry for, choosing a zone story raised an error on every refresh and left the panel half drawn. The story's quest list treats that character like any other.
- **The group holding the card you follow has no fold button.** That group always stays open so its card is never lost; its header used to show a button that did nothing but quietly save a fold for later.

## [0.8.0] - 2026-10-05

- **A ready hand-in beside you comes first, and a broad objective area counts as reached.** Standing in the Valley of Trials with Simple Parchment ready and Frang a few steps away, the guide still headed for an objective hundreds of yards off, and it walked you to the middle of an area you were already standing in. A ready hand-in or a pickup within a short walk now leads over a farther step, and an objective area counts the ground between its objectives as reached: the tracker says you are in the area, with no walking leg.
- **A dungeon's interior map opens from its entrance, with the game's own floor selector.** A dungeon the guide offers is pinned at its entrance on the world map, and clicking the pin opens that instance's interior without going there first; a dungeon's Maps control in the guide opens the same view. An instance with several Atlas maps chooses its wings and floors from the game's own dropdown, which returns to the floor you last looked at for the rest of the session. Both are absent without Atlas and its Classic module, and the guide shows its usual empty state instead of erroring.
- **Inside a quest's area, the guide shows the area instead of pointing at it.** While you work inside the objective area of the step the guide is on, the world map shows the area's outline in yellow, the minimap turns the game's own quest area gold, and the ring and the dots leading to its middle are gone, because they only told you to go where you already are. Stepping out brings them back.
- **Lower-level work comes first.** A zone and the quests inside a stop rank by one level preference: work at your level or one or two below is best, each level above costs twice its distance, and each level further below costs one, so a zone you have just outgrown, such as Darkshore at 21, stays on offer instead of being buried by the higher zones, and a starting zone kept afloat by one near-level quest does not outrank a zone that fits.
- **A stop is the named place it stands in.** Quest givers are grouped into one stop when they stand in the same named area of the map, the areas the world map reveals as you explore, and the stop takes that area's name in your game's language: Goldshire, Razor Hill, Maestra's Post. A whole city is one stop, so its inn and trainers count as here anywhere inside it.
- **Quest data is ready as soon as you log in.** The guide composed the whole QuestieDB catalogue, some 4,000 quests and their givers, at every login and `/reload`, and the tracker showed "Loading quest data..." for a few seconds while it did. It now keeps that catalogue in the character's saved data and reuses it while QuestieDB, the game build, the language and the character are unchanged, rebuilding only when one of them moves. The saved catalogue is taken up at once, so the route is on the tracker from the start instead of after Questie is ready.
- **Long lines in the guide's menus and on a walk are no longer cut short.** A menu widens to its longest entry, and a line too long for the screen still shows its whole text in a tooltip. A walk inside the zone you are already in names the stop you are heading for instead of the zone under your feet.
- **The tracker reads in game order.** The game's All Objectives header leads the shared column, the Forever sections follow it, and your quests stay below them. In combat the game keeps its quest list in its own slot, so the header and quests stay together and the Forever sections sit directly below them, keeping the tracker to one column.
- **A step's badge says what the work is.** An objective step wears the sword for something to kill, the bag for something to collect and the gear for something to use, in place of the plain yellow dot; a step that mixes them keeps the dot.
- **A town stop is named by its town in Shortest Path Forever.** The journey list read "Journey to Visit Stormwind City: Pick up 3" and "Walk to Visit Stormwind City: Pick up 3"; it now reads "Journey to Stormwind City" and "Walk to Stormwind City".
- **The route's next stop stands out on the map.** Its numbered ring is lit the way the game lights the quest it tracks, and the later stops keep the plain ring.
- **The overview groups its cards under quest log headers.** The long list of journey cards is now grouped under collapsible headers like the quest log's own: Continue, Zones for your level, Dungeons and Battlegrounds. A group with no card draws no header, each header remembers whether you left it open, and the group holding the route the guide follows stays open.

- **The class trainer line names a trainer of your side.** For a class and race pairing Forever adds, such as an Alliance shaman, the line could point at the other side's trainer, for example one in Stonard. A trainer who serves only the other side is no longer offered.
- **A quest the route cannot finish is no longer handed in early.** When the quest data placed only some of a quest's objectives, the route could still return to hand it in, so a town said "2 to hand in" with only one ready. A quest like that now waits with your log until it is really done, and the next build offers its turn-in.
- **The tracker comes back after Edit Mode is put away.** Opening a settings or keybind panel from Edit Mode hid the guide's tracker column and left it hidden until a reload. It now returns as soon as the Edit Mode panel goes away.
- **An objective the game does not count no longer shows a bare 0.** For an objective kind the quest log gives no count for, the tooltip showed a line like "2/0". It now uses the guide's own count for that objective, and shows no count at all when the data has none either.
- **Quest data loads sooner after a login or a reload.** The build read a quest giver's place from QuestieDB, then asked again which side it serves and whether it keeps an inn; it now reads each one once and lets the objective pass share the spawns it already has.
- **A plain quest giver is no longer called a class trainer.** When the bundled trainer list did not name the giver of a class quest, the quest's class was stamped on it, so the calling card said "Your class trainer has a task" for someone like Harry Burlguard or Islen Waterseer. A giver counts as a trainer only when QuestieDB's own NPC flags mark it as one.
- **A chain with one prerequisite now shows its total.** QuestieDB files a lone prerequisite as one of several alternatives, so a chain containing one was shown as a chapter with no total. A single alternative now reads as the one quest it requires, so those chains show "Chapter 2 of 8" instead of a bare chapter.
- **The guide no longer offers quests your character cannot take.** A quest gated behind a profession rank or a reputation standing is read from QuestieDB with its requirement, so a route no longer sends you to a pickup the game would refuse.
- **The guide works for the Skyborne.** A Skyborne character got an "integer overflow" error whenever the guide planned or the map opened, and the guide stayed on "Loading quest data". Their race is now read the way QuestieDB records it, and their side's quests are theirs.
- **The guide's map data matches the current game build.** The maps, flight masters and Forever's own lands the guide carries are read from client build 1.60.1.70205. The Stormwind flight master sits where the game now has it, and the guide no longer plans steps on the Alterac Valley battleground map, which the game no longer lists as a zone.
- **A route settles the first time it is drawn.** With a nearly full quest log, a route could put a hand-in last, then move it up to second a moment later with nothing changed. The order you first see is now the one it keeps.
- **Bosses and loot move to Adventure Guide for Classic.** The Dungeons tab no longer lists bosses, their abilities or loot, and no longer wears the Encounter Journal's art. It keeps the instance list, each dungeon's quests with their detail and pre-quest chains, Prep, Plan to run, Go to entrance and the Atlas interior maps with their floor selector, in the window's own look. Where those pages were, one Bosses and loot control opens Adventure Guide for Classic, the recommended companion for a dungeon's bosses and loot, and stays disabled with a hint naming that addon when it is not installed or enabled.
- **The story finishes the zone it is in.** While the zone the story led with still has work, the guide keeps leading with it instead of swapping to the zone the ranking likes a little better that level, and it does not go straight back to a zone it just left. The choice survives a reload, so the lead no longer flips back and forth between two zones.
- **Every list in the window scrolls like the game's own.** The dungeon catalogue, its quests and the other lists were drawn with a hand-rolled scroll frame that hid rows by hand; they now use the client's own scroll box and thin minimal scrollbar, so a row is made only while it is on screen and the list reads like the Encounter Journal. Headings, row names and the featured titles take the Journal's own fonts and colours, and a page the client has no art for shows a plain dark tile instead of a question mark.

## [0.7.1] - 2026-10-04

- **A boss's level no longer runs into its loot.** In a dungeon's Loot view, the level under each boss's name was drawn over the first item beneath it. The boss heading is now tall enough for both lines, and the Bosses view still jumps to the right place in the list.
- **View loot opens at the boss you picked.** From the Bosses view, *View loot* on a boss far down the list stopped short and showed an earlier boss's items. It now opens the Loot view at that boss's heading.

## [0.7.0] - 2026-10-03

- **Quest data loads sooner after login and a reload.** While "Loading quest data..." was up, the guide asked QuestieDB where the same creature or object is found once for every quest that needs it, tens of thousands of times in all. It now asks once for each, under a third of the reading, so the journeys and the tracker fill in sooner.
- **A detached tracker keeps clear of your quests.** With Attach to quest tracker off, the Forever column could open on top of the quest list. Until you drag it, it now sits beside the quest tracker, level with its top; once dragged, it stays where you put it.
- **A journey card follows your own order.** After you reordered a journey's stops, its card kept naming the stop that used to come first, such as "Turn in: The Adventurer and 1 more stop". The card now names the stop your order starts with.
- **A dungeon's entrance reads the same from the first moment.** The Dungeons tab showed one entrance position, then a slightly different one a moment later once the dungeon's details had loaded. It now shows the QuestieDB position straight away, and a dungeon journey's card and its Go to entrance button use that same position. Tweaks Forever still supplies an entrance QuestieDB does not list.
- **The Bosses view says when AtlasLoot is installed but not running.** With AtlasLoot in the AddOns folder but turned off or marked out of date, an empty Bosses view asked you to install it. It now asks you to enable or update it, and says so plainly when AtlasLoot is running and lists no encounters for that dungeon.
- **Bosses appear when AtlasLoot loads late.** If the Dungeons tab was opened during a fight, or before AtlasLoot had loaded, the Bosses and Loot views stayed without AtlasLoot's encounters until the next reload. They now fill in as soon as the fight ends or AtlasLoot loads.
- **Towns, trainers and innkeepers follow the installed QuestieDB.** Where a quest giver's town is, where a trainer, battlemaster or innkeeper stands and which side each serves used to come from a list packed with the guide and made for Classic Era. They are now read from QuestieDB, so places that exist only in Forever count as towns and its trainers and inns are found where they stand in this game.
- **A mount seller is no longer taken for an innkeeper.** Eight mount sellers, such as Katie Hunter in Eastvale, and one other character were listed as innkeepers, so the hearthstone hint could send you to one of them to set your home. Only real innkeepers are used now.

## [0.6.8] - 2026-10-03

- **A stuck Questie no longer holds the guide.** If Questie loaded but never finished starting on a character, the guide sat on "Loading quest data..." for the whole session, with an empty tracker and empty journeys. After a minute it now reads the quest data on its own, so quests in your log are guided again. New pickups are recommended once Questie is running.
- **Dungeon quests in a dungeon's side areas count as its quests.** A quest that Questie files under one of a dungeon's other area names was treated as an ordinary zone quest, so it was missing from that dungeon's journey and quest list. It is now filed under the dungeon, like the enemies of the same area.
- **Dungeon loot no longer shows a slot code.** In the Dungeons tab, a drop that cannot be equipped, such as an item that starts a quest, showed the game's internal text INVTYPE_NON_EQUIP_IGNORE in its details. That text is now left out.

## [0.6.7] - 2026-10-03

- **Dungeons show their real level range.** The Dungeons tab showed some dungeons as a single level written twice, such as Level 13-13, because the game answers with one level for them. It now shows the dungeon's recommended range, such as Level 13-18 for Ragefire Chasm.

## [0.6.6] - 2026-10-02

- **The tracker fills in seconds, not most of a minute.** After logging in or reloading, the guide read the quest catalogue so gently that the tracker sat on "Loading quest data..." for 40 seconds or more. It now takes a few seconds.
- **Opening the map from the guide no longer breaks it in combat.** After the guide opened the world map or turned it to another zone, opening the map in a fight could raise a blocked-action warning and lose its quest markers until a reload. The guide now asks the game to open the map itself. With the quest list collapsed or the map maximized, the guide opens in its own window. Show quest and a click on a step whose quest is in your log now open the map on that quest's zone and select the quest, instead of opening its details page.
- **The guides stay put in a fight.** In combat the game stretches its quest tracker and nudges it back on screen, which shoved the Forever sections sideways across the screen until the fight ended. They now stay stacked above the quest list.
- **A damaged save no longer breaks the guide.** A hand-edited saved file with a bad "Not interested" entry or window position is now ignored, instead of raising an error in the Skipped menu or when the window opens.
- **Setting names fit the settings panel.** Five were cut off with an ellipsis; they are shorter now and their tooltips carry the detail.
- **Other addons can follow the guide.** `AdventureGuideForever.API` tells an addon which stop the tracker shows and the stops after it, with each town's hand-in and pickup counts. See `docs/api.md`.
- **Boss rows jump to the right loot.** Clicking a boss in the Dungeons tab now scrolls its loot list to that boss's drops, instead of stopping short once the list has section headings.
- **Scaling quests show your level.** A quest that scales to you appears in the full guide at your level with the right difficulty colour, where it used to read "[-1]" in grey.
- **Completion zones always have a name.** A zone the client cannot name falls back to the guide's own zone name, and is left out when there is none, instead of showing a map number.

## [0.6.5] - 2026-10-01

- **Session estimates follow your speed.** Without Shortest Path installed, local travel estimates account for mounts and slows, keeping the last readable speed when combat hides it.

- **Keep guides clear of quests in combat.** Companion sections stay clear when the quest list grows during a fight. Detaching restores the quest tracker’s original Edit Mode position.

## [0.6.4] - 2026-09-30

- **Move the shared tracker.** Turn off Attach to quest tracker in Settings to drag all Forever sections together. The position survives `/reload`.
- **The addon's files now follow the guide's own parts.** The planner, integrations and UI live in separate folders, while the game still loads them in the same order.

## [0.6.3] - 2026-09-30

- **The tracker names your story, and every pin finds its way back.** The tracker now shows which journey it is following above the current step, and clicking that line, or right-clicking a numbered map pin past the first, sends you back along the story from its first step. While Questie is still reading its quest data, the guide holds your route and shows a quiet loading line instead of first building one from your log and swapping it out when the real quests arrive.
- **Raids share the dungeon tab.** Onyxia's Lair and the other raid instances the client carries sit beside the dungeons, split into the announced Forever raids and the rest, each row showing its group size. Bosses and loot still come from AtlasLoot or the game's encounter journal, and nothing lists a boss the addon does not ship.
- **Stand in the area, not beside it.** When you are inside the objective area the guide is sending you to, it selects that quest and stops telling you to walk there or marking the spot, even when the same area also holds a quest you have yet to pick up. The marker now sits on the objective itself rather than on the area's edge, and the route no longer moves on to the next area while the one you are in still has objectives left.
- **Your nearest stop first.** The route is now just the nearest action at every step: the closest town to pick quests up in, the closest place to work the quests you are carrying, or the closest turn-in when one is ready. A town's work is finished before the guide moves on, so the list no longer jumps back and forth, and it never sends you back to a stop it has already placed.
- **Pick how the route is ordered.** The nearest-action order is the default, and a new "Optimised route (beta)" checkbox on the Add-ons page switches back to the older order, which leads with a story's chapter, finishes a town's work before leaving it and keeps its earlier suggestions steady. It is experimental, so the simple order stays the default.
- **A trainer hint never crashes the guide.** A Tweaks Forever reply the addon cannot place (a spell with no level) is left out of the next-step hint, like an unknown fee, instead of raising during a rebuild such as a settings change.
- **Find every option in one place.** The Add-ons page now opens a clear Adventure Guide index with Route, Map, Objective tracker and Interface pages, so settings are easier to find without changing the quick switches beside the guide.
- **Keep your story through a reload.** The guide now waits for QuestieDB to finish loading before rebuilding and restarting a saved journey, so the story you chose does not fall back to quests in your log or reset to Home.

- **Arrival cues stop at your objective area.** The quest route stays active while you work, with no direction back to the point you have already reached. Leaving the area brings directions back.
- **Adventure Guide for Classic is optional.** Open its full dungeon and raid journal from the Dungeons tab when it is installed and enabled.

- **Development disclosure.** This release was developed with AI assistance. Changes were reviewed and checked with automated tests, linting and type checks; live verification remains ongoing.

## [0.6.2] - 2026-09-29

- **Always use the newest quests.** Quest data now comes from your installed QuestieDB and nothing else: every quest it knows, including ones outside the guide's old bundled list, and new quests after a Questie update. The addon no longer ships a quest list of its own, so a missing quest can only mean Questie is missing it too.
- **Dungeons and raids come from AtlasLoot.** Bosses and loot come from AtlasLoot, or the game's own encounter journal where AtlasLoot has none. The guide no longer ships its own boss list to disagree with them.
- **Sharper maps from the game.** Map, zone, instance and skill names are read from your client where it can answer, with the bundled route geometry kept for what the client cannot provide (zone level ranges, boats and zeppelins, dungeon entrances, zone art).
- **Trainer hints for every class.** With Tweaks Forever, the guide finds your class trainer even for the extra class and race combinations Forever adds, and a class quest's giver is recognised as its trainer.

## [0.6.1] - 2026-09-29

- **Do less work when suggesting quests.** Route rebuilds reuse quest lists for your level and faction, including dungeon suggestions; your progress and availability are still checked on each rebuild.
- **Keep tracking in one column.** Adventure Guide and companion addons sit above your quests and move together when sections expand or collapse. During Edit Mode, addon sections hide while you position the native quest tracker, then return above it.
- **Identify the quests behind each stop.** Related quests keep their names, levels and difficulty colours in the tracker while Shortest Path handles navigation.
- **Wait for the quest interaction.** With the updated Shortest Path, arriving near a quest giver or objective keeps the route visible until your quest progress changes.
- **See the next ten actions.** Routes continue across successive quest loops, with active steps above alternative destinations. Short routes show clearly labelled upcoming quests; locked quests never become navigation targets.
- **Keep the work between pickup and turn-in.** QuestieDB objective icons are decoded correctly, preserving objective locations even when the icon value is zero. Unknown requirements are left unclaimed until the quest log supplies them.
- **Keep nearby routes visible.** Standing near a town or inside an objective area no longer shortens the route handed to Shortest Path or clears the guide's waypoint.
- **Stay stacked in combat.** The native quest tracker is protected in a fight and returns to its own slot, so the guide's column moves above it instead of overlapping.

## [0.6.0] - 2026-09-28

- **Keep town tracker steps concise.** Pickup and turn-in checklists no longer repeat the same NPC names in a separate summary. Story and resume explanations remain visible.

- **Avoid the remaining guide menu crashes.** The extra hints, settings and right-click actions use the guide’s own menus, with scrolling and nested Back navigation, instead of the native menu path that asserts in Forever build 70009.
- **Keep map updates safe during combat.** Guide pins wait until combat ends and then refresh the current map; delayed map pings also recheck combat. Pickup markers use a per-map quest index while checking your current progress on each redraw.

- **Browse dungeon interiors in the guide.** The Maps tab reads installed Atlas Classic WoW maps and legends, including separate wings and entrances. Maps have separate framed artwork and readable legends. While inside a supported dungeon, its interior also opens on the main map, with Back to map to return to the ordinary view. Atlas and its Classic WoW module are optional; the guide does not bundle their artwork or invent maps when they are absent.

- **See beyond the current quest lap.** View full guide shows ten rows per page: your next actions followed by the area's quest outline. Follow-ups to your active quests come first, with prerequisite quests before their successors. Later quests show their level and difficulty; they become route actions only when Questie confirms availability.

- **Open the guide as a normal window.** Adventure Guide now uses the game’s panel placement by default. Enable Float window in Settings to move it independently. Tweaks Forever’s Windows tab in Edit Mode can move, scale and reset either mode; switching modes waits until combat ends.
- **Match hover to the card.** Clickable cards highlight their own border, following its shape and size instead of drawing an oversized panel-shaped overlay.

## [0.5.0] - 2026-09-28

- **Open the guide as a normal window.** Adventure Guide now uses the game’s panel placement by default. Enable Float window in Settings to move it independently. Tweaks Forever’s Windows tab in Edit Mode can move, scale and reset either mode; switching modes waits until combat ends.
- **Match hover to the card.** Clickable cards highlight their own border, following its shape and size instead of drawing an oversized panel-shaped overlay.

## [0.4.3] - 2026-09-28

- **Avoid the session picker crash.** The No limit control now opens an addon-owned list of session lengths, bypassing the native menu creation path that crashes Forever build 70009. Choose a length, click outside, or press Escape to close it.

## [0.4.2] - 2026-09-28

- **Keep new quest turn-ins on the route.** Completed quests use the game's map marker when no next waypoint or QuestieDB record exists, including Dawn in the Mountains. Standalone turn-in tooltips show the known level and difficulty colour.
- **Make route stops easier to read.** Warm gold rings replace the dim blue tint, and later stops keep their contrast and quest-action badges.

## [0.4.1] - 2026-09-28

- **Separate addon tracking from Blizzard’s layout.** Addon sections now use their own frame pools and sit beside the quest tracker, avoiding the shared tracker registration implicated in Edit Mode aura errors.
- **Check the client integration in CI.** Regression checks run against pinned Forever tracker source and reject native tracker registration.

## [0.4.0] - 2026-09-28

- **The full QuestieDB catalogue.** Quests, giver positions, objective locations and XP now come from the installed provider, without limiting it to the guide's old quest list. Questie checks live pickup availability; the game supplies progress. Enable QuestieDB and Questie for quest recommendations.
- **One set of quest markers.** Questie owns background markers when loaded, including its hide/show switch. The guide keeps its route rings, and Tweaks keeps the native styling.
- **Consistent gold card hover.** Journey and completion cards use the map panel’s warm gold highlight, including cards with tooltips.
- **More useful boss lists.** Gold encounter names, difficulty-coloured levels, encounter classification and known loot counts make the list easier to scan. Click an encounter with recorded drops to open its loot group; native encounter descriptions appear on hover when available.
- **Clear missing-data states.** Missing or incompatible providers no longer silently substitute a smaller quest catalogue. Provider startup, failures, new quest IDs and marker ownership have regression coverage.

## [0.3.3] - 2026-09-28

- **Clickable cards light up on hover.** Completion zones and journey cards show their subtle highlight above the map art, so it is clear which cards you can select. Trainer and other suggestions also highlight; static information cards stay unchanged.

## [0.3.2] - 2026-09-28

- **Bosses without listed loot stay visible.** AtlasLoot still supplies encounter details and loot, while the bundled database fills missing bosses such as Oggleflint and Bazzalan in Ragefire Chasm.

## [0.3.1] - 2026-09-28

- **Boss lists work without extra addons.** A small verified Classic encounter baseline covers every dungeon. Native journal records and optional AtlasLoot enrich it; quest and loot databases remain optional.

## [0.3.0] - 2026-09-28

- **Easier work before harder detours.** Route estimates account for above-level objectives and the counts still left to finish, while keeping useful green and yellow quests available.

- **Every useful destination is visible.** The home view scrolls through all offered journeys, and the window pages through them. Recommendations use your current level and keep useful green and yellow quests, including Redridge and Loch Modan at level 19.
- **Quest routes read more clearly.** Quests in your log replaces Loose ends, with an explanation in its tooltip. Blue route rings keep their pickup, objective or turn-in badge even when several stops overlap.
- **Loot shows its rarity and type.** Item names use their rarity colour, with equipment type, slot and required level underneath. Missing boss records explain the optional AtlasLoot source.

- **Show on map opens the map and marks the spot.** Dungeon givers, prep steps and entrances now open the right zone and pulse the destination. Hovering a map control lights its pin; combat keeps the route without opening the map.

- **Dungeon loot is grouped by boss, with trash at the end.** Items appear once, world drops and junk stay out, and AtlasLoot supplies its boss order when installed. The Today strip's extra suggestions use a small text control.

- **The dungeon guide is easier to read.** Quests your faction, race or class cannot do stay out of the list. Planning is a checkbox, quest rows are tighter, and the details and Today hints have room to breathe.

## [0.2.4] - 2026-09-27

- **Dungeon plans survive without available prep quests.** Planning a run is saved separately from choosing its quest route. AtlasLoot encounters load through its locale-independent difficulty identifier.
- **Tracker initialization avoids native method hooks.** Load-order tests and complete Lua coverage checks now run before publishing.

- **A route keeps its place after a rebuild.** Hand-ins still free space before the same town's pickups, and the next town's work waits for its own lap.

- **Quest givers stay on the right map where zones overlap.** Nalpak and Ebru now point to the Wailing Caverns cave in The Barrens, with the same correction applied to other affected givers and trainers.

- **Plan a dungeon from the guide.** The Dungeons tab lists quests, earlier steps and entrance requirements, with a link to the dungeon journey. QuestieDB adds rewards, enemy ranks and drops when installed; unknown requirements never become pickup suggestions.

## [0.2.3] - 2026-09-27

- **The window names the zone you're in even where the game has no name for it.** The line under the title falls back to the guide's own zone and map names, as search already did.
- **A quest objective the data places off its map is never a step.** A quest under way whose objective area lay outside its zone could send a route off the edge; that objective is now left out, as it already was for new quests.
- **The objective tracker's heading follows a translation.** It uses the guide's name, so a translated title shows there too.
- **The *Include dungeons by default* tooltip says when it applies:** the first time you log in on a character with the guide installed.

## [0.2.2] - 2026-09-27

- **Clicking the journey you already chose in the window no longer restarts it.** The route stays on the stop you'd reached, as it does on the map; a paused route resumes.
- **Wanderer mode means no waypoints on the Professions tab too.** A trainer or vendor step no longer sets one when clicked, and its tooltip stops offering to.
- **A zone you've finished says so.** The Completion tab's Next steps read "No completion categories are available here." once everything was done; it now reads "Nothing left to do here."
- **A quest giver's tooltip always names its quests.** A quest the game hadn't loaded yet showed as "[12]" with no title.
- **The zone you're standing in stays your story when its quests lead into its dungeon.** Dungeon quests counted for picking zones but not for keeping the one you're in.
- **A quest QuestieDB can't say is for your race or class isn't offered.** An unreadable restriction used to count as none.

## [0.2.1] - 2026-09-26

- **Art keeps its shape.** Icons, pictures and row backgrounds are drawn at their own proportions instead of squeezed to fit: the Legacy icon on a Completion card is round in its ring again, step rows and progress bars repeat their middle rather than stretching it, and a card's picture is cropped to the card. Hovering a window card now lights it with a faint blue.

## [0.2.0] - 2026-09-25

- **Ready for translation.** Every line the guide writes itself now lives in one file, so a translation is one copied template in the Locales folder on GitHub. Anything not yet translated stays in English.
- **The guide tells you which companion addon fills a gap.** A route step's tooltip says to install Shortest Path Forever for walked routes and boat times, and the Professions and Completion tabs name SkillUp Forever and Legacy Forever. When one is installed but turned off, it says to enable it instead. *Suggest companion addons* in the settings hides these lines.
- **One line in chat after an update** says what changed, the first time you log in on the new version. Never on a first install; *Tell me what's new after an update* turns it off.
- **Completion says what it can't check yet in words.** A fresh character's flight paths read "Flight paths  1 not known yet" rather than "0/0 · 1 pending", and the zone's line says how to find out, in Legacy Forever's own words: "Open a flight master on this continent to check these."

## [0.1.1] - 2026-09-25

- **An empty progress bar stays in its card.** The PvP tab's rank points bar at 0, and a Completion zone with nothing done yet, drew their bar across the whole window; they now show an empty bar where it belongs.

## [0.1.0] - 2026-09-25

- **The first release: a few journeys to choose from on the world map, each with a reason, and a short route for the one you pick.** I wanted the game to suggest what to do next without handing me a fixed guide.
- **An Adventure Guide tab on the world map's quest log** offers up to six journeys: finish the quests you carry, follow a zone's story, or head to the next zone with enough quests for your level. The chosen journey shows its steps, up to nine, so you choose where to go rather than being handed a list. The same journeys open in their own window with `/agf`.
- **The map's journey cards fit on one page.** Compact full-width rows keep titles and details on one line, with the full text on hover. Smaller maps offer a link to the Adventure Guide window for the remaining journeys; the overview no longer scrolls.
- **Zone stories read as chapters.** A chain shows "Chapter 2 of 4" only when the quest data proves how long it is, and never names a later chapter, so the story is not spoiled. Finishing a story of known length glows the tracker once and plays the game's stage-end sound.
- **Choosing a journey starts its route.** The map turns to the journey's zone and hands its steps to Shortest Path Forever as one journey, or sets the game's own waypoint without it, or when Shortest Path can't plan the trip. A setting makes choosing preview only; Go in a step's menu starts from there.
- **A stop is a town.** Everything to hand in and pick up in one place is one step, "Lakeshire, Redridge" with "2 to hand in, 4 to pick up", and Shortest Path takes you to the giver nearest the stop before. Its tooltip lists each NPC's quests with their level, in the quest log's difficulty colours. Hand-ins come first, then quests about to turn grey, then those nearest your level.
- **Cards tell you the cost of a choice.** With Shortest Path Forever each card shows the minutes to its first stop ("11 min", or "11 min by boat" where it fits), its first town and how many stops follow, and a group tag when any of its quests needs a group. Hover a card for all of it. The guide asks for one estimate a frame, and none in combat.
- **Stop only removes what the guide set.** A waypoint you placed or moved yourself survives Stop, even after a `/reload`. The Stop button goes as soon as Shortest Path ends the journey or you clear the waypoint yourself.
- **A journey lasts until you finish it.** The card you chose stays through a new quest, a level-up or travel: head to Redridge and it becomes the Redridge story on arrival. The route follows the journey as towns empty or you're taken elsewhere, comes back after a `/reload` or login, and says "Journey complete" in the tracker when your last hand-in ends it. If you clear the route in Shortest Path or another journey replaces it, the footer says so, and a click on the card or the tracker title resumes it.
- **Routes cross the sea at most once.** Steps are ordered by distance, a far turn-in never pushes out a nearby pickup, and a quest to hand in on another continent waits at the end with "Hand in when you're in Stormwind City".
- **Search shows why a quest isn't offered.** Type three letters or more and each match lists what the data says it needs, ticked when you meet it: level, earlier quests, race, class or faction.
- **An Adventure Guide section in the objective tracker** shows the current step, how you'll travel there with Shortest Path Forever ("Fly to Sentinel Hill · 6 min"), and the step after. Click its title to start the route; tracking the route's quests is a separate, opt-in setting. Right-click for Go, Skip for now or another journey. After a login, when step 1 is still the step you stopped on, it says "Where you left off".
- **Clicking a quest from your log** in the guide or the tracker opens Blizzard's own quest details, never in combat.
- **Dungeon quests only when you ask.** Turn on *Dungeons* in the guide's settings menu and a card offers the dungeon with the most quests you can take, routed to their quest givers. Raids are never suggested. Quests already in your log always show, whatever the filters.
- **Visit your class trainer** appears above the steps when Tweaks Forever says you have new spells to train. It names the nearest suitable trainer's town when the data places one, and clicking it routes there. A chosen journey passing that town can add a training stop.
- **The map stays yours.** With the tab closed the guide draws nothing on the world map. Route pins and a "!" over every quest giver with a quest you can take now are opt-in under *Show map pins* and *Show quest givers*.
- **Skip for now** hides a step until your next `/reload`; *Skipped (n)* under the steps brings one back.
- **The window has PvP and Completion tabs.** PvP shows your rank, the points to the next and its reward, and the battlegrounds open at your level with the nearest battlemaster. Completion reads Legacy Forever: how much of your zone and the next ones you've done, and the next three things to do there. Without Legacy the tab greys and says so.
- **Pick how long you've got.** A dropdown over the steps takes No limit, 15, 30 or 60 minutes, and shortens the route using rough travel and quest-time estimates, with "About 25 min" under it.
- **Put the steps in your own order.** Drag one onto another, or right-click for *Do this next*, *Do this sooner* or *Do this later*. Moves that would break the route are greyed out, the card says "Your order", and *Back to suggested order* undoes it.
- **A town lists its quest givers** under its step, ticked as you finish with each; right-click the town to skip one. Each step's ring shows what it is: a "!" to pick up, a "?" to hand in, the objective mark, a trainer or a battlemaster. A town the route comes back to keeps one map ring with "+1".
- **Go to entrance** on a dungeon card takes you to the way in when Tweaks Forever knows it. The window's Today line shows three and "+2 more" when there's more, including setting your hearth.
- **The window opens with Shift-J** the first time, when nothing else has that key, and a line in chat says so. Change it under *Key Bindings*.
- **The Professions tab reads SkillUp Forever:** your next recipes in their difficulty colours with the training fee, the next steps and the reagents to buy. With two crafting professions a picker switches between them; without SkillUp the tab greys and says why.
- **Other things to do show above the steps.** "You have 2 talent points to spend" while any are; a profession rank at its cap, naming the next rank's trainer, or a free profession slot; "You haven't seen" an area of the zone yet; and, when your rested XP is low, a route that ends "Rest at the inn here".
- **No quest three or more levels up is offered.** At 19 in Redridge the story no longer sends you into a Blackrock camp for a level 25 quest. The map's "!" still shows those givers, as the game does.
- **A breadcrumb is offered only until you take the quest it leads to,** and its card says so.
- **QuestieDB supplies the quest data when it is loaded,** on its own or with Questie. The bundled data fills what it leaves out, and nothing from Questie ships with the addon.
- **A quest the data can't check is never suggested,** and a step never points at a place the data doesn't have. Quest and zone names come from the game, in your language.
