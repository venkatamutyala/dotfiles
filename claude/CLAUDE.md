# Global instructions (all projects)

Installed from github.com/venkatamutyala/dotfiles (`claude/CLAUDE.md`). Edit it there,
not in `~/.claude/` — the installer overwrites this file.

## Run everything in Docker

- Use the `docker` CLI to run, build, test, and develop. Do not install languages,
  package managers, linters, or other tools on the host (no `apt install`, `pip
  install`, `npm install -g`, `go install`, `curl | sh`, etc.). If a tool is needed,
  run it from a container image (e.g. `docker run --rm -v "$PWD":/w -w /w <image> …`).
- Prefer official, version-pinned images (`python:3.12-slim`, not `python:latest`).
- My CI and GitHub Actions pipelines always run in Docker images, so local runs
  should use the same images and commands CI uses.
- Bind mounts: the Docker daemon may run on the host (e.g. from a devcontainer), so a
  `-v` path must exist on the host too. If a mount comes up empty or fails, put the
  files under `/workspaces/glueops` and mount from there, never from `/tmp` or the
  scratchpad.

## Shell

- The Bash tool runs bash (`CLAUDE_CODE_SHELL=/bin/bash`), even though my login shell
  is zsh. Write bash syntax; zsh-only functions and aliases from `~/.zshrc` are not
  available there.

## Isolate and parallelize

- Give each independent task its own Docker network (`docker network create <name>`)
  so containers don't collide; clean up networks and containers when done
  (`--rm`, `docker network rm`).
- Use unique container/network names (e.g. suffix with the task or a short random id)
  so parallel runs don't clash.
- Run independent jobs in parallel (e.g. a test matrix across images) rather than
  one after another.

## Code reviews

- Verify every finding before reporting it: read the surrounding code, trace the real
  call path, and reproduce it (in Docker) when practical. Drop anything you couldn't
  confirm rather than reporting it as "possible".
- Focus on issues that realistic inputs and normal usage would actually hit. Skip
  speculative or very rare scenarios.
- If an edge case is still worth knowing about, put it in a separate section
  labeled **Edge cases (FYI)** after the main findings, with one line on how likely
  it is. Don't recommend fixing it unless it's cheap and clearly worthwhile.
- Every main finding should state the concrete scenario that triggers it and why it
  matters. Don't pad the review; if nothing real turns up, say so.

## Commits

- Use Conventional Commits: `type(scope): summary`, e.g. `feat(installer): …`,
  `fix: …`, `docs: …`, `chore: …`, `ci: …`, `refactor: …`, `test: …`.
- Keep them release-please friendly: `feat` = minor bump, `fix` = patch, and breaking
  changes use `feat!:` / `fix!:` or a `BREAKING CHANGE:` footer. Use one logical change
  per commit so the generated changelog reads cleanly.
- Write the summary in the imperative mood, lowercase, with no trailing period.
