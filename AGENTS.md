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
| `tmux.conf` → `~/.tmux.conf` | Mouse on + OSC52 clipboard (`set-clipboard on`) + copy-mode bindings. `prefix + ?` shows a curated cheat sheet instead of tmux's default `list-keys` dump. |
| `tmux-cheatsheet.txt` → `~/.tmux-cheatsheet.txt` | Plain-text reference shown by `tmux.conf`'s `prefix + ?` popup. |
| `vimrc` → `~/.vimrc` | vim-plug + plugins, gruvbox colorscheme. |
| `htoprc` → `~/.config/htop/htoprc` | htop layout. |
| `venkatamutyala-functions.zsh` → `~/.oh-my-zsh/custom/` | zsh functions (`vm`, `gha-ls`, `gha-trigger`, `debug-pod`, `dev-start`, `sshpass`, `claude`) + line-editor keybindings. Auto-sourced by Oh-My-Zsh. |
| `vm-manage.sh` → `~/.oh-my-zsh/custom/` | KVM/libvirt VM management over SSH (called via the `vm` wrapper). |
| `remote-access.sh` | Standalone, not installed by `index.html`. Served at setup.venkatamutyala.com/remote-access.sh; run via `curl … \| sh` **on a third-party remote box** (NAT'd/outbound-only, nothing pre-installed) to open an ephemeral, key-only SSH session over [tailcat](https://github.com/tailscale/tailcat) — no `sshd`, no package manager, no root required. |
| `remote-session.sh` | Standalone, not installed by `index.html`. Control-side companion to `remote-access.sh`, run directly (`./remote-session.sh`) on the machine Claude Code operates from: `new` generates the session key material and the one-liner for the remote box; `connect` connects to it. Primary consumer is an agent, not a human typing commands. |
| `claude/` → `~/.claude/` | Claude Code config tree: `settings.json`, global `CLAUDE.md`, `guardrails.json` (deny/ask rules + hooks, loaded only outside `--yolo`), `hooks/`, `agents/`, `skills/`, `statusline.sh`. Every file must be listed in `claude/MANIFEST` (CI enforces). |
| `tests/` | Docker integration test + local runner. |
| `.github/workflows/ci.yml` | CI: integration test on debian bookworm + trixie, shellcheck, and the secret-scan hook test. |
| `.github/workflows/release-please.yml`, `release-please-config.json`, `.release-please-manifest.json` | release-please: on push to `main`, opens a release PR from Conventional Commits; merging it creates the `vX.Y.Z` tag the installer offers. |
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

## Decisions

Settled; reviewers shouldn't re-raise these.

- `claude --yolo` skips `guardrails.json` entirely (deny/ask rules and the secret-scan
  hook), and guardrails only load through the zsh `claude` wrapper. Both on purpose.
- Reviewer, verifier, and expert agents keep the Agent/Skill tools.
- The dedicated `*-expert` agents stay alongside `domain-expert`; experts may pull in
  related experts with no fixed limit.
- No host-install blocker for now (removed: regex matching kept blocking normal Docker
  use). The `CLAUDE.md` rule stays as an instruction.
- The secret scan is a Claude Code hook, not a native git hook.
- Bash permission rules are prefix/pattern matches, not a security boundary; that
  limitation is accepted.
- `remote-access.sh` and `remote-session.sh` deliberately duplicate the tailcat
  fetch/checksum-verify logic rather than sharing it: `remote-access.sh` must stay a
  single self-contained `curl | sh` payload for a box with nothing pre-installed, and
  sourcing a shared snippet would add a second network fetch and a version-skew
  problem to the one script that most needs to stay dependency-free.
- `remote-session.sh` never auto-deletes a session's key material (`~/.cache/remote-session/<id>/`,
  `~/.config/tailcat/keys/<id>*`) on completion. Deliberate: sessions are short-lived
  and agent-driven, the control machine is a single-operator trusted box, and a
  listing/expiry mechanism isn't worth the complexity for that threat model. Clean up
  manually (see `remote-session.sh`'s header comment).
- Accepted edge cases: repo `.gitleaksignore` isn't honored (stdin mode); a user-passed
  second `--settings` replaces the guardrails; `gh auth status -t`; kubectl comma lists
  (`get secret,configmap`); a namespace named exactly `secret(s)` is denied; a network
  blip fetching `claude/MANIFEST` reads as "older tag"; CI `cancel-in-progress` on main.

## Verify your changes

```bash
tests/run-in-docker.sh bookworm   # tmux 3.3a
tests/run-in-docker.sh trixie     # tmux 3.5a
tests/hooks-test.sh               # Claude secret-scan hook (needs docker + jq)
```

Each must end with `ALL CHECKS PASSED` (`ALL HOOK CHECKS PASSED` for the hook test). Pushing also runs CI.

## Detailed docs (imported)

@docs/architecture.md
@docs/testing.md
