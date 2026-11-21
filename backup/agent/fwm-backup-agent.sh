#!/usr/bin/env bash
# Runs on production as root (via sudo), only through the backup server's forced SSH command.
# Installed as a root-owned copy:
#   sudo install -o root -g root -m 755 backup/agent/fwm-backup-agent.sh /usr/local/bin/fwm-backup-agent

set -euo pipefail

METRICS_DIR="/var/lib/node_exporter/textfile_collector"

log() { logger -t fwm-backup-agent "$*"; }

# sshd passes the requested command here; sudoers keeps it (env_keep)
REQUEST="${SSH_ORIGINAL_COMMAND:-}"

# Paths come from the running containers, so nothing is configured twice
STACK_DIR=$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' fwm-postgres)
mount_source() {
    docker inspect -f "{{range .Mounts}}{{if eq .Destination \"$1\"}}{{.Source}}{{end}}{{end}}" fwm-directus
}

sql() {
    printf '%s\n' "$1" | docker exec -i fwm-postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At -v ON_ERROR_STOP=1'
}

case "$REQUEST" in
    dump-counts)
        log "dump-counts"
        echo "weather_data|$(sql 'SELECT count(*) FROM weather_data')"
        echo "weather_stations|$(sql 'SELECT count(*) FROM weather_stations')"
        echo "directus_users|$(sql 'SELECT count(*) FROM directus_users')"
        echo "directus_files|$(sql 'SELECT count(*) FROM directus_files')"
        echo "newest_reading|$(sql "SELECT to_char(max(date_created) AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS') FROM weather_data")"
        echo "latest_migration|$(sql 'SELECT max(version) FROM directus_migrations')"
        echo "db_size|$(sql 'SELECT pg_size_pretty(pg_database_size(current_database()))')"
        echo "server_version|$(sql 'SHOW server_version')"
        echo "db_user|$(sql 'SELECT current_user')"
        echo "postgres_image|$(docker inspect -f '{{.Config.Image}}' fwm-postgres)"
        ;;
    dump-globals)
        log "dump-globals"
        docker exec fwm-postgres sh -c 'pg_dumpall -U "$POSTGRES_USER" --globals-only'
        ;;
    dump-db)
        log "dump-db"
        # Uncompressed: restic compresses and deduplicates it better
        docker exec fwm-postgres sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc -Z 0 --lock-wait-timeout=60000'
        ;;
    dump-uploads)
        log "dump-uploads"
        uploads=$(mount_source /directus/uploads)
        tar -cf - -C "$(dirname "$uploads")" "$(basename "$uploads")"
        ;;
    dump-config)
        log "dump-config"
        extensions=$(mount_source /directus/extensions)
        config_files=$(cd "$STACK_DIR" && {
            find . -maxdepth 3 -type f -name '.env*' ! -name '*.example'
            find . -maxdepth 6 -type f -name 'contact-points.yml'
        } | sort)
        # shellcheck disable=SC2086
        tar -cf - -C "$(dirname "$extensions")" "$(basename "$extensions")" -C "$STACK_DIR" $config_files
        ;;
    report\ *)
        # report <unix time of success> <free disk ratio 0..1>
        read -r _ last_success free_ratio extra <<< "$REQUEST"
        if ! [[ "$last_success" =~ ^[0-9]{10}$ && "$free_ratio" =~ ^(0(\.[0-9]+)?|1(\.0+)?)$ && -z "${extra:-}" ]]; then
            log "refused malformed report: $REQUEST"
            echo "malformed report" >&2
            exit 2
        fi
        mkdir -p "$METRICS_DIR"
        tmp="$METRICS_DIR/.fwm_backup.prom.$$"
        cat > "$tmp" <<EOF
# HELP fwm_backup_last_success_timestamp_seconds Unix time of the last successful nightly backup
# TYPE fwm_backup_last_success_timestamp_seconds gauge
fwm_backup_last_success_timestamp_seconds $last_success
# HELP fwm_backup_disk_free_ratio Free disk space on the backup server (0..1)
# TYPE fwm_backup_disk_free_ratio gauge
fwm_backup_disk_free_ratio $free_ratio
EOF
        chmod 644 "$tmp"
        mv "$tmp" "$METRICS_DIR/fwm_backup.prom"
        log "report: last_success=$last_success free_ratio=$free_ratio"
        ;;
    *)
        log "refused: ${REQUEST:-<empty>}"
        echo "refused" >&2
        exit 2
        ;;
esac
