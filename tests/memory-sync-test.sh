#!/usr/bin/env bash
#
# Tests claude/hooks/agent-memory-sync.sh against a local bare remote, two clones
# standing in for two machines, stubbed `gh` and `docker` (so no network and no real
# gitleaks run), and a hermetic $HOME. Needs bash, git, util-linux. Runs on the
# host / CI runner, same tier as tests/remote-session-test.sh.
#
# Usage: tests/memory-sync-test.sh

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
script="$root/claude/hooks/agent-memory-sync.sh"
pass() { printf '  \033[32mPASS\033[0m %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*" >&2; exit 1; }

export HOME
HOME="$(mktemp -d)"
trap 'rm -rf "$HOME" || true' EXIT
unset AGENT_MEMORY_DIR CLAUDE_PROJECT_DIR
git config --global user.name test
git config --global user.email test@example.com
git config --global init.defaultBranch main

# Stub docker: saves what the scanner is fed, sleeps $FAKE_GITLEAKS_SLEEP, exits with
# $FAKE_GITLEAKS_EXIT (default 0 = clean), and records its argv.
# Stub gh: `repo clone <repo> <dir> ...` clones $GH_STUB_REMOTE.
mkdir -p "$HOME/bin"
cat >"$HOME/bin/docker" <<'STUB'
#!/bin/sh
cat >"$HOME/scan.in"
echo "$*" >>"$HOME/docker.calls"
sleep "${FAKE_GITLEAKS_SLEEP:-0}"
exit "${FAKE_GITLEAKS_EXIT:-0}"
STUB
cat >"$HOME/bin/gh" <<'STUB'
#!/bin/sh
[ "$1 $2" = "repo clone" ] && exec git clone -q "$GH_STUB_REMOTE" "$4"
STUB
chmod +x "$HOME/bin/docker" "$HOME/bin/gh"
export PATH="$HOME/bin:$PATH"

remote="$HOME/remote.git"
git init -q --bare "$remote"
seed="$HOME/seed"
git clone -q "$remote" "$seed" 2>/dev/null
mkdir -p "$seed/memory" "$seed/projects"
printf '*.md merge=union\n' >"$seed/.gitattributes"
printf '# Memory index\n' >"$seed/memory/MEMORY.md"
git -C "$seed" add -A
git -C "$seed" commit -q -m seed
git -C "$seed" push -q origin HEAD:main

export GH_STUB_REMOTE="$remote"
A="$HOME/a"; B="$HOME/b"
on() { local dir="$1"; shift; AGENT_MEMORY_DIR="$dir" "$script" "$@"; }
start() { CLAUDE_PROJECT_DIR="${2:-$HOME}" on "$1" start; }
remote_has() { git -C "$remote" show "main:$1" >/dev/null 2>&1; }
marker() { cat "$1/.git/agent-sync-failed" 2>/dev/null || true; }

echo "== start: clones through gh when the repo is missing, or says why it can't"
start "$A" >/dev/null
[ -f "$A/memory/MEMORY.md" ] && pass "cloned" || fail "no clone at $A"
mkdir -p "$B/memory"
start "$B" >/dev/null
[ -d "$B/.git" ] && pass "the empty dir Claude pre-creates is replaced by a clone" || fail "empty dir not replaced"
mkdir -p "$HOME/c/memory"; echo note >"$HOME/c/memory/x.md"
out="$(start "$HOME/c")" || fail "start exited nonzero"
[ -f "$HOME/c/memory/x.md" ] && grep -q 'WARNING: memory is not syncing' <<<"$out" \
  && pass "a dir holding notes is left alone, with a warning" || fail "unexpected: $out"

echo "== push: commits, feeds the unpushed diff to the pinned gitleaks image, pushes"
echo "- uses pnpm" >"$A/memory/tooling.md"
echo "- [tooling.md](tooling.md): tooling" >>"$A/memory/MEMORY.md"
mkdir -p "$A/projects/ACMECorp"; echo "deploy with make ship" >"$A/projects/ACMECorp/api.md"
{ head -c 9000 /dev/zero | tr '\0' 'a'; printf '\0\n'; } >"$A/memory/big.md"
on "$A" sync
remote_has memory/tooling.md && pass "memory reached the remote" || fail "push did not land"
grep -aq 'uses pnpm' "$HOME/scan.in" && grep -aq 'deploy with make ship' "$HOME/scan.in" \
  && pass "scanner was fed the added lines, even with a stray binary byte in the diff" \
  || fail "scanner input is missing added lines"
pin="$(grep -E '^GITLEAKS_IMAGE=' "$script")"
[ "$pin" = "$(grep -E '^GITLEAKS_IMAGE=' "$root/claude/hooks/gitleaks-guard.sh")" ] \
  && pass "gitleaks pin matches gitleaks-guard.sh" || fail "gitleaks image pin differs from gitleaks-guard.sh"
image="${pin#GITLEAKS_IMAGE=\"}"; image="${image%\"}"
grep -qF -- "--network none $image stdin" "$HOME/docker.calls" \
  && pass "scan ran offline with the pinned image" || fail "unexpected docker call: $(cat "$HOME/docker.calls")"

echo "== two machines: start and every turn pull; markdown edits from both survive"
echo "- [k8s.md](k8s.md): k8s" >>"$B/memory/MEMORY.md"; echo "- k8s" >"$B/memory/k8s.md"
start "$B" >/dev/null
[ -f "$B/memory/tooling.md" ] && remote_has memory/k8s.md \
  && pass "start pulled A's memory and pushed B's" || fail "start did not sync both ways"
grep -q tooling.md "$B/memory/MEMORY.md" && grep -q k8s.md "$B/memory/MEMORY.md" \
  && pass "MEMORY.md lines from both machines kept" || fail "index lines lost: $(cat "$B/memory/MEMORY.md")"
echo "- from A" >"$A/memory/from-a.md"; on "$A" sync
on "$B" sync
[ -f "$B/memory/from-a.md" ] && pass "a turn with nothing to push still pulls" || fail "no pull without local changes"

echo "== start: prints the current repo's private notes"
work="$HOME/work"; git init -q "$work"
git -C "$work" remote add origin git@github.com:ACMECorp/api.git
grep -q 'deploy with make ship' <<<"$(start "$B" "$work")" && pass "ssh origin" || fail "notes not printed (ssh origin)"
git -C "$work" remote set-url origin https://github.com/ACMECorp/api.git
grep -q 'deploy with make ship' <<<"$(start "$B" "$work")" && pass "https origin" || fail "notes not printed (https origin)"
git -C "$work" remote set-url origin https://github.com/ACMECorp/other
grep -q 'No private notes yet for ACMECorp/other' <<<"$(start "$B" "$work")" \
  && pass "points at the notes path when there are none" || fail "no hint for a repo without notes"
head -c 12000 /dev/zero | tr '\0' 'n' >"$B/projects/ACMECorp/other.md"
out="$(start "$B" "$work")"
[ "${#out}" -lt 10000 ] && pass "long notes stay under Claude Code's 10,000-character cap" || fail "output is ${#out} chars"

echo "== push: held when gitleaks finds a secret or can't run, released once it's clean"
start "$A" >/dev/null
before="$(git -C "$remote" rev-parse main)"
echo "token" >"$A/memory/leak.md"
FAKE_GITLEAKS_EXIT=1 on "$A" sync
out="$(FAKE_GITLEAKS_EXIT=1 start "$A")"
[ "$(git -C "$remote" rev-parse main)" = "$before" ] \
  && grep -q 'WARNING.*push held: gitleaks found a secret.*memory/leak.md' <<<"$out" \
  && pass "nothing pushed; next start warns and names the file" || fail "unexpected: $out"
echo "later note" >"$A/memory/later.md"
FAKE_GITLEAKS_EXIT=125 on "$A" sync
[ "$(git -C "$remote" rev-parse main)" = "$before" ] && grep -q 'scan could not run' <<<"$(marker "$A")" \
  && pass "held when the scan can't run" || fail "scan failure not recorded"
grep -q '^+token$' "$HOME/scan.in" && grep -q 'later note' "$HOME/scan.in" \
  && pass "every unpushed commit is rescanned, not just the newest" || fail "held commit dropped out of the scan"
out="$(start "$A")"
remote_has memory/leak.md && [ -z "$(marker "$A")" ] && ! grep -q WARNING <<<"$out" \
  && pass "a clean start pushes it, clears the error, and doesn't warn" || fail "did not recover: $out"

echo "== failures are recorded with a reason"
touch "$A/.git/index.lock"; echo "- stuck" >"$A/memory/stuck.md"
on "$A" sync
grep -q '^commit failed: fatal' <<<"$(marker "$A")" && pass "a failed git add is recorded" || fail "marker: $(marker "$A")"
rm -f "$A/.git/index.lock"; on "$A" sync
remote_has memory/stuck.md && [ -z "$(marker "$A")" ] && pass "and syncs once the cause is gone" || fail "did not recover"

echo "== conflict in a non-markdown file: aborted with a warning; a manual fix is left alone"
start "$B" >/dev/null
echo "A version" >"$A/memory/data.txt"; echo "B version" >"$B/memory/data.txt"
on "$B" sync
out="$(start "$A")" || fail "start exited nonzero on a conflict"
grep -q 'pull failed: CONFLICT.*pull --rebase' <<<"$out" && pass "warning printed with recovery steps" || fail "unexpected: $out"
[ ! -d "$A/.git/rebase-merge" ] && [ "$(cat "$A/memory/data.txt")" = "A version" ] \
  && pass "no rebase left in progress; local version kept" || fail "repo left mid-rebase"
git -C "$A" pull --rebase -q >/dev/null 2>&1 || true
[ -d "$A/.git/rebase-merge" ] || fail "test setup: expected a manual rebase in progress"
on "$A" sync
[ -d "$A/.git/rebase-merge" ] && pass "sync stays out of a manual rebase" || fail "sync disturbed a manual rebase"
echo "resolved" >"$A/memory/data.txt"; git -C "$A" add -A; GIT_EDITOR=true git -C "$A" rebase --continue >/dev/null 2>&1
on "$A" sync
[ "$(git -C "$remote" show main:memory/data.txt)" = "resolved" ] && [ -z "$(marker "$A")" ] \
  && pass "syncs again after the manual fix" || fail "did not recover after manual resolution"

echo "== push: returns at once and finishes in the background"
start "$B" >/dev/null
echo "- bg" >"$B/memory/bg.md"
SECONDS=0
FAKE_GITLEAKS_SLEEP=3 on "$B" push
[ "$SECONDS" -le 1 ] && pass "returned immediately" || fail "push blocked for ${SECONDS}s"
sleep 1; flock -w 20 "$B/.git/agent-sync.lock" true
remote_has memory/bg.md && pass "background push landed" || fail "background push never landed"

echo "== never fails a session"
"$script" bogus >/dev/null && AGENT_MEMORY_DIR="$HOME/none" "$script" sync && AGENT_MEMORY_DIR="$HOME/none" "$script" push \
  && pass "exits 0 on bad input and with no clone" || fail "nonzero exit"

echo
echo "== ALL CHECKS PASSED =="
