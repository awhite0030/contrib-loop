- Conventional Commits style for PR/commit titles (fix:, feat(vscode):, ci:).
- User-facing changes require a changeset: add a `.changeset/<slug>.md` file with
  a one-line summary. Docs-only or chore PRs may skip it.
- New features MUST include tests in `.spec.ts`/`.tsx` files; bug fixes should
  include a regression test. Tests live next to the code or in `__tests__/`.
- Never modify `benchmarks/baseline.json`, `CHANGELOG.md` or package versions.
- Style is enforced by Biome (tabs); pre-commit hook auto-formats staged files.
- Do not use `--no-verify`.
