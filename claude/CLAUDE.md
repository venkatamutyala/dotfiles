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

## Writing code

- Keep it simple. Solve the problem in front of you; no speculative abstractions,
  options, or layers "for later".
- Don't comment obvious code. Comment only the non-obvious *why* (a workaround, a
  constraint, a gotcha), in one short line where possible.

## PRs and comments

- Keep PR descriptions, review comments, and issue comments clear and concise: what
  changed, why, and how it was tested. No filler or restating the diff.

## Agent docs

- When creating a new repo, or when asked to update or check a repo's docs, and the
  repo has no AGENTS.md: create one, plus a CLAUDE.md that only imports it
  (`@AGENTS.md`), so other AI tools share the same instructions.
- Keep AGENTS.md concise: what the repo is, a short repo map, how to build/test (in
  Docker), and the standards or rules a new agent needs to contribute safely. Update it
  when those change.

## Agent teams

- Always work with a team of agents (defined in `~/.claude/agents/`) for both code
  reviews and feature builds. Agents use the session's model.
- **Reviews:** use the `/review` skill: core reviewers plus every domain expert the
  change touches (routing table in `~/.claude/skills/review/SKILL.md`), then verify
  each finding.
- **Feature builds:** before implementing, send the plan to the matching experts (or a
  `domain-expert` for technologies without one) in parallel and fold in their
  feedback. After implementing, run `/review` before shipping.

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

## Git and GitHub

- Never push to `main`/`master`; work on a branch (e.g. `feat/<short-desc>`) and open
  a PR.
- Never force-push, amend pushed commits, or otherwise rewrite pushed history without
  asking first.

## Safety

- Before every commit, scan staged changes for secrets, and before every push, scan the
  commits being pushed. Stop and tell me if anything is found (exit code 1):
  ```bash
  docker run --rm -v "$PWD":/repo -w /repo ghcr.io/gitleaks/gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f git --staged --redact
  docker run --rm -v "$PWD":/repo -w /repo ghcr.io/gitleaks/gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f git --redact --log-opts="origin/main..HEAD"
  ```
- Never commit or push customer data, PII, or tenant information (real company names,
  people, emails, domains, cluster/tenant IDs, IPs). Use placeholders such as
  `ACMECorp`, `foobar`, `user@example.com`, `example.com`.
- Never print, log, or commit secrets. If one shows up in output, stop and tell me.
- Ask before anything destructive or hard to undo: deleting resources, dropping data,
  changing DNS.

## Commits

- Use Conventional Commits: `type(scope): summary`, e.g. `feat(installer): …`,
  `fix: …`, `docs: …`, `chore: …`, `ci: …`, `refactor: …`, `test: …`.
- Keep them release-please friendly: `feat` = minor bump, `fix` = patch, and breaking
  changes use `feat!:` / `fix!:` or a `BREAKING CHANGE:` footer. Use one logical change
  per commit so the generated changelog reads cleanly.
- Write the summary in the imperative mood, lowercase, with no trailing period.
