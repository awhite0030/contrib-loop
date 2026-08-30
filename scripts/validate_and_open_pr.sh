#!/usr/bin/env bash
# Validate a completed Jules fork PR against the target's own commands, and on
# success open the pull request upstream. Runs inside loop.yml (validate mode)
# with the PR tree checked out at "$PR_TREE" and the target toolchain installed.
set -euo pipefail

. scripts/lib.sh

TARGET="${VALIDATE_TARGET:?}"
ISSUE="${VALIDATE_ISSUE:?}"
PR_NUM="${VALIDATE_PR_NUMBER:?}"        # fork PR number
PR_TREE="${PR_TREE:-pr-tree}"
UPSTREAM=$(cfg_target "$TARGET" upstream)
FORK=$(cfg_target "$TARGET" fork)
PR_BASE=$(cfg_target "$TARGET" base_branch); PR_BASE=${PR_BASE:-main}
MAX_BODY=$(cfg_target "$TARGET" max_pr_body_chars)

pr_json=$(gh api "repos/${FORK}/pulls/${PR_NUM}")
pr_branch=$(jq -r '.head.ref' <<<"$pr_json")
fork_owner=${FORK%%/*}
pr_title=$(jq -r '.title' <<<"$pr_json")
pr_body=$(jq -r '.body // ""' <<<"$pr_json")

# Strip Jules provenance footer from the fork PR body (and sync the edit back
# to the fork) so it never reaches the upstream PR.
clean_body=$(jq -rn --arg b "$pr_body" '
  $b | split("\n")
  | map(select(
      (test("created automatically by Jules"; "i") | not)
      and (test("jules[.]google[.]com/task") | not)
      and (test("^---\\s*$") | not)))
  | join("\n")
  | gsub("\\n{3,}"; "\n\n")')
if [ "$clean_body" != "$pr_body" ]; then
  tmp_body=$(mktemp); printf '%s' "$clean_body" > "$tmp_body"
  gh pr edit "$PR_NUM" -R "$FORK" --body-file "$tmp_body" >/dev/null 2>&1 || true
  rm -f "$tmp_body"
fi
pr_body="$clean_body"

# --- validate in the PR tree -----------------------------------------------------
echo "::group::Validate ${TARGET} (fork PR #${PR_NUM}, branch ${pr_branch})"
if ! bash "scripts/validate/${TARGET}.sh" "$PR_TREE"; then
  echo "::endgroup::"
  retries=$(jq -r --arg t "$TARGET" --arg i "$ISSUE" \
    '.targets[$t].tasks[$i].retries // 0' <<<"$(state_get)")
  if [ "${retries:-0}" -ge 1 ]; then
    echo "validation FAILED again for ${TARGET} fork PR #${PR_NUM} - closing (terminal)"
    gh pr close "$PR_NUM" -R "$FORK" \
      --comment "Automated validation failed again; closing. The loop will pick the next task." || true
    new_status="validation_failed"
  else
    echo "validation FAILED for ${TARGET} fork PR #${PR_NUM} - scheduling a retry session on the same branch"
    gh pr comment "$PR_NUM" -R "$FORK" \
      --body "Automated validation failed. A follow-up fix session will continue from this branch." || true
    new_status="validation_retry"
  fi
  state=$(state_get)
  state=$(jq -c --arg t "$TARGET" --arg i "$ISSUE" --arg s "$new_status" --argjson r "$((retries + 1))" \
    '.targets[$t].tasks[$i].status = $s | .targets[$t].tasks[$i].retries = $r' <<<"$state")
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
  echo "PR cap for ${TARGET} reached today (${prs_today}/${pr_cap}) - keeping fork PR #${PR_NUM} open for tomorrow"
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
