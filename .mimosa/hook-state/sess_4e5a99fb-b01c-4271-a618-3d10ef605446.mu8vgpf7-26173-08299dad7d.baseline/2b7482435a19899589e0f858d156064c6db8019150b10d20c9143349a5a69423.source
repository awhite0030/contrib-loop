#!/usr/bin/env bash
# Validate a mteb PR. Requires uv. $1 = PR tree.
# make test already excludes the heavy dataset/reference-model suites.
set -euo pipefail
tree="${1:?}"
cd "$tree"

make install
make lint
make typecheck
make test
