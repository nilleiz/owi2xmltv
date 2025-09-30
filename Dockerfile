# syntax=docker/dockerfile:1
# Use Python 3.10 because owi2plex pins lxml==4.3.2 which is not compatible with CPython 3.12
FROM python:3.10-alpine

# --- Runtime packages (plus libs lxml needs at runtime) ---
RUN apk add --no-cache \
    bash tzdata ca-certificates curl shadow \
    libxml2 libxslt \
 && addgroup -S app && adduser -S -G app app

ENV TZ=Europe/Berlin
WORKDIR /app

# --- Build deps just for pip install (build lxml from source on Alpine) ---
RUN apk add --no-cache --virtual .build-deps \
      build-base libxml2-dev libxslt-dev python3-dev \
 && pip install --no-cache-dir --upgrade pip \
 && pip install --no-cache-dir owi2plex \
 && apk del .build-deps

# --- Layout & permissions ---
RUN mkdir -p /data /config /var/log/cron \
 && chown -R app:app /app /data /config /var/log/cron

# --- Entrypoint (same as before; make sure this file is in the build context) ---
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER app

VOLUME ["/data", "/config"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
