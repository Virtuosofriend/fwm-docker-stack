-- Read-only Postgres login for Grafana. Run once:
--   docker exec -i fwm-postgres psql -U weather -d weather -v pw="<GRAFANA_DB_PASSWORD>" < grafana/create-reader.sql

CREATE ROLE grafana_reader LOGIN PASSWORD :'pw' CONNECTION LIMIT 5;

-- Cancel any Grafana query that runs longer than 10 seconds, so dashboards can't slow down production
ALTER ROLE grafana_reader SET statement_timeout = '10s';
ALTER ROLE grafana_reader SET default_transaction_read_only = on;

GRANT USAGE ON SCHEMA public TO grafana_reader;
GRANT SELECT ON weather_data, weather_stations, weather_station_types TO grafana_reader;
