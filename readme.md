# owi2xmltv Docker image

This image runs `owi2plex` with the same environment variables as before, but with a rewritten runtime scheduler that is deterministic and fully visible in container logs.

## Runtime behavior

The container now uses an internal Python scheduler (`runner.py`) with cron expression support:

- `RUN_ONCE=true` -> run one job and exit.
- `CRON_SCHEDULE` set -> run on schedule.
- `RUN_ON_START=true` with `CRON_SCHEDULE` -> run immediately, then continue scheduled runs.
- no `CRON_SCHEDULE` + `RUN_ON_START=true` -> run once and exit.
- no `CRON_SCHEDULE` + `RUN_ON_START=false` -> stay idle.

The image now also installs an explicit `/usr/local/bin/owi2plex` launcher so the scheduler can always execute `owi2plex` reliably.

## Logs now include

- Effective runtime config (run-related env vars, secrets masked as *_SET booleans).
- Exact `owi2plex` command start reason (`RUN_ON_START`, `CRON_SCHEDULE`, `RUN_ONCE`).
- Live `owi2plex` stdout/stderr in container logs.
- The next scheduled execution timestamp after each cycle.

## Supported environment variables (unchanged)

- `TZ`
- `OWI_HOST` (required)
- `OWI_PORT`
- `OWI_USERNAME`
- `OWI_PASSWORD`
- `OWI_BOUQUETS` (comma-separated)
- `OWI_OUTPUT_FILE`
- `OWI_CONTINUOUS_NUMBERING`
- `OWI_CATEGORY_OVERRIDE`
- `OWI_DEBUG`
- `CRON_SCHEDULE`
- `RUN_ON_START`
- `RUN_ONCE`

## Example compose

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
    volumes:
      - ./data:/data
      - ./config:/config
    restart: unless-stopped
```

## GitHub Actions publish

Workflow: `.github/workflows/docker-publish.yml`

It builds/tests and pushes to `nillivanilli0815/owi2xmltv` on `master`/`main`, tags (`v*`), and manual dispatch.

Required GitHub repository secrets:

- `DOCKERHUB_USERNAME`
- `DOCKERHUB_TOKEN`
