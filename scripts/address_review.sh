#!/usr/bin/env bash
# Trigger a Jules session that addresses reviewer feedback on an existing fork
# PR. Used to act on will-lamerton's blocking reviews without human in the loop.
# Args: TARGET UPSTREAM FORK_OWNER PR_NUMBER ISSUE_NUM "REVIEW_QUOTED"
set -euo pipefail
. /Users/zaharfomenko/.zcode/workspace/default/contrib-loop/scripts/lib.sh

TARGET="$1"; UPSTREAM="$2"; FORK_OWNER="$3"; PR_NUM="$4"; ISSUE_NUM="$5"
shift 5; REVIEW="$*"

pr_branch=$(gh api "repos/${FORK_OWNER}/${TARGET}/pulls/${PR_NUM}" --jq .head.ref)
[ -n "$pr_branch" ] || { echo "PR #${PR_NUM} branch not found" >&2; exit 1; }

# Sync fork with upstream so we start on latest code
gh api -X POST "repos/${FORK_OWNER}/${TARGET}/merge-upstream" -F branch=main >/dev/null 2>&1 || true

body_file=$(mktemp); prompt_file=$(mktemp); payload_file=$(mktemp)
trap 'rm -f "$body_file" "$prompt_file" "$payload_file"' RETURN

gh issue view -R "$UPSTREAM" "$ISSUE_NUM" --json body --jq '.body // ""' | head -c 4000 > "$body_file"

{
  cat /Users/zaharfomenko/.zcode/workspace/default/contrib-loop/prompt_template_review.md
  printf '\n--- Reviewer feedback on PR #%s (branch %s) ---\n' "$PR_NUM" "$pr_branch"
  printf 'PR URL: https://github.com/%s/%s/pull/%s\n\n' "$UPSTREAM" "$TARGET" "$PR_NUM"
  printf '%s\n' "$REVIEW"
  printf '\n--- Issue #%s body (context) ---\n' "$ISSUE_NUM"
  cat "$body_file"
  printf '\n\n--- Validation commands (must pass before you finish) ---\n'
  cat "/Users/zaharfomenko/.zcode/workspace/default/contrib-loop/scripts/validate/${TARGET}.sh"
  printf '\n\n--- Repository rules ---\n'
  cat "/Users/zaharfomenko/.zcode/workspace/default/contrib-loop/rules/${TARGET}.md"
} > "$prompt_file"

jq -n \
  --rawfile prompt "$prompt_file" \
  --arg src "sources/github/${FORK_OWNER}/${TARGET}" \
  --arg title "Address review: ${TARGET}#${PR_NUM}" \
  --arg branch "$pr_branch" \
  '{
    prompt: $prompt,
    sourceContext: { source: $src, githubRepoContext: { startingBranch: $branch } },
    requirePlanApproval: false,
    automationMode: "AUTO_CREATE_PR",
    title: $title
  }' > "$payload_file"

resp=$(jules_create_session "$payload_file")
session_name=$(jq -r '.name // empty' <<<"$resp")
if [ -z "$session_name" ]; then
  echo "ERROR: Jules API: $(jq -r '.error.message // .' <<<"$resp")"
  exit 1
fi
sid=${session_name##*/}
echo "session $sid for review of ${TARGET}#${PR_NUM} (issue #${ISSUE_NUM})"
echo "url: $(jq -r '.url // empty' <<<"$resp")"
