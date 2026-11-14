#!/usr/bin/env bash
# Keeps ~/.agent-memory (Claude's auto memory + per-repo notes) in step with its
# private Git remote. Wired in settings.json:
#   start   SessionStart: clone if missing, commit, pull --rebase, print this repo's notes
#   push    Stop / SessionEnd: commit, secret-scan, push (detached, returns at once)
#   status  run by hand when memory from another machine doesn't show up
# Never fails or blocks a session: every path exits 0. Failures are recorded and
# printed by the next `start`, whose stdout goes into Claude's context.
GITLEAKS_IMAGE="ghcr.io/gitleaks/gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f"

MEM="${AGENT_MEMORY_DIR:-$HOME/.agent-memory}"
REPO="${AGENT_MEMORY_REPO:-venkatamutyala/agent-memory}"
LOCK="$MEM/.git/agent-sync.lock"
FAIL="$MEM/.git/agent-sync-failed"
LOG="$MEM/.git/agent-sync.log"

export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o BatchMode=yes -o ConnectTimeout=10"

g() { git -C "$MEM" "$@"; }
log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG" 2>/dev/null; }
record() { printf '%s\n' "$1" >"$FAIL"; log "$1${2:+: $2}"; }
have_repo() { [ -d "$MEM/.git" ]; }
unpushed() { g rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0; }

take_lock() {
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if mkdir "$LOCK" 2>/dev/null; then
      trap 'rmdir "$LOCK" 2>/dev/null' EXIT
      return 0
    fi
    # A lock older than 5 minutes belongs to a sync that died.
    [ -n "$(find "$LOCK" -maxdepth 0 -mmin +5 2>/dev/null)" ] && rmdir "$LOCK" 2>/dev/null
    sleep 0.5
  done
  return 1
}

# Prints a reason and returns 1 when there is no clone and one can't be made.
ensure_clone() {
  have_repo && return 0
  if [ -e "$MEM" ]; then
    # Claude creates the empty memory dir before this hook first runs.
    if [ -n "$(find "$MEM" -type f 2>/dev/null | head -n 1)" ]; then
      echo "$MEM has files but is not a Git clone. Move it aside, start a new session, then copy your notes back in."
      return 1
    fi
    find "$MEM" -depth -type d -empty -delete 2>/dev/null
  fi
  if [ -n "${AGENT_MEMORY_REMOTE:-}" ]; then
    git clone -q "$AGENT_MEMORY_REMOTE" "$MEM" 2>/dev/null && return 0
  elif command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    gh repo clone "$REPO" "$MEM" -- -q 2>/dev/null && return 0
  fi
  echo "could not clone $REPO to $MEM. Run 'gh auth login', then start a new session."
  return 1
}

commit_local() {
  local out
  g add -A >/dev/null 2>&1
  g diff --cached --quiet 2>/dev/null && return 0
  out=$(g commit -q -m "sync: $(hostname -s 2>/dev/null || echo host) $(date '+%Y-%m-%d %H:%M')" 2>&1) && return 0
  record "commit failed: $(printf '%s' "$out" | grep -v '^$' | head -n 1)" "$out"
  return 1
}

# On a conflict, abort and keep the commits local; the next sync retries.
pull_rebase() {
  local out
  out=$(g pull --rebase --autostash -q 2>&1) && return 0
  g rebase --abort >/dev/null 2>&1
  record "pull failed: $(printf '%s' "$out" | grep -v '^$' | tail -n 1)" "$out"
  return 1
}

# Same scan as gitleaks-guard.sh; that hook only sees Claude's own Bash commands.
scan_unpushed() {
  local rc files
  if ! command -v docker >/dev/null 2>&1; then
    record "push held: the secret scan needs docker"
    return 1
  fi
  g log -p --no-color '@{u}..HEAD' | grep '^+' |
    docker run --rm -i --network none "$GITLEAKS_IMAGE" stdin --redact --no-banner \
      --log-level error >/dev/null 2>&1
  rc=$?
  [ "$rc" -eq 0 ] && return 0
  if [ "$rc" -eq 1 ]; then
    files=$(g diff --name-only '@{u}..HEAD' | tr '\n' ' ')
    record "push held: gitleaks found a secret in unpushed memory (files: $files). Remove it, then run: git -C $MEM reset --soft '@{u}'"
  else
    record "push held: the secret scan failed to run (exit $rc)"
  fi
  return 1
}

do_push() {
  local out
  out=$(g push -q 2>&1) && return 0
  record "push failed: $(printf '%s' "$out" | grep -v '^$' | tail -n 1)" "$out"
  return 1
}

# owner/repo of the Git repository at $1, from its origin URL.
repo_slug() {
  local url
  url=$(git -C "$1" remote get-url origin 2>/dev/null) || return 1
  url="${url%/}"
  url="${url%.git}"
  printf '%s\n' "$url" | sed -nE 's#^.*[:/]([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)$#\1/\2#p'
}

session_cwd() {
  local cwd=""
  if [ ! -t 0 ] && command -v jq >/dev/null 2>&1; then
    cwd=$(jq -r '.cwd // empty' 2>/dev/null)
  fi
  printf '%s\n' "${cwd:-${CLAUDE_PROJECT_DIR:-$PWD}}"
}

cmd_start() {
  local cwd why ahead slug notes
  cwd=$(session_cwd)
  if ! why=$(ensure_clone); then
    echo "[agent-memory] WARNING: memory is not syncing: $why"
    return 0
  fi
  if take_lock; then
    commit_local && pull_rebase && [ "$(unpushed)" -eq 0 ] && rm -f "$FAIL"
  fi

  ahead=$(unpushed)
  if [ -s "$FAIL" ]; then
    echo "[agent-memory] WARNING: memory sync is behind (${ahead:-0} unpushed commit(s)). Tell the user."
    echo "[agent-memory] Last error: $(cat "$FAIL")"
    echo "[agent-memory] To inspect: gh auth status; ~/.claude/hooks/agent-memory-sync.sh status"
  fi
  # Retry anything an earlier session left unpushed.
  [ "${ahead:-0}" -gt 0 ] && ( "$0" push-now </dev/null >/dev/null 2>&1 & )

  slug=$(repo_slug "$cwd") || return 0
  case "$slug" in ''|*..*) return 0 ;; esac
  notes="$MEM/projects/$slug.md"
  if [ -s "$notes" ]; then
    echo "[agent-memory] Private notes for $slug ($notes):"
    cat "$notes"
  else
    echo "[agent-memory] No private notes yet for $slug. Notes specific to this repo go in $notes, not in memory/."
  fi
}

cmd_push_now() {
  have_repo || return 0
  take_lock || return 0
  commit_local || return 0
  [ "$(unpushed)" -gt 0 ] || return 0
  pull_rebase && scan_unpushed && do_push && rm -f "$FAIL"
}

cmd_status() {
  have_repo || { echo "$MEM is not a Git clone."; return 0; }
  echo "Memory repo: $MEM"
  echo "Remote:      $(g remote get-url origin 2>/dev/null || echo none)"
  echo "Uncommitted: $(g status --porcelain 2>/dev/null | wc -l | tr -d ' ') file(s)"
  echo "Unpushed:    $(unpushed) commit(s)"
  if [ -s "$FAIL" ]; then echo "Last error:  $(cat "$FAIL")"; else echo "Last error:  none"; fi
  if [ -f "$LOG" ]; then echo "Recent log:"; tail -n 5 "$LOG"; fi
}

case "${1:-}" in
  start)    cmd_start ;;
  # SessionEnd allows about 1.5s, so the real work runs detached.
  push)     ( "$0" push-now </dev/null >/dev/null 2>&1 & ) ;;
  push-now) cmd_push_now ;;
  status)   cmd_status ;;
  *)        echo "usage: agent-memory-sync.sh {start|push|status}" ;;
esac
exit 0
