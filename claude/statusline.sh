#!/usr/bin/env bash
# Claude Code status line: model | dir (branch) | context used
input=$(cat)
command -v jq >/dev/null 2>&1 || { echo "claude (install jq for the status line)"; exit 0; }

model=$(jq -r '.model.display_name // "claude"' <<<"$input")
dir=$(jq -r '.workspace.current_dir // empty' <<<"$input")
ctx=$(jq -r '.context_window.used_percentage // empty' <<<"$input")
branch=$(git -C "${dir:-.}" branch --show-current 2>/dev/null)

out="$model | ${dir##*/}"
[ -n "$branch" ] && out+=" ($branch)"
[ -n "$ctx" ] && out+=" | ctx ${ctx%.*}%"
echo "$out"
