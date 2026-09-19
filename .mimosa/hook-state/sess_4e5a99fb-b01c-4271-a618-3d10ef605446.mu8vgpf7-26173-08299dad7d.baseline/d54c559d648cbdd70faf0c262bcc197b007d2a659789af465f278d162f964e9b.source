#!/usr/bin/env bash
# Validate a kana-dojo PR. Requires Node 18+. $1 = PR tree.
# NB: upstream AGENTS.md forbids npm run build as verification - do not add it.
set -euo pipefail
tree="${1:?}"
cd "$tree"

npm ci
npm run check
npm run i18n:check
