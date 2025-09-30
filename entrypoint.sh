#!/usr/bin/env bash
set -euo pipefail

# -------- Config from ENV ----------
OWI_HOST="${OWI_HOST:-}"
OWI_PORT="${OWI_PORT:-80}"
OWI_USERNAME="${OWI_USERNAME:-}"
OWI_PASSWORD="${OWI_PASSWORD:-}"
OWI_BOUQUETS="${OWI_BOUQUETS:-}"
OWI_OUTPUT_FILE="${OWI_OUTPUT_FILE:-/data/epg.xml}"
OWI_CONTINUOUS_NUMBERING="${OWI_CONTINUOUS_NUMBERING:-false}"
OWI_CATEGORY_OVERRIDE="${OWI_CATEGORY_OVERRIDE:-}"
OWI_DEBUG="${OWI_DEBUG:-false}"

CRON_SCHEDULE="${CRON_SCHEDULE:-}"
RUN_ON_START="${RUN_ON_START:-true}"
RUN_ONCE="${RUN_ONCE:-false}"

# Build CLI args
args=()
[[ -n "$OWI_HOST" ]] && args+=("--host" "$OWI_HOST")
[[ -n "$OWI_PORT" ]] && args+=("--port" "$OWI_PORT")
[[ -n "$OWI_USERNAME" ]] && args+=("--username" "$OWI_USERNAME")
[[ -n "$OWI_PASSWORD" ]] && args+=("--password" "$OWI_PASSWORD")
[[ -n "$OWI_OUTPUT_FILE" ]] && args+=("--output-file" "$OWI_OUTPUT_FILE")

if [[ -n "$OWI_BOUQUETS" ]]; then
  IFS=',' read -r -a BQ <<< "$OWI_BOUQUETS"
  for b in "${BQ[@]}"; do
    b="$(echo "$b" | sed 's/^ *//;s/ *$//')"
    [[ -n "$b" ]] && args+=("--bouquet" "$b")
  done
fi

shopt -s nocasematch
[[ "$OWI_CONTINUOUS_NUMBERING" == "true" ]] && args+=("--continuous-numbering" "true")
[[ -n "$OWI_CATEGORY_OVERRIDE" ]] && args+=("--category-override" "$OWI_CATEGORY_OVERRIDE")
[[ "$OWI_DEBUG" == "true" ]] && args+=("--debug")
shopt -u nocasematch

run_job() {
  echo "[owi2plex] Running as 'app': owi2plex ${args[*]}"
  exec su-exec app owi2plex "${args[@]}"
}

run_once() {
  echo "[owi2plex] Start-on-boot run..."
  su-exec app owi2plex "${args[@]}" || true
}

setup_cron() {
  local schedule="$1"
  # Write a user crontab file directly (root owns /etc/crontabs/* on Alpine)
  local line="$schedule /usr/bin/flock -n /tmp/owi2plex.lock -c 'su-exec app owi2plex ${args[*]} >> /var/log/cron/owi2plex.log 2>&1'"
  echo "$line" > /etc/crontabs/root
  echo "[owi2plex] Installed cron: $line"
  # -f: foreground; -L: log file
  exec crond -f -L /var/log/cron/cron.log
}

# --- Flow control ---
if [[ "${RUN_ONCE,,}" == "true" ]]; then
  run_job
fi

if [[ -n "$CRON_SCHEDULE" ]]; then
  [[ "${RUN_ON_START,,}" == "true" ]] && run_once
  setup_cron "$CRON_SCHEDULE"
else
  if [[ "${RUN_ON_START,,}" == "true" ]]; then
    run_job
  else
    echo "[owi2plex] No CRON_SCHEDULE and RUN_ON_START=false. Sleeping..."
    tail -f /dev/null
  fi
fi
