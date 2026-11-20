#!/usr/bin/env bash
set -euo pipefail

DIR="${1:?usage: restore-test.sh <backup-folder> [--delete-files]}"
DIR="$(cd "$DIR" && pwd)"
DELETE_FILES="${2:-}"
NAME="fwm-restore-test"
RESTORE_DB="weather_restore"

recorded() {
    local value
    value=$(grep "^$1|" "$DIR/counts.txt" | cut -d'|' -f2-)
    [ -n "$value" ] || { echo "$1 is missing from $DIR/counts.txt" >&2; exit 1; }
    printf '%s' "$value"
}
IMAGE="$(recorded postgres_image)"
DB_OWNER="$(recorded db_user)"

step() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*"; }
# -v also removes the container's data volume (the postgis image keeps its data in one)
cleanup() { docker rm -f -v "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT
trap 'echo "FAIL: stopped at line $LINENO; backup kept in $DIR" >&2' ERR

FAILED=0
check() { # name, ok (0/1), details
    if [ "$2" = "1" ]; then printf '  PASS  %-28s %s\n' "$1" "$3"; else printf '  FAIL  %-28s %s\n' "$1" "$3"; FAILED=1; fi
}
expected() { recorded "$1"; }
sql() { docker exec -i "$NAME" psql -U postgres -d "$RESTORE_DB" -At -v ON_ERROR_STOP=1 -c "$1"; }

SECONDS=0
step "Verifying checksums"
if command -v sha256sum >/dev/null; then HASH="sha256sum"; else HASH="shasum -a 256"; fi
(cd "$DIR" && $HASH -c SHA256SUMS)

step "Starting throwaway $IMAGE as $NAME"
cleanup
docker run -d --name "$NAME" -e POSTGRES_PASSWORD="$(openssl rand -hex 16)" \
    -v "$DIR":/backup:ro "$IMAGE" >/dev/null
# The image starts a temporary server for its init scripts first; wait for the real one
until docker logs "$NAME" 2>&1 | grep -q 'PostgreSQL init process complete'; do sleep 1; done
until docker exec "$NAME" pg_isready -U postgres -q; do sleep 1; done

step "Loading roles"
docker exec "$NAME" psql -U postgres -q -f /backup/globals.sql 2>&1 | grep -v 'already exists' || true

step "Creating $RESTORE_DB from template0"
docker exec "$NAME" createdb -U postgres -T template0 -O "$DB_OWNER" "$RESTORE_DB"

step "Restoring (pg_restore -j 4)"
RESTORE_START=$SECONDS
docker exec "$NAME" pg_restore -U postgres -d "$RESTORE_DB" -j 4 --exit-on-error /backup/weather.dump
RESTORE_TIME=$((SECONDS - RESTORE_START))

step "Checking"
for table in weather_data weather_stations directus_users directus_files; do
    got=$(sql "SELECT count(*) FROM $table"); want=$(expected "$table")
    check "$table rows" "$([ "$got" -ge "$want" ] && [ "$got" -gt 0 ] && echo 1 || echo 0)" "restored $got, at backup time $want"
done

got=$(sql "SELECT to_char(max(date_created) AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SS') FROM weather_data")
want=$(expected newest_reading)
check "newest reading" "$([ "$got" \> "$want" ] || [ "$got" = "$want" ] && echo 1 || echo 0)" "restored $got, at backup time $want"

got=$(sql "SELECT max(version) FROM directus_migrations"); want=$(expected latest_migration)
check "latest Directus migration" "$([ "$got" = "$want" ] && echo 1 || echo 0)" "$got"

got=$(sql "SELECT postgis_lib_version()" 2>/dev/null || echo "")
check "PostGIS" "$([ -n "$got" ] && echo 1 || echo 0)" "${got:-not working}"

# Every image Directus knows about (local storage) must be in uploads.tar
FILES_TMP="$(mktemp -d)"
tar -tf "$DIR/uploads.tar" | sed 's#^uploads/##' | grep -v '^$' | sort -u > "$FILES_TMP/in-archive"
sql "SELECT filename_disk FROM directus_files WHERE storage = 'local' AND filename_disk IS NOT NULL" | sort -u > "$FILES_TMP/in-db"
MISSING=$(comm -13 "$FILES_TMP/in-archive" "$FILES_TMP/in-db" | wc -l | tr -d ' ')
check "uploads complete" "$([ "$MISSING" = "0" ] && echo 1 || echo 0)" "$(wc -l < "$FILES_TMP/in-db" | tr -d ' ') files in DB, $MISSING missing from uploads.tar"
[ "$MISSING" = "0" ] || comm -13 "$FILES_TMP/in-archive" "$FILES_TMP/in-db" | head -5 | sed 's/^/        missing: /'
rm -rf "$FILES_TMP"

ENV_FILES=$(tar -tf "$DIR/config.tar" | grep -c '\.env' || true)
check "config archive" "$([ "$ENV_FILES" -gt 0 ] && echo 1 || echo 0)" "$ENV_FILES .env files, extensions included: $(tar -tf "$DIR/config.tar" | grep -q '^extensions/' && echo yes || echo no)"

echo
if [ "$FAILED" = "0" ]; then
    echo "PASS: restore took ${RESTORE_TIME}s, whole test ${SECONDS}s"
    if [ "$DELETE_FILES" = "--delete-files" ]; then
        rm -rf "$DIR"
        echo "Deleted $DIR"
    fi
else
    echo "FAIL: backup kept in $DIR for inspection"
    exit 1
fi
