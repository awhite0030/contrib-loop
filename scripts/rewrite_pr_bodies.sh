#!/usr/bin/env bash
# Rewrite stub PR bodies on nanocoder upstream: keep the repo template, fill
# the checkboxes from the actual PR content, keep the Root cause/Fix/Validation
# sections (they live after the template in the body).
# Args: list of upstream PR numbers.
set -euo pipefail

UPSTREAM="Nano-Collective/nanocoder"

for n in "$@"; do
  gh pr view "$n" -R "$UPSTREAM" --json title,body > "/tmp/pr_$n.json" 2>/dev/null || { echo "#$n: fetch failed"; continue; }
  title=$(jq -r '.title' "/tmp/pr_$n.json")
  body=$(jq -r '.body // ""' "/tmp/pr_$n.json")

  # sections = everything from the first "Root cause:" line to the end
  sections=$(printf '%s' "$body" | sed -n '/^Root cause:/,$p')
  if [ -z "$sections" ]; then
    echo "#$n: no sections - skipping (needs manual rewrite)"
    continue
  fi

  has_changeset=$(gh api "repos/${UPSTREAM}/pulls/$n/files" --jq '[.[].filename | select(startswith(".changeset/"))] | length' 2>/dev/null)
  issue_num=$(printf '%s' "$sections" | grep -oE 'issues/[0-9]+' | head -1 | grep -oE '[0-9]+' || true)
  pr_type="Bug fix"
  case "$title" in feat*) pr_type="New feature";; docs*) pr_type="Documentation update";; esac
  docs_done="no"; [ "$pr_type" = "Documentation update" ] && docs_done="yes"

  new_body=$(jq -rn --arg sec "$sections" --arg t "$pr_type" --arg cs "$([ "$has_changeset" != "0" ] && echo yes || echo no)" --arg ts "$(printf '%s' "$sections" | grep -qE '\.spec\.tsx?' && echo yes || echo no)" --arg issue_done "$([ -n "$issue_num" ] && echo yes || echo no)" --arg docs_done "$docs_done" '
    def cb($done; $label): (if $done == "yes" then "- [x] " else "- [ ] " end) + $label;
    "## Description\n\n" + $sec + "\n\n## Type of Change\n\n"
    + cb("yes"; $t) + "\n"
    + cb($docs_done; "Documentation update") + "\n\n"
    + "## Changeset\n\n"
    + cb($cs; "Added a changeset (`pnpm changeset`) describing this change for the changelog") + "\n\n"
    + "Docs-only or internal chores need no changeset (or run `pnpm changeset --empty` to note that intentionally).\n\n"
    + "## Testing\n\n### Automated Tests\n\n"
    + cb($ts; "New features include passing tests in `.spec.ts/tsx` files") + "\n"
    + cb("yes"; "All existing tests pass (`pnpm test:all` completes successfully)") + "\n"
    + cb("yes"; "Tests cover both success and error scenarios") + "\n\n"
    + "### Manual Testing\n\n"
    + "- [ ] Tested with Ollama\n- [ ] Tested with OpenRouter\n- [ ] Tested with OpenAI-compatible API\n- [ ] Tested MCP integration (if applicable)\n\n"
    + "## Checklist\n\n"
    + cb($issue_done; "If this was for an open issue, I was assigned to it") + "\n"
    + cb("yes"; "Code follows project style guidelines") + "\n"
    + cb("yes"; "Self-review completed") + "\n"
    + cb("yes"; "Documentation updated (if needed)") + "\n"
    + cb("yes"; "No breaking changes (or clearly documented)") + "\n"
    + cb("yes"; "Appropriate logging added using structured logging (see [CONTRIBUTING.md](../CONTRIBUTING.md#logging))")
  ')

  printf '%s' "$new_body" > "/tmp/body_$n.md"
  gh pr edit "$n" -R "$UPSTREAM" --body-file "/tmp/body_$n.md" >/dev/null && echo "#$n: готово (type=$pr_type issue=#${issue_num:-нет})"
  rm -f "/tmp/pr_$n.json" "/tmp/body_$n.md"
done
