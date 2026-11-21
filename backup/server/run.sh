#!/usr/bin/env bash
# Runs one job with a time limit; on any failure (error, timeout, crash) sends a Telegram message.
#   run.sh <job-name> <command> [args...]

set -uo pipefail

JOB="${1:?usage: run.sh <job-name> <command> [args...]}"
shift
LOG="/tmp/$JOB.log"

# 2 hours, in seconds (busybox timeout)
timeout 7200 "$@" > >(tee "$LOG") 2>&1
status=$?

if [ "$status" -ne 0 ]; then
    echo "$JOB failed with exit code $status"
    /app/notify.sh "$JOB" "$LOG" "$status" || echo "Telegram notification failed too"
fi
exit "$status"
