#!/usr/bin/env bash
# Validate a rakazo PR. Requires Node 22 + pnpm (corepack). $1 = PR tree.
# Unit tests are offline/deterministic; integration (Docker) and e2e are CI-only.
set -euo pipefail
tree="${1:?}"
cd "$tree"

corepack enable >/dev/null 2>&1 || true
cp -n .env.example .env || true
pnpm install --frozen-lockfile
pnpm check
pnpm lint
pnpm test
