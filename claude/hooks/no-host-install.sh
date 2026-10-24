#!/usr/bin/env bash
# PreToolUse(Bash): block installing tools on the host; they belong in a container.
command -v jq >/dev/null 2>&1 || exit 0
cmd=$(jq -r '.tool_input.command // empty')

# Ignore heredoc bodies and quoted strings: that text runs elsewhere (e.g. inside
# `docker run … sh -c "…"`) or is just data (commit messages, grep patterns).
cmd=$(sed '/<</q' <<<"$cmd" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")

s='[[:space:]]+'
flags="($s-[^[:space:]]+)*"
prefix="((sudo$flags|env|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*)$s)*"
pkg="(apt|apt-get|brew|snap|cargo|gem|pipx|go|uv${s}tool)$flags${s}install"
pip="(uv$s)?(python[0-9.]*$s-m$s)?pip[0-9.]*$flags${s}install"
pipe_sh="\|[[:space:]]*(sudo$s)?(ba|z)?sh([[:space:]]|$)"

while IFS= read -r seg; do
  seg="${seg#"${seg%%[![:space:]]*}"}"
  if [[ "$seg" =~ ^$prefix($pkg|$pip)([[:space:]]|$) ]] \
     || { [[ "$seg" =~ ^${prefix}npm[[:space:]] && "$seg" =~ (^|$s)(i|install|add)([[:space:]]|$) && "$seg" =~ $s(-g|--global)([[:space:]]|$) ]]; }; then
    echo "Blocked: don't install tools on the host ($seg). Run it in a Docker container instead." >&2
    exit 2
  fi
done < <(sed -E 's/(&&|\|\||;|\|)/\n/g' <<<"$cmd")

if [[ "$cmd" =~ (curl|wget)[^|]*$pipe_sh ]]; then
  echo "Blocked: don't pipe a download into a shell on the host. Run it in a Docker container instead." >&2
  exit 2
fi
exit 0
