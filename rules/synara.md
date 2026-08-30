- ONLY small, focused bug fixes. The maintainers close large/drive-by/feature
  PRs quickly and may ban 1000+ line PRs. One issue = one minimal fix.
- Bun monorepo: `bun install --frozen-lockfile`; lint via oxlint, typecheck via
  tsc; tests: `bun run test` (full) or `bun run test:web:focused <path>`.
- Every PR needs: What Changed / Why / Verification sections; UI changes need
  before-after screenshots - avoid UI-only changes.
- PRs are auto-labeled vouch:* / size:*; unvouched external PRs are normal -
  small fixes get merged in waves, keep the diff tiny.
- Reference the open bug issue in the PR; reproduction evidence helps.
- No CLA/DCO. MIT.
