#!/usr/bin/env bash
# The fast local gate: format, lint, the headless specs and the changelog check.
#   tools/gate.sh            the whole set
#   tools/gate.sh --changed  lint only the Lua files this branch changed against origin/main, and run the specs
#                            only when a Lua or TOC file changed
# LuaLS (tools/typecheck.sh) and the repo-wide tools in AGENTS.md stay CI's. FOREVER_CORE names the ForeverCore
# checkout at tools/forever-core.txt's ref when it is not at ../forever-core.
set -euo pipefail

cd "$(dirname "$0")/.."

changed=0
case "${1:-}" in
    "") ;;
    --changed) changed=1 ;;
    *) echo "usage: tools/gate.sh [--changed]" >&2; exit 2 ;;
esac

lua_files=()
run_specs=1
if ((changed)); then
    base=$(git merge-base origin/main HEAD)
    files=$({ git diff --name-only "$base"; git ls-files --others --exclude-standard; } | sort -u)
    # Deleted files still select the specs, but only files that exist are linted.
    while IFS= read -r f; do
        if [[ $f == *.lua && -f $f ]]; then lua_files+=("$f"); fi
    done <<<"$files"
    run_specs=0
    grep -qE '\.(lua|toc|xml)$' <<<"$files" && run_specs=1
fi

if ((!changed)); then
    stylua --check .
    luacheck --no-color -q .
elif ((${#lua_files[@]})); then
    stylua --check "${lua_files[@]}"
    luacheck --no-color -q "${lua_files[@]}"
fi

if [[ -f tools/pyproject.toml ]]; then
    uv run --project tools --frozen --group dev ruff format --check tools
    uv run --project tools --frozen --group dev ruff check tools
fi

if ((run_specs)); then
    # The test corpus is gitignored and follows the QuestieDB pin: rebuild it (the first run downloads the release).
    python3 tools/gen_corpus.py >/dev/null
    for spec in tests/*_spec.lua; do
        # Four specs take about three minutes together (playthrough, laps, smoke, ui): CI runs them.
        # GATE_SLOW=1 includes them, as a lap-route or UI change needs.
        case "$spec" in tests/playthrough_spec.lua | tests/laps_spec.lua | tests/smoke_spec.lua | tests/ui_spec.lua)
            [[ -n ${GATE_SLOW:-} ]] || continue ;;
        esac
        luajit "$spec" >/dev/null || { echo "FAILED: $spec" >&2; luajit "$spec" 2>&1 | tail -20 >&2; exit 1; }
    done
fi

python3 tools/changelog.py --check
