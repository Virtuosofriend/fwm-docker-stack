#!/usr/bin/env bash
# Nightly: pull each part from production into restic, apply the keep rules, report to production.

set -euo pipefail

SSH=(ssh -F /secrets/ssh_config prod)

step() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*"; }

# Never two runs at once
exec 9> /tmp/fwm-backup.lock
flock -n 9 || { echo "Another backup is still running"; exit 1; }

# Each part is its own snapshot; a failed dump cancels that snapshot (non-zero exit)
for part in counts:counts.txt globals:globals.sql db:weather.dump uploads:uploads.tar config:config.tar; do
    command="dump-${part%%:*}"
    file="${part##*:}"
    step "Backing up $file"
    restic backup --host fwm-prod --tag nightly --stdin-filename "$file" --stdin-from-command -- "${SSH[@]}" "$command"
done

step "Applying keep rules (7 daily, 4 weekly)"
restic forget --host fwm-prod --keep-daily 7 --keep-weekly 4 --prune

free_ratio=$(df -P /repo | awk 'NR == 2 { printf "%.3f", $4 / ($3 + $4) }')
step "Reporting to production (free disk ratio $free_ratio)"
"${SSH[@]}" report "$(date -u +%s)" "$free_ratio"

step "Done"
