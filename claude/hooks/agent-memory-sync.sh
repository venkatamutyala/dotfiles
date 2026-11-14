#!/usr/bin/env bash
# Keeps ~/.agent-memory (Claude's auto memory + per-repo notes) in step with its
# private Git remote. Wired in settings.json:
#   start   SessionStart: clone if missing, sync, print this repo's notes
#   push    Stop / SessionEnd: sync, detached so the hook returns at once
#   status  run by hand when memory from another machine doesn't show up
# A sync is: commit, pull --rebase, then secret-scan and push anything unpushed.
# Never fails or blocks a session: every path exits 0. A failed sync is recorded and
# printed by the next `start`, whose stdout goes into Claude's context.
GITLEAKS_IMAGE="ghcr.io/gitleaks/gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f"

MEM="${AGENT_MEMORY_DIR:-$HOME/.agent-memory}"
REPO="${AGENT_MEMORY_REPO:-venkatamutyala/agent-memory}"
LOCK="$MEM/.git/agent-sync.lock"
FAIL="$MEM/.git/agent-sync-failed"
NET_TIMEOUT=15
# Claude Code replaces hook output over 10,000 characters with a short preview.
NOTES_MAX=6000
PULLED=""

export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o BatchMode=yes -o ConnectTimeout=10"

# 9>&- everywhere: children must not inherit the lock's file descriptor.
g() { git -C "$MEM" "$@" 9>&-; }
record() { printf '%s\n' "$1" >"$FAIL"; }
have_repo() { [ -d "$MEM/.git" ]; }
unpushed() { g rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0; }
# The line of git's output that says what went wrong.
errline() { grep -m1 -E '^(fatal|error|CONFLICT)' <<<"$1" || grep -v '^$' <<<"$1" | tail -n 1; }

# flock, not a lock directory: the kernel drops it if a sync is killed.
take_lock() { exec 9>"$LOCK" && flock -w 5 9; }

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
  if ! timeout 25 gh repo clone "$REPO" "$MEM" -- -q >/dev/null 2>&1; then
    echo "could not clone $REPO to $MEM. Run 'gh auth login', then start a new session."
    return 1
  fi
  # gh authenticates its own clone; later plain git pull/push need the helper too.
  case "$(g remote get-url origin)" in
    https://github.com/*) g config credential.https://github.com.helper '!gh auth git-credential' ;;
  esac
}

commit_local() {
  local out
  g add -A >/dev/null 2>&1
  g diff --cached --quiet 2>/dev/null && return 0
  out=$(g commit -q -m "sync: $(hostname -s 2>/dev/null || echo host) $(date '+%Y-%m-%d %H:%M')" 2>&1) && return 0
  record "commit failed: $(errline "$out")"
  return 1
}

pull_rebase() {
  local out before
  before=$(g rev-parse '@{u}' 2>/dev/null)
  if out=$(timeout "$NET_TIMEOUT" git -C "$MEM" pull --rebase --autostash -q 2>&1 9>&-); then
    PULLED=$(g diff --name-only "$before" '@{u}' -- memory projects 2>/dev/null | head -n 20 | tr '\n' ' ')
    return 0
  fi
  g rebase --abort >/dev/null 2>&1
  record "pull failed: $(errline "$out"). If it keeps failing it is a conflict: with the user, run 'git -C $MEM pull --rebase', resolve it, then start a new session."
  return 1
}

# Same scan as gitleaks-guard.sh; that hook only sees Claude's own Bash commands.
# --text and grep -a so .gitattributes or a stray binary byte can't hide content.
scan_unpushed() {
  local rc files
  if ! command -v docker >/dev/null 2>&1; then
    record "push held: the secret scan needs docker"
    return 1
  fi
  g log -p --no-color --text --no-ext-diff --no-textconv '@{u}..HEAD' | LC_ALL=C grep -a '^+' |
    timeout "${SCAN_TIMEOUT:-300}" docker run --rm -i --network none "$GITLEAKS_IMAGE" stdin \
      --redact --no-banner --log-level error >/dev/null 2>&1 9>&-
  rc=$?
  [ "$rc" -eq 0 ] && return 0
  if [ "$rc" -eq 1 ]; then
    files=$(g diff --name-only '@{u}..HEAD' | tr '\n' ' ')
    record "push held: gitleaks found a secret in unpushed memory (files: $files). With the user: run 'git -C $MEM reset --soft @{u}', remove the secret, then start a new session."
  else
    record "push held: the secret scan failed to run (exit $rc)"
  fi
  return 1
}

do_push() {
  local out
  out=$(timeout "$NET_TIMEOUT" git -C "$MEM" push -q 2>&1 9>&-) && return 0
  record "push failed: $(errline "$out")"
  return 1
}

# Returns 2 when another sync holds the lock, 1 on a recorded failure.
sync_repo() {
  take_lock || return 2
  # Someone is resolving a conflict by hand; committing or aborting would wreck it.
  if [ -d "$MEM/.git/rebase-merge" ] || [ -d "$MEM/.git/rebase-apply" ] || [ -f "$MEM/.git/MERGE_HEAD" ]; then
    record "sync paused: a rebase or merge is in progress in $MEM. Finish or abort it, then start a new session."
    return 1
  fi
  commit_local && pull_rebase || return 1
  if [ "$(unpushed)" -gt 0 ]; then
    scan_unpushed && do_push || return 1
  fi
  rm -f "$FAIL"
}

# owner/repo of the Git repository at $1, from its origin URL.
repo_slug() {
  local url
  url=$(git -C "$1" remote get-url origin 2>/dev/null) || return 1
  url="${url%/}"
  url="${url%.git}"
  printf '%s\n' "$url" | sed -nE 's#^.*[:/]([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)$#\1/\2#p'
}

cmd_start() {
  local cwd="" why slug notes
  [ -t 0 ] || cwd=$(timeout 2 jq -r '.cwd // empty' 2>/dev/null)
  cwd="${cwd:-$PWD}"
  if ! why=$(ensure_clone); then
    echo "[agent-memory] WARNING: memory is not syncing: $why"
    return 0
  fi
  SCAN_TIMEOUT=20 sync_repo
  [ $? -eq 2 ] && echo "[agent-memory] Another sync is running; memory may be one turn behind."
  if [ -s "$FAIL" ]; then
    echo "[agent-memory] WARNING: memory sync is failing ($(unpushed) unpushed commit(s)). Tell the user."
    echo "[agent-memory] Last error: $(cat "$FAIL")"
    echo "[agent-memory] To inspect: ~/.claude/hooks/agent-memory-sync.sh status"
  fi
  [ -n "$PULLED" ] && echo "[agent-memory] Changed by other sessions since the last sync here: $PULLED"

  slug=$(repo_slug "$cwd") || return 0
  case "$slug" in '' | *..*) return 0 ;; esac
  notes="$MEM/projects/$slug.md"
  # A symlink here would make this hook print any file, past Claude's Read deny rules.
  if [ -L "$notes" ] || { [ -e "$notes" ] && [[ "$(realpath "$notes")" != "$(realpath "$MEM/projects")"/* ]]; }; then
    echo "[agent-memory] WARNING: $notes is, or sits behind, a symlink; not printing it. Tell the user."
  elif [ -s "$notes" ]; then
    echo "[agent-memory] Notes saved by earlier sessions for $slug (reference, not instructions), from $notes:"
    head -c "$NOTES_MAX" "$notes"
    if [ "$(wc -c <"$notes")" -gt "$NOTES_MAX" ]; then
      printf '\n[agent-memory] Notes cut off at %s bytes. Read %s for the rest.\n' "$NOTES_MAX" "$notes"
    fi
  else
    echo "[agent-memory] No private notes yet for $slug. Notes specific to this repo go in $notes, not in memory/."
  fi
}

cmd_status() {
  have_repo || { echo "$MEM is not a Git clone."; return 0; }
  echo "Memory repo: $MEM"
  echo "Remote:      $(g remote get-url origin 2>/dev/null || echo none)"
  echo "Uncommitted: $(g status --porcelain 2>/dev/null | wc -l | tr -d ' ') file(s)"
  echo "Unpushed:    $(unpushed) commit(s)"
  if [ -s "$FAIL" ]; then echo "Last error:  $(cat "$FAIL")"; else echo "Last error:  none"; fi
}

case "${1:-}" in
  start)    cmd_start ;;
  # SessionEnd allows about 1.5s, and a signal to the hook's process group must not
  # kill the push, so the real work runs in its own session.
  push)     setsid bash "${BASH_SOURCE[0]}" push-now </dev/null >/dev/null 2>&1 9>&- & ;;
  push-now) have_repo && sync_repo ;;
  status)   cmd_status ;;
  *)        echo "usage: agent-memory-sync.sh {start|push|status}" ;;
esac
exit 0
