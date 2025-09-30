# syntax=docker/dockerfile:1
FROM python:3.12-alpine

# Minimal runtime packages
RUN apk add --no-cache bash tzdata ca-certificates curl shadow \
 && addgroup -S app && adduser -S -G app app

ENV TZ=Europe/Berlin
WORKDIR /app

# ---- Dependency strategy -----------------------------------------------------
# owi2plex pins very old deps including lxml==4.3.2 which won't build on modern stacks.
# Fix: install a recent prebuilt lxml wheel, then install owi2plex *without* deps,
# and add its pinned deps explicitly.
# This avoids any native compilation and keeps the image tiny & stable.
RUN pip install --no-cache-dir --upgrade pip \
 && pip install --no-cache-dir "lxml==4.9.4" \
 && pip install --no-cache-dir --no-deps "owi2plex==0.1a14" \
 && pip install --no-cache-dir "click==7.0" "requests==2.21.0" "future==0.17.1" "PyYAML==5.1.2"

# Layout & permissions
RUN mkdir -p /data /config /var/log/cron \
 && chown -R app:app /app /data /config /var/log/cron

# Entrypoint script (place this file next to the Dockerfile)
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER app

VOLUME ["/data", "/config"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
