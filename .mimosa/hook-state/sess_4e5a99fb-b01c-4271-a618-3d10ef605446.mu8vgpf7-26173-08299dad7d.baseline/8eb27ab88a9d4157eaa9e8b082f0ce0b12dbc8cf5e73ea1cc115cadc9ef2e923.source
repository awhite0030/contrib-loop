#!/usr/bin/env bash
# Validate a clawsweeper PR. Requires Node 24 + pnpm 11 (corepack). $1 = PR tree.
set -euo pipefail
tree="${1:?}"
cd "$tree"

corepack enable >/dev/null 2>&1 || true
pnpm install --frozen-lockfile
pnpm run build
pnpm run check
