- PRs must target the `develop` branch, never `main`.
- Every new user-facing string must be added to ALL nine ARB files
  (intl_en/de/cs/it/pl/sk/tr/uk/zh.arb) with a real translation (machine
  translation is acceptable as a start). Never hand-edit `lib/generated/`.
- Run code generation after changing @HiveType/@HiveField/@JsonSerializable types.
- Line width 120; run the formatter before finishing.
- PR title follows conventional commits: `fix: ...` / `feat(scope): ...`.
- Mention the fixed issue in the PR description (`Fixes #123`).
- New interactive widgets need `Semantics(identifier: '...')`.
- Do not add AI assistants as commit co-authors; no Co-authored-by trailers.
