# Shared helpers for the contrib-loop scripts. Source, do not execute.
# Requires env: GH_TOKEN (classic PAT), JULES_API_KEY (where Jules is called).

STATE_VAR="STATE"
JULES_API="https://jules.googleapis.com/v1alpha"
CFG_JSON="${CFG_JSON:-/tmp/contrib-loop-cfg.json}"

# --- config -------------------------------------------------------------------
load_config() {
  cp targets.json "$CFG_JSON"
}

cfg_target() { jq -r --arg id "$1" --arg key "$2" '.[$id][$key] // ""' "$CFG_JSON"; }
cfg_globals() { jq -r --arg key "$1" '.globals[$key] // ""' "$CFG_JSON"; }
cfg_target_labels() { jq -r --arg id "$1" '.[$id].discovery.labels | join("\n")' "$CFG_JSON"; }
cfg_target_exclude() { jq -r --arg id "$1" '.[$id].discovery.exclude_labels | join("\n")' "$CFG_JSON"; }

# --- state --------------------------------------------------------------------
state_get() {
  gh api "repos/${GITHUB_REPOSITORY}/actions/variables/${STATE_VAR}" --jq .value 2>/dev/null \
    | jq -cS . 2>/dev/null || echo '{}'
}

state_set() {
  local json="$1" i
  for i in 1 2 3; do
    if gh api "repos/${GITHUB_REPOSITORY}/actions/variables/${STATE_VAR}" >/dev/null 2>&1; then
      if gh api -X PATCH "repos/${GITHUB_REPOSITORY}/actions/variables/${STATE_VAR}" \
           -f value="$json" >/dev/null 2>&1; then return 0; fi
    else
      if gh api -X POST "repos/${GITHUB_REPOSITORY}/actions/variables" \
           -f name="${STATE_VAR}" -f value="$json" >/dev/null 2>&1; then return 0; fi
    fi
    sleep $((i * 5))
  done
  echo "ERROR: could not persist ${STATE_VAR}" >&2
  return 1
}

state_prune() {
  jq -cS '
    .targets //= {}
    | .targets |= with_entries(
        .value.tasks //= {} | .value.posted //= {}
        | .value.tasks |= (to_entries | sort_by(.value.ts // "") | reverse | .[0:100]
                           | reduce .[] as $e ({}; .[$e.key] = $e.value)))'
}

# --- jules api ------------------------------------------------------------------
jules_sessions_last_24h() {
  local cutoff
  cutoff=$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)
  curl -sS -H "X-Goog-Api-Key: ${JULES_API_KEY}" "${JULES_API}/sessions?pageSize=100" \
    | jq --arg c "$cutoff" '[.sessions // [] | .[] | select((.createTime // "") >= $c)] | length'
}

jules_get_session() {
  curl -sS -H "X-Goog-Api-Key: ${JULES_API_KEY}" "${JULES_API}/sessions/$1"
}

jules_create_session() {
  curl -sS -X POST "${JULES_API}/sessions" \
    -H "X-Goog-Api-Key: ${JULES_API_KEY}" \
    -H "Content-Type: application/json" \
    --data-binary "@$1"
}

jules_send_message() {
  local payload
  payload=$(jq -n --rawfile p "$2" '{prompt: $p}')
  curl -sS -X POST "${JULES_API}/sessions/$1:sendMessage" \
    -H "X-Goog-Api-Key: ${JULES_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$payload"
}

jules_approve_plan() {
  curl -sS -X POST "${JULES_API}/sessions/$1:approvePlan" \
    -H "X-Goog-Api-Key: ${JULES_API_KEY}" \
    -H "Content-Type: application/json" \
    -d '{}'
}

jules_sources_has() {
  local sources
  sources=$(curl -sS -H "X-Goog-Api-Key: ${JULES_API_KEY}" "${JULES_API}/sources?pageSize=100")
  jq -e --arg src "sources/github/$1" '.sources // [] | map(.name) | index($src)' \
    <<<"$sources" >/dev/null
}

# --- misc ----------------------------------------------------------------------
self_dispatch() {
  gh workflow run loop.yml --repo "${GITHUB_REPOSITORY}" --ref main \
    && echo "queued the next loop run" \
    || echo "WARNING: could not self-dispatch the next loop run"
}
