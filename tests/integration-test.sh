#!/usr/bin/env bash
#
# Integration test for the dotfiles installer.
#
# Runs the real installer end-to-end and asserts it behaves: installs Oh-My-Zsh
# + plugins, applies the tmux copy/paste fix, edits ~/.zshrc idempotently, backs
# up existing files, and keeps the browser `#<plaintext>` marker / curl|zsh
# polyglot intact.
#
# Designed to run as root inside a fresh Debian/Ubuntu container with the repo
# mounted (read-only) at /repo -- see tests/run-in-docker.sh and the CI workflow.
# It uses a throwaway $HOME, so it never touches your real dotfiles and is safe
# to run anywhere that has apt.
#
# Env:
#   REPO   path to the repo checkout (default: /repo)

set -euo pipefail

REPO="${REPO:-/repo}"
export DEBIAN_FRONTEND=noninteractive
export TERM="${TERM:-xterm}"
# Hermetic home so we never clobber real dotfiles.
HOME="$(mktemp -d)"; export HOME

note() { printf '\n\033[1;34m== %s ==\033[0m\n' "$*"; }
pass() { printf '  \033[32mPASS\033[0m %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*" >&2; exit 1; }

note "Install prerequisites (zsh git curl tmux vim)"
apt-get update -qq
apt-get install -y -qq zsh git curl ca-certificates tmux vim >/dev/null
printf 'using: '; zsh --version; printf 'using: '; tmux -V

note "Static checks on index.html (the browser/curl polyglot)"
zsh -n "$REPO/index.html" && pass "zsh -n parses index.html" || fail "index.html has syntax errors"
[ "$(head -1 "$REPO/index.html")" = '#<plaintext>' ] \
  && pass "line 1 is the #<plaintext> browser marker" \
  || fail "line 1 is not '#<plaintext>' (browser rendering fix missing)"
printf '#<plaintext>\necho inert\n' | zsh | grep -qx inert \
  && pass "#<plaintext> is an inert comment in zsh (curl|zsh still runs)" \
  || fail "#<plaintext> broke zsh execution"
# REPO_RAW must be a well-formed assignment (regression guard for the 'can =' bug).
repo_raw_line="$(grep -nE '^[[:space:]]*REPO_RAW=' "$REPO/index.html" | head -1 | cut -d: -f2-)"
printf '%s\n' "$repo_raw_line" | grep -Eq '^[[:space:]]*REPO_RAW=' \
  && pass "REPO_RAW line assigns to REPO_RAW" || fail "REPO_RAW assignment malformed/missing: $repo_raw_line"
# Install-from-tag resolution (DOTFILES_RESOLVE_ONLY dry-run; no network/TTY needed).
r_tag="$(cd "$REPO" && env -u REPO_RAW DOTFILES_REF='v9.9.9-test' DOTFILES_RESOLVE_ONLY=1 zsh index.html 2>/dev/null | grep '^REPO_RAW=')"
[ "$r_tag" = "REPO_RAW=https://raw.githubusercontent.com/venkatamutyala/dotfiles/v9.9.9-test" ] \
  && pass "DOTFILES_REF resolves REPO_RAW to that tag's raw URL" || fail "tag resolution wrong: $r_tag"
r_ovr="$(cd "$REPO" && REPO_RAW='file:///repo' DOTFILES_REF='v1' DOTFILES_RESOLVE_ONLY=1 zsh index.html 2>/dev/null | grep '^REPO_RAW=')"
[ "$r_ovr" = "REPO_RAW=file:///repo" ] \
  && pass "explicit REPO_RAW overrides DOTFILES_REF" || fail "REPO_RAW override failed: $r_ovr"

note "tmux.conf validation (the copy/paste fix)"
tmux -L citest -f "$REPO/tmux.conf" new-session -d -s t 'sleep 5'
clip="$(tmux -L citest show -g set-clipboard 2>/dev/null | awk '{print $2}')"
[ "$clip" = on ] && pass "set-clipboard on (OSC52 clipboard enabled)" || fail "set-clipboard is '$clip', expected 'on'"
tmux -L citest list-keys -T copy-mode-vi 2>/dev/null | grep -q 'MouseDragEnd1Pane' \
  && pass "mouse drag copy binding present" || fail "MouseDragEnd1Pane copy binding missing"
tmux -L citest kill-server 2>/dev/null || true

note "Run the installer against the LOCAL checkout (REPO_RAW=file://$REPO)"
REPO_RAW="file://$REPO" zsh "$REPO/index.html"

note "Post-install assertions"
[ -d "$HOME/.oh-my-zsh" ] && pass "oh-my-zsh installed" || fail "oh-my-zsh missing"
[ "$(grep -c '^plugins=(' "$HOME/.zshrc")" = 1 ] \
  && pass "exactly one plugins=() line in ~/.zshrc" || fail "plugins=() line not present exactly once"
for p in zsh-syntax-highlighting zsh-autosuggestions you-should-use; do
  [ -d "$HOME/.oh-my-zsh/custom/plugins/$p/.git" ] && pass "zsh plugin cloned: $p" || fail "zsh plugin missing: $p"
done
grep -q 'set-clipboard on' "$HOME/.tmux.conf" \
  && pass "installed ~/.tmux.conf carries the copy/paste fix" || fail "installed ~/.tmux.conf missing the fix"
[ -x "$HOME/.oh-my-zsh/custom/vm-manage.sh" ] && pass "vm-manage.sh installed and executable" || fail "vm-manage.sh missing/not executable"
for vp in gruvbox NERDTree fzf; do
  [ -d "$HOME/.vim/plugged/$vp" ] && pass "vim plugin installed: $vp" || fail "vim plugin missing: $vp (PlugInstall failed)"
done
zsh -ic 'echo interactive-ok' 2>/dev/null | grep -qx interactive-ok \
  && pass "interactive zsh loads cleanly with the new config" || fail "interactive zsh failed to load"
zsh -ic 'bindkey "^[[1;5C"' 2>/dev/null | grep -q forward-word \
  && pass "Ctrl+Right bound to forward-word (fast word navigation)" || fail "word-navigation keybinding not active"

note "Claude Code integration (settings.json + claude wrapper)"
grep -q 'CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS' "$HOME/.claude/settings.json" \
  && pass "~/.claude/settings.json enables agent teams" || fail "settings.json missing CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"
# Stub the claude binary so we can test the wrapper without installing/running it.
mkdir -p "$HOME/.local/bin"
printf '#!/bin/sh\necho "CLAUDE_ARGS: $*"\n' > "$HOME/.local/bin/claude"
chmod +x "$HOME/.local/bin/claude"
yolo_out="$(zsh -ic 'claude --yolo -p hi' 2>/dev/null)"
printf '%s' "$yolo_out" | grep -q -- '--allow-dangerously-skip-permissions' \
  && pass "'claude --yolo' maps to --allow-dangerously-skip-permissions" || fail "--yolo not translated (got: $yolo_out)"
printf '%s' "$yolo_out" | grep -q -- '--yolo' \
  && fail "--yolo leaked through to the claude binary" || pass "--yolo is not passed through literally"
grep -q 'install.sh | bash -s -- ' "$HOME/.oh-my-zsh/custom/venkatamutyala-functions.zsh" \
  && pass "claude install pins a version (bash -s -- VERSION)" || fail "claude install is not version-pinned"

note "Pinned dependency versions (reproducible installs)"
omz_ref="$(grep -E '^OMZ_REF=' "$REPO/index.html" | head -1 | cut -d'"' -f2)"
omz_got="$(git -C "$HOME/.oh-my-zsh" rev-parse HEAD 2>/dev/null)"
[ -n "$omz_ref" ] && [ "$omz_got" = "$omz_ref" ] \
  && pass "Oh-My-Zsh pinned at $omz_ref" || fail "Oh-My-Zsh not at pinned ref (want $omz_ref, got $omz_got)"
gv_want="$(grep 'morhetz/gruvbox' "$REPO/vimrc" | grep -oE '[0-9a-f]{40}' | head -1)"
gv_got="$(git -C "$HOME/.vim/plugged/gruvbox" rev-parse HEAD 2>/dev/null)"
[ -n "$gv_want" ] && [ "$gv_got" = "$gv_want" ] \
  && pass "vim plugin gruvbox pinned at $gv_want" || fail "gruvbox not at pinned commit (want $gv_want, got $gv_got)"
ysu_want="$(grep -oE 'YOU_SHOULD_USE_SHA="[0-9a-f]{40}"' "$REPO/index.html" | grep -oE '[0-9a-f]{40}')"
ysu_got="$(git -C "$HOME/.oh-my-zsh/custom/plugins/you-should-use" rev-parse HEAD 2>/dev/null)"
[ -n "$ysu_want" ] && [ "$ysu_got" = "$ysu_want" ] \
  && pass "zsh plugin you-should-use verified at pinned SHA $ysu_want" || fail "you-should-use SHA mismatch (want $ysu_want, got $ysu_got)"

note "Idempotency (re-run must not change ~/.zshrc or duplicate plugins)"
cp "$HOME/.zshrc" /tmp/zshrc.before
REPO_RAW="file://$REPO" zsh "$REPO/index.html" >/dev/null
cp "$HOME/.zshrc" /tmp/zshrc.after
diff -u /tmp/zshrc.before /tmp/zshrc.after && pass "~/.zshrc unchanged on re-run" || fail "~/.zshrc changed on re-run"
[ "$(grep -c '^plugins=(' "$HOME/.zshrc")" = 1 ] && pass "still exactly one plugins=() line" || fail "duplicate plugins=() after re-run"

note "Backup behavior (existing files preserved before overwrite)"
ls -d "$HOME"/.dotfiles-backup-* >/dev/null 2>&1 && pass "timestamped backup directory created" || fail "no backup directory created"

note "ALL CHECKS PASSED"
