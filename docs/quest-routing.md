# Quest difficulty and route choices

Classic routes balance fighting, recovery and travel. Quest colour alone is not a speed estimate: a level-21 quest is yellow at level 19, but may still take longer than nearby level-17 work. A zone's minimum level does not mean every quest there is a good next step.

Research checked on 2026-09-27:

- [Icy Veins: Classic leveling](https://www.icy-veins.com/wow-classic/leveling-guide), sections 5 and 5.3: balance combat, recovery and travel; finish efficient chains and favour lower-level content when higher-level work slows you down. Its broad Alliance route stays in secondary zones through 21.
- [Wowhead: Alliance zones](https://www.wowhead.com/classic/guide/alliance-leveling-classic-wow): Loch Modan remains a 10–20 option; Redridge becomes useful near 20. These are overlapping choices, not a requirement to finish one entire zone before leaving.

The guide uses those principles with the character's actual quests, including Forever additions, instead of copying a fixed Classic quest sequence:

- Offer all eligible zones with useful green/yellow work; don't recommend new orange/red quests.
- Keep pickups, grouped objectives, turn-ins and prerequisites in a coherent route.
- Estimate objective work from remaining counts. Three of ten means seven remain; it is not a separate sunk-progress bonus.
- Charge above-level objectives more work: `1 + 0.5 × max(0, questLevel − playerLevel)²`. This is a conservative tuning heuristic, not a measured kill-time formula. +1 costs 1.5 times base work; +2 costs three times.
- Apply that cost to new-quest value, lap size and choosing between nearby laps. Useful green work has no difficulty penalty. Completed turn-ins have no combat penalty.
- Keep a committed route stable; proximity, shared work and a player's explicit choice still matter. A harder yellow quest can remain worthwhile.

These inputs cannot prove optimal XP/hour: actual enemy levels, drop rates, class, gear, crowding and group strength are not yet measured. Regression fixtures cover the level-19 / level-21 / 3-of-10 case and retain all useful zone options.
