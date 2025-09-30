# syntax=docker/dockerfile:1
FROM python:3.12-alpine

# System deps
RUN apk add --no-cache bash tzdata ca-certificates curl shadow \
    && addgroup -S app && adduser -S -G app app

# Install owi2plex CLI from PyPI
# (provides the `owi2plex` entrypoint with the flags from upstream)
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir owi2plex

# Folders
ENV TZ=Europe/Berlin
WORKDIR /app
RUN mkdir -p /data /config /var/log/cron && chown -R app:app /app /data /config /var/log/cron

# Copy entrypoint
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER app

# Default: nothing exposed; XML is written to /data by default
VOLUME ["/data", "/config"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
