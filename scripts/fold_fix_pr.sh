#!/usr/bin/env bash
# Fold a review-fix fork PR into the ORIGINAL PR branch so the upstream PR
# gets the fixes as a new commit (GitHub auto-updates the upstream PR).
# Jules cannot push to an existing branch (API limitation), so the review
# session opens a new PR on the fork; this script merges that work back.
# Args: FORK_OWNER TARGET ORIGINAL_PR_NUM FIX_PR_NUM
set -euo pipefail
. scripts/lib.sh
load_config

FORK_OWNER="$1"; TARGET="$2"; ORIG_PR="$3"; FIX_PR="$4"

orig_branch=$(gh api "repos/${FORK_OWNER}/${TARGET}/pulls/${ORIG_PR}" --jq .head.ref)
fix_branch=$(gh api "repos/${FORK_OWNER}/${TARGET}/pulls/${FIX_PR}" --jq .head.ref)
echo "orig=$orig_branch fix=$fix_branch"

work=$(mktemp -d)
trap 'rm -rf "$work"' RETURN
git clone --quiet "https://github.com/${FORK_OWNER}/${TARGET}.git" "$work/repo"
cd "$work/repo"
git config user.name "awhite0030"
git config user.email "awhite0030@users.noreply.github.com"
git fetch --quiet origin "$orig_branch" "$fix_branch"

git checkout --quiet -B "$orig_branch" "origin/$orig_branch"
# bring the fix commits; prefer merge to preserve the reviewer-facing history
if ! git merge --quiet --no-edit "origin/$fix_branch" 2>/dev/null; then
  echo "merge conflict - falling back to cherry-pick of fix commits"
  git merge --abort 2>/dev/null || true
  git log --oneline "origin/$orig_branch..origin/$fix_branch" | tac | while read -r sha _; do
    git cherry-pick "$sha" || { git cherry-pick --abort 2>/dev/null; echo "CONFLICT on $sha - stopping"; exit 1; }
  done
fi

git push --quiet "https://x-access-token:${GH_TOKEN}@github.com/${FORK_OWNER}/${TARGET}.git" "$orig_branch"
echo "pushed fixes into $orig_branch - upstream PR will update automatically"
