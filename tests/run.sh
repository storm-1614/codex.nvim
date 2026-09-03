#!/usr/bin/env sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_state_dir=${XDG_STATE_HOME:-/tmp/codex-nvim-test-state}
mkdir -p "$test_state_dir"

cd "$project_dir"
for test_file in tests/*_spec.lua; do
  XDG_STATE_HOME="$test_state_dir" nvim --headless -u NONE -c "luafile $test_file"
done
