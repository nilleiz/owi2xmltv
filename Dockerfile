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
      click \
      lxml \
      requests

COPY owi2plex.py /app/owi2plex.py
COPY runner.py /app/runner.py

RUN useradd --system --uid 10001 --create-home app \
 && mkdir -p /data /config \
 && chown -R app:app /app /data /config

USER app
VOLUME ["/data", "/config"]
ENTRYPOINT ["/usr/bin/tini", "--", "python", "/app/runner.py"]
