- Conventional Commits: `<type>(<scope>): <subject>` with type in
  feat|fix|test|refactor|docs|chore|perf and scope = changed package
  (agent-core|ios-agent|android-agent|relay|dashboard|cli|playground).
- Every PR that changes published source needs a changeset file (`.changeset/*.md`).
  Test-only or comment-only changes instead add this exact line to the PR body:
  `<!-- no-changeset: test-only -->`.
- Tests must be written to cover the new behavior and pass BEFORE the PR is opened.
  No `any`. Mock only at system boundaries. No flaky timing (use vi.useFakeTimers).
- Interface changes land in `agent-core` first.
- PRs, commit messages and code comments in English. No emojis.
- README.md and packages/cli/README.md must stay in sync if either changes.
- Do not touch CHANGELOG.md version headers or `benchmarks/baseline.json`.
