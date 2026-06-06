# My dev setup

Personal dotfiles for **Debian/Ubuntu Linux**, used mostly over SSH / on remote
VMs / in devcontainers.

## Get started with:

```bash
curl setup.venkatamutyala.com | zsh
```

When you run it interactively, the installer **prompts you to choose which version
(git tag) to install** — nothing to pass:

```text
Which version of venkatamutyala/dotfiles do you want to install?
  1) v2.0
  2) v1.0
  3) main (latest, unpinned)
Enter a number [default 1 = v2.0]:
```

(Immutable tags give reproducible, tamper-evident installs.) For unattended/CI use,
escape hatches exist: set `REPO_RAW`, or run with no TTY plus `DOTFILES_REF=v1.2.3`
(or `zsh -s -- v1.2.3`).

You can also open <https://setup.venkatamutyala.com> in a browser to read the
installer — it renders as the raw script, not a mangled web page.

Re-runnable and safe: existing dotfiles are backed up before anything is
overwritten (see below). Then start a fresh shell:

```bash
exec zsh
```

## What it installs

- **Oh-My-Zsh** (non-interactive; your existing `~/.zshrc` is preserved, only the
  `plugins=(…)` line is rewritten).
- **Zsh plugins:** `zsh-autosuggestions`, `zsh-syntax-highlighting`,
  `you-should-use` (+ Oh-My-Zsh `git` / `kubectl`).
- **Config files:** `~/.tmux.conf`, `~/.vimrc`, `~/.config/htop/htoprc`,
  `~/.claude/settings.json`, and custom scripts in `~/.oh-my-zsh/custom/`
  (`vm-manage.sh`, `venkatamutyala-functions.zsh`).
- Runs `vim +PlugInstall` so the vim-plug plugins install.

All third-party code (Oh-My-Zsh, vim-plug, the vim/zsh plugins, Claude Code) is
**pinned** to versions current as of 2026-05-07 for reproducible installs — bump the
`*_REF` vars in `index.html`, the `{ 'commit': … }` values in `vimrc`, and
`CLAUDE_VERSION` in `venkatamutyala-functions.zsh`.

## Install these yourself (not installed by the script)

| Tool | Why |
|------|-----|
| `tmux` (**>= 3.2** recommended) | clean OSC52 clipboard; Debian bookworm ships 3.3a |
| `gh`, `jq`, `kubectl` | used by `gha-ls`, `gha-trigger`, `debug-pod` |
| `nethogs` | used by `dev-start` |
| `vim` | editor config + plugin install |

On Debian/Ubuntu: `sudo apt install tmux gh jq nethogs vim` (install `kubectl`
separately).

## Safety

- Re-runnable / idempotent.
- Existing `~/.tmux.conf`, `~/.vimrc`, `~/.config/htop/htoprc`, custom scripts, and
  `~/.zshrc` are copied into `~/.dotfiles-backup-<timestamp>/` before being
  overwritten.
- The script does **not** change your login shell. To make zsh your default:
  `chsh -s "$(which zsh)"`.

## tmux clipboard (copy/paste)

tmux uses **OSC52** to forward copies to your **local** terminal's clipboard — so
mouse drag-select inside a remote tmux lands in your laptop's clipboard with no
clipboard tool needed on the remote box.

- **Copy:** drag-select with the mouse, or use vi copy-mode (`prefix [`, then `v`
  to select and `y` to yank). Double/triple-click copies a word/line.
- **Paste:** use your terminal's paste (Ctrl+Shift+V or middle-click).
- Your **local** terminal must allow OSC52 clipboard writes — kitty, WezTerm,
  Alacritty, Windows Terminal, and foot allow it by default.

## Shell line editing (faster cursor movement)

Moving through text one character at a time with the arrow keys is slow. The zsh
config speeds this up:

- **Word jumps:** `Ctrl+←/→` and `Alt+←/→` move a whole word at a time.
- `Home`/`End` jump to the start/end of the line; `Alt+f`/`Alt+b` also move by word.
- `KEYTIMEOUT=1` so key sequences (arrows, ESC) register instantly instead of
  after the default 0.4s wait.

The *repeat speed* of a held-down arrow key is controlled by your local machine,
not the remote box. On a Linux desktop: `xset r rate 250 40` (the config runs this
automatically when `$DISPLAY` is set). In a VS Code / devcontainer terminal it's
your local OS keyboard settings.

## Claude Code

- **Settings:** `~/.claude/settings.json` is installed enabling
  `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`. ⚠️ The installer **replaces** an existing
  `~/.claude/settings.json` (backing the old one up to `~/.dotfiles-backup-<timestamp>/`
  first), so anything you've added there — permissions, MCP servers, hooks — moves to
  the backup. Re-merge what you need.
- **`claude` wrapper** (in `venkatamutyala-functions.zsh`):
  - If Claude Code isn't installed, the first `claude` run installs it via
    `curl -fsSL https://claude.ai/install.sh | bash`.
  - `claude --yolo` is shorthand for `claude --allow-dangerously-skip-permissions`,
    which *enables* the skip-permissions option for the session (you can turn it on)
    rather than bypassing every check automatically.
