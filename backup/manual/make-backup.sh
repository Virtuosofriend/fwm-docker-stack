#!/usr/bin/env bash

set -euo pipefail

OUT_PARENT="$(cd "${1:?usage: make-backup.sh <output-dir>}" && pwd)"
OUT="$OUT_PARENT/fwm-backup-$(date -u +%Y-%m-%dT%H%MZ)"

# Work from the stack folder, so ../data is the same path docker-compose.yml uses
cd "$(dirname "${BASH_SOURCE[0]}")/../.."

umask 077
mkdir -p "$OUT"

sql() {
    printf '%s\n' "$1" | docker exec -i fwm-postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At -v ON_ERROR_STOP=1'
}

step() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*"; }
SECONDS=0

for dir in ../data/cms/uploads ../data/cms/extensions; do
    [ -d "$dir" ] || { echo "Missing $PWD/$dir" >&2; exit 1; }
done

step "Recording counts"
{
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
} > "$OUT/counts.txt"

step "Dumping database"
docker exec fwm-postgres sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Fc --lock-wait-timeout=60000' > "$OUT/weather.dump"

step "Dumping roles"
docker exec fwm-postgres sh -c 'pg_dumpall -U "$POSTGRES_USER" --globals-only' > "$OUT/globals.sql"

# After the dump, so every image the dump refers to is included
step "Archiving uploads"
tar -cf "$OUT/uploads.tar" -C ../data/cms uploads

step "Archiving extensions and config files"
CONFIG_FILES=$({
    find . -maxdepth 3 -type f -name '.env*' ! -name '*.example'
    find . -maxdepth 6 -type f -name 'contact-points.yml'
} | sort)
# shellcheck disable=SC2086
tar -cf "$OUT/config.tar" -C "$PWD/../data/cms" extensions -C "$PWD" $CONFIG_FILES

step "Writing checksums"
if command -v sha256sum >/dev/null; then HASH="sha256sum"; else HASH="shasum -a 256"; fi
(cd "$OUT" && $HASH weather.dump globals.sql uploads.tar config.tar counts.txt > SHA256SUMS)

echo
echo "Backup written to $OUT in ${SECONDS}s"
ls -lh "$OUT" | tail -n +2
echo
cat "$OUT/counts.txt"
echo "Config files included:"
echo "$CONFIG_FILES" | sed 's/^/  /'
