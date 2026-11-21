#!/usr/bin/env bash
# Sends a failure message to Telegram, directly from the backup server.
#   notify.sh <job-name> <log-file> <exit-code>

set -euo pipefail

JOB="$1"
LOG="$2"
STATUS="$3"

TOKEN=$(cat /secrets/telegram-bot-token)
CHAT_ID=$(cat /secrets/telegram-chat-id)

TEXT="❌ FWM $JOB failed on the backup server (exit $STATUS)
$(tail -n 15 "$LOG" | cut -c1-200)"

curl -fsS -m 30 -X POST "https://api.telegram.org/bot${TOKEN}/sendMessage" \
    -d chat_id="$CHAT_ID" \
    --data-urlencode text="$TEXT" > /dev/null
