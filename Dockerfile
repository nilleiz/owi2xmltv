# syntax=docker/dockerfile:1
FROM python:3.12-alpine

# Runtime deps + su-exec to drop privileges for the job
RUN apk add --no-cache bash tzdata ca-certificates curl shadow su-exec

# App user
RUN addgroup -S app && adduser -S -G app app
ENV TZ=Europe/Berlin
WORKDIR /app

# Python deps:
#  - modern prebuilt lxml (no compile)
#  - install owi2plex *without deps*
#  - add its pinned deps explicitly
RUN pip install --no-cache-dir --upgrade pip \
 && pip install --no-cache-dir "lxml==4.9.4" \
 && pip install --no-cache-dir --no-deps "owi2plex==0.1a14" \
 && pip install --no-cache-dir --no-deps "click==7.0" "future==0.17.1" "PyYAML==5.1.2"

# ***** CRITICAL: re-pin the legacy HTTP stack last *****
# requests 2.21.0 expects urllib3 1.24.x and uses urllib3.packages.six.*
RUN pip uninstall -y urllib3 requests six chardet idna certifi || true \
 && pip install --no-cache-dir --no-deps \
      "urllib3==1.24.3" \
      "requests==2.21.0" \
      "six==1.16.0" \
      "chardet==3.0.4" \
      "idna==2.8" \
      "certifi==2020.4.5.1" \
 && python - <<'PY'
import urllib3, requests, six
print("urllib3:", urllib3.__version__, "| requests:", requests.__version__, "| six:", six.__version__)
PY

# Folders & perms
RUN mkdir -p /data /config /var/log/cron \
 && chown -R app:app /app /data /config /var/log/cron

# Entrypoint
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# keep root to manage cron; actual job runs as 'app' via su-exec
USER root

VOLUME ["/data", "/config"]
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
