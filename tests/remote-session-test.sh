#!/usr/bin/env bash
#
# Tests remote-session.sh's own logic against a stubbed tailcat binary (no real
# network, no real tailscale infra) and a hermetic $HOME. Needs bash, openssh-client
# (ssh-keygen/ssh-agent/ssh-add), coreutils. Runs on the host / CI runner, same tier
# as tests/hooks-test.sh.
#
# Usage: tests/remote-session-test.sh

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
script="$root/remote-session.sh"
pass() { printf '  \033[32mPASS\033[0m %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*" >&2; exit 1; }

export HOME
HOME="$(mktemp -d)"
unset XDG_CACHE_HOME XDG_CONFIG_HOME
trap 'rm -rf "$HOME"' EXIT

bin_dir="$HOME/.cache/remote-session/bin"
mkdir -p "$bin_dir"

# Stub tailcat: `genkey [--client] --key=<name>` prints an address/nodekey (or fails
# or prints nothing, per env vars) and writes a dummy server key file to the same
# path remote-session.sh itself reads. `--key=<x> ping ...` exits with $FAKE_PING_EXIT
# (default success). `--key=<x> ssh <addr> [cmd]` exits with $FAKE_SSH_EXIT, recording
# its argv for inspection.
cat >"$bin_dir/tailcat" <<'STUB'
#!/bin/sh
if [ "$1" = "genkey" ]; then
  shift
  is_client=0
  key=""
  for a in "$@"; do
    case "$a" in
      --client) is_client=1 ;;
      --key=*) key="${a#--key=}" ;;
    esac
  done
  if [ "$is_client" = "1" ]; then
    [ "${FAKE_CLIENT_FAIL:-0}" = "1" ] && { echo "stub: forced genkey --client failure" >&2; exit 1; }
    [ "${FAKE_CLIENT_EMPTY:-0}" = "1" ] && exit 0
    echo "# wrote file to .../$key.private.json"
    echo "${FAKE_CLIENT_NODEKEY:-nodekey:deadbeef}"
  else
    [ "${FAKE_GENKEY_FAIL:-0}" = "1" ] && { echo "stub: forced genkey failure" >&2; exit 1; }
    keyfile="${XDG_CONFIG_HOME:-$HOME/.config}/tailcat/keys/$key.private.json"
    mkdir -p "$(dirname "$keyfile")"
    echo '{"stub":"key"}' >"$keyfile"
    [ "${FAKE_GENKEY_EMPTY:-0}" = "1" ] && exit 0
    echo "# wrote file to $keyfile"
    echo "${FAKE_ADDRESS:-tcpFAKEADDRESS}"
  fi
else
  is_ping=0
  for a in "$@"; do
    [ "$a" = "ping" ] && is_ping=1
  done
  if [ "$is_ping" = "1" ]; then
    exit "${FAKE_PING_EXIT:-0}"
  fi
  [ -n "${FAKE_RECORD_ARGS_TO:-}" ] && printf '%s\n' "$@" >"$FAKE_RECORD_ARGS_TO"
  exit "${FAKE_SSH_EXIT:-0}"
fi
STUB
chmod +x "$bin_dir/tailcat"

# `|| true` guards against pipefail propagating pgrep's "no match" exit 1 through
# the otherwise-successful wc/tr stages and killing this script via set -e.
agent_count() { pgrep -f 'ssh-agent' 2>/dev/null | wc -l | tr -d ' ' || true; }

echo "== new: genkey (server) failure is a clear die(), not a silent exit"
FAKE_GENKEY_FAIL=1 "$script" new >/dev/null 2>"$HOME/err" </dev/null && got=0 || got=$?
[ "$got" != 0 ] || fail "expected nonzero exit, got 0"
grep -q 'ERROR:.*genkey' "$HOME/err" && pass "clear die() message: $(cat "$HOME/err")" \
  || fail "no die() message (silent failure): $(cat "$HOME/err")"

echo "== new: genkey (server) producing no address is a clear die(), not an empty ADDRESS"
FAKE_GENKEY_EMPTY=1 "$script" new >/dev/null 2>"$HOME/err" </dev/null && got=0 || got=$?
[ "$got" != 0 ] || fail "expected nonzero exit, got 0"
grep -q 'ERROR:.*no address' "$HOME/err" && pass "clear die() message: $(cat "$HOME/err")" \
  || fail "no die() message: $(cat "$HOME/err")"

echo "== new: genkey --client failure is a clear die(), not a silently-missing --allow"
FAKE_CLIENT_FAIL=1 "$script" new >/dev/null 2>"$HOME/err" </dev/null && got=0 || got=$?
[ "$got" != 0 ] || fail "expected nonzero exit, got 0"
grep -q 'ERROR:.*client' "$HOME/err" && pass "clear die() message: $(cat "$HOME/err")" \
  || fail "no die() message: $(cat "$HOME/err")"

echo "== new: stdout is exactly a file path (no key material on stdout); file is 0600; address with a space round-trips safely"
addr_with_space="100.64.0.1 touch $HOME/should-not-exist"
path=$(FAKE_ADDRESS="$addr_with_space" "$script" new 2>/dev/null </dev/null)
[ -f "$path" ] || fail "new's stdout ($path) is not a file"
case "$(cat "$path")" in *key\ material*|*PUBKEY*TAILKEY_B64*) pass "remote-cmd.txt holds the one-liner" ;; *) fail "unexpected remote-cmd.txt content" ;; esac
case "$(echo "$path" | tr -d '[:print:]')" in '') pass "stdout contains no non-printable/binary noise" ;; *) fail "stdout looked suspicious" ;; esac
mode=$(stat -c '%a' "$path" 2>/dev/null || stat -f '%Lp' "$path")
[ "$mode" = "600" ] && pass "remote-cmd.txt is 0600" || fail "remote-cmd.txt mode is $mode, want 600"
sess_dir="$(dirname "$path")"
sess_id="$(basename "$sess_dir")"
source "$sess_dir/meta.env"
[ "$ADDRESS" = "$addr_with_space" ] && pass "address with embedded space round-tripped intact through meta.env" \
  || fail "address corrupted: got [$ADDRESS], want [$addr_with_space]"
[ ! -e "$HOME/should-not-exist" ] && pass "no code executed while sourcing meta.env" \
  || fail "SECURITY: sourcing meta.env executed injected command"

echo "== connect: unreachable session (ping fails) is a clear die(), never attempts ssh, still cleans up ssh-agent"
record="$HOME/ssh-args"
rm -f "$record"
before=$(agent_count)
FAKE_PING_EXIT=1 FAKE_RECORD_ARGS_TO="$record" "$script" connect "$sess_id" >/dev/null 2>"$HOME/err" && fail "expected nonzero exit" || true
grep -q 'ERROR:.*not reachable\|ERROR:.*isn.t reachable' "$HOME/err" && pass "clear die() message: $(cat "$HOME/err")" \
  || fail "no clear die() message: $(cat "$HOME/err")"
[ ! -f "$record" ] && pass "ssh was never attempted after a failed reachability check" \
  || fail "ssh ran anyway despite the ping failure: $(cat "$record")"
sleep 0.2
after=$(agent_count)
[ "$after" -le "$before" ] && pass "ssh-agent count did not increase after an unreachable session ($before -> $after)" \
  || fail "ssh-agent leaked after a ping failure ($before -> $after)"

echo "== connect: successful session cleans up the ssh-agent it started"
before=$(agent_count)
FAKE_SSH_EXIT=0 "$script" connect "$sess_id" >/dev/null 2>&1
sleep 0.2
after=$(agent_count)
[ "$after" -le "$before" ] && pass "ssh-agent count did not increase after a successful connect ($before -> $after)" \
  || fail "ssh-agent leaked after success ($before -> $after)"

echo "== connect: a FAILED session still cleans up the ssh-agent (the trap-scoping regression this guards against)"
before=$(agent_count)
FAKE_SSH_EXIT=1 "$script" connect "$sess_id" >/dev/null 2>&1 && fail "expected nonzero exit" || true
sleep 0.2
after=$(agent_count)
[ "$after" -le "$before" ] && pass "ssh-agent count did not increase after a failed connect ($before -> $after)" \
  || fail "ssh-agent leaked after failure ($before -> $after) -- this is the bug an EXIT-vs-RETURN trap regression would reintroduce"

echo "== connect: unknown session id fails loudly"
"$script" connect "no-such-session" >/dev/null 2>"$HOME/err" && fail "expected nonzero exit" || true
grep -q 'ERROR:.*unknown session' "$HOME/err" && pass "clear die() message" || fail "unexpected: $(cat "$HOME/err")"

echo
echo "== ALL CHECKS PASSED =="
