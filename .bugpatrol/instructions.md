# About the app

Adventure Guide Forever is a World of Warcraft: Forever addon written in Lua 5.1. It cannot run
outside the game client, and you must never start the game. What runs here is its headless test
harness: each `tests/<name>_spec.lua` stubs the client API, loads the addon files the TOC lists, and
checks one feature. Run a spec with `luajit tests/<name>_spec.lua`; a failing spec exits non-zero and
prints the failed assertion. `luacheck <file>` lints a file.

Some specs need a corpus: `python3 tools/gen_corpus.py` builds it into `tests/.corpus/`, which is never
committed. Run it once before the specs if a spec complains the corpus is missing.

`luajit -joff tests/plan_bench.lua` times the planner and is part of the suite.

Use the specs and `luajit -e` one-liners that load the harness to check what a change claims. Report a
spec that fails, an error that a spec prints, or a behaviour a spec shows that the change does not
intend.

## Sign in

No sign-in.

## Important flows

- Choosing a journey from the world map's quest log, and following its route: the tracker section with
  the current stop and the next two, and the map pins.
- Quest search: the best match first, each quest's requirements under it, and the wanderer mode that
  suggests quests for the level.
- Settings: the tooltips on the guide's options, and the ones that attach the shared tracker.
- The report and issue windows from the help menu.

## Never do these things

- Never launch the game, Battle.net, Lutris or Wine.
- Never edit, move or delete files.
- Never use the network.
