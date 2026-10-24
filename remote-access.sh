#!/bin/sh
# Run on a remote Linux box with outbound-only internet to open an ephemeral,
# key-only SSH session via tailcat (https://github.com/tailscale/tailcat) --
# no sshd, no package manager, and no root required (root just additionally
# gets you an isolated throwaway account instead of running as yourself).
#
#   curl -fsSL <url> | PUBKEY="ssh-ed25519 AAAA..." TAILKEY_B64="..." sh
#
# Required env vars (generated ahead of time on the connecting side):
#   PUBKEY       literal OpenSSH public key line to authorize
#   TAILKEY_B64  base64 of a tailcat server key file (tailcat genkey --fixed-region),
#                so the resulting tailcat address is known in advance
# Optional:
#   ALLOW        tailcat client node key ("nodekey:...") to also restrict at the tunnel layer
#   GRANT_SUDO   "1" to give the throwaway account passwordless sudo (default: no sudo)
#                note: cleanup runs on exit/Ctrl+C but can't run on `kill -9`/OOM/crash,
#                which would leave this account + its sudoers file behind permanently

set -eu

TAILCAT_VERSION=0.7.0

die() { echo "ERROR: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }

[ -n "${PUBKEY:-}" ] || die "PUBKEY env var is required (the SSH public key to authorize)"
[ -n "${TAILKEY_B64:-}" ] || die "TAILKEY_B64 env var is required (see: tailcat genkey --fixed-region)"

need curl
need tar
need sha256sum
need base64

[ "$(uname -s)" = "Linux" ] || die "this script only supports Linux"

case "$(uname -m)" in
  x86_64) ARCH=amd64 ;;
  aarch64) ARCH=arm64 ;;
  armv7l) ARCH=armv7 ;;
  *) die "unsupported architecture: $(uname -m)" ;;
esac

WORKDIR=$(mktemp -d)
EPHEMERAL_USER=""
SUDOERS_FILE=""

cleanup() {
  set +e
  [ -n "$SUDOERS_FILE" ] && rm -f "$SUDOERS_FILE"
  [ -n "$EPHEMERAL_USER" ] && userdel -r "$EPHEMERAL_USER" >/dev/null 2>&1
  rm -rf "$WORKDIR"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

echo "==> fetching tailcat v$TAILCAT_VERSION (linux/$ARCH)" >&2
BASE_URL="https://github.com/tailscale/tailcat/releases/download/v$TAILCAT_VERSION"
TARBALL="tailcat_${TAILCAT_VERSION}_linux_${ARCH}.tar.gz"

curl -fsSL -o "$WORKDIR/checksums.txt" "$BASE_URL/checksums.txt" || die "couldn't fetch checksums.txt"
curl -fsSL -o "$WORKDIR/$TARBALL" "$BASE_URL/$TARBALL" || die "couldn't fetch $TARBALL"

EXPECTED=$(grep " $TARBALL\$" "$WORKDIR/checksums.txt" | cut -d' ' -f1)
[ -n "$EXPECTED" ] || die "no checksum entry for $TARBALL in checksums.txt"
ACTUAL=$(sha256sum "$WORKDIR/$TARBALL" | cut -d' ' -f1)
[ "$EXPECTED" = "$ACTUAL" ] || die "checksum mismatch for $TARBALL"

tar -xzf "$WORKDIR/$TARBALL" -C "$WORKDIR" tailcat
chmod 755 "$WORKDIR/tailcat"

base64 -d >"$WORKDIR/session.private.json" <<EOF || die "TAILKEY_B64 did not decode as base64"
$TAILKEY_B64
EOF

set -- serve --key="$WORKDIR/session.private.json" --ssh-authorized-keys="$PUBKEY"
[ -n "${ALLOW:-}" ] && set -- "$@" --allow="$ALLOW"
set -- "$@" ssh

echo "==> starting tailcat: an ephemeral, key-only shell will be reachable by" >&2
echo "==> whoever holds the matching private key (and, if set, the allowed" >&2
echo "==> tailcat client identity). Ctrl+C ends the session and removes" >&2
echo "==> everything this script created." >&2

if [ "$(id -u)" = "0" ]; then
  need useradd
  need runuser
  EPHEMERAL_USER=$(mktemp -u claude-remote-XXXXXX)
  useradd -m -s /bin/sh "$EPHEMERAL_USER"
  if [ "${GRANT_SUDO:-0}" = "1" ]; then
    SUDOERS_FILE="/etc/sudoers.d/$EPHEMERAL_USER"
    echo "$EPHEMERAL_USER ALL=(ALL) NOPASSWD:ALL" >"$SUDOERS_FILE"
    chmod 440 "$SUDOERS_FILE"
  fi
  chown -R "$EPHEMERAL_USER:$EPHEMERAL_USER" "$WORKDIR"
  echo "==> session shell runs as throwaway account '$EPHEMERAL_USER' (sudo: ${GRANT_SUDO:-0})" >&2
  runuser -u "$EPHEMERAL_USER" -- "$WORKDIR/tailcat" "$@"
else
  echo "==> not root: running as the current user ($(id -un)), no throwaway account created" >&2
  "$WORKDIR/tailcat" "$@"
fi
