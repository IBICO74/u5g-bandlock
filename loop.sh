#!/bin/sh
# Container entrypoint: run apply.sh every INTERVAL seconds (default 15 min).
# The systemd install doesn't use this — the timer handles scheduling there.
set -eu
INTERVAL="${INTERVAL:-900}"
while true; do
  /app/apply.sh || echo "apply failed (rc=$?) — retrying in ${INTERVAL}s"
  sleep "$INTERVAL"
done
