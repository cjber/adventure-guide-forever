# Third-party inputs

Everything Adventure Guide Forever is built from that it did not write itself: where each comes from, where its pin
lives, its licence, and whether any of it reaches the zip players install. A pin is named by the constant that holds
it, so a data refresh that moves the pin never leaves this file behind. The addon itself is GPL-3.0-or-later
([LICENSE](LICENSE)).

## Ships in the zip

| Input | Used for | Pin | Licence |
|---|---|---|---|
| WoW: Forever client tables, via [wago.tools](https://wago.tools) | Zones, maps, crossings, overlays, faction territories and new quests in `Data/Geometry.lua`, `Data/Forever.lua`, `Data/ZoneArt.lua` and `Data/Territory.lua` | `BUILD` in `tools/gen_quests.py` (also read by `tools/gen_territory.py`); `LEGACY_MAP_BUILD` there for the old map areas | Blizzard Entertainment's game data |
| Classic Era client tables, via wago.tools | What Forever added over Classic Era, in `Data/Forever.lua` | `ERA` in `tools/diff_forever.py` | Blizzard Entertainment's game data |
| [CMaNGOS classic-db](https://github.com/cmangos/classic-db) | Trainer roles, profession ranks, dungeon entrance requirements and boat routes in `Data/Geometry.lua` (the WFA-28 waivers in `AGENTS.md`) | `CLASSICDB_COMMIT` in `tools/gen_quests.py` | GPL-3.0 |
| [Warcraft Wiki: Zones by level (original)](https://warcraft.wiki.gg/wiki/Zones_by_level_(original)) | The original zones' level ranges, typed into `PUBLISHED` in `tools/gen_quests.py` | `ZONE_SOURCE` there; the table is the pin | Facts cited from the wiki; no text copied |
| AI-assisted originals in `tools/number_source/` | The gold numbered route markers in `media/Numbers/<n>.tga` and the empty `Ring.tga` | The source files and `tools/export_numbers.py` | This addon's own; no Blizzard art |

No embedded libraries ship. `media/` is this addon's own: the icon is drawn in `media/icon.svg`, and the numbered markers are keyed from the originals in `tools/number_source/`.

## Read in game, never bundled

| Input | Used for | Licence |
|---|---|---|
| [QuestieDB](https://github.com/Questie/QuestieDB) and Questie, installed by the player | Quest records, NPC places, towns and the library books (WFA-2 and WFA-28 in `AGENTS.md`) | QuestieDB 1.0.16 ships a LICENSE.md (GPLv3 from 2026-10-21) and treats earlier content as all rights reserved; nothing is copied |
| AtlasLoot Classic, if installed | Dungeon loot in the Dungeons tab | Its own; nothing is copied |
| [RestedXP Guides](https://github.com/RestedXP/RXPGuides), if installed | The current guide's steps in the Adventure tab and tracker: read from its loaded tables and hooks, and its steps skipped or advanced through its own step controls | CC BY-NC-SA 4.0; nothing is copied, and `tests/rxp_fixture.lua` holds only original example steps |
| [Polestar](https://github.com/fitzforge/polestar), if installed | Whether it has a guide running, from `Polestar.Engine.GetGuide()` and its `GUIDE_CHANGED` message, so the route steps aside | GPL-3.0; read only, nothing is copied |
| Shortest Path Forever, if installed | Routes to each step, through its public API | GPL-3.0-or-later |
| SkillUp Forever and Tweaks Forever, if installed | The Professions tab, and class trainer places and dungeon entrances, through their public APIs | GPL-3.0-or-later |

## Build and test only

| Input | Used for | Pin | Licence |
|---|---|---|---|
| QuestieDB Forever release | The test corpus, `quests.lua`, `towns.lua` and `books.lua` in the gitignored `tests/.corpus/`, built from the release at test time by `tools/gen_corpus.py` | `QUESTIEDB_TAG`, `QUESTIEDB_ASSET` and `QUESTIEDB_SHA256` in `tools/gen_corpus.py` | 1.0.16's LICENSE.md is GPLv3 and treats earlier content as all rights reserved, so the corpus is fetched for the tests and never committed or shipped |
| Shortest Path Forever types and source | The API contract spec and the map screenshots | `SPF_SHA` in `tests/contract_spec.lua` and `tools/screenshots_spf.py` | GPL-3.0-or-later |
| [Ketho's WoW API annotations](https://github.com/Ketho/vscode-wow-api) | lua-language-server types in `tools/typecheck.sh` | `revision` in `tools/typecheck.sh` | MIT |
| [forever_tools](https://github.com/cjber/forever-core/tree/main/.agents/skills/wow-forever-addon/tooling/forever_tools) | Shared lints, release checks and the generated-data gate, vendored in `tools/forever_tools/` | `revision` in `tools/forever_tools/MANIFEST.json` | MIT |
| [forever-core/tools/wowmock](https://github.com/cjber/forever-core/tree/main/tools/wowmock) and the client art it fetches | `tools/screenshots.py` | `FOREVER_CORE` (a local forever-core checkout); UI art at the independently reviewed `UI_ART_BUILD`, and map/content data at `DATA_BUILD` (the `BUILD` pin from `tools/gen_quests.py`) | MIT; the art is Blizzard Entertainment's, fetched at build time and committed only as it appears in `docs/screenshots/` |
| AtlasLoot Classic data | Dungeon loot fixture in `tests/scenes.lua` | The fixture in that file | Its own; no AtlasLoot addon code or tables are bundled |
| Forever Core native simulator | `tools/forever_sim/`, used by `tests/sim/` | Revision in `tools/forever_sim/MANIFEST.json`; Blizzard inputs pinned by its fetcher | GPL-3.0-or-later; development only. Downloaded Blizzard source and data are not shipped |
| Ko-fi's Support me on Ko-fi button | The support button in the README (`ko-fi.com/img/githubbutton_sm.svg`) and its PNG render, `docs/kofi-button.png`, in the store description | None: the README links Ko-fi's live file; the PNG is rendered from it | Ko-fi's brand asset, used as Ko-fi provides it for linking to a Ko-fi page |
| `docs/github-sponsors-button.png` | The GitHub Sponsors button in the README and store description; drawn here to match the Ko-fi button, with the heart from GitHub's [Octicons](https://github.com/primer/octicons) and the Adwaita Sans font | None | Octicons: MIT; Adwaita Sans: SIL OFL 1.1 |
| `docs/discord-button.png` | The Discord button on the store page; drawn in forever-core with Discord's logo from [Simple Icons](https://simpleicons.org) and the Adwaita Sans font | None | Simple Icons: CC0; Adwaita Sans: SIL OFL 1.1; the logo is Discord's, used to link to a Discord server |

CI tools (StyLua, ruff, luacheck, lua-language-server, actionlint, zizmor, gitleaks, the BigWigs packager) are pinned in `.github/workflows/` and `tools/typecheck.sh`, except luajit and luacheck, which come from the runner's apt; they build and check the addon and are never part of it.

## Players

Credit for the reports and requests behind the addon.

| Who | What | Notes |
|---|---|---|
| VinzNL | Battlegrounds left out of suggestions | GitHub; #62 |
| fuguer-ai | Read-only API for the current stop | GitHub; #79 |
| rhednak | Fixed the overflow that broke Skyborne guides | CurseForge; 0.8.0 |
| jechten | Faster login | CurseForge; #166 |
| Gnatz_0815 | RestedXP's item and target windows kept | CurseForge; #237 |
| CodeHoax | Fixed the RestedXP overview-header error | GitHub; #233 |
| starkovsky | Near-level quests lead the route | GitHub; #474 |
| starkovsky | Ira's Dagger starts from its item | GitHub; #591 |
| starkovsky | Journey cards clickable with the map open | GitHub; #592 |
| eliasbusato | RestedXP target buttons respond to clicks | GitHub; #550 |
| wfournier | Journey cards select the guide again | GitHub; #590 |
| InfamousMunky | Journey cards select the guide again | GitHub; #599 |
| sampconrad | Next step handed to Waypoint UI | CurseForge; #482 |
| sampconrad | Arrival keeps a pin with the objective | CurseForge; #565 |
| methabolic | Next step stays after a town trip | CurseForge; #554 |
| kragmars | Map quest tabs no longer fight Queston Forever | Discord; #542 |
| Naburiel | Faster login | GitHub; #166 |
| vladsnz | Marker no longer taken from another guide | CurseForge; cjber/shortest-path-forever#531 |
| jixxor | Show of Force held until Encroaching Gnolls is done | Discord; #642 |
| InfamousMunky | Daily Delivery no longer offered once handed on | GitHub; #629 |
| lanprite | The guide's target button kept its own row under the step | Discord; cjber/shortest-path-forever#787 |
| InfamousMunky | Library books journey | GitHub; #706 |

## Inspired by

Credit for the addons and projects an idea came from.

| Who | What | Notes |
|---|---|---|
| [Polestar](https://github.com/fitzforge/polestar) by Fitz | Ideas for many features | Tracker tooltips, objective matching, ranked search, waypoint hysteresis, step actions and camp weighting; the shared report window, issue forms and addon tooling. GPL-3.0. Inspired only; no code was copied. Fitz is welcome to use our code. |
| [Pawn](https://www.curseforge.com/wow/addons/pawn) by Vger | Marking a quest reward that beats your gear | Inspired only; no code was copied. A narrower version that steps aside when Pawn is loaded. |

Thanks also to everyone else who reported a bug or asked for a feature, here or on CurseForge.
