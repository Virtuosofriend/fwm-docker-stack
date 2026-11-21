#!/usr/bin/env bash

set -euo pipefail

DUMP_ARG="${1:?usage: load-weather-data.sh <weather.dump>}"
DUMP="$(cd "$(dirname "$DUMP_ARG")" && pwd)/$(basename "$DUMP_ARG")"
[ -f "$DUMP" ] || { echo "No such file: $DUMP" >&2; exit 1; }

step() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*"; }

# Runs inside fwm-postgres with the user and database Compose gave it (POSTGRES_USER / POSTGRES_DB)
sql() {
    printf '%s\n' "$1" | docker exec -i fwm-postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At -v ON_ERROR_STOP=1'
}
summary() {
    sql "SELECT count(*) || ' rows, ' || coalesce(min(date_created)::date::text, '-') || ' to ' || coalesce(max(date_created)::date::text, '-') || ', ' || count(DISTINCT weather_station_id) || ' stations' FROM weather_data"
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Extract only the rows of weather_data, fully, before touching the database
step "Extracting weather_data rows from $(basename "$DUMP")"
docker exec -i fwm-postgres pg_restore --data-only -t weather_data -f - < "$DUMP" > "$WORK/weather_data.sql"
grep -q '^COPY public.weather_data ' "$WORK/weather_data.sql" || { echo "No weather_data rows in $DUMP" >&2; exit 1; }
[ "$(grep -c '^\\\.$' "$WORK/weather_data.sql")" = "1" ] || { echo "Extracted data is incomplete" >&2; exit 1; }
ROWS=$(awk '/^COPY public.weather_data /{on=1; next} /^\\\.$/{on=0} on' "$WORK/weather_data.sql" | wc -l | tr -d ' ')
step "Extracted $ROWS rows"

step "Before: $(summary)"

step "Stopping the local crawler during the load"
docker stop fwm-crawlers >/dev/null
trap 'docker start fwm-crawlers >/dev/null; rm -rf "$WORK"' EXIT

# One transaction: on any error (missing station, column mismatch) nothing changes
step "Replacing weather_data rows in one transaction"
{
    echo "TRUNCATE public.weather_data;"
    cat "$WORK/weather_data.sql"
    # The dump empties search_path, so names must be schema-qualified from here on
    echo "SELECT setval('public.weather_data_id_seq', (SELECT coalesce(max(id), 1) FROM public.weather_data));"
} | docker exec -i fwm-postgres sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -q -v ON_ERROR_STOP=1 --single-transaction' >/dev/null

step "Refreshing table statistics"
sql "ANALYZE weather_data" >/dev/null

step "After:  $(summary)"
LOADED=$(sql "SELECT count(*) FROM weather_data")
[ "$LOADED" = "$ROWS" ] || { echo "Row count mismatch: extracted $ROWS, table has $LOADED" >&2; exit 1; }
step "Done: $LOADED rows loaded; id sequence at $(sql "SELECT last_value FROM weather_data_id_seq"); restarting the crawler"
