- PR title format REQUIRED: `type: user-facing description` with type in
  feat|fix|improve|refactor|docs|chore. Fix titles state the user-visible
  symptom, not the implementation.
- PR body template is MANDATORY: What Problem This Solves / Why This Change Was
  Made / User Impact / Evidence. Code changes need a "## Real Behavior Proof"
  package: claim, surface, fixture, command+env, observed result, artifact, limits.
- NEVER touch files owned by @openclaw/openclaw-sesops in CODEOWNERS (workflows,
  package.json, pnpm-lock.yaml) - that requires maintainer routing.
- Never open PRs for issues labeled `clawsweeper:no-new-fix-pr` or with
  `clawsweeper:linked-pr-open`.
- No automerge/approve/workflow-dispatch routes for agents; agents must not merge.
- Node 24, pnpm 11; validation gate is `pnpm run check` (15 min CI timeout).
- Do not summon parallel repair lanes when a maintainer is actively repairing.
