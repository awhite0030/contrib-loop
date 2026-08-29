- The pull request description MUST stay under 2000 characters - long PR
  descriptions are auto-labeled and may be closed without review. Be terse.
- Release prefixes (used by maintainers on squash): fix: (patch), model:/dataset:/
  feat: (minor). Prefer `fix: <short imperative summary>` as the PR title.
- Python code style via ruff (`make lint`); type hints via mypy (`make typecheck`).
- Tests must not download models or datasets; CI excludes the slow suites.
- Model/dataset additions need their checklists - avoid those issue types.
- No DCO/CLA. Link the issue in the PR description.
