# Helping you choose your next adventure

The guide should help a player who has logged in, finished a quest or reached a city decide what to do next. It should offer a reason and a useful first action, while leaving room to wander.

```mermaid
flowchart TB
  Player[Level, quest log and player choices] --> Offers[Eligible journeys and useful hints]
  Offers --> Next[One next action and a few alternatives]
  Next --> Choice[You choose]
  Choice --> Route[Existing journey or known destination]
  Route --> Progress[Live quest progress]
  Progress --> Offers
  classDef guide fill:#332719,color:#ffe4a1,stroke:#ad8b50;
  class Player,Offers,Next,Choice,Route,Progress guide;
```

## Guide

Journey brings the current adventure, upcoming steps and useful next actions together. Activities offers journeys, professions and PvP; Progress records story milestones. Collection and zone completion stay in Legacy Forever. The navigation and action contracts are in [guide-navigation-design.md](guide-navigation-design.md).

## Next steps for the wider guide

1. **Context before leaving town.** Group useful errands by their proven location, show which fit the current trip, and distinguish learning a new profession from advancing one the character already has. Keep optional errands separate from quest route progress.
2. **Progression goals.** Let the player name a goal such as a zone story, class milestone or dungeon preparation. Explain the next proven prerequisite and retain the goal across travel and reloads. Build on the current journey and planned-dungeon state instead of another route system.
3. **Better choices for the time available.** Apply the existing session estimates to comparisons between journeys. Show an estimate only when both travel and required work are known, and never leave a newly picked-up quest without its planned return.
4. **Crafting choices.** Bring useful actions from SkillUp into Activities through its public API. Keep collection and zone completion in Legacy Forever, reached through the Progress map link.
5. **What happens after a milestone.** Offer a quiet explanation of the next available chapter, training opportunity or destination after a level or story ending. Keep unknown requirements explicit, and leave fixed walkthroughs, boss advice and loot selection to their existing sources.

Each step needs source-backed eligibility, a visible reason, reversible player choices and checks for missing companions, stale data, combat, reload and frame cost. No recommendation depends on a guessed location or on reading a companion's private tables.

## Client checks

- Open `/agf` on a character with no saved tab, then reload with another tab selected.
- Browse every Activities category. Check that the tracked journey and waypoint do not change until an action is pressed.
- Start an offered journey, stop it, then choose another in Activities. Repeat with Shortest Path disabled.
- Dismiss a hint or complete the leading task and check that the page updates without an old action remaining active.
- Walk between city districts, enter and leave combat, and check trainer destinations and profession hints.
- Check Journey with no suggestions, a text-only hint, Wanderer mode and a missing Questie source.

The repository's headless checks and generated previews cover the logic and layout. These client checks remain necessary before merging a player-visible change.
