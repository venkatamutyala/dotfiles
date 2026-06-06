# Testing & CI

## What runs

- **`tests/integration-test.sh`** — the real installer, end-to-end, with assertions.
  Designed to run **as root inside a fresh Debian/Ubuntu container** with the repo
  mounted read-only at `/repo`. It is **hermetic**: it sets `HOME="$(mktemp -d)"`, so
  it never touches real dotfiles and is safe to run anywhere with `apt`.
- **`tests/run-in-docker.sh [bookworm|bullseye]`** — convenience wrapper that runs
  the above in a throwaway `debian:<tag>` container, exactly like CI. Default
  `bookworm`.
- **`.github/workflows/ci.yml`** — runs the test on every `push` and `pull_request`,
  in a matrix across `debian:bookworm` (tmux 3.3a) and `debian:bullseye` (tmux 3.1c).

## How the test installs the checked-out code

It runs the installer with `REPO_RAW="file://$REPO"`, so configs are pulled from the
mounted checkout (curl's `file://` support), not from GitHub `main`. This means the
test validates the code in the current commit/branch.

## What it asserts

- **Polyglot:** `index.html` passes `zsh -n`; line 1 is exactly `#<plaintext>`; that
  marker is an inert comment in zsh (so `curl | zsh` still runs).
- **tmux fix:** `tmux.conf` loads; `set-clipboard` is `on`; the `MouseDragEnd1Pane`
  copy binding exists.
- **Install:** Oh-My-Zsh present; exactly one `plugins=(` line in `~/.zshrc`; the 3
  pinned zsh plugins cloned; installed `~/.tmux.conf` contains the fix; `vm-manage.sh`
  is executable; vim plugins (`gruvbox`, `NERDTree`, `fzf`) installed; interactive zsh
  loads cleanly; `Ctrl+Right` is bound to `forward-word` (word navigation).
- **Idempotency:** a second run leaves `~/.zshrc` byte-identical with one `plugins=(`
  line.
- **Backups:** a `~/.dotfiles-backup-*` directory is created.

## Running locally

```bash
tests/run-in-docker.sh            # debian:bookworm
tests/run-in-docker.sh bullseye   # debian:bullseye
```

Both must finish with `ALL CHECKS PASSED`. The script is `set -euo pipefail`, so the
first failed assertion aborts the run.

## Extending the test

Add assertions with the `pass "msg"` / `fail "msg"` helpers, e.g.:

```sh
[ -L "$HOME/.tmux.conf" ] && pass "..." || fail "..."
```

When you add a config or feature, add a matching assertion and re-run both Debian
versions before shipping.
