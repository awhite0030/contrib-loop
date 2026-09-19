#!/usr/bin/env bash
# Validate a bernstein PR. Requires uv. $1 = PR tree.
set -euo pipefail
tree="${1:?}"
cd "$tree"

uv venv
uv pip install -e ".[dev]"
uv run ruff check src/
uv run lint-imports
uv run pyright src/
# Safe isolated runner; NEVER raw pytest (2000+ tests leak 100+ GB RAM).
uv run python scripts/run_tests.py -x
