#!/usr/bin/env bash
# Validate a completed Jules fork PR against the target's own commands, and on
# success open the pull request upstream. Runs inside loop.yml (validate mode)
# with the PR tree checked out at "$PR_TREE" and the target toolchain installed.
set -euo pipefail

. scripts/lib.sh

TARGET="${VALIDATE_TARGET:?}"
ISSUE="${VALIDATE_ISSUE:?}"
PR_URL="${VALIDATE_PR_URL:?}"          # fork PR url
PR_TREE="${PR_TREE:-pr-tree}"
UPSTREAM=$(cfg_target "$TARGET" upstream)
FORK=$(cfg_target "$TARGET" fork)
PR_BASE=$(cfg_target "$TARGET" base_branch); PR_BASE=${PR_BASE:-main}
MAX_BODY=$(cfg_target "$TARGET" max_pr_body_chars)

pr_num=${PR_URL##*/}
pr_json=$(gh api "repos/${FORK}/pulls/${pr_num}")
pr_branch=$(jq -r '.head.ref' <<<"$pr_json")
fork_owner=${FORK%%/*}
pr_title=$(jq -r '.title' <<<"$pr_json")
pr_body=$(jq -r '.body // ""' <<<"$pr_json")

# --- validate in the PR tree -----------------------------------------------------
echo "::group::Validate ${TARGET} (fork PR #${pr_num}, branch ${pr_branch})"
if ! bash "scripts/validate/${TARGET}.sh" "$PR_TREE"; then
  echo "::endgroup::"
  echo "validation FAILED for ${TARGET} fork PR #${pr_num} - closing"
  gh pr close "$pr_num" -R "$FORK" \
    --comment "Automated validation failed; closing. The loop will pick the next task." || true
  state=$(state_get)
  state=$(jq -c --arg t "$TARGET" --arg i "$ISSUE" '.targets[$t].tasks[$i].status = "validation_failed"' <<<"$state")
  state_set "$state"
  exit 1
fi
echo "::endgroup::"
echo "validation passed"

# --- build the upstream PR body ----------------------------------------------------
body_file=$(mktemp)
# extract the three sections with plain awk (robust, no fancy regex)
sections=$(awk '
  /^[[:space:]]*Root cause:/  {inrc=1; infx=0; invl=0}
  /^[[:space:]]*Fix:/         {inrc=0; infx=1; invl=0}
  /^[[:space:]]*Validation:/  {inrc=0; infx=0; invl=1}
  inrc {rc = rc $0 "\n"}
  infx {fx = fx $0 "\n"}
  invl {vl = vl $0 "\n"}
  END {
    if (rc != "") printf "%s", rc
    if (fx != "") printf "%s", fx
    if (vl != "") printf "%s", vl
  }' <<<"$pr_body")
[ -n "$sections" ] || sections="Fixes the issue with a minimal, focused change.

Validation: ${TARGET} lint, build and test commands pass."

# upstream PR template (if the repo has one) goes first - some repos require it
template=""
tmpl_b64=$(gh api "repos/${UPSTREAM}/contents/.github/pull_request_template.md" --jq .content 2>/dev/null || true)
[ -z "$tmpl_b64" ] && tmpl_b64=$(gh api "repos/${UPSTREAM}/contents/.github/PULL_REQUEST_TEMPLATE.md" --jq .content 2>/dev/null || true)
if [ -n "$tmpl_b64" ]; then
  template=$(base64 -d <<<"$tmpl_b64" 2>/dev/null || true)
fi

{
  [ -n "$template" ] && printf '%s\n\n---\n\n' "$template"
  printf '%s\n' "$sections"
  printf '\nFixes #%s\n' "$ISSUE"
} > "$body_file"

if [ -n "${MAX_BODY:-}" ]; then
  head -c "$MAX_BODY" "$body_file" > "$body_file.tmp" && mv "$body_file.tmp" "$body_file"
fi

# --- open the PR upstream -----------------------------------------------------------
prs_today=$(jq -r --arg t "$TARGET" --arg d "$(date -u +%F)" \
  'if .day == $d then (.prsDay[$t] // 0) else 0 end' <<<"$(state_get)")
pr_cap=$(cfg_target "$TARGET" max_prs_per_day)
if [ "${prs_today:-0}" -ge "${pr_cap:-0}" ]; then
  echo "PR cap for ${TARGET} reached today (${prs_today}/${pr_cap}) - keeping fork PR #${pr_num} open for tomorrow"
  exit 0
fi

upstream_url=$(gh pr create -R "$UPSTREAM" \
  --base "$PR_BASE" \
  --head "${fork_owner}:${pr_branch}" \
  --title "$pr_title" \
  --body-file "$body_file")
echo "upstream PR created: $upstream_url"

state=$(state_get)
state=$(jq -c --arg t "$TARGET" --arg i "$ISSUE" --arg u "$upstream_url" --arg d "$(date -u +%F)" '
  .targets[$t].tasks[$i].status = "pr_open"
  | .targets[$t].tasks[$i].upstreamPr = $u
  | .day = $d
  | .prsDay[$t] = ((.prsDay[$t] // 0) + 1)' <<<"$state")
state=$(state_prune <<<"$state")
state_set "$state"
echo "done"
