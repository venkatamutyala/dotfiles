#!/usr/bin/env bash
# PreToolUse(Bash): before `git commit` / `git push`, secret-scan everything that could
# go out: uncommitted changes, untracked files, and unpushed commits. Runs before the
# whole command, so `git add -A && git commit` is covered too.
GITLEAKS_IMAGE="ghcr.io/gitleaks/gitleaks:v8.30.1"

command -v jq >/dev/null 2>&1 || { echo "Blocked: the secret-scan hook needs jq." >&2; exit 2; }
input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
[[ "$cmd" =~ git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+(commit|push) ]] || exit 0

cd "$(jq -r '.cwd // empty' <<<"$input")" 2>/dev/null || true
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
command -v docker >/dev/null 2>&1 || { echo "Blocked: the secret scan needs docker." >&2; exit 2; }

base=$(git rev-parse -q --verify HEAD || git hash-object -t tree /dev/null)
if upstream=$(git rev-parse -q --verify '@{u}' 2>/dev/null) \
   || upstream=$(git rev-parse -q --verify origin/HEAD 2>/dev/null); then
  range="$upstream..HEAD"
else
  range="HEAD"
fi

out=$({
  git diff --no-color "$base"
  git ls-files --others --exclude-standard -z | xargs -0 -r -n1 sh -c 'echo "+++ $1"; sed "s/^/+/" "$1"' _
  git rev-parse -q --verify HEAD >/dev/null && git log -p --no-color "$range"
} | grep '^+' | docker run --rm -i "$GITLEAKS_IMAGE" stdin -v --redact --no-banner --no-color 2>&1)
rc=$?

case $rc in
  0) exit 0 ;;
  1) printf 'Blocked: gitleaks found secrets in the changes or unpushed commits:\n%s\n' "$out" >&2 ;;
  *) printf 'Blocked: the secret scan failed to run (exit %s):\n%s\n' "$rc" "$out" >&2 ;;
esac
exit 2
