#!/usr/bin/env bash
# Validate a nanocoder PR. Requires Node 22 + pnpm (corepack). $1 = PR tree.
set -euo pipefail
tree="${1:?}"
cd "$tree"

corepack enable >/dev/null 2>&1 || true
pnpm install --frozen-lockfile
pnpm run build
pnpm test:format
pnpm test:lint
pnpm test:types
pnpm test:knip
pnpm test:ava
