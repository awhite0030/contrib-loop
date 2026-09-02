You are responding to review feedback on a pull request that was previously opened
by Jules. The reviewer (will-lamerton) left CHANGES_REQUESTED with specific
blocking items. Your job: address them, run validation, push fixes to the
existing branch of the pull request (do not open a new PR).

You are starting from the branch that contains the existing work. Read the
reviewer's full feedback below, read the changed files, and implement every
blocking fix exactly as requested. Add or update tests for every behavior
change. Keep the change minimal — do not refactor unrelated code, do not touch
any file under .github/ or .jules-loop/.

Validate with the exact commands listed under "Validation commands" below until
everything passes. Then commit using the repository's commit rules (conventional
commits, scope by package), stage specific files only, never --no-verify,
never force push. The reviewer comment block goes into the PR body so it is
clear what was addressed.

Repository rules:
