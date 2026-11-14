#!/usr/bin/env bash
#
# Tests claude/hooks/claude-memory-sync.sh against a local bare remote, two clones
# standing in for two machines, a stubbed `docker` (so no real gitleaks run), and a
# hermetic $HOME. Needs bash, git, jq. Runs on the host / CI runner, same tier as
# tests/remote-session-test.sh.
#
# Usage: tests/memory-sync-test.sh

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
script="$root/claude/hooks/claude-memory-sync.sh"
pass() { printf '  \033[32mPASS\033[0m %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*" >&2; exit 1; }

export HOME
HOME="$(mktemp -d)"
trap 'rm -rf "$HOME"' EXIT
git config --global user.name test
git config --global user.email test@example.com
git config --global init.defaultBranch main

# Stub docker: exits with $FAKE_GITLEAKS_EXIT (default 0 = clean) and records its argv.
mkdir -p "$HOME/bin"
cat >"$HOME/bin/docker" <<'STUB'
#!/bin/sh
cat >/dev/null
echo "$*" >>"$HOME/docker.calls"
exit "${FAKE_GITLEAKS_EXIT:-0}"
STUB
chmod +x "$HOME/bin/docker"
export PATH="$HOME/bin:$PATH"

remote="$HOME/remote.git"
git init -q --bare "$remote"
seed="$HOME/seed"
git clone -q "$remote" "$seed" 2>/dev/null
mkdir -p "$seed/memory" "$seed/projects"
printf 'MEMORY.md merge=union\n' >"$seed/.gitattributes"
printf '# Memory index\n' >"$seed/memory/MEMORY.md"
git -C "$seed" add -A
git -C "$seed" commit -q -m seed
git -C "$seed" push -q origin HEAD:main

export CLAUDE_MEMORY_REMOTE="$remote"
A="$HOME/a"; B="$HOME/b"
on() { local dir="$1"; shift; CLAUDE_MEMORY_DIR="$dir" "$script" "$@"; }
start() { printf '{"cwd":"%s"}' "${2:-$HOME}" | on "$1" start; }
remote_has() { git -C "$remote" show "main:$1" >/dev/null 2>&1; }

echo "== start: clones the memory repo when it's missing"
start "$A" >/dev/null
[ -f "$A/memory/MEMORY.md" ] && pass "cloned" || fail "no clone at $A"

echo "== start: replaces the empty dir Claude pre-creates, refuses one holding files"
mkdir -p "$B/memory"
start "$B" >/dev/null
[ -d "$B/.git" ] && pass "empty dir replaced by a clone" || fail "empty dir not replaced"
mkdir -p "$HOME/c/memory"; echo note >"$HOME/c/memory/x.md"
out="$(start "$HOME/c")"
[ ! -d "$HOME/c/.git" ] && [ -f "$HOME/c/memory/x.md" ] && grep -q 'WARNING.*not a Git clone' <<<"$out" \
  && pass "non-empty dir left alone, with a warning" || fail "unexpected: $out"

echo "== start: warns (and still exits 0) when it can't clone"
out="$(printf '{}' | CLAUDE_MEMORY_REMOTE="$HOME/nope.git" CLAUDE_MEMORY_DIR="$HOME/d" "$script" start)" \
  || fail "start exited nonzero"
grep -q 'WARNING: memory is not syncing' <<<"$out" && pass "warning printed" || fail "unexpected: $out"

echo "== push: commits, scans with the pinned gitleaks image, pushes"
echo "- uses pnpm" >"$A/memory/tooling.md"
echo "- [tooling.md](tooling.md): tooling" >>"$A/memory/MEMORY.md"
mkdir -p "$A/projects/ACMECorp"; echo "deploy with make ship" >"$A/projects/ACMECorp/api.md"
on "$A" push-now
remote_has memory/tooling.md && pass "memory reached the remote" || fail "push did not land"
pin="$(grep -E '^GITLEAKS_IMAGE=' "$script")"
[ "$pin" = "$(grep -E '^GITLEAKS_IMAGE=' "$root/claude/hooks/gitleaks-guard.sh")" ] \
  && pass "gitleaks pin matches gitleaks-guard.sh" || fail "gitleaks image pin differs from gitleaks-guard.sh"
image="${pin#GITLEAKS_IMAGE=\"}"; image="${image%\"}"
grep -qF -- "--network none $image stdin" "$HOME/docker.calls" \
  && pass "scan ran offline with the pinned image" || fail "unexpected docker call: $(cat "$HOME/docker.calls")"

echo "== start: pulls the other machine's memory; concurrent index lines both survive"
echo "- [k8s.md](k8s.md): k8s" >>"$B/memory/MEMORY.md"; echo "- k8s" >"$B/memory/k8s.md"
start "$B" >/dev/null
[ -f "$B/memory/tooling.md" ] && pass "pulled" || fail "B did not get A's memory"
grep -q tooling.md "$B/memory/MEMORY.md" && grep -q k8s.md "$B/memory/MEMORY.md" \
  && pass "MEMORY.md union-merged" || fail "index lines lost: $(cat "$B/memory/MEMORY.md")"
on "$B" push-now

echo "== start: prints the current repo's private notes"
work="$HOME/work"; git init -q "$work"
git -C "$work" remote add origin git@github.com:ACMECorp/api.git
grep -q 'deploy with make ship' <<<"$(start "$B" "$work")" && pass "ssh origin" || fail "notes not printed (ssh origin)"
git -C "$work" remote set-url origin https://github.com/ACMECorp/api.git
grep -q 'deploy with make ship' <<<"$(start "$B" "$work")" && pass "https origin" || fail "notes not printed (https origin)"
git -C "$work" remote set-url origin https://github.com/ACMECorp/other
grep -q 'No private notes yet for ACMECorp/other' <<<"$(start "$B" "$work")" \
  && pass "points at the notes path when there are none" || fail "no hint for a repo without notes"

echo "== push: held when gitleaks finds a secret, released once it's clean"
before="$(git -C "$remote" rev-parse main)"
echo "token" >"$A/memory/leak.md"
FAKE_GITLEAKS_EXIT=1 on "$A" push-now
[ "$(git -C "$remote" rev-parse main)" = "$before" ] && pass "nothing pushed" || fail "pushed despite a finding"
out="$(FAKE_GITLEAKS_EXIT=1 start "$A")"
grep -q 'WARNING' <<<"$out" && grep -q 'push held: gitleaks found a secret.*memory/leak.md' <<<"$out" \
  && pass "next start warns and names the file" || fail "unexpected: $out"
FAKE_GITLEAKS_EXIT=125 on "$A" push-now
grep -q 'push held: the secret scan failed to run' "$A/.git/claude-sync-failed" \
  && pass "held when the scan can't run" || fail "scan failure not recorded"
on "$A" push-now
remote_has memory/leak.md && [ ! -e "$A/.git/claude-sync-failed" ] \
  && pass "pushed and error cleared after a clean scan" || fail "did not recover"

echo "== conflict: rebase aborted, commits kept local, session not blocked"
start "$B" >/dev/null
echo "A version" >"$A/memory/tooling.md"; echo "B version" >"$B/memory/tooling.md"
on "$B" push-now
out="$(start "$A")" || fail "start exited nonzero on a conflict"
grep -q 'Last error: pull failed' <<<"$out" && pass "warning printed" || fail "unexpected: $out"
[ ! -d "$A/.git/rebase-merge" ] && [ ! -d "$A/.git/rebase-apply" ] \
  && [ "$(cat "$A/memory/tooling.md")" = "A version" ] \
  && pass "no rebase left in progress; local version kept" || fail "repo left mid-rebase"

echo "== push: returns at once and finishes in the background"
echo "- bg" >"$B/memory/bg.md"
SECONDS=0
on "$B" push
[ "$SECONDS" -le 1 ] && pass "returned immediately" || fail "push blocked for ${SECONDS}s"
for _ in $(seq 20); do remote_has memory/bg.md && break; sleep 0.5; done
remote_has memory/bg.md && pass "background push landed" || fail "background push never landed"

echo "== never fails a session"
"$script" bogus >/dev/null && CLAUDE_MEMORY_DIR="$HOME/none" "$script" push-now \
  && pass "exits 0 on bad input and with no clone" || fail "nonzero exit"

echo
echo "== ALL CHECKS PASSED =="
