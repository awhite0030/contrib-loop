#!/usr/bin/env bash
# Validate a formae PR (pilot). Requires Go 1.25+. $1 = PR tree.
# Full upstream CI (pkl, REUSE, e2e) runs on the PR itself; this is the fast gate.
set -euo pipefail
tree="${1:?}"
cd "$tree"

go build ./...
go vet ./...
