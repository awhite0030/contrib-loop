#!/usr/bin/env bash
# Validate a synara PR. Requires Bun. $1 = PR tree.
set -euo pipefail
tree="${1:?}"
cd "$tree"

bun install --frozen-lockfile
bun run lint
bun run typecheck
bun run test
