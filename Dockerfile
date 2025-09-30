# syntax=docker/dockerfile:1
FROM python:3.12-alpine

# Runtime deps + su-exec for dropping privileges at runtime
RUN apk add --no-cache bash tzdata ca-certificates curl shadow su-exec

# Create unprivileged user
RUN addgroup -S app && adduser -S -G app app

ENV TZ=Europe/Berlin
WORKDIR /app

# ---- Python deps -------------------------------------------------------------
# 1) Install a modern prebuilt lxml (no compiling on Alpine)
# 2) Force the legacy HTTP stack that owi2plex expects (requests 2.21 + urllib3 1.24 + friends)
# 3) Install owi2plex without deps, then its pins explicitly
RUN pip install --no-cache-dir --upgrade pip \
 && pip install --no-cache-dir "lxml==4.9.4" \
 && pip uninstall -y urllib3 || true \
 && pip install --no-cache-dir \
      "urllib3==1.24.3" \
      "chardet==3.0.4" \
      "idna==2.8" \
      "certifi==2020.4.5.1" \
 && pip install --no-cache-dir --no-deps "requests==2.21.0" \
 && pip install --no-cache-dir --no-deps "click==7.0" "future==0.17.1" "PyYAML==5.1.2" \
 && pip install --no-cache-dir --no-deps "owi2plex==0.1a14"

# Folders & perms
RUN mkdir -p /data /config /var/log/cron \
 && chown -R app:app /app /data /config /var/log/cron

# Entrypoint
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# IMPORTANT: keep root so we can manage cron, but we'll run jobs as "app"
USER root

VOLUME ["/data", "/config"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
