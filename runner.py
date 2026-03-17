#!/usr/bin/env python3
import os
import shlex
import signal
import subprocess
import sys
import time
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo


def is_true(value: str) -> bool:
    return str(value or "").strip().lower() in {"1", "true", "yes", "on"}


def log(message: str) -> None:
    ts = datetime.now().isoformat(timespec="seconds")
    print(f"[owi2xmltv][{ts}] {message}", flush=True)


def _parse_part(part: str, min_v: int, max_v: int) -> set[int]:
    values: set[int] = set()
    for token in part.split(','):
        token = token.strip()
        if not token:
            continue
        if token == '*':
            values.update(range(min_v, max_v + 1))
            continue

        step = 1
        if '/' in token:
            token, step_raw = token.split('/', 1)
            step = int(step_raw)

        if token == '*':
            start, end = min_v, max_v
        elif '-' in token:
            start_raw, end_raw = token.split('-', 1)
            start, end = int(start_raw), int(end_raw)
        else:
            start = end = int(token)

        start = max(min_v, start)
        end = min(max_v, end)
        values.update(range(start, end + 1, step))

    return values


def parse_cron(expr: str):
    parts = expr.split()
    if len(parts) != 5:
        raise ValueError("CRON_SCHEDULE must have 5 fields: minute hour day month weekday")

    minute = _parse_part(parts[0], 0, 59)
    hour = _parse_part(parts[1], 0, 23)
    day = _parse_part(parts[2], 1, 31)
    month = _parse_part(parts[3], 1, 12)
    weekday = _parse_part(parts[4].replace('7', '0'), 0, 6)  # allow 0/7 as Sunday
    return minute, hour, day, month, weekday


def cron_matches(dt: datetime, cron_fields) -> bool:
    minute, hour, day, month, weekday = cron_fields
    cron_weekday = (dt.weekday() + 1) % 7  # convert Mon=0..Sun=6 to Sun=0..Sat=6
    return (
        dt.minute in minute
        and dt.hour in hour
        and dt.day in day
        and dt.month in month
        and cron_weekday in weekday
    )


def next_run_after(now: datetime, cron_fields) -> datetime:
    candidate = now.replace(second=0, microsecond=0) + timedelta(minutes=1)
    for _ in range(60 * 24 * 366):  # up to ~1 year search window
        if cron_matches(candidate, cron_fields):
            return candidate
        candidate += timedelta(minutes=1)
    raise RuntimeError("Could not compute next run from CRON_SCHEDULE")


def build_args(env: dict[str, str]) -> list[str]:
    host = env.get("OWI_HOST", "")
    if not host:
        log("ERROR: OWI_HOST is required.")
        sys.exit(2)

    args = ["--host", host]

    port = env.get("OWI_PORT", "80")
    if port:
        args += ["--port", port]

    username = env.get("OWI_USERNAME", "")
    password = env.get("OWI_PASSWORD", "")
    if username:
        args += ["--username", username]
    if password:
        args += ["--password", password]

    output_file = env.get("OWI_OUTPUT_FILE", "/data/epg.xml")
    args += ["--output-file", output_file]

    bouquets = [b.strip() for b in env.get("OWI_BOUQUETS", "").split(",") if b.strip()]
    for bouquet in bouquets:
        args += ["--bouquet", bouquet]

    if is_true(env.get("OWI_CONTINUOUS_NUMBERING", "false")):
        args += ["--continuous-numbering"]

    category_override = env.get("OWI_CATEGORY_OVERRIDE", "")
    if category_override:
        args += ["--category-override", category_override]

    if is_true(env.get("OWI_DEBUG", "false")):
        args += ["--debug"]

    return args


def run_owi2plex(args: list[str], reason: str) -> int:
    cmd = ["owi2plex"] + args
    log(f"Starting owi2plex ({reason}): {' '.join(shlex.quote(a) for a in cmd)}")
    process = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
    )

    assert process.stdout is not None
    for line in process.stdout:
        print(f"[owi2plex] {line.rstrip()}", flush=True)

    rc = process.wait()
    if rc == 0:
        log("owi2plex finished successfully.")
    else:
        log(f"owi2plex exited with code {rc}.")
    return rc


stop_requested = False


def _handle_signal(signum, _frame):
    global stop_requested
    stop_requested = True
    log(f"Signal {signum} received, stopping scheduler...")


def main() -> int:
    signal.signal(signal.SIGTERM, _handle_signal)
    signal.signal(signal.SIGINT, _handle_signal)

    env = os.environ
    tz_name = env.get("TZ", "Europe/Berlin")
    tz = ZoneInfo(tz_name)

    os.makedirs("/data", exist_ok=True)
    os.makedirs("/config", exist_ok=True)

    args = build_args(env)

    cron_schedule = env.get("CRON_SCHEDULE", "").strip()
    run_on_start = is_true(env.get("RUN_ON_START", "true"))
    run_once = is_true(env.get("RUN_ONCE", "false"))

    safe_env_view = {
        "TZ": tz_name,
        "OWI_HOST": env.get("OWI_HOST", ""),
        "OWI_PORT": env.get("OWI_PORT", "80"),
        "OWI_USERNAME_SET": bool(env.get("OWI_USERNAME", "")),
        "OWI_PASSWORD_SET": bool(env.get("OWI_PASSWORD", "")),
        "OWI_BOUQUETS": env.get("OWI_BOUQUETS", ""),
        "OWI_OUTPUT_FILE": env.get("OWI_OUTPUT_FILE", "/data/epg.xml"),
        "OWI_CONTINUOUS_NUMBERING": env.get("OWI_CONTINUOUS_NUMBERING", "false"),
        "OWI_CATEGORY_OVERRIDE": env.get("OWI_CATEGORY_OVERRIDE", ""),
        "OWI_DEBUG": env.get("OWI_DEBUG", "false"),
        "CRON_SCHEDULE": cron_schedule,
        "RUN_ON_START": run_on_start,
        "RUN_ONCE": run_once,
    }
    log(f"Runtime configuration: {safe_env_view}")

    if run_once:
        return run_owi2plex(args, "RUN_ONCE")

    if not cron_schedule:
        if run_on_start:
            return run_owi2plex(args, "RUN_ON_START")
        log("No CRON_SCHEDULE and RUN_ON_START=false; container will stay idle.")
        while not stop_requested:
            time.sleep(2)
        return 0

    try:
        cron_fields = parse_cron(cron_schedule)
    except Exception as exc:
        log(f"ERROR: Invalid CRON_SCHEDULE '{cron_schedule}': {exc}")
        return 2

    if run_on_start:
        run_owi2plex(args, "RUN_ON_START")

    while not stop_requested:
        now = datetime.now(tz)
        next_run = next_run_after(now, cron_fields)
        log(f"Next scheduled execution at {next_run.isoformat()}")

        while not stop_requested:
            remaining = (next_run - datetime.now(tz)).total_seconds()
            if remaining <= 0:
                break
            time.sleep(min(remaining, 1.0))

        if stop_requested:
            break

        run_owi2plex(args, "CRON_SCHEDULE")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
