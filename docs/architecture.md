# Architecture & install flow

## How it's served and run

- The repo is published with **GitHub Pages**; `CNAME` maps
  `setup.venkatamutyala.com` to it. GitHub Pages serves `index.html` at the root.
- `index.html` is a **`#!/bin/zsh` script**, not a web page. `curl … | zsh` ignores
  the `text/html` content-type GitHub Pages sends and just runs the bytes.
- **Browser rendering:** GitHub Pages forces `Content-Type: text/html` on
  `index.html` and gives no way to set a header, so a browser would parse the
  script as HTML (collapsing whitespace, eating `</dev/null` etc.). Line 1
  `#<plaintext>` is a zsh comment **and** the legacy `<plaintext>` tag, which flips
  the browser parser into raw-text mode for the rest of the file. Result: the page
  shows the real script; the curl command is unchanged. Don't remove line 1.

## Installer steps (`index.html`)

Run in order by `main()`; the script uses `set -euo pipefail`:

1. `os_guard` — require Linux (die otherwise); warn if not Debian/Ubuntu; require
   `git` + `curl`.
2. `select_repo_ref` — decide which git ref of this repo to install configs from and
   set `REPO_RAW` (interactive prompt / automation escape hatches — see *Choosing a
   version* below). `DOTFILES_RESOLVE_ONLY=1` stops here after printing `REPO_RAW`.
3. `backup_existing` — copy any existing `~/.tmux.conf`, `~/.vimrc`,
   `~/.config/htop/htoprc`, `~/.zshrc`, every `~/.claude/` file listed in
   `claude/MANIFEST`, and the two custom scripts into `~/.dotfiles-backup-<timestamp>/`
   (copy, not move — originals stay until overwritten).
4. `install_omz` — install Oh-My-Zsh by **cloning it and checking out a pinned commit**
   (`OMZ_REF`) rather than piping the upstream installer to `sh`. Skipped if already
   present; creates `~/.zshrc` from the OMZ template if none exists.
5. `fetch_configs` — `curl -fsSL` each config from `$REPO_RAW` into place, plus
   vim-plug's `plug.vim` (pinned via `VIM_PLUG_REF`). Configs are **copied**, not
   symlinked.
6. `configure_zshrc_plugins` — idempotently set the `plugins=(…)` line in `~/.zshrc`
   with `awk` (handles single- and multi-line `plugins=(`; replaces only the first
   occurrence; safe to re-run). Replaces the old fragile `sed` approach.
7. `install_zsh_plugins` — clone the 3 zsh plugins by tag, then **verify** each
   resolved commit against a pinned SHA (`*_SHA`): `zsh-syntax-highlighting` 0.8.0,
   `zsh-autosuggestions` v0.7.1, `you-should-use` 1.11.1; skip if present.
8. `install_vim_plugins` — `vim +PlugInstall +qall` if `vim` exists; warn otherwise.

## `REPO_RAW` override

`REPO_RAW` is normally resolved by `select_repo_ref` (see *Choosing a version*), but
setting it explicitly overrides everything — no prompt, no ref lookup:

```sh
REPO_RAW="file:///repo" zsh index.html
```

The integration test sets `REPO_RAW="file:///repo"` so it installs the
**checked-out** files (via curl's `file://` support), not whatever is on a tag/`main`.
This is also useful for testing a fork/branch.

## Config placement: copy, not symlink

Configs are fetched/copied into their `$HOME` locations from the selected ref. The
"pick a version" UX is implemented (tag selection; the prompt reads from `/dev/tty`,
sidestepping the `curl | zsh` stdin constraint), but a full clone-the-repo +
**symlink** model remains **deferred** — switching versions still means re-running the
installer rather than `git checkout`.

## tmux clipboard (the copy/paste fix)

`tmux.conf` sets `mouse on` + `set-clipboard on`. `set-clipboard on` makes tmux
forward copies to the **local** terminal's clipboard via **OSC52**, which is what
makes copy/paste work over SSH / in containers with no clipboard tool on the remote.
Copy bindings cover mouse drag (`MouseDragEnd1Pane`), vi `v`/`y`, and
double/triple-click. Caveats: the **local** terminal must allow OSC52 writes, and
tmux **≥ 3.2** gives the cleanest behavior (bookworm = 3.3a, trixie = 3.5a).

## Claude Code

- The `claude/` directory mirrors `~/.claude/`. `install_claude_config` fetches every
  path listed in `claude/MANIFEST` from `${REPO_RAW}/claude/<path>` to
  `~/.claude/<path>` (`*.sh` made executable). It only adds/overwrites listed files
  (backed up first) — it never deletes, and never touches machine state
  (`.credentials.json`, `history.jsonl`, `projects/`, `sessions/`, `~/.claude.json`).
- Contents today: `settings.json` (enables `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`; sets
  `CLAUDE_CODE_SHELL=/bin/bash` so Claude's Bash tool doesn't inherit the zsh login
  shell, whose `=word` expansion and nomatch globbing break bash-style commands) and a
  global `CLAUDE.md` (Docker-only workflow, `/workspaces/glueops` bind mounts, bash,
  simple code with minimal comments, concise PRs, verified-only code reviews,
  Conventional Commits).
- `guardrails.json` holds deny/ask permission rules (secret files, `kubectl` secrets,
  `gh auth token`; configmaps and `kubectl config view` ask first). Deny rules apply in
  every mode, so it is *not* merged into `settings.json`: the `claude` wrapper passes
  `--settings ~/.claude/guardrails.json` only when `--yolo` isn't given. Sessions not
  started via the wrapper (VS Code, `command claude`) don't get them.
- **Adding a skill/agent/command/hook:** drop the file(s) under `claude/` (e.g.
  `claude/skills/<name>/SKILL.md`) and list each file in `claude/MANIFEST`; no
  installer change needed. The test fails if the manifest and tree disagree.
- **Old tags** have no `claude/MANIFEST`, only a top-level `claude-settings.json`; the
  installer detects that and installs just the legacy settings file.
- The `claude` zsh function (in `venkatamutyala-functions.zsh`) auto-installs Claude
  Code on first use (`curl -fsSL https://claude.ai/install.sh | bash`, which drops the
  binary in `~/.local/bin`) and translates `claude --yolo` →
  `claude --allow-dangerously-skip-permissions` (which *enables* the skip-permissions
  option for the session rather than auto-bypassing everything). It uses `whence -p` /
  `command claude` so it targets the real binary, not the function.

## Choosing a version (install-from-tag)

`select_repo_ref()` sets `REPO_RAW` to the chosen git ref of **this** repo:

- **Interactive (a TTY is present): always prompt** with a numbered menu of tags
  (newest first) plus `main`. The menu is written to and read from `/dev/tty`, so it
  works even though `curl | zsh` makes the script itself stdin.
- `REPO_RAW` set explicitly (tests use `file://`) overrides everything — no prompt.
- **No TTY** (CI/automation): `DOTFILES_REF` env / `zsh -s -- <tag>` positional, else
  newest tag, else `main`.
- `DOTFILES_RESOLVE_ONLY=1` prints the resolved `REPO_RAW` and exits (dry run; tests
  use it). `REPO_SLUG` is overridable (fork-friendly).

Tags come from release-please: Conventional Commits on `main` accumulate in a release
PR, and merging it creates the next `vX.Y.Z` tag (`feat` → minor, `fix` → patch). Set the
`RELEASE_PLEASE` secret (fine-grained PAT) so release PRs trigger CI; without it the
action falls back to `GITHUB_TOKEN`, whose PRs get no checks.

This pins the *config files* to an immutable tag — but the entry bootstrap (the served
`index.html`) is still fetched live, so to also pin the install logic run
`curl .../<tag>/index.html | zsh` directly.

## Pinned versions

All third-party code the installer pulls is pinned to the latest release/commit
available as of **2026-05-07** (reproducible, supply-chain-safe installs):

- **Oh-My-Zsh** and **vim-plug**: pinned commit SHAs (`OMZ_REF`, `VIM_PLUG_REF` in
  index.html). OMZ is cloned and checked out at the pin instead of piping the upstream
  installer to `sh`.
- **zsh plugins**: cloned by tag (`*_REF`), then the resolved commit is **verified
  against a pinned SHA** (`*_SHA`) — a moved/tampered upstream tag aborts the install.
- **vim plugins**: pinned per-plugin commit SHAs via vim-plug `{ 'commit': '…' }` in vimrc.
- **Claude Code**: the `claude` wrapper installs a pinned version (`CLAUDE_VERSION`,
  default `2.1.133`); override with `CLAUDE_VERSION=latest`.

To bump: edit the `*_REF` vars in index.html, the `{ 'commit': … }` values in vimrc, and
`CLAUDE_VERSION` in venkatamutyala-functions.zsh. The integration test asserts the OMZ
and gruvbox pins took effect. Note: OMZ is checked out at a detached commit, so
`omz update` won't track master until you `git -C ~/.oh-my-zsh checkout master`.

## Adding or renaming a config file

1. Add a `fetch "${REPO_RAW}/<name>" <dest>` line in `fetch_configs`.
2. Add the destination to the `backup_existing` loop.
3. Add an assertion in `tests/integration-test.sh`.
4. Run `tests/run-in-docker.sh` for both Debian versions.
