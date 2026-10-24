---
name: ship
description: Commit, secret-scan, push, and open (or update) a PR for the current changes.
disable-model-invocation: true
---

# Ship

1. **Branch.** If on `main`/`master`, create a branch named for the change
   (`feat/<short-desc>`, `fix/<short-desc>`, …). Never push to the default branch.
2. **Verify.** Run the repo's test/check command (see its AGENTS.md), in Docker. If it
   fails, stop and show the output.
3. **Stage.** Review `git status` and stage only files that belong to this change.
4. **Check the diff** for customer data, PII, or tenant info. Replace with placeholders
   (`ACMECorp`, `foobar`, `user@example.com`) before continuing.
5. **Scan staged changes.** Stop and report if it exits non-zero:
   ```bash
   docker run --rm -v "$PWD":/repo -w /repo ghcr.io/gitleaks/gitleaks:v8.30.1 git --staged --redact
   ```
6. **Commit** with a Conventional Commit message (`type(scope): summary`, `!` or a
   `BREAKING CHANGE:` footer for breaking changes). One logical change per commit.
7. **Scan outgoing commits** (use the PR's base branch if it isn't `main`):
   ```bash
   docker run --rm -v "$PWD":/repo -w /repo ghcr.io/gitleaks/gitleaks:v8.30.1 git --redact --log-opts="origin/main..HEAD"
   ```
8. **Push** with `git push -u origin HEAD`. No force-push unless the user asked.
9. **PR.** If none exists, `gh pr create` with a Conventional Commit title and a short
   body: what changed, why, how it was tested. If one exists, update its body when the
   new commits change what it does.
10. **Report** the PR URL and anything skipped or failed.
