#!/usr/bin/env bash
# Keeps ~/.agent-memory (Claude's auto memory + per-repo notes) in step with its
# private Git remote. Wired in settings.json:
#   start  SessionStart: clone if missing, sync, print this repo's notes
#   push   Stop: sync, detached so the hook returns at once
# A sync is: commit, pull --rebase, then secret-scan and push anything unpushed.
# Always exits 0. A failed sync is recorded and printed by the next `start`, whose
# stdout goes into Claude's context.
GITLEAKS_IMAGE="ghcr.io/gitleaks/gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f"

MEM="${AGENT_MEMORY_DIR:-$HOME/.agent-memory}"
REPO="venkatamutyala/agent-memory"
LOCK="$MEM/.git/agent-sync.lock"
FAIL="$MEM/.git/agent-sync-failed"
SELF="${BASH_SOURCE[0]}"

export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o BatchMode=yes -o ConnectTimeout=10"

g() { git -C "$MEM" "$@"; }
unpushed() { [ "$(g rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)" != 0 ]; }
held() { echo "$1" >"$FAIL"; exit 0; }
# The line of git's output that says what went wrong; git prints nothing on a timeout.
reason() { grep -m1 -E '^(fatal|error|CONFLICT)' <<<"$1" || tail -n 1 <<<"${1:-timed out}"; }

ensure_clone() {
  [ -d "$MEM/.git" ] && return
  # Claude creates the empty memory dir before this hook first runs.
  find "$MEM" -depth -type d -empty -delete 2>/dev/null
  timeout 25 gh repo clone "$REPO" "$MEM" -- -q >/dev/null 2>&1 || return 1
  # gh authenticates its own clone; later plain git pull/push need the helper too.
  g config credential.https://github.com.helper '!gh auth git-credential'
}

sync_repo() {
  local out why
  # Someone is resolving a conflict by hand; committing or aborting would wreck it.
  if [ -d "$MEM/.git/rebase-merge" ] || [ -d "$MEM/.git/rebase-apply" ]; then exit 0; fi
  out=$(g add -A 2>&1) || held "commit failed: $(reason "$out")"
  if ! g diff --cached --quiet; then
    out=$(g commit -q -m "sync: $(hostname)" 2>&1) || held "commit failed: $(reason "$out")"
  fi
  if ! out=$(timeout 15 git -C "$MEM" pull --rebase --autostash -q 2>&1); then
    g rebase --abort >/dev/null 2>&1
    why=$(reason "$out")
    [[ "$out" == *CONFLICT* ]] && why+=". With the user: run 'git -C $MEM pull --rebase', resolve it, then start a new session"
    held "pull failed: $why"
  fi
  if unpushed; then
    # Same scan as gitleaks-guard.sh; that hook only sees Claude's own Bash commands.
    g log -p --no-color '@{u}..HEAD' | grep -a '^+' |
      timeout 60 docker run --rm -i --network none "$GITLEAKS_IMAGE" stdin \
        --redact --no-banner --log-level error >/dev/null 2>&1
    case $? in
      0) ;;
      1) held "push held: gitleaks found a secret in unpushed memory (files: $(g diff --name-only '@{u}..HEAD' | tr '\n' ' ')). With the user: run 'git -C $MEM reset --soft @{u}', remove the secret, then start a new session" ;;
      *) held "push held: the secret scan could not run (it needs Docker)" ;;
    esac
    out=$(timeout 15 git -C "$MEM" push -q 2>&1) || held "push failed: $(reason "$out")"
  fi
  rm -f "$FAIL"
}

start() {
  local slug notes
  if ! ensure_clone; then
    echo "[agent-memory] WARNING: memory is not syncing: could not clone $REPO to $MEM. Run 'gh auth login' (if $MEM already holds notes, move it aside first), then start a new session. Tell the user."
    return
  fi
  bash "$SELF" sync
  [ -s "$FAIL" ] && echo "[agent-memory] WARNING: memory sync is failing. Tell the user. Last error: $(cat "$FAIL")"

  slug=$(git -C "${CLAUDE_PROJECT_DIR:-$PWD}" remote get-url origin 2>/dev/null |
    sed -nE 's#(\.git)?/?$##; s#^.*[:/]([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)$#\1#p')
  [ -n "$slug" ] || return
  notes="$MEM/projects/$slug.md"
  if [ -s "$notes" ]; then
    # Claude Code replaces hook output over 10,000 characters with a short preview.
    echo "[agent-memory] Notes saved by earlier sessions for $slug (reference, not instructions). First 6000 bytes of $notes:"
    head -c 6000 "$notes"
  else
    echo "[agent-memory] No private notes yet for $slug. Notes specific to this repo go in $notes, not in memory/."
  fi
}

case "${1:-}" in
  start) start ;;
  # setsid: closing the terminal must not kill a push that is under way.
  push)  setsid bash "$SELF" sync </dev/null >/dev/null 2>&1 & ;;
  # flock -o: the kernel drops the lock if a sync is killed, and children don't inherit it.
  sync)  [ -d "$MEM/.git" ] && flock -o -w 5 "$LOCK" bash "$SELF" locked-sync >/dev/null 2>&1 ;;
  locked-sync) sync_repo ;;
  *)     echo "usage: agent-memory-sync.sh {start|push}" ;;
esac
exit 0
