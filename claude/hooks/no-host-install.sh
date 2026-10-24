#!/usr/bin/env bash
# PreToolUse(Bash): block installing tools on the host; they belong in a container.
command -v jq >/dev/null 2>&1 || exit 0
cmd=$(jq -r '.tool_input.command // empty')

pkg='((sudo|env)[[:space:]]+)?(apt|apt-get|brew|snap|cargo|gem|pipx|go)[[:space:]]+install'
pip='((sudo|env)[[:space:]]+)?(python3?[[:space:]]+-m[[:space:]]+)?pip3?[[:space:]]+install'
npm='((sudo|env)[[:space:]]+)?npm[[:space:]]+(i|install)[[:space:]].*(-g|--global)'
pipe_sh='(curl|wget)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(ba|z)?sh'

# Check each command segment, so `docker run img pip install x` stays allowed.
while IFS= read -r seg; do
  seg="${seg#"${seg%%[![:space:]]*}"}"
  if [[ "$seg" =~ ^($pkg|$pip|$npm)([[:space:]]|$) ]]; then
    echo "Blocked: don't install tools on the host ($seg). Run it in a Docker container instead." >&2
    exit 2
  fi
done < <(sed -E 's/(&&|\|\||;)/\n/g' <<<"$cmd")

if [[ "$cmd" =~ $pipe_sh ]] && [[ "$cmd" != docker* ]]; then
  echo "Blocked: don't pipe a download into a shell on the host. Run it in a Docker container instead." >&2
  exit 2
fi
exit 0
