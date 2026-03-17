#!/usr/bin/env python3
import os
import re
import shlex
import signal
import subprocess
import sys
import time
from errno import EACCES
from datetime import datetime, timedelta
from zoneinfo import ZoneInfo


def is_true(value: str) -> bool:
    return str(value or "").strip().lower() in {"1", "true", "yes", "on"}


def log(message: str) -> None:
    ts = datetime.now().isoformat(timespec="seconds")
    print(f"[owi2xmltv][{ts}] {message}", flush=True)


_BYTES_LINE_RE = re.compile(r"^b(['\"])(.*)\1$")


def clean_owi2plex_line(line: str) -> str:
    text = line.rstrip()
    match = _BYTES_LINE_RE.match(text)
    if not match:
        return text

    quote = match.group(1)
    body = match.group(2)
    escaped = body.replace('\\', '\\\\').replace(quote, f"\\{quote}")
    try:
        return bytes(escaped, "utf-8").decode("unicode_escape")
    except UnicodeDecodeError:
        return text


def _describe_cron_field(field: str, unit: str) -> str:
    token = field.strip()
    if token == "*":
        return f"every {unit}"
    if token.startswith("*/"):
        return f"every {token[2:]} {unit}s"
    if "," in token:
        return f"{unit}s {token}"
    if "-" in token:
        return f"{unit}s {token}"
    return f"{unit} {token}"


def describe_cron(expr: str) -> str:
    parts = expr.split()
    if len(parts) != 5:
        return "(invalid cron expression)"

    minute, hour, day, month, weekday = parts
    return (
        f"{_describe_cron_field(minute, 'minute')}, "
        f"{_describe_cron_field(hour, 'hour')}, "
        f"{_describe_cron_field(day, 'day')}, "
        f"{_describe_cron_field(month, 'month')}, "
        f"{_describe_cron_field(weekday, 'weekday')}"
    )


def log_run_options(env: dict[str, str], args: list[str], *, cron_schedule: str, run_on_start: bool, run_once: bool, tz_name: str) -> None:
    masked_password = "set" if env.get("OWI_PASSWORD", "") else "not set"
    masked_username = "set" if env.get("OWI_USERNAME", "") else "not set"
    mode = "RUN_ONCE" if run_once else ("CRON" if cron_schedule else "SINGLE_RUN" if run_on_start else "IDLE")

    log("Run options:")
    log(f"  • Mode: {mode}")
    log(f"  • Time zone: {tz_name}")
    log(f"  • OpenWebif: {env.get('OWI_HOST', '')}:{env.get('OWI_PORT', '80')}")
    log(f"  • Credentials: username {masked_username}, password {masked_password}")
    log(f"  • Bouquets: {env.get('OWI_BOUQUETS', '') or '<all>'}")
    log(f"  • Output file: {env.get('OWI_OUTPUT_FILE', '/data/epg.xml')}")
    log(
        "  • Flags: "
        f"continuous_numbering={is_true(env.get('OWI_CONTINUOUS_NUMBERING', 'false'))}, "
        f"debug={is_true(env.get('OWI_DEBUG', 'false'))}, "
        f"category_override={env.get('OWI_CATEGORY_OVERRIDE', '') or '<none>'}"
    )
    if cron_schedule:
        log(f"  • Schedule: {cron_schedule}")
        log(f"  • Schedule (human): {describe_cron(cron_schedule)}")
        log(f"  • Run on start: {run_on_start}")
    log(f"  • Command: {' '.join(shlex.quote(a) for a in ['owi2plex', *args])}")


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



def _coerce_id(raw: str, fallback: int, label: str) -> int:
    try:
        return int(raw)
    except (TypeError, ValueError):
        log(f"WARNING: Invalid {label}='{raw}', using {fallback}.")
        return fallback


def runtime_ids_from_env(env: dict[str, str]) -> tuple[int, int]:
    default_uid = os.getuid()
    default_gid = os.getgid()
    uid = _coerce_id(env.get("OWI_UID", str(default_uid)), default_uid, "OWI_UID")
    gid = _coerce_id(env.get("OWI_GID", str(default_gid)), default_gid, "OWI_GID")
    return uid, gid


def _take_ownership(path: str, uid: int, gid: int) -> None:
    try:
        os.chown(path, uid, gid)
    except OSError as exc:
        log(f"WARNING: Could not chown '{path}' to {uid}:{gid}: {exc}")


def ensure_writable_path(output_file: str, run_uid: int, run_gid: int) -> bool:
    output_dir = os.path.dirname(output_file) or "."
    is_root = os.geteuid() == 0
    try:
        os.makedirs(output_dir, exist_ok=True)
    except OSError as exc:
        log(f"ERROR: Could not create output directory '{output_dir}': {exc}")
        return False

    # When starting as root, proactively transfer ownership of the output
    # directory so the runtime user can create/modify files later.
    if is_root:
        _take_ownership(output_dir, run_uid, run_gid)

    # Best-effort permission normalization for directories/files we own.
    try:
        os.chmod(output_dir, 0o775)
    except OSError:
        pass

    if os.path.exists(output_file):
        try:
            os.chmod(output_file, 0o664)
        except OSError:
            pass

    try:
        with open(output_file, "a", encoding="utf-8"):
            pass

        # If root created the file during startup, ownership would otherwise
        # remain 0:0 and writes would fail after dropping privileges.
        if is_root:
            _take_ownership(output_file, run_uid, run_gid)

        return True
    except OSError as exc:
        if is_root and exc.errno == EACCES:
            log(
                "Output file is not writable; attempting ownership fix "
                f"for {output_file} -> {run_uid}:{run_gid}."
            )
            _take_ownership(output_dir, run_uid, run_gid)
            if os.path.exists(output_file):
                _take_ownership(output_file, run_uid, run_gid)
            else:
                try:
                    with open(output_file, "a", encoding="utf-8"):
                        pass
                except OSError:
                    pass
                _take_ownership(output_file, run_uid, run_gid)

            try:
                os.chmod(output_dir, 0o775)
            except OSError:
                pass
            try:
                os.chmod(output_file, 0o664)
            except OSError:
                pass

            try:
                with open(output_file, "a", encoding="utf-8"):
                    pass
                log(f"Ownership fix succeeded for '{output_file}'.")
                return True
            except OSError as retry_exc:
                exc = retry_exc

        log(
            "ERROR: Output file is not writable. "
            f"path={output_file} uid={os.getuid()} gid={os.getgid()} error={exc}"
        )
        log(
            "Hint: run container as root once to auto-fix ownership, or ensure host "
            f"bind-mount paths are writable by UID:GID {run_uid}:{run_gid}."
        )
        return False


def drop_privileges(uid: int, gid: int) -> None:
    if os.geteuid() != 0:
        return

    try:
        os.setgroups([])
    except OSError:
        pass

    os.setgid(gid)
    os.setuid(uid)
    log(f"Dropped privileges to UID:GID {uid}:{gid}.")


def run_owi2plex(args: list[str], reason: str) -> int:
    cmd = ["owi2plex"] + args
    log(f"Starting owi2plex ({reason}): {' '.join(shlex.quote(a) for a in cmd)}")
    try:
        process = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
    except FileNotFoundError:
        log("ERROR: owi2plex executable was not found in PATH.")
        return 127

    assert process.stdout is not None
    for line in process.stdout:
        print(f"[owi2plex] {clean_owi2plex_line(line)}", flush=True)

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

    run_uid, run_gid = runtime_ids_from_env(env)
    args = build_args(env)

    output_file = env.get("OWI_OUTPUT_FILE", "/data/epg.xml")
    if not ensure_writable_path(output_file, run_uid, run_gid):
        return 2

    drop_privileges(run_uid, run_gid)

    cron_schedule = env.get("CRON_SCHEDULE", "").strip()
    run_on_start = is_true(env.get("RUN_ON_START", "true"))
    run_once = is_true(env.get("RUN_ONCE", "false"))

    log_run_options(
        env,
        args,
        cron_schedule=cron_schedule,
        run_on_start=run_on_start,
        run_once=run_once,
        tz_name=tz_name,
    )

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
        seconds_left = max(int((next_run - now).total_seconds()), 0)
        log(f"Next scheduled execution at {next_run.isoformat()} (in {seconds_left}s)")

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
