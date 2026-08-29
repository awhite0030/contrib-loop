#!/usr/bin/env bash
# Validate a tapflow PR. Requires Node 22 + pnpm (corepack). $1 = PR tree.
set -euo pipefail
tree="${1:?}"
cd "$tree"

corepack enable >/dev/null 2>&1 || true
pnpm install --frozen-lockfile
pnpm lint
pnpm typecheck
pnpm build
pnpm test
