# Changelog

What changed in each release, in the terms someone levelling a character would notice. Dates are UTC.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html). The entries are prose rather than bare
Added/Fixed lists: what matters about a release is why the guide now sends you somewhere different.

Each version's entry is also its release notes on GitHub, CurseForge and Wago. Older entries are kept
verbatim rather than rewritten as the addon moves.

## [Unreleased]

- **The route's next stop stands out on the map.** Its numbered ring is lit the way the game lights the quest it tracks, and the later stops keep the plain ring.
- **Quest data loads sooner after a login or a reload.** The build read a quest giver's place from QuestieDB, then asked again which side it serves and whether it keeps an inn; it now reads each one once and lets the objective pass share the spawns it already has.
- **A plain quest giver is no longer called a class trainer.** When the bundled trainer list did not name the giver of a class quest, the quest's class was stamped on it, so the calling card said "Your class trainer has a task" for someone like Harry Burlguard or Islen Waterseer. A giver counts as a trainer only when QuestieDB's own NPC flags mark it as one.
- **A chain with one prerequisite now shows its total.** QuestieDB files a lone prerequisite as one of several alternatives, so a chain containing one was shown as a chapter with no total. A single alternative now reads as the one quest it requires, so those chains show "Chapter 2 of 8" instead of a bare chapter.
- **The guide no longer offers quests your character cannot take.** A quest gated behind a profession rank or a reputation standing is read from QuestieDB with its requirement, so a route no longer sends you to a pickup the game would refuse.
- **The guide works for every race.** A character of the race the game numbers 32 got an "integer overflow" error when the guide planned or the map opened; its routes now plan like any other race's.
- **The guide's map data matches the current game build.** The maps, flight masters and Forever's own lands the guide carries are read from client build 1.60.1.70205. The Stormwind flight master sits where the game now has it, and the guide no longer plans steps on the Alterac Valley battleground map, which the game no longer lists as a zone.
- **A route settles the first time it is drawn.** With a nearly full quest log, a route could put a hand-in last, then move it up to second a moment later with nothing changed. The order you first see is now the one it keeps.
- **The story finishes the zone it is in.** While the zone the story led with still has work, the guide keeps leading with it instead of swapping to the zone the ranking likes a little better that level, and it does not go straight back to a zone it just left. The choice survives a reload, so the lead no longer flips back and forth between two zones.

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
