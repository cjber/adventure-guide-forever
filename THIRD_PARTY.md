# Third-party inputs

Everything Adventure Guide Forever is built from that it did not write itself: where each comes from, where its pin
lives, its licence, and whether any of it reaches the zip players install. A pin is named by the constant that holds
it, so a data refresh that moves the pin never leaves this file behind. The addon itself is GPL-3.0-or-later
([LICENSE](LICENSE)).

## Ships in the zip

| Input | Used for | Pin | Licence |
|---|---|---|---|
| WoW: Forever client tables, via [wago.tools](https://wago.tools) | Zones, maps, crossings, overlays and new quests in `Data/Geometry.lua`, `Data/Forever.lua` and `Data/ZoneArt.lua` | `BUILD` in `tools/gen_quests.py`; `LEGACY_MAP_BUILD` there for the old map areas | Blizzard Entertainment's game data |
| Classic Era client tables, via wago.tools | What Forever added over Classic Era, in `Data/Forever.lua` | `ERA` in `tools/diff_forever.py` | Blizzard Entertainment's game data |
| [CMaNGOS classic-db](https://github.com/cmangos/classic-db) | Trainer roles, profession ranks, dungeon entrance requirements and boat routes in `Data/Geometry.lua` (the WFA-28 waivers in `AGENTS.md`) | `CLASSICDB_COMMIT` in `tools/gen_quests.py` | GPL-3.0 |
| [Warcraft Wiki: Zones by level (original)](https://warcraft.wiki.gg/wiki/Zones_by_level_(original)) | The original zones' level ranges, typed into `PUBLISHED` in `tools/gen_quests.py` | `ZONE_SOURCE` there; the table is the pin | Facts cited from the wiki; no text copied |

No embedded libraries ship.

## Read in game, never bundled

| Input | Used for | Licence |
|---|---|---|
| [QuestieDB](https://github.com/Questie/QuestieDB) and Questie, installed by the player | Quest records, NPC places and towns (WFA-2 and WFA-28 in `AGENTS.md`) | QuestieDB carries no licence; nothing is copied |
| AtlasLoot Classic, if installed | Dungeon loot in the Dungeons tab | Its own; nothing is copied |
| Shortest Path Forever, if installed | Routes to each step, through its public API | GPL-3.0-or-later |

## Build and test only

| Input | Used for | Pin | Licence |
|---|---|---|---|
| QuestieDB Forever release | The test corpus in `tests/fixtures/` (`tools/gen_corpus.py`) | `QUESTIEDB_TAG` and `QUESTIEDB_SHA256` in `tools/gen_corpus.py` | No licence; test fixture only |
| [Blizzard UI source](https://github.com/Gethe/wow-ui-source) | The native tracker integration spec, fetched into `tools/.cache/` | `REVISION` in `tools/fetch_tracker_ui.py` | Blizzard Entertainment's; fetched, never committed |
| Shortest Path Forever types and source | The API contract spec and the map screenshots | `SPF_SHA` in `tests/contract_spec.lua` and `tools/screenshots_spf.py` | GPL-3.0-or-later |
| [Ketho's WoW API annotations](https://github.com/Ketho/vscode-wow-api) | lua-language-server types in `tools/typecheck.sh` | `revision` in `tools/typecheck.sh` | MIT |
| [forever_tools](https://github.com/cjber/skills/tree/main/wow-forever-addon/tooling/forever_tools) | Shared lints, release checks and the generated-data gate, vendored in `tools/forever_tools/` | `revision` in `tools/forever_tools/MANIFEST.json` | MIT |
| [wow-mock-screenshots](https://github.com/cjber/skills/tree/main/wow-mock-screenshots) and the client art it fetches | `tools/screenshots.py` | `WOWMOCK` (a local checkout); the art at `BUILD` in `tools/gen_quests.py` | MIT; the art is Blizzard Entertainment's |
| AtlasLoot Classic data | Loot in the screenshots (`tools/screenshot_loot.lua`) | A local install (`AGF_ATLASLOOT`) | Its own; only `docs/screenshots/loot.png`, which shows the items it lists, is committed |
| sift gate | `.sift/gate.py` and `.sift/agents.py` in CI | Vendored by `sift setup` | MIT (`.sift/LICENSE`) |

CI tools (StyLua, ruff, luacheck, lua-language-server, actionlint, zizmor, gitleaks, the BigWigs packager) are pinned in `.github/workflows/` and `tools/typecheck.sh`, except luajit and luacheck, which come from the runner's apt; they build and check the addon and are never part of it.
