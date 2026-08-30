- uv is the package manager. NEVER run raw `pytest tests/ -x -q` - the full
  suite (2000+ tests) leaks 100+ GB of RAM. Use `uv run python scripts/run_tests.py -x`.
- Lint/typecheck: `uv run ruff check src/`, `uv run ruff format src/`,
  `uv run pyright src/`, `uv run lint-imports` (architecture contracts).
- Docs MUST ship in the same PR as the code change ("PRs without the matching
  docs change will be sent back") - update the relevant docs page yourself.
- Conventional, short PR titles; fill the PR template (What/Why/How + checklist).
- Comment on the issue to claim it. Add a release-note fragment file if the
  template asks for one.
- Type hints everywhere; `pyright src/` must pass.
- Do not touch benchmark baselines or generated files.
