# syntax=docker/dockerfile:1
FROM python:3.12-alpine

RUN apk add --no-cache bash tzdata ca-certificates curl shadow su-exec
RUN addgroup -S app && adduser -S -G app app
ENV TZ=Europe/Berlin
WORKDIR /app

# No native builds: prebuilt lxml + owi2plex without deps
RUN pip install --no-cache-dir --upgrade pip \
 && pip install --no-cache-dir "lxml==4.9.4" \
 && pip install --no-cache-dir --no-deps "owi2plex==0.1a14" \
 && pip install --no-cache-dir --no-deps "click==7.0" "future==0.17.1" "PyYAML==5.1.2"

# Legacy-but-stable HTTP stack compatible with Py3.12 and urllib3.packages.six
RUN pip uninstall -y urllib3 requests chardet idna certifi six || true \
 && pip install --no-cache-dir --no-deps \
      "requests==2.25.1" \
      "urllib3==1.26.18" \
      "chardet==3.0.4" \
      "idna==2.10" \
      "certifi==2020.12.5" \
      "six==1.16.0" \
 && python - <<'PY'
import requests, urllib3, six
print("requests", requests.__version__, "| urllib3", urllib3.__version__, "| six", six.__version__)
import urllib3.exceptions  # prove vendored six path exists
print("vendored six OK")
PY

RUN mkdir -p /data /config /var/log/cron \
 && chown -R app:app /app /data /config /var/log/cron

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER root
VOLUME ["/data", "/config"]
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
