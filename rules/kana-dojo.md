- Conventional Commits required: `feat(theme): ...`, `fix(vocab): ...`,
  `content: add ...` for data/JSON content files.
- Do NOT run `npm run build` for verification (upstream AGENTS.md forbids it);
  `npm run check` (tsc + eslint) is the gate.
- Style: use the `cn()` helper from `lib/utils.ts` for class names.
- User-facing strings go through next-intl namespace JSON; run `npm run i18n:check`.
- Content additions (themes, trivia, haiku, proverbs, facts) go in
  `community/content/` JSON files and follow the existing entry schema exactly.
