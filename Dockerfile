# syntax=docker/dockerfile:1
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TZ=Europe/Berlin

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      tini \
      tzdata \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN pip install --no-cache-dir --upgrade pip \
 && pip install --no-cache-dir \
      click==8.1.8 \
      lxml==5.3.1 \
      requests==2.32.3

COPY owi2plex.py /app/owi2plex.py
COPY runner.py /app/runner.py

RUN printf '%s\n' '#!/usr/bin/env sh' 'exec python /app/owi2plex.py "$@"' > /usr/local/bin/owi2plex \
 && chmod +x /usr/local/bin/owi2plex

# Default runtime user/group aligned to typical host UID/GID for bind mounts.
RUN groupadd --gid 1000 app \
 && useradd --uid 1000 --gid 1000 --create-home app \
 && mkdir -p /data /config \
 && chown -R 1000:1000 /app /data /config

USER 1000:1000
VOLUME ["/data", "/config"]
ENTRYPOINT ["/usr/bin/tini", "--", "python", "/app/runner.py"]
