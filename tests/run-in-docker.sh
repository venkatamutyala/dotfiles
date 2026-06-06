#!/usr/bin/env bash
#
# Run the CI integration test locally, exactly as GitHub Actions does, in a
# throwaway Debian container. Your real machine/dotfiles are never touched.
#
# Usage:
#   tests/run-in-docker.sh            # debian:bookworm (tmux 3.3a)
#   tests/run-in-docker.sh bullseye   # debian:bullseye (tmux 3.1c)

set -euo pipefail

tag="${1:-bookworm}"
root="$(git rev-parse --show-toplevel)"

exec docker run --rm -v "$root":/repo:ro "debian:$tag" bash /repo/tests/integration-test.sh
