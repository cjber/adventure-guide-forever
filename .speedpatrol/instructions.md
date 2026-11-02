# About the app

Adventure Guide Forever is a World of Warcraft: Forever addon written in Lua 5.1. The game cannot run
here, so what is measured is the planner under its own headless bench, which stubs the client API and
loads the addon files the TOC lists, in order.

One benchmark, `kind: command`, runs `luajit -joff tests/plan_bench.lua`. Some specs need the corpus
that `python3 tools/gen_corpus.py` builds into `tests/.corpus/`, so run that once in a fresh checkout
before measuring anything that depends on it.

Wall time includes luajit's own startup, so a change under about 10 percent will not be visible. A
`custom` benchmark printing the planner's own milliseconds would remove that noise; it is the
improvement to make if these numbers prove too coarse.

Anything worth keeping also has to pass the repo's gate, with lua-language-server 3.19.1 and stylua
2.5.2, the CI pins rather than whatever this machine has installed.

## Never do these things

- Never launch the game, Battle.net, Lutris or Wine.
- Never commit a speed-up that only the benchmark likes: it has to pass the full gate.
- Never leave scratch files in the commit.
