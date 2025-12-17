#!/usr/bin/env bash
set -euo pipefail

# -------------------- Helpers --------------------
is_true() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    1|true|yes|on) return 0 ;;
    *)             return 1 ;;
  esac
}

trim() { sed 's/^[[:space:]]*//;s/[[:space:]]*$//' ; }

log() { echo "[owi2plex] $*"; }

# Quote a single arg for writing into a shell script safely
sq() {
  local s=${1//\'/\'"\'"\'}
  printf "'%s'" "$s"
}

# -------------------- Config ---------------------
TZ="${TZ:-Europe/Berlin}"

OWI_HOST="${OWI_HOST:-}"
OWI_PORT="${OWI_PORT:-80}"
OWI_USERNAME="${OWI_USERNAME:-}"
OWI_PASSWORD="${OWI_PASSWORD:-}"
OWI_BOUQUETS="${OWI_BOUQUETS:-}"            # comma-separated
OWI_OUTPUT_FILE="${OWI_OUTPUT_FILE:-/data/epg.xml}"
OWI_CONTINUOUS_NUMBERING="${OWI_CONTINUOUS_NUMBERING:-false}"
OWI_CATEGORY_OVERRIDE="${OWI_CATEGORY_OVERRIDE:-}"
OWI_DEBUG="${OWI_DEBUG:-false}"

CRON_SCHEDULE="${CRON_SCHEDULE:-}"          # e.g. "0 4 * * *"
RUN_ON_START="${RUN_ON_START:-true}"
RUN_ONCE="${RUN_ONCE:-false}"

# -------------------- Validate -------------------
if [[ -z "$OWI_HOST" ]]; then
  log "ERROR: OWI_HOST is required (IP/hostname of OpenWebIF)."
  exit 2
fi

# Ensure output folder exists
mkdir -p "$(dirname "$OWI_OUTPUT_FILE")" || true
mkdir -p /var/log/cron || true

# -------------------- Build args -----------------
args=()
args+=("--host" "$OWI_HOST")
[[ -n "$OWI_PORT" ]] && args+=("--port" "$OWI_PORT")
[[ -n "$OWI_USERNAME" ]] && args+=("--username" "$OWI_USERNAME")
[[ -n "$OWI_PASSWORD" ]] && args+=("--password" "$OWI_PASSWORD")
args+=("--output-file" "$OWI_OUTPUT_FILE")

# Bouquets: split on commas, keep spaces inside names
if [[ -n "$OWI_BOUQUETS" ]]; then
  IFS=',' read -r -a _BQ_ <<< "$OWI_BOUQUETS"
  for b in "${_BQ_[@]}"; do
    b="$(printf '%s' "$b" | trim)"
    [[ -n "$b" ]] && args+=("--bouquet" "$b")
  done
fi

# Booleans: include flag only when true (no value after it)
if is_true "$OWI_CONTINUOUS_NUMBERING"; then
  args+=("--continuous-numbering")
fi
if [[ -n "$OWI_CATEGORY_OVERRIDE" ]]; then
  args+=("--category-override" "$OWI_CATEGORY_OVERRIDE")
fi
if is_true "$OWI_DEBUG"; then
  args+=("--debug")
fi

# -------------------- Runners --------------------
run_job() {
  log "Running as 'app': owi2plex ${args[*]}"
  exec /sbin/su-exec app owi2plex "${args[@]}"
}

run_once() {
  log "Start-on-boot run..."
  /sbin/su-exec app owi2plex "${args[@]}" || true
}

# Create a tiny wrapper for cron to avoid quoting headaches
make_cron_wrapper() {
  local f=/usr/local/bin/owi2plex_run
  {
    printf '#!/bin/sh\nexec /sbin/su-exec app owi2plex'
    for a in "${args[@]}"; do
      printf ' %s' "$(sq "$a")"
    done
    printf '\n'
  } > "$f"
  chmod +x "$f"
  echo "$f"
}

install_crontab() {
  local schedule="$1" runner="$2"
  local cron_dir=/var/spool/cron/crontabs
  local cron_file="$cron_dir/root"

  mkdir -p "$cron_dir"
  local line="$schedule /usr/bin/flock -n /tmp/owi2plex.lock $runner >> /var/log/cron/owi2plex.log 2>&1"
  printf '%s\n' "$line" > "$cron_file"
  chmod 600 "$cron_file"

  log "Installed cron: $line"
}

run_scheduler() {
  local schedule="$1"
  local runner
  runner="$(make_cron_wrapper)"

  install_crontab "$schedule" "$runner"

  # Foreground cron so the container stays up; log to file and point at the right spool dir
  exec crond -f -L /var/log/cron/cron.log -c /var/spool/cron/crontabs
}

# -------------------- Control flow ---------------
if is_true "$RUN_ONCE"; then
  run_job
fi

if [[ -n "$CRON_SCHEDULE" ]]; then
  if is_true "$RUN_ON_START"; then
    run_once
  fi
  run_scheduler "$CRON_SCHEDULE"
else
  if is_true "$RUN_ON_START"; then
    run_job
  else
    log "No CRON_SCHEDULE and RUN_ON_START=false. Idling..."
    tail -f /dev/null
  fi
fi
