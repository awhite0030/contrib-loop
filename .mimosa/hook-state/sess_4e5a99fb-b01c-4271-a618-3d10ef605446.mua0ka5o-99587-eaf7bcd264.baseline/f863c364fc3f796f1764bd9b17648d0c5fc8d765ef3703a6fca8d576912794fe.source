#!/usr/bin/env bash
# Validate an updatecli PR. Requires Go (per go.mod). $1 = PR tree.
set -euo pipefail
tree="${1:?}"
cd "$tree"

go build ./...
make test-short
