#!/usr/bin/env bash
set -euo pipefail

# -------- Config from ENV -> CLI flags ----------
# Upstream CLI (for reference):
# -b/--bouquet, -u/--username, -p/--password, -h/--host, -P/--port,
# -o/--output-file, -c/--continuous-numbering, -O/--category-override, -d/--debug
# Source: upstream README. (see repo)
#
# ENV variables (all optional unless noted)
OWI_HOST="${OWI_HOST:-}"
OWI_PORT="${OWI_PORT:-80}"
OWI_USERNAME="${OWI_USERNAME:-}"
OWI_PASSWORD="${OWI_PASSWORD:-}"
OWI_BOUQUETS="${OWI_BOUQUETS:-}"           # comma-separated list; each becomes -b
OWI_OUTPUT_FILE="${OWI_OUTPUT_FILE:-/data/epg.xml}"
OWI_CONTINUOUS_NUMBERING="${OWI_CONTINUOUS_NUMBERING:-false}"  # "true"/"false"
OWI_CATEGORY_OVERRIDE="${OWI_CATEGORY_OVERRIDE:-}"             # path to YAML mounted under /config or /data
OWI_DEBUG="${OWI_DEBUG:-false}"

# Scheduling controls
CRON_SCHEDULE="${CRON_SCHEDULE:-}"          # e.g. "0 4 * * *"
RUN_ON_START="${RUN_ON_START:-true}"        # "true"/"false"
RUN_ONCE="${RUN_ONCE:-false}"               # "true"/"false" overrides cron

# Build CLI args
args=()
[[ -n "$OWI_HOST" ]] && args+=("--host" "$OWI_HOST")
[[ -n "$OWI_PORT" ]] && args+=("--port" "$OWI_PORT")
[[ -n "$OWI_USERNAME" ]] && args+=("--username" "$OWI_USERNAME")
[[ -n "$OWI_PASSWORD" ]] && args+=("--password" "$OWI_PASSWORD")
[[ -n "$OWI_OUTPUT_FILE" ]] && args+=("--output-file" "$OWI_OUTPUT_FILE")

# Multiple bouquets: "TV,Radio Sports" => -b "TV" -b "Radio Sports"
if [[ -n "$OWI_BOUQUETS" ]]; then
  IFS=',' read -r -a BQ <<< "$OWI_BOUQUETS"
  for b in "${BQ[@]}"; do
    # trim
    b="$(echo "$b" | sed 's/^ *//;s/ *$//')"
    [[ -n "$b" ]] && args+=("--bouquet" "$b")
  done
fi

# booleans
shopt -s nocasematch
if [[ "$OWI_CONTINUOUS_NUMBERING" == "true" ]]; then
  args+=("--continuous-numbering" "true")
fi
if [[ -n "$OWI_CATEGORY_OVERRIDE" ]]; then
  args+=("--category-override" "$OWI_CATEGORY_OVERRIDE")
fi
if [[ "$OWI_DEBUG" == "true" ]]; then
  args+=("--debug")
fi
shopt -u nocasematch

run_once() {
  echo "[owi2plex] Running: owi2plex ${args[*]}"
  exec owi2plex "${args[@]}"
}

run_now() {
  echo "[owi2plex] Start-on-boot run..."
  owi2plex "${args[@]}" || true
}

setup_cron() {
  local schedule="$1"
  # write crontab; use flock to avoid overlap
  CRON_LINE="$schedule /usr/bin/flock -n /tmp/owi2plex.lock -c \"owi2plex ${args[*]} >> /var/log/cron/owi2plex.log 2>&1\""
  echo "$CRON_LINE" > /tmp/cronfile
  crontab /tmp/cronfile
  echo "[owi2plex] Installed cron: $CRON_LINE"
  crond -f -L /var/log/cron/cron.log
}

# Behavior
if [[ "${RUN_ONCE,,}" == "true" ]]; then
  run_once
fi

if [[ -n "$CRON_SCHEDULE" ]]; then
  if [[ "${RUN_ON_START,,}" == "true" ]]; then
    run_now
  fi
  setup_cron "$CRON_SCHEDULE"
else
  # No cron -> single run (unless RUN_ON_START=false)
  if [[ "${RUN_ON_START,,}" == "true" ]]; then
    run_once
  else
    echo "[owi2plex] Nothing to do (no CRON_SCHEDULE, RUN_ON_START=false). Sleeping..."
    tail -f /dev/null
  fi
fi
