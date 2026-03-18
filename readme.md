# owi2xmltv Docker image

This container runs `owi2plex` and writes XMLTV data to your configured output file.
It is designed to be easy to operate with environment variables, clear startup logs, and optional cron-based scheduling.

## Quick start

```yaml
version: "3.9"

services:
  owi2xmltv:
    image: nillivanilli0815/owi2xmltv:latest
    container_name: owi2xmltv
    environment:
      TZ: Europe/Berlin
      OWI_HOST: "192.168.1.50"
      OWI_PORT: "80"
      OWI_USERNAME: ""
      OWI_PASSWORD: ""
      OWI_BOUQUETS: "TV,Radio"
      OWI_OUTPUT_FILE: "/data/epg.xml"
      OWI_CONTINUOUS_NUMBERING: "true"
      OWI_CATEGORY_OVERRIDE: "/config/cat_overrides.yml"
      OWI_DEBUG: "false"
      CRON_SCHEDULE: "*/5 * * * *"
      RUN_ON_START: "true"
      RUN_ONCE: "false"
      OWI_UID: "1000"
      OWI_GID: "1000"
    volumes:
      - ./data:/data
      - ./config:/config
    restart: unless-stopped
```

## Runtime modes

The scheduler behavior is controlled by `RUN_ONCE`, `CRON_SCHEDULE`, and `RUN_ON_START`:

- `RUN_ONCE=true` → run one job and exit.
- `CRON_SCHEDULE` set → run on the given schedule.
- `RUN_ON_START=true` with `CRON_SCHEDULE` → run immediately, then continue on schedule.
- no `CRON_SCHEDULE` + `RUN_ON_START=true` → run once and exit.
- no `CRON_SCHEDULE` + `RUN_ON_START=false` → container stays idle.

## Environment variables

### Required

- `OWI_HOST` — OpenWebif host/IP.

### Optional connection/auth

- `OWI_PORT` (default `80`)
- `OWI_USERNAME`
- `OWI_PASSWORD`
- `OWI_BOUQUETS` (comma-separated; empty means all)

### Optional output/behavior

- `OWI_OUTPUT_FILE` (default `/data/epg.xml`)
- `OWI_CONTINUOUS_NUMBERING` (`true`/`false`)
- `OWI_CATEGORY_OVERRIDE` (path to mapping file)
- `OWI_DEBUG` (`true`/`false`)

### Optional scheduler/runtime

- `TZ` (default `Europe/Berlin`)
- `CRON_SCHEDULE` (5-field cron)
- `RUN_ON_START` (`true`/`false`, default `true`)
- `RUN_ONCE` (`true`/`false`, default `false`)
- `OWI_UID` runtime UID (default `1000`)
- `OWI_GID` runtime GID (default `1000`)

## Volumes

- `/data` — output location (for example `epg.xml`)
- `/config` — optional config files (for example category override YAML)

## Logs you can expect

Startup logs include:

- effective mode and time zone
- target OpenWebif endpoint
- selected bouquets and output file
- enabled flags
- full executed command
- schedule in short human-readable form
- exact run reason (`RUN_ON_START`, `CRON_SCHEDULE`, `RUN_ONCE`)
- live `owi2plex` output
- next scheduled run time

## Permissions and ownership

Container startup ensures output paths are writable and then drops privileges to `OWI_UID:OWI_GID`.

If your bind mount is not writable, fix ownership on the host:

```bash
chown -R 1000:1000 ./data ./config
```

The container also performs a startup write-check for `OWI_OUTPUT_FILE` and logs a clear hint when permissions are still incorrect.
