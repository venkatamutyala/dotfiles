#!/usr/bin/env bash
#
# Tests the Claude Code secret-scan hook (claude/hooks/gitleaks-guard.sh). Needs bash,
# git, jq, and docker (gitleaks runs in a container), so it runs on the host / CI runner
# rather than inside the Debian integration-test container.
#
# Usage: tests/hooks-test.sh

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
hook="$root/claude/hooks/gitleaks-guard.sh"
pass() { printf '  \033[32mPASS\033[0m %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*" >&2; exit 1; }

# expect <want-exit> <command> [cwd]; stderr is kept in $tmp/err.
expect() {
  local want="$1" cmd="$2" cwd="${3:-$PWD}" got=0
  jq -n --arg c "$cmd" --arg d "$cwd" '{cwd: $d, tool_input: {command: $c}}' \
    | "$hook" 2>"$tmp/err" || got=$?
  [ "$got" = "$want" ] && pass "'$cmd' -> $got" || fail "'$cmd' -> $got, want $want: $(cat "$tmp/err")"
}

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
git -C "$tmp" init -q --bare remote.git
git -C "$tmp" init -q -b main w && cd "$tmp/w"
git config user.email test@example.com && git config user.name test
git remote add origin "$tmp/remote.git"
# Built at runtime so this file never contains a token-shaped string.
tok="ghp_$(head -c 300 /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 36)"
w="$PWD"

echo "== clean"
echo hello > a.txt
expect 0 'git add -A && git commit -m init'
git add -A && git commit -qm init && git push -q -u origin main 2>/dev/null
expect 0 'git status'
expect 0 'git commit --amend -C HEAD'
expect 0 'git commit -m "docs: use git -C instead of cd"'

echo "== untracked secret: blocked only when the command adds it"
echo "token = \"$tok\"" > leak.cfg
expect 2 'git add -A && git commit -m leak'
grep -q 'leak.cfg (github-pat)' "$tmp/err" && pass "block message names the file" || fail "file not named: $(cat "$tmp/err")"
expect 0 'git commit -m unrelated'
expect 2 'cd w && git add -A && git commit -m leak' "$tmp"
expect 2 '(cd w && git add -A && git commit -m leak)' "$tmp"
expect 2 'pushd w && git add -A && git commit -m leak' "$tmp"
expect 2 "git -C $w add -A && git -C $w commit -m leak" "$tmp"
rm leak.cfg

echo "== staged secret (added in an earlier step)"
echo "token = \"$tok\"" > s.cfg && git add s.cfg
expect 2 'git commit -m leak'
git rm -q --cached s.cfg && rm s.cfg

echo "== tracked file"
echo "token = \"$tok\"" >> a.txt
expect 2 'git commit -am leak'
expect 2 'git --no-pager commit -am leak'
expect 2 'GIT_PAGER=cat git commit -am leak'
expect 2 "git --git-dir=$w/.git --work-tree=$w commit -am leak" "$tmp"

echo "== push: unpushed commits on any branch"
git switch -q -c side && git commit -qam leak && git switch -q main
expect 2 'git push origin side'
git switch -q side && expect 2 'git push' && git switch -q main
git branch -q -D side
git checkout -q -- a.txt

echo "== old, removed secrets don't block new branches"
echo "token = \"$tok\"" >> a.txt && git commit -qam leak
echo hello > a.txt && git commit -qam scrub && git push -q 2>/dev/null
git switch -q -c feat && echo more >> a.txt
expect 0 'git commit -am more'
expect 0 'git push -u origin feat'

echo "== fail closed"
expect 0 'git commit -m x' "$tmp"                    # not a repo: git itself fails
expect 2 'cd "$REPO" && git commit -m x'             # can't resolve the repo
mkdir -p "$tmp/bin" && printf '#!/bin/sh\nexit 125\n' > "$tmp/bin/docker" && chmod +x "$tmp/bin/docker"
PATH="$tmp/bin:$PATH" expect 2 'git commit -am more'   # scan can't run
grep -q 'failed to run' "$tmp/err" && pass "scan failure is reported" || fail "no failure message: $(cat "$tmp/err")"

echo "ALL HOOK CHECKS PASSED"
