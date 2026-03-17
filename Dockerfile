# syntax=docker/dockerfile:1
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TZ=Europe/Berlin

RUN apt-get update \
 && apt-get install -y --no-install-recommends tzdata ca-certificates curl git tini \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install dependencies for local runner and owi2plex CLI.
RUN pip install --no-cache-dir --upgrade pip \
 && pip install --no-cache-dir requests click future PyYAML lxml

# Install owi2plex from upstream source to avoid depending on stale binary wheels.
RUN git clone --depth=1 https://github.com/cvarelaruiz/owi2plex /tmp/owi2plex-src \
 && pip install --no-cache-dir /tmp/owi2plex-src \
 && rm -rf /tmp/owi2plex-src

COPY runner.py /app/runner.py

RUN useradd -r -u 10001 -m app \
 && mkdir -p /data /config \
 && chown -R app:app /app /data /config

USER app
VOLUME ["/data", "/config"]
ENTRYPOINT ["/usr/bin/tini", "--", "python", "/app/runner.py"]
