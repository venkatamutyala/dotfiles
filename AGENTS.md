# AGENTS.md — venkatamutyala/dotfiles

Personal **Debian/Ubuntu Linux** dotfiles, installed with one command:

```bash
curl setup.venkatamutyala.com | zsh
```

Used mostly over SSH / on remote VMs / in devcontainers. **macOS is intentionally
unsupported** — do not add macOS/Homebrew/pbcopy/iTerm references back.

## Repo map

| Path | Role |
|------|------|
| `index.html` | The installer. A `#!/bin/zsh` script despite the name; served at setup.venkatamutyala.com via GitHub Pages and run with `curl … \| zsh`. Line 1 is `#<plaintext>` so browsers render it as raw text. Prompts for which git tag to install configs from, and pins/verifies all third-party deps. |
| `tmux.conf` → `~/.tmux.conf` | Mouse on + OSC52 clipboard (`set-clipboard on`) + copy-mode bindings. |
| `vimrc` → `~/.vimrc` | vim-plug + plugins, gruvbox colorscheme. |
| `htoprc` → `~/.config/htop/htoprc` | htop layout. |
| `venkatamutyala-functions.zsh` → `~/.oh-my-zsh/custom/` | zsh functions (`vm`, `gha-ls`, `gha-trigger`, `debug-pod`, `dev-start`, `sshpass`, `claude`) + line-editor keybindings. Auto-sourced by Oh-My-Zsh. |
| `vm-manage.sh` → `~/.oh-my-zsh/custom/` | KVM/libvirt VM management over SSH (called via the `vm` wrapper). |
| `claude-settings.json` → `~/.claude/settings.json` | Claude Code settings; enables `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`. |
| `tests/` | Docker integration test + local runner. |
| `.github/workflows/ci.yml` | CI: runs the integration test on push/PR across debian bookworm + bullseye. |
| `docs/` (`architecture.md`, `testing.md`) | Detailed agent docs, imported by `AGENTS.md`. |
| `CLAUDE.md`, `CNAME`, `LICENSE`, `README.md` | Claude entry (imports `AGENTS.md`), Pages domain, license, human docs. |

## Golden rules (don't break these)

- **Keep `index.html` line 1 = `#<plaintext>`.** It's an inert zsh comment but it
  makes the GitHub-Pages-served page render as raw script instead of mangled HTML.
- **`curl … | zsh` means stdin is the script** — you cannot `read` from the user
  interactively. If you ever need a prompt, read from `/dev/tty`, or take input via
  `zsh -s -- <args>` / env vars.
- **The installer must stay idempotent and back up before overwriting.** Never
  `rm -rf ~/.oh-my-zsh/custom`. Re-running must not duplicate `.zshrc` lines.
- **Linux/Debian only.** No macOS, no system-package installation (the user installs
  `tmux`/`gh`/`jq`/`kubectl`/`nethogs`/`vim` themselves).
- **Configs install from a selected git tag.** Interactive runs prompt via `/dev/tty`;
  don't reintroduce a silent default or require an env var for the human path.
- **Dependencies stay pinned.** OMZ/vim-plug/vim plugins use commit SHAs; zsh plugins
  are tag-cloned but verified against pinned `*_SHA`; Claude Code is version-pinned.
  Keep any new third-party fetch pinned.
- **Verify every change in Docker before shipping** (see testing doc).

## Verify your changes

```bash
tests/run-in-docker.sh bookworm   # tmux 3.3a
tests/run-in-docker.sh bullseye   # tmux 3.1c
```

Both must end with `ALL CHECKS PASSED`. Pushing also runs CI.

## Detailed docs (imported)

@docs/architecture.md
@docs/testing.md
