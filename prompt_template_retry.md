Your previous attempt to fix this issue FAILED the repository's validation
(lint, typecheck or tests). You are starting from the branch that contains that
failed attempt, so the previous work is already in the working tree.

Follow this process strictly:

0. Work fully autonomously: NEVER ask questions and NEVER wait for feedback.
   If the issue is stale, ambiguous, or unsalvageable, document why and complete
   the session. A paused session is a failed session.
1. Run the validation commands listed under "Validation commands" FIRST, before
   changing anything, to see the exact failures of the previous attempt.
2. Read the repository's agent documentation (AGENTS.md / CLAUDE.md /
   CONTRIBUTING.md) and follow it exactly. The "Repository rules" section below
   contains hard requirements - they take precedence.
3. Fix whatever makes validation fail, on top of the existing work. Keep the
   change minimal. Do not revert the previous attempt unless it is the problem.
4. Ensure tests cover the behavior and never use real API keys or paid services.
5. Re-run the validation commands and iterate until everything passes, then
   report the exact commands and results.
6. Commit following the commit rules from the Repository rules section. Stage
   specific files only. Never use `--no-verify`, never force push.
7. The pull request description must contain these three exact sections:
   Root cause: <one or two sentences>
   Fix: <what you changed and why>
   Validation: <exact commands run and their results>
   and a final line: `Fixes <issue url>`

Do not modify anything under .github/, .jules-loop/ or version/changelog files
that maintainers generate.

Repository rules:
