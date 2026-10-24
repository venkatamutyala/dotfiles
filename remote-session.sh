#!/usr/bin/env bash
# Control-side companion to remote-access.sh. Run this on the machine Claude Code
# itself operates from -- never on the remote target.
#
#   remote-session.sh new                 generate a session; writes the one-liner
#                                          to run on the remote box to a file and
#                                          prints that file's path on stdout (not
#                                          the command itself -- it contains real
#                                          key material, so read the file directly
#                                          rather than relaying it through an
#                                          agent's own transcript/logs)
#   remote-session.sh connect <id> [command...]
#                                          connect to a session (tailcat's ssh service
#                                          always runs as whoever invoked `serve` on
#                                          the remote side -- there's no destination
#                                          username to supply). With no command, opens
#                                          an interactive shell; with one, runs it
#                                          non-interactively and exits. Gives up after
#                                          $CONNECT_TIMEOUT seconds (tailcat's --allow
#                                          silently hangs rather than erroring on a
#                                          tunnel-layer mismatch).
#
# Session state lives under ~/.cache/remote-session/<id>/ and under tailcat's own
# key store (~/.config/tailcat/keys/<id>*). Nothing here expires on its own --
# unlike the remote side, which cleans up on Ctrl+C -- delete the session
# directory and run `tailcat genkey --delete --key=<id>` (and `--key=<id>-client`)
# when you're done with a session.

set -euo pipefail

TAILCAT_VERSION=0.7.0
CONNECT_TIMEOUT=20
# Assumes this script and remote-access.sh have both landed on main and GitHub
# Pages has redeployed; update if the Pages path ever changes.
REMOTE_ACCESS_URL="https://setup.venkatamutyala.com/remote-access.sh"

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/remote-session"
TAILCAT_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tailcat"
BIN_DIR="$CACHE_DIR/bin"
TAILCAT_BIN="$BIN_DIR/tailcat"

die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }

usage() {
  cat >&2 <<'EOF'
Usage:
  remote-session.sh new
  remote-session.sh connect <id> [command...]
EOF
  exit 1
}

ensure_tailcat() {
  [ -x "$TAILCAT_BIN" ] && return
  need curl
  need tar
  need sha256sum
  mkdir -p "$BIN_DIR"

  [ "$(uname -s)" = "Linux" ] || die "this script only supports Linux"
  local arch
  case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64) arch=arm64 ;;
    armv7l) arch=armv7 ;;
    *) die "unsupported architecture: $(uname -m)" ;;
  esac

  local workdir base_url tarball checksum_line hash_line expected actual
  workdir=$(mktemp -d)
  base_url="https://github.com/tailscale/tailcat/releases/download/v$TAILCAT_VERSION"
  tarball="tailcat_${TAILCAT_VERSION}_linux_${arch}.tar.gz"

  curl -fsSL -o "$workdir/checksums.txt" "$base_url/checksums.txt" || die "couldn't fetch checksums.txt"
  curl -fsSL -o "$workdir/$tarball" "$base_url/$tarball" || die "couldn't fetch $tarball"

  # Each lookup below is kept out of a `cmd1 | cmd2` assignment on purpose: under
  # `pipefail`, a failing first stage kills the script via `set -e` right there,
  # before the die() message on the next line ever runs.
  checksum_line=$(grep " $tarball\$" "$workdir/checksums.txt") || die "no checksum entry for $tarball in checksums.txt"
  expected=$(cut -d' ' -f1 <<<"$checksum_line")
  hash_line=$(sha256sum "$workdir/$tarball") || die "couldn't hash downloaded $tarball"
  actual=$(cut -d' ' -f1 <<<"$hash_line")
  [ "$expected" = "$actual" ] || die "checksum mismatch for $tarball"

  tar -xzf "$workdir/$tarball" -C "$workdir" tailcat
  install -m 755 "$workdir/tailcat" "$TAILCAT_BIN"
  rm -rf "$workdir"
}

cmd_new() {
  need ssh-keygen
  need base64
  ensure_tailcat

  local id sess_dir client_key
  id="sess-$(date +%s)-$(mktemp -u XXXXXX)"
  sess_dir="$CACHE_DIR/$id"
  mkdir -p "$sess_dir"
  client_key="$id-client"

  ssh-keygen -q -t ed25519 -f "$sess_dir/id_ed25519" -N "" -C "remote-session:$id"

  local address_out address client_out client_nodekey pubkey tailkey_b64
  address_out=$("$TAILCAT_BIN" genkey --key="$id" --fixed-region) || die "tailcat genkey (server) failed"
  address=$(tail -n1 <<<"$address_out")
  [ -n "$address" ] || die "tailcat genkey (server) produced no address"

  client_out=$("$TAILCAT_BIN" genkey --client --key="$client_key") || die "tailcat genkey --client failed"
  client_nodekey=$(tail -n1 <<<"$client_out")
  [ -n "$client_nodekey" ] || die "tailcat genkey --client produced no node key"

  pubkey=$(cat "$sess_dir/id_ed25519.pub")
  tailkey_b64=$(base64 -w0 "$TAILCAT_CONFIG_DIR/keys/$id.private.json")

  {
    printf 'ADDRESS=%q\n' "$address"
    printf 'CLIENT_KEY=%q\n' "$client_key"
  } >"$sess_dir/meta.env"

  {
    echo "curl -fsSL $REMOTE_ACCESS_URL \\"
    echo "  | PUBKEY=\"$pubkey\" TAILKEY_B64=\"$tailkey_b64\" ALLOW=\"$client_nodekey\" sh"
  } >"$sess_dir/remote-cmd.txt"
  chmod 600 "$sess_dir/remote-cmd.txt"

  echo "Session: $id" >&2
  echo "Command to run on the remote box is in the file below -- it contains real" >&2
  echo "key material, so read it yourself (e.g. 'cat') and paste it onto the remote" >&2
  echo "box directly, rather than relaying it through an agent's own transcript/logs:" >&2
  echo "Then: $0 connect $id" >&2
  echo "$sess_dir/remote-cmd.txt"
}

cmd_connect() {
  local id="${1:-}"
  [ -n "$id" ] || usage
  shift
  need ssh-agent
  need ssh-add
  need timeout
  ensure_tailcat

  local sess_dir="$CACHE_DIR/$id"
  [ -d "$sess_dir" ] || die "unknown session: $id (expected $sess_dir)"
  local ADDRESS CLIENT_KEY
  # shellcheck source=/dev/null
  source "$sess_dir/meta.env"

  eval "$(ssh-agent -s)" >/dev/null
  trap 'kill "$SSH_AGENT_PID" >/dev/null 2>&1 || true' EXIT
  ssh-add "$sess_dir/id_ed25519" >/dev/null

  echo "==> connecting to session $id ($ADDRESS)" >&2
  timeout "$CONNECT_TIMEOUT" "$TAILCAT_BIN" --key="$CLIENT_KEY" ssh "$ADDRESS" "$@"
}

case "${1:-}" in
  new) cmd_new ;;
  connect) shift; cmd_connect "$@" ;;
  *) usage ;;
esac
