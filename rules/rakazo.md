- pnpm monorepo (turbo). Setup: `cp .env.example .env`, then `pnpm install`.
- Unit tests (`pnpm test`) are deterministic and offline - they must pass
  WITHOUT Docker, Postgres or network. Integration/e2e tests are out of scope
  for the automated validation (CI runs them).
- `pnpm check` (tsc) and `pnpm lint` (Biome) must pass.
- Keep PRs small and focused on one issue; target `main`.
- AGENTS.md: after opening a PR stay with it until CI/review bots finish;
  do not merge; never commit secrets; keep connector tests offline.
- PR body: describe what changed and how it was tested; link the issue.
