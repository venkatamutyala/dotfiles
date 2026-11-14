#!/usr/bin/env bash
#
# Tests claude/hooks/agent-memory-sync.sh against a local bare remote, two clones
# standing in for two machines, stubbed `gh` and `docker` (so no network and no real
# gitleaks run), and a hermetic $HOME. Needs bash, git, jq, util-linux. Runs on the
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
git config --global user.name test
git config --global user.email test@example.com
git config --global init.defaultBranch main

# Stub docker: saves what the scanner is fed, sleeps $FAKE_GITLEAKS_SLEEP, exits with
# $FAKE_GITLEAKS_EXIT (default 0 = clean), and records its argv.
# Stub gh: `repo clone <repo> <dir> ...` clones $GH_STUB_REMOTE and records <repo>.
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
[ "$1 $2" = "repo clone" ] || exit 1
echo "$3" >>"$HOME/gh.calls"
exec git clone -q "$GH_STUB_REMOTE" "$4"
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
start() { printf '{"cwd":"%s"}' "${2:-$HOME}" | on "$1" start; }
remote_has() { git -C "$remote" show "main:$1" >/dev/null 2>&1; }
remote_head() { git -C "$remote" rev-parse main; }
marker() { cat "$1/.git/agent-sync-failed" 2>/dev/null || true; }

echo "== start: clones the memory repo through gh when it's missing"
start "$A" >/dev/null
[ -f "$A/memory/MEMORY.md" ] && pass "cloned" || fail "no clone at $A"
grep -qx 'venkatamutyala/agent-memory' "$HOME/gh.calls" \
  && pass "asked gh for the default repo" || fail "unexpected gh call: $(cat "$HOME/gh.calls")"

echo "== start: replaces the empty dir Claude pre-creates, refuses one holding files"
mkdir -p "$B/memory"
start "$B" >/dev/null
[ -d "$B/.git" ] && pass "empty dir replaced by a clone" || fail "empty dir not replaced"
mkdir -p "$HOME/c/memory"; echo note >"$HOME/c/memory/x.md"
out="$(start "$HOME/c")"
[ ! -d "$HOME/c/.git" ] && [ -f "$HOME/c/memory/x.md" ] && grep -q 'WARNING.*not a Git clone' <<<"$out" \
  && pass "non-empty dir left alone, with a warning" || fail "unexpected: $out"

echo "== start: warns (and still exits 0) when it can't clone"
out="$(printf '{}' | GH_STUB_REMOTE="$HOME/nope.git" AGENT_MEMORY_DIR="$HOME/d" "$script" start)" \
  || fail "start exited nonzero"
grep -q 'WARNING: memory is not syncing' <<<"$out" && pass "warning printed" || fail "unexpected: $out"

echo "== push: commits, feeds the unpushed diff to the pinned gitleaks image, pushes"
echo "- uses pnpm" >"$A/memory/tooling.md"
echo "- [tooling.md](tooling.md): tooling" >>"$A/memory/MEMORY.md"
mkdir -p "$A/projects/ACMECorp"; echo "deploy with make ship" >"$A/projects/ACMECorp/api.md"
on "$A" push-now
remote_has memory/tooling.md && pass "memory reached the remote" || fail "push did not land"
grep -q 'uses pnpm' "$HOME/scan.in" && grep -q 'deploy with make ship' "$HOME/scan.in" \
  && pass "scanner was fed the added lines" || fail "scanner input: $(cat "$HOME/scan.in")"
pin="$(grep -E '^GITLEAKS_IMAGE=' "$script")"
[ "$pin" = "$(grep -E '^GITLEAKS_IMAGE=' "$root/claude/hooks/gitleaks-guard.sh")" ] \
  && pass "gitleaks pin matches gitleaks-guard.sh" || fail "gitleaks image pin differs from gitleaks-guard.sh"
image="${pin#GITLEAKS_IMAGE=\"}"; image="${image%\"}"
grep -qF -- "--network none $image stdin" "$HOME/docker.calls" \
  && pass "scan ran offline with the pinned image" || fail "unexpected docker call: $(cat "$HOME/docker.calls")"

echo "== scan: content can't be hidden by .gitattributes or a binary byte"
echo 'hidden-*.md -diff' >>"$A/.gitattributes"; echo "token-one" >"$A/memory/hidden-x.md"
{ head -c 9000 /dev/zero | tr '\0' 'a'; printf '\0\n'; } >"$A/memory/big.md"
echo "token-two" >"$A/memory/after-big.md"
on "$A" push-now
grep -aq 'token-one' "$HOME/scan.in" && grep -aq 'token-two' "$HOME/scan.in" \
  && pass "scanner still saw both" || fail "scanner missed hidden content"
rm -f "$A/memory/hidden-x.md" "$A/memory/big.md"; printf '*.md merge=union\n' >"$A/.gitattributes"
on "$A" push-now

echo "== start: pulls the other machine's memory and says what changed"
echo "- [k8s.md](k8s.md): k8s" >>"$B/memory/MEMORY.md"; echo "- k8s" >"$B/memory/k8s.md"
out="$(start "$B")"
[ -f "$B/memory/tooling.md" ] && pass "pulled" || fail "B did not get A's memory"
grep -q 'Changed by other sessions.*memory/tooling.md' <<<"$out" \
  && pass "lists the files other sessions changed" || fail "unexpected: $out"
grep -q tooling.md "$B/memory/MEMORY.md" && grep -q k8s.md "$B/memory/MEMORY.md" \
  && pass "MEMORY.md union-merged" || fail "index lines lost: $(cat "$B/memory/MEMORY.md")"
remote_has memory/k8s.md && pass "start pushed B's own unpushed memory" || fail "start left B's commit unpushed"

echo "== push: pulls even with nothing to push"
echo "- from A" >"$A/memory/from-a.md"; on "$A" push-now
on "$B" push-now
[ -f "$B/memory/from-a.md" ] && pass "B picked up A's change after its turn" || fail "no pull without local changes"

echo "== start: prints the current repo's private notes"
work="$HOME/work"; git init -q "$work"
git -C "$work" remote add origin git@github.com:ACMECorp/api.git
grep -q 'deploy with make ship' <<<"$(start "$B" "$work")" && pass "ssh origin" || fail "notes not printed (ssh origin)"
git -C "$work" remote set-url origin https://github.com/ACMECorp/api.git
grep -q 'deploy with make ship' <<<"$(start "$B" "$work")" && pass "https origin" || fail "notes not printed (https origin)"
git -C "$work" remote set-url origin https://github.com/ACMECorp/other
grep -q 'No private notes yet for ACMECorp/other' <<<"$(start "$B" "$work")" \
  && pass "points at the notes path when there are none" || fail "no hint for a repo without notes"

echo "== start: long notes are cut off with a pointer to the file"
mkdir -p "$B/projects/ACMECorp"; head -c 12000 /dev/zero | tr '\0' 'n' >"$B/projects/ACMECorp/other.md"
out="$(start "$B" "$work")"
[ "${#out}" -lt 10000 ] && grep -q 'Notes cut off.*Read .*projects/ACMECorp/other.md' <<<"$out" \
  && pass "output stays under Claude Code's 10,000-character cap" || fail "output is ${#out} chars"

echo "== start: never prints through a symlink or outside projects/"
echo "OUTSIDE" >"$HOME/outside.txt"
mkdir -p "$B/projects/evil"; ln -s "$HOME/outside.txt" "$B/projects/evil/repo.md"
ln -s "$HOME" "$B/projects/linked"; echo "OUTSIDE" >"$HOME/dir.md"
git -C "$work" remote set-url origin https://github.com/evil/repo
out="$(start "$B" "$work")"
! grep -q OUTSIDE <<<"$out" && grep -q 'WARNING.*symlink' <<<"$out" \
  && pass "symlinked notes file refused" || fail "printed through a symlink: $out"
git -C "$work" remote set-url origin https://github.com/linked/dir
! grep -q OUTSIDE <<<"$(start "$B" "$work")" && pass "symlinked owner directory refused" || fail "printed through a symlinked dir"
git -C "$work" remote set-url origin 'git@host:../x.git'
! grep -q 'x.md' <<<"$(start "$B" "$work")" && pass "'..' in the repo path is ignored" || fail "'..' slug used"
rm -rf "$B/projects/evil" "$B/projects/linked"; on "$B" push-now

echo "== push: held when gitleaks finds a secret, released once it's clean"
start "$A" >/dev/null
before="$(remote_head)"
echo "token" >"$A/memory/leak.md"
FAKE_GITLEAKS_EXIT=1 on "$A" push-now
[ "$(remote_head)" = "$before" ] && pass "nothing pushed" || fail "pushed despite a finding"
out="$(FAKE_GITLEAKS_EXIT=1 start "$A")"
grep -q 'WARNING' <<<"$out" && grep -q 'push held: gitleaks found a secret.*memory/leak.md' <<<"$out" \
  && pass "next start warns and names the file" || fail "unexpected: $out"
echo "later note" >"$A/memory/later.md"
FAKE_GITLEAKS_EXIT=125 on "$A" push-now
grep -q 'push held: the secret scan failed to run' <<<"$(marker "$A")" \
  && pass "held when the scan can't run" || fail "scan failure not recorded"
grep -q '^+token$' "$HOME/scan.in" && grep -q 'later note' "$HOME/scan.in" \
  && pass "every unpushed commit is rescanned, not just the newest" || fail "held commit dropped out of the scan"
# A PATH holding everything the hook needs except docker.
nodocker="$HOME/nodocker"; mkdir -p "$nodocker"
for tool in bash git jq flock timeout setsid realpath cat date hostname find head tail wc tr grep sed sleep rm; do
  ln -s "$(command -v "$tool")" "$nodocker/$tool"
done
PATH="$nodocker" on "$A" push-now
[ "$(remote_head)" = "$before" ] && grep -q 'needs docker' <<<"$(marker "$A")" \
  && pass "held when docker is missing" || fail "pushed, or no record, without docker: $(marker "$A")"
out="$(start "$A")"
remote_has memory/leak.md && [ ! -e "$A/.git/agent-sync-failed" ] && ! grep -q WARNING <<<"$out" \
  && pass "a clean start pushes it, clears the error, and doesn't warn" || fail "did not recover: $out"

echo "== lock: a running sync makes others skip; a killed one doesn't block"
flock "$A/.git/agent-sync.lock" sleep 30 &
holder=$!
sleep 0.3
echo "- locked" >"$A/memory/locked.md"
out="$(start "$A")"
grep -q 'Another sync is running' <<<"$out" && ! remote_has memory/locked.md \
  && pass "start says so and skips" || fail "unexpected: $out"
pkill -9 -P "$holder" 2>/dev/null || true; kill -9 "$holder" 2>/dev/null || true; wait "$holder" 2>/dev/null || true
on "$A" push-now
remote_has memory/locked.md && pass "next sync proceeds once the holder is killed" || fail "lock stuck after the holder died"

echo "== conflicts: markdown merges; anything else pauses with a warning; manual fixes are left alone"
start "$B" >/dev/null
echo "A line" >>"$A/memory/tooling.md"; echo "B line" >>"$B/memory/tooling.md"
on "$B" push-now; on "$A" push-now
grep -q 'A line' "$A/memory/tooling.md" && grep -q 'B line' "$A/memory/tooling.md" && [ -z "$(marker "$A")" ] \
  && pass "same .md edited on both machines keeps both sides" || fail "markdown conflict: $(marker "$A")"
start "$B" >/dev/null
echo "A version" >"$A/memory/data.txt"; echo "B version" >"$B/memory/data.txt"
on "$B" push-now
out="$(start "$A")" || fail "start exited nonzero on a conflict"
grep -q 'Last error: pull failed' <<<"$out" && grep -q 'pull --rebase' <<<"$out" \
  && pass "warning printed with recovery steps" || fail "unexpected: $out"
[ ! -d "$A/.git/rebase-merge" ] && [ ! -d "$A/.git/rebase-apply" ] && [ "$(cat "$A/memory/data.txt")" = "A version" ] \
  && pass "no rebase left in progress; local version kept" || fail "repo left mid-rebase"
git -C "$A" pull --rebase -q >/dev/null 2>&1 || true
[ -d "$A/.git/rebase-merge" ] || fail "test setup: expected a manual rebase in progress"
on "$A" push-now
[ -d "$A/.git/rebase-merge" ] && grep -q 'sync paused' <<<"$(marker "$A")" \
  && pass "sync stays out of a manual rebase" || fail "sync disturbed a manual rebase"
echo "resolved" >"$A/memory/data.txt"; git -C "$A" add -A; GIT_EDITOR=true git -C "$A" rebase --continue >/dev/null 2>&1
on "$A" push-now
[ "$(git -C "$remote" show main:memory/data.txt)" = "resolved" ] && [ -z "$(marker "$A")" ] \
  && pass "syncs again after the manual fix" || fail "did not recover after manual resolution"

echo "== push: returns at once, in its own session, and finishes in the background"
start "$B" >/dev/null
echo "- bg" >"$B/memory/bg.md"
SECONDS=0
FAKE_GITLEAKS_SLEEP=3 on "$B" push
[ "$SECONDS" -le 1 ] && pass "returned immediately" || fail "push blocked for ${SECONDS}s"
sleep 0.5
bg="$(pgrep -f "agent-memory-sync.sh push-now" | head -n 1)"
[ -n "$bg" ] && [ "$(ps -o sid= -p "$bg" | tr -d ' ')" != "$(ps -o sid= -p $$ | tr -d ' ')" ] \
  && pass "background push runs in its own session" || fail "background push shares the caller's session"
flock -w 20 "$B/.git/agent-sync.lock" true
remote_has memory/bg.md && pass "background push landed" || fail "background push never landed"

echo "== status and exit codes"
on "$B" status | grep -q 'Last error:  none' && pass "status reports a clean repo" || fail "status output unexpected"
"$script" bogus >/dev/null && AGENT_MEMORY_DIR="$HOME/none" "$script" push-now \
  && pass "exits 0 on bad input and with no clone" || fail "nonzero exit"

echo
echo "== ALL CHECKS PASSED =="
