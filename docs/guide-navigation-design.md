# Adventure Guide navigation

## Purpose

Help a player who opens the guide answer: what can I do next, why does it suit me,
and how do I get there? The guide should feel like a Classic quest journal. A player
should not need to understand the addon's modules or companion APIs to choose an activity.

## Main page

Journeys is the main page and the first page for a new character. Suggestions share its featured area with route guidance.

When following a journey, the featured area shows its name, current objective and
live count, a short reason or destination, and the next two steps. Its primary action
is Show on map or Resume. Stop is a smaller secondary action. Changing pages or
inspecting another activity never changes the chosen journey or waypoint.

Without a chosen journey, this area shows one useful suggestion and why it suits
the character. Start journey is explicit. A trainer visit can instead say Visit
trainer; unspent talents are advice with no travel button. Do not invent locations.
The existing destination art supplies atmosphere behind readable text, without
making every suggestion a large decorative card.

Below it, a collapsed Other adventures section offers alternatives. Browse opens
details; Start commits the choice. Keep session length beside journey controls.
Class spell reminders and automatic spell-training visits are off by default; an
explicit Route setting enables them. Unspent talent and profession hints remain
independent. Show each enabled trainer or profession hint once, as a compact contextual row, rather
than repeating it in the featured area and the Today strip are removed.

## Navigation

Keep three top-level destinations, using the existing stock journal frame and tabs.

| Destination | Contents |
| --- | --- |
| Journeys | Current adventure, one next suggestion, alternatives and session length |
| Activities | Dungeons, professions and PvP, selected from a left-hand list |
| Progress | Completion categories and character milestones |

Activities opens the last inspected category. Its left-hand list makes the available
categories visible without adding another horizontal tab bar. Dungeon Quests, Prep
and Maps remain local controls inside a selected dungeon. Profession recipe and
training detail remain local to professions. Progress stays separate from dungeons:
exploration, reputations and quest completion are broader character interests.

Map pins, journey cards and tracker menus open the same relevant detail view.
Back returns to the previous list and preserves its selection and scroll position.
Settings remain in the existing cog. Do not add another permanent preference row
to the main page; infer useful suggestions from the character and expose deliberate
activity browsing when the player wants a different kind of task.

## Recommendation meaning

Dungeon browsing lists all suitable instances, including Deadmines when its range
fits the character. A featured dungeon explains its ranking, such as accepted
quests or nearby preparation. Eligible quest count alone must not hide every other
suitable dungeon. Preserve a deliberately chosen dungeon until it ends or is stopped.
Quest preparation and a dungeon run are distinct actions: a questless dungeon can
be browsed without fabricating a quest route.

Quest destinations may include a valid low-level errand in a high-level zone.
Label this as a quest visit, show the zone's recommended range as a warning, and
explain the actual task. Never call every such destination a zone for the player's
level. Prefer normal questing areas over distant isolated errands when recommending
a new levelling journey; keep explicit visits available in browsing.

## States and actions

| State | Presentation and behavior |
| --- | --- |
| Active journey | Current objective and count agree with tracker and Shortest Path; Show on map |
| Paused journey | Keep the same journey visible; Resume is explicit |
| Browsing another activity | Preserve active journey; show a preview and explicit Start action |
| Quest source building | Explain that quest suggestions are loading; do not publish a partial quest route |
| Quest source unavailable | Explain QuestieDB or quest-policy requirement only in the affected quest view |
| No profession suggestion | Explain what is known about training or SkillUp availability, without a quest error |
| No suitable dungeon | Keep the dungeon catalogue browsable and explain level or source limitations |
| Unknown destination | Show advice or detail without a travel action |
| Combat | Disable restricted actions immediately; browsing remains available |
| Wanderer mode | Keep advice and previews; explain why travel controls are disabled |

Missing optional providers must never throw a Lua error. Distinguish no offer from
unknown data. Buttons must visibly open a view, perform their named action, or
explain why they are unavailable; a focus change that leaves the same blank page is
not sufficient feedback.

## Map and tracker

The tracker shows the current action once, its live progress, and the next destination.
Use the active journey's title as its single section heading, such as Ashenvale story,
in place of Adventure Guide. Put the current action, such as Turn in: Bathran's Hair,
beneath it in the normal objective style. Do not repeat the journey title as another
block or stack it beneath an addon heading. Without an active journey, the heading
falls back to Adventure Guide; the icon and tooltip retain the addon's identity.
Show the current objective with its action icon, then up to two upcoming objectives
with smaller icons and muted text. Keep the preview in route order and update it
after progress changes. Hide it when there are no further objectives, and keep the
current objective readable when space is limited. Keep zone context secondary.
Avoid repeating a whole quest title on every line.
Progress changes update the existing route label rather than restarting it.

On a map pin, the original icon or numbered disc remains readable. Put a small
action badge in its lower-right corner, preserving native aspect and the click
target. Use the same treatment for AGF and Shortest Path numbered stops. A route
selected by shift-click wears a corner tag on the clicked icon. Do not stack a full-size
sword over the disc or add a second central marker at the same point.

## Story completion

Finishing a proven story shows an achievement-style popup: Story complete, the story
name, a small quest or destination icon, warm gold trim, a brief glow and the existing
completion sound. Use the client's visual language in an addon-owned frame. This is
a guide milestone, so it must not claim to award a Blizzard achievement or achievement
points. It fades without requiring a click; optional interaction can open its completed
story entry when the player chooses.

Use the existing verified story-ending turn-in signal. A route becoming empty, a zone
change, a skipped quest or an unavailable provider does not complete a story. Persist
the announcement by stable story identity per character, suppress repeats on reload,
and do not announce historical completions on login. Completion is independent of
whether the tracker or guide is visible. Queue simultaneous completions and avoid
covering existing alerts or replacing a popup already being shown. Defer presentation
if the relevant client UI is not ready, without losing the completion.

The tracker can retain its completed-story line, but the milestone plays one sound
and one visual celebration. Reuse that same completion record in Progress.

## Implementation

1. Fix missing-catalogue errors and misleading empty states with regression tests.
2. Fold recommendations into the existing Journeys featured area. Remove the Next
   page registration and route saved `next` selections to Journeys. Normalize the
   obsolete focus preference without resetting chosen journeys or window placement.
3. Group professions, PvP and dungeons under Activities. Migrate their saved page
   selections to a category key; preserve selected dungeon, floor and profession.
4. Make inspection and commitment distinct. Reuse Guidance, Session and companion
   APIs as the only sources of route ownership and live progress.
5. Review dungeon alternatives and zone-visit ranking, with fixtures that include
   level-21 Deadmines, Wailing Caverns and a low-level Theramore errand.
6. Verify map badge sizes in both addon renderers and refresh previews and player docs.
7. Add the story completion popup using the existing proven chain-ending signal,
   with per-character deduplication and a queue independent of tracker visibility.

## Acceptance

- A new character opens Journeys and sees one understandable next action.
- The window has three top-level destinations and no permanent focus-button row.
- Following, paused and stopped journeys have distinct actions and survive reload.
- Opening dungeon or profession details never changes the active route.
- QuestieDB absent, building, incompatible and ready states produce no errors;
  training and profession views do not show unrelated quest-policy messages.
- Dungeon controls open their detail view. A level-21 character can inspect both
  Deadmines and Wailing Caverns when appropriate; exclusions explain their reason.
- A high-level zone visit identifies its eligible quest and its zone warning.
- Completing an objective updates the main page, tracker and Shortest Path count.
- An active story uses one tracker heading with its action below it; the generic
  Adventure Guide heading and a duplicate story-title row are absent.
- Long names, UI scale and compact layouts keep text and controls readable.
- Pin badges leave the original icon or numeral readable, at normal and zoomed scales.
- A final story hand-in produces one named completion popup, including with the
  tracker hidden. Intermediate hand-ins, abandoned routes and reloads do not.
- Two stories completed together queue their popups; sound and progress records
  are not duplicated.

## Design review

Pi reviewed the current window modules and proposed either adding a recommendation
header above Journeys or replacing its featured area. Replacing the featured area
avoids duplicate actions and uses the space already available. This design also
removes the proposed segmented focus control: activity browsing already serves that
choice. Completion stays in Progress rather than being nested under Dungeons.

This document describes the guide navigation and its acceptance checks.
