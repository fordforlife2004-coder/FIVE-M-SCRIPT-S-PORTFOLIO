#!/usr/bin/env bash
# Runs every script's tests, outside the game. Needs Lua 5.3 or newer:
#   ./run-tests.sh                   (uses `lua`)
#   LUA=lua5.4 ./run-tests.sh        (or any other Lua command)
set -u
LUA="${LUA:-lua}"
cd "$(dirname "$0")"
failed=0

run() { # run <folder> <spec file inside it>
    if [ "$1" = . ]; then printf '%-48s ' "$2"; else printf '%-48s ' "$1/$2"; fi
    if output=$(cd "$1" && "$LUA" "$2" 2>&1); then
        echo "$output" | tail -n 1
    else
        echo 'FAILED'
        echo "$output" | sed 's/^/    /'
        failed=1
    fi
}

for spec in */tests/*_spec.lua; do
    run "${spec%%/tests/*}" "tests/${spec##*/}"
done
run . tests/version_spec.lua

if [ "$failed" -ne 0 ]; then echo 'Some tests failed.'; exit 1; fi
echo 'All tests passed.'
