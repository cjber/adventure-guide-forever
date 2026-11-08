# About the app

Adventure Guide Forever is a World of Warcraft: Forever addon written in Lua 5.1. The game cannot run
here, so what is measured is the planner under its own headless bench, which stubs the client API and
loads the addon files the TOC lists, in order.

One benchmark, `kind: command`, runs `luajit -joff tests/plan_bench.lua`. The script fails when a frame
is over its budget, with three times the measured time allowed unless `AGF_BENCH_STRICT=1`. Some specs need the corpus
that `python3 tools/gen_corpus.py` builds into `tests/.corpus/`, so run that once in a fresh checkout
before measuring anything that depends on it.

Wall time includes luajit's own startup, so a change under about 10 percent will not be visible. A
`custom` benchmark printing the planner's own milliseconds would remove that noise; it is the
improvement to make if these numbers prove too coarse.

Anything worth keeping also has to pass the repo's gate, with lua-language-server 3.19.1 and stylua
2.5.2, the CI pins rather than whatever this machine has installed.

## On pull requests

`.github/workflows/speedpatrol.yml` runs `speedpatrol compare` on every pull request: three A/B rounds
against the base branch, over `planner.plan` only, failing the job on a regression. CI's `check` job runs the same bench,
which fails a rebuild or travel frame over its 3 ms budget.

## Never do these things

- Never start the game, Battle.net, Lutris or Wine. The headless client (forever-core's `wow-forever-addon/in-game.md`) tests the build linked into the game, not this checkout, so in-game checks belong to the agent that ships a change.
- Never commit a speed-up that only the benchmark likes: it has to pass the full gate.
- Never leave scratch files in the commit.
