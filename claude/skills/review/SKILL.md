---
name: review
description: Review a change with a team of agents: core reviewers plus the domain experts the change touches, then verify every finding. Use for any code review or before shipping a feature.
---

# Team review

1. **Scope.** Get the changed files and diff (`git diff <base>...HEAD` plus uncommitted
   changes, or the PR/branch the user named).
2. **Pick the team.** Always the core reviewers: `correctness-reviewer`,
   `security-reviewer`, `simplicity-reviewer`, `tests-docs-reviewer`. Add every expert
   whose trigger the change matches:

   | Expert | Trigger |
   |---|---|
   | `yaml-expert` | any `*.yaml` / `*.yml` |
   | `kubernetes-expert` | manifests (`apiVersion` + `kind`), kustomize, controllers, cluster config |
   | `helm-expert` | `Chart.yaml`, `templates/`, `values*.yaml` |
   | `argocd-expert` | Argo CD `Application` / `ApplicationSet`, GitOps layout |
   | `etcd-expert` | etcd config, backup/restore, control-plane datastore |
   | `ansible-expert` | playbooks, `roles/`, inventories, `ansible.cfg` |
   | `golang-expert` | `*.go`, `go.mod` |
   | `docker-expert` | `Dockerfile`, compose files, container scripts |
   | `shell-expert` | `*.sh`, `*.bash`, `*.zsh`, inline shell in CI |
   | `github-actions-expert` | `.github/workflows/`, `action.yml` |
   | `terraform-expert` | `*.tf`, `*.tfvars` |
   | `python-expert` | `*.py`, Python packaging |

   For any other technology the change uses, add a `domain-expert` and name the
   technology in its prompt (e.g. "You are a cert-manager expert").
3. **Review in parallel.** Launch all chosen agents in one message. Give each the diff
   (or file list), the repo's AGENTS.md if present, and these rules:
   - Report only issues that realistic usage would hit, each with `file:line`, the
     concrete scenario that triggers it, and why it matters.
   - Mark rare or speculative cases as edge cases, with how likely they are.
   - No style nits a linter would catch; say "nothing found" if so.
4. **Verify.** Send all findings to `verifier` (split across several verifiers in
   parallel if there are many). Drop REJECTED findings.
5. **Report** in one merged list, de-duplicated, most severe first:
   - **Findings:** CONFIRMED items, each with the evidence.
   - **Edge cases (FYI):** EDGE CASE items with likelihood. Recommend a fix only if
     it's cheap and clearly worthwhile.
   - Which experts ran, so gaps are visible.
