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

note "Idempotency (re-run must not change ~/.zshrc or duplicate plugins)"
cp "$HOME/.zshrc" /tmp/zshrc.before
REPO_RAW="file://$REPO" zsh "$REPO/index.html" >/dev/null
cp "$HOME/.zshrc" /tmp/zshrc.after
diff -u /tmp/zshrc.before /tmp/zshrc.after && pass "~/.zshrc unchanged on re-run" || fail "~/.zshrc changed on re-run"
[ "$(grep -c '^plugins=(' "$HOME/.zshrc")" = 1 ] && pass "still exactly one plugins=() line" || fail "duplicate plugins=() after re-run"

note "Backup behavior (existing files preserved before overwrite)"
ls -d "$HOME"/.dotfiles-backup-* >/dev/null 2>&1 && pass "timestamped backup directory created" || fail "no backup directory created"

note "ALL CHECKS PASSED"
