#!/usr/bin/env bash
# PreToolUse(Bash): before `git commit` / `git push`, secret-scan everything that could
# go out: uncommitted changes, untracked files, and commits not yet on any remote. Runs
# before the whole command, so `git add -A && git commit` is covered too.
GITLEAKS_IMAGE="ghcr.io/gitleaks/gitleaks:v8.30.1@sha256:c00b6bd0aeb3071cbcb79009cb16a60dd9e0a7c60e2be9ab65d25e6bc8abbb7f"

command -v jq >/dev/null 2>&1 || { echo "Blocked: the secret-scan hook needs jq." >&2; exit 2; }
input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
git_op='(^|[[:space:]])git([[:space:]]+-[cC][[:space:]]+[^[:space:]]+)*[[:space:]]+(commit|push)([[:space:]]|$)'
[[ "$cmd" =~ $git_op ]] || exit 0

# Find the repo each commit/push runs in, following `cd <dir>` and `git -C <dir>`.
unquote() { local s="${1%\"}"; s="${s#\"}"; s="${s%\'}"; s="${s#\'}"; printf '%s' "${s/#\~/$HOME}"; }
resolve() { if [[ "$2" == /* ]]; then printf '%s' "$2"; else printf '%s/%s' "$1" "$2"; fi; }
dir=$(jq -r '.cwd // empty' <<<"$input"); dir="${dir:-$PWD}"
targets=()
while IFS= read -r seg; do
  read -ra words <<<"$seg"
  if [[ "${words[0]}" == cd && -n "${words[1]}" ]]; then
    dir=$(resolve "$dir" "$(unquote "${words[1]}")")
  elif [[ "$seg" =~ $git_op ]]; then
    t="$dir"
    for ((i = 1; i < ${#words[@]} - 1; i++)); do
      [[ "${words[i]}" == -C ]] && t=$(resolve "$t" "$(unquote "${words[i+1]}")")
    done
    targets+=("$t")
  fi
done < <(sed -E 's/(&&|\|\||;)/\n/g' <<<"$cmd")

command -v docker >/dev/null 2>&1 || { echo "Blocked: the secret scan needs docker." >&2; exit 2; }

for t in "${targets[@]}"; do
  if [[ "$t" == *'$'* || "$t" == *'`'* || ! -d "$t" ]]; then
    echo "Blocked: couldn't tell which repo this commits/pushes to ($t). Run git from the repo directory." >&2
    exit 2
  fi
  git -C "$t" rev-parse --is-inside-work-tree >/dev/null 2>&1 || continue   # git itself will fail

  out=$(cd "$t" && {
    git diff --no-color --cached
    git diff --no-color
    git ls-files --others --exclude-standard -z | xargs -0 -r -n1 sh -c 'echo "+++ $1"; sed "s/^/+/" -- "$1"' _
    if git rev-parse -q --verify HEAD >/dev/null && [[ -n "$(git remote)" ]]; then
      git log -p --no-color HEAD --not --remotes
    fi
  } | grep '^+' | docker run --rm -i --network none "$GITLEAKS_IMAGE" stdin -v --redact --no-banner --no-color 2>&1)
  rc=$?

  case $rc in
    0) ;;
    1) printf 'Blocked: gitleaks found secrets in %s (changes or unpushed commits):\n%s\n' "$t" "$out" >&2; exit 2 ;;
    *) printf 'Blocked: the secret scan failed to run in %s (exit %s):\n%s\n' "$t" "$rc" "$out" >&2; exit 2 ;;
  esac
done
exit 0
