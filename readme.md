# owi2xmltv Docker image

This image runs `owi2plex` either once at startup or on a cron schedule (or both).

## Why cron only ran once before

The entrypoint uses:

- one run at container startup when `RUN_ON_START=true`
- periodic runs from BusyBox cron when `CRON_SCHEDULE` is set

The cron line uses `flock` to avoid overlapping runs. If `flock` is missing in the container, cron executions fail while the startup run still succeeds, which looks like "it only triggers once".

This repository now installs `util-linux` in the image so `/usr/bin/flock` is available.

## Example compose

```yaml
version: "3.9"

services:
  owi2xmltv:
    image: nillivanilli0815/owi2xmltv:latest
    container_name: owi2xmltv
    environment:
      TZ: Europe/Berlin

      # OpenWebIf (required)
      OWI_HOST: "192.168.1.50"
      OWI_PORT: "80"
      OWI_USERNAME: ""
      OWI_PASSWORD: ""

      # Export
      OWI_BOUQUETS: "TV,Radio"
      OWI_OUTPUT_FILE: "/data/epg.xml"
      OWI_CONTINUOUS_NUMBERING: "true"
      OWI_CATEGORY_OVERRIDE: "/config/cat_overrides.yml"
      OWI_DEBUG: "false"

      # Scheduling
      CRON_SCHEDULE: "0 4 * * *"
      RUN_ON_START: "true"
      RUN_ONCE: "false"

    volumes:
      - ./data:/data
      - ./config:/config
    restart: unless-stopped
```

## GitHub Actions Docker publish

Workflow: `.github/workflows/docker-publish.yml`

It builds and pushes multi-arch images (`linux/amd64`, `linux/arm64`) to:

- `nillivanilli0815/owi2xmltv:latest` (on `main`)
- `nillivanilli0815/owi2xmltv:<tag>` (on git tags like `v1.0.0`)
- `nillivanilli0815/owi2xmltv:sha-...`

### Required GitHub repository secrets for Docker Hub auth

Add these under **GitHub repo → Settings → Secrets and variables → Actions**:

- `DOCKERHUB_USERNAME` = your Docker Hub username (`nillivanilli0815`)
- `DOCKERHUB_TOKEN` = a Docker Hub **Access Token** (recommended) or password

To create token in Docker Hub:

1. Docker Hub → Account Settings → Personal access tokens
2. Create token (Read/Write/Delete permission for pushes)
3. Save token once, then place it in `DOCKERHUB_TOKEN`

