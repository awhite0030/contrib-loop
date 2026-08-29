#!/usr/bin/env bash
# One cycle of the contribution loop:
#   reconcile all target sessions -> pick one completed PR for validation ->
#   dispatch new tasks within budget -> decide what the next run should do.
# Outputs (for the workflow): mode = validate|watch|idle, plus validate_* fields.
set -euo pipefail
cd "${GITHUB_WORKSPACE:-.}"

. scripts/lib.sh
load_config

TODAY=$(date -u +%F)
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
GLOBAL_CAP=$(cfg_globals daily_task_cap); GLOBAL_CAP=${GLOBAL_CAP:-92}
TIMEOUT_H=$(cfg_globals session_timeout_hours); TIMEOUT_H=${TIMEOUT_H:-6}
OVERRIDE_TARGET="${OVERRIDE_TARGET:-}"
OVERRIDE_ISSUE="${OVERRIDE_ISSUE:-}"

state=$(state_get)

# --- day rollover: reset per-day counters ---------------------------------------
if [ "$(jq -r --arg d "$TODAY" 'if .day == $d then "same" else "new" end' <<<"$state")" = "new" ]; then
  state=$(jq -c --arg d "$TODAY" '.day = $d | .dispatchedDay = {} | .prsDay = {}' <<<"$state")
fi

# --- 1. reconcile sessions for every target --------------------------------------
for target in $(jq -r 'keys[] | select(. != "globals")' "$CFG_JSON"); do
  for issue in $(jq -r --arg t "$target" '
      (.targets[$t].tasks // {}) | to_entries[]
      | select(.value.status == "dispatched") | .key' <<<"$state"); do
    sid=$(jq -r --arg t "$target" --arg i "$issue" '.targets[$t].tasks[$i].sessionId' <<<"$state")
    [ -n "$sid" ] && [ "$sid" != "null" ] || continue
    sess=$(jules_get_session "$sid")
    st=$(jq -r '.state // "UNKNOWN"' <<<"$sess")
    ts=$(jq -r --arg t "$target" --arg i "$issue" '.targets[$t].tasks[$i].ts // ""' <<<"$state")
    cutoff=$(date -u -d "${TIMEOUT_H} hours ago" +%Y-%m-%dT%H:%M:%SZ)

    case "$st" in
      COMPLETED)
        pr_url=$(jq -r '[.outputs // [] | .[] | .pullRequest.url // empty] | first // empty' <<<"$sess")
        if [ -n "$pr_url" ] && [ "$pr_url" != "null" ]; then
          state=$(jq -c --arg t "$target" --arg i "$issue" --arg u "$pr_url" \
            '.targets[$t].tasks[$i].status = "in_review" | .targets[$t].tasks[$i].forkPr = $u' <<<"$state")
          echo "reconcile[$target] #$issue: session completed -> fork PR awaiting validation"
        else
          state=$(jq -c --arg t "$target" --arg i "$issue" \
            '.targets[$t].tasks[$i].status = "no_pr"' <<<"$state")
          echo "reconcile[$target] #$issue: session completed with no PR"
        fi
        ;;
      FAILED)
        echo "reconcile[$target] #$issue: session FAILED"
        state=$(jq -c --arg t "$target" --arg i "$issue" \
          '.targets[$t].tasks[$i].status = "failed"' <<<"$state")
        ;;
      AWAITING_USER_FEEDBACK)
        nudges=$(jq -r --arg t "$target" --arg i "$issue" '.targets[$t].tasks[$i].nudges // 0' <<<"$state")
        if [ "$nudges" -lt 3 ]; then
          jules_send_message "$sid" scripts/nudge.txt >/dev/null \
            && echo "reconcile[$target] #$issue: waiting for feedback -> nudged ($((nudges + 1))/3)"
          state=$(jq -c --arg t "$target" --arg i "$issue" --argjson c "$((nudges + 1))" \
            '.targets[$t].tasks[$i].nudges = $c' <<<"$state")
        else
          echo "reconcile[$target] #$issue: asked again after 3 nudges -> stuck"
          state=$(jq -c --arg t "$target" --arg i "$issue" \
            '.targets[$t].tasks[$i].status = "stuck"' <<<"$state")
        fi
        ;;
      AWAITING_PLAN_APPROVAL)
        jules_approve_plan "$sid" >/dev/null \
          && echo "reconcile[$target] #$issue: plan approved automatically"
        ;;
      QUEUED|PLANNING|IN_PROGRESS|PAUSED)
        if [ "${ts:-}" \< "$cutoff" ]; then
          echo "reconcile[$target] #$issue: stuck in $st since $ts"
          state=$(jq -c --arg t "$target" --arg i "$issue" \
            '.targets[$t].tasks[$i].status = "stuck"' <<<"$state")
        fi
        ;;
    esac
  done
done

# --- 2. pick one completed fork PR for validation --------------------------------
VALIDATE_TARGET=""; VALIDATE_ISSUE=""; VALIDATE_PR_URL=""
for target in $(jq -r 'keys[] | select(. != "globals")' "$CFG_JSON"); do
  hit=$(jq -r --arg t "$target" '
    (.targets[$t].tasks // {}) | to_entries[]
    | select(.value.status == "in_review" and ((.value.upstreamPr // "") == ""))
    | .key' <<<"$state" | head -1)
  if [ -n "$hit" ]; then
    VALIDATE_TARGET="$target"
    VALIDATE_ISSUE="$hit"
    VALIDATE_PR_URL=$(jq -r --arg t "$target" --arg i "$hit" '.targets[$t].tasks[$i].forkPr' <<<"$state")
    break
  fi
done

state=$(state_prune <<<"$state")

# --- 3. dispatch new tasks for eligible targets -----------------------------------
if [ -z "$VALIDATE_TARGET" ]; then
  used=$(jules_sessions_last_24h)
  echo "budget: ${used}/${GLOBAL_CAP} sessions in the last 24h"

  for target in $(jq -r 'keys[] | select(. != "globals")' "$CFG_JSON"); do
    if [ -n "$OVERRIDE_TARGET" ] && [ "$target" != "$OVERRIDE_TARGET" ]; then continue; fi

    upstream=$(cfg_target "$target" upstream)
    fork=$(cfg_target "$target" fork)
    budget=$(cfg_target "$target" budget)
    jules_branch=$(cfg_target "$target" jules_branch); jules_branch=${jules_branch:-main}

    in_flight=$(jq -r --arg t "$target" '[(.targets[$t].tasks // {}) | to_entries[]
                 | select(.value.status == "dispatched")] | length' <<<"$state")
    [ -n "$OVERRIDE_TARGET" ] && in_flight=0
    if [ "${in_flight:-0}" -gt 0 ]; then echo "dispatch[$target]: session in flight, skipping"; continue; fi
    if [ "${used:-0}" -ge "${GLOBAL_CAP:-92}" ]; then echo "dispatch[$target]: global cap reached"; continue; fi

    used_today=$(jq -r --arg t "$target" --arg d "$TODAY" \
      'if .day == $d then (.dispatchedDay[$t] // 0) else 0 end' <<<"$state")
    if [ "${used_today:-0}" -ge "${budget:-0}" ]; then echo "dispatch[$target]: budget spent"; continue; fi

    prs_today=$(jq -r --arg t "$target" --arg d "$TODAY" \
      'if .day == $d then (.prsDay[$t] // 0) else 0 end' <<<"$state")
    pr_cap=$(cfg_target "$target" max_prs_per_day)
    [ -n "$OVERRIDE_TARGET" ] && pr_cap=$((pr_cap + prs_today))
    if [ "${prs_today:-0}" -ge "${pr_cap:-0}" ]; then echo "dispatch[$target]: PR cap for today reached"; continue; fi

    # discovery: oldest open unassigned issue with any wanted label, not yet handled
    issues_json="[]"
    while IFS= read -r l; do
      [ -n "$l" ] || continue
      batch=$(gh issue list -R "$upstream" --state open --limit 40 --label "$l" \
        --json number,title,labels,assignees,createdAt 2>/dev/null || echo "[]")
      issues_json=$(jq -c 'add | unique_by(.number)' <<<"[$issues_json, $batch]")
    done <<<"$(cfg_target_labels "$target")"
    handled=$(jq -c --arg t "$target" \
      '[(.targets[$t].tasks // {}) | keys[], (.targets[$t].prs // {}) | keys[]] | unique' <<<"$state")
    excl=$(cfg_target_exclude "$target" | jq -Rsc 'split("\n") | map(select(length > 0))')
    candidates=$(jq -c --argjson handled "$handled" --argjson excl "$excl" '
      [.[]
       | select((.assignees | length) == 0)
       | select((.number | tostring) as $n | ($handled | index($n) | not))
       | select((.labels | map(.name)) as $ls | ($excl | all(. as $x | ($ls | index($x) | not))))]'
      <<<"$issues_json")

    chosen=""
    if [ -n "$OVERRIDE_ISSUE" ]; then
      chosen=$(jq -c --argjson n "$OVERRIDE_ISSUE" '[.[] | select(.number == $n)] | first // empty' <<<"$candidates")
    else
      chosen=$(jq -c 'sort_by(.createdAt) | first // empty' <<<"$candidates")
    fi
    if [ -z "$chosen" ]; then
      echo "dispatch[$target]: no candidates (issues=$(jq length <<<"${issues_json:-[]}") handled=$handled excl=$excl)"
      continue
    fi

    issue=$(jq -r .number <<<"$chosen")
    title=$(jq -r .title <<<"$chosen")
    echo "dispatch[$target]: issue #$issue - $title"

    # claim etiquette: comment first; strict claimers verify the assignment landed
    if [ "$(cfg_target "$target" claim_comment)" = "true" ]; then
      gh issue comment -R "$upstream" "$issue" --body "Picking this up - a fix will follow shortly." >/dev/null
      echo "dispatch[$target]: claimed #$issue"
      if [ "$(cfg_target "$target" claim_verify)" = "true" ]; then
        sleep 30
        assignees=$(gh issue view -R "$upstream" "$issue" --json assignees --jq '[.assignees[].login] | join(",")')
        if [ "$assignees" != "awhite0030" ]; then
          echo "dispatch[$target]: claim on #$issue lost (assignees: ${assignees:-none}) - skipping"
          state=$(jq -c --arg t "$target" --arg i "$issue" --arg now "$NOW" \
            '.targets[$t].tasks[$i] = {ts: $now, status: "claim_lost"}' <<<"$state")
          continue
        fi
      fi
    fi

    # keep the fork current, verify Jules can see it, then dispatch
    gh api -X POST "repos/${fork}/merge-upstream" -F branch="${jules_branch}" >/dev/null 2>&1 || true
    if ! jules_sources_has "$fork"; then
      echo "dispatch[$target]: WARNING $fork is not connected to Jules - connect it at https://jules.google.com"
      continue
    fi

    body_file=$(mktemp); comments_file=$(mktemp); prompt_file=$(mktemp); payload_file=$(mktemp)
    gh issue view -R "$upstream" "$issue" --json body --jq '.body // ""' | head -c 8000 > "$body_file"
    gh issue view -R "$upstream" "$issue" --json comments \
      --jq '[.comments[] | "[\(.author.login)]: \(.body | .[0:1500])"] | join("\n\n")' > "$comments_file"

    {
      cat prompt_template.md
      printf '\n--- Issue #%s: %s\n' "$issue" "$title"
      printf 'URL: https://github.com/%s/issues/%s\n\nIssue body:\n' "$upstream" "$issue"
      cat "$body_file"
      printf '\n\n--- Issue comments ---\n'
      cat "$comments_file"
      printf '\n\n--- Validation commands (must pass before you finish) ---\n'
      cat "scripts/validate/${target}.sh"
      printf '\n\n--- Repository rules ---\n'
      cat "rules/${target}.md"
    } > "$prompt_file"

    jq -n \
      --rawfile prompt "$prompt_file" \
      --arg src "sources/github/${fork}" \
      --arg title "Fix issue #${issue}: ${title}" \
      --arg branch "$jules_branch" \
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
      echo "dispatch[$target]: ERROR Jules API: $(jq -r '.error.message // .' <<<"$resp")"
      rm -f "$body_file" "$comments_file" "$prompt_file" "$payload_file"
      continue
    fi
    sid=${session_name##*/}
    session_url=$(jq -r '.url // empty' <<<"$resp")
    echo "dispatch[$target]: session $sid ($session_url) for issue #$issue"

    state=$(jq -c --arg t "$target" --arg i "$issue" --arg sid "$sid" --arg ts "$NOW" --arg u "$session_url" \
      '.targets[$t].tasks[$i] = {sessionId: $sid, ts: $ts, status: "dispatched", sessionUrl: $u}
       | .dispatchedDay[$t] = ((.dispatchedDay[$t] // 0) + 1)' <<<"$state")
    rm -f "$body_file" "$comments_file" "$prompt_file" "$payload_file"
  done
fi

state=$(state_prune <<<"$state")
state_set "$state"

# --- 4. decide the next step -------------------------------------------------------
if [ -n "$VALIDATE_TARGET" ]; then
  v_fork=$(cfg_target "$VALIDATE_TARGET" fork)
  v_pr_num=${VALIDATE_PR_URL##*/}
  v_branch=$(gh api "repos/${v_fork}/pulls/${v_pr_num}" --jq .head.ref)
  {
    echo "mode=validate"
    echo "validate_target=${VALIDATE_TARGET}"
    echo "validate_issue=${VALIDATE_ISSUE}"
    echo "validate_fork=${v_fork}"
    echo "validate_branch=${v_branch}"
  } >> "${GITHUB_OUTPUT:-/dev/null}"
  echo "next: validate ${VALIDATE_TARGET} issue #${VALIDATE_ISSUE} (branch ${v_branch})"
else
  busy=$(jq -r '[(.targets // {}) | to_entries[] | .value.tasks // {} | to_entries[]
           | select(.value.status == "dispatched" or .value.status == "in_review")] | length' <<<"$state")
  if [ "${busy:-0}" -gt 0 ]; then
    echo "watch: $busy task(s) in flight - sleeping 10m, then re-checking"
    sleep 600
    echo "mode=watch" >> "${GITHUB_OUTPUT:-/dev/null}"
  else
    echo "mode=idle" >> "${GITHUB_OUTPUT:-/dev/null}"
    echo "idle: nothing in flight, nothing to dispatch (hourly cron will re-check)"
  fi
fi
echo "done"
