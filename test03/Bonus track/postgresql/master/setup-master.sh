#!/bin/bash
echo "host replication all 172.0.0.0/8 md5" >> "$PGDATA/pg_hba.conf"
echo "host replication all 192.0.0.0/8 md5" >> "$PGDATA/pg_hba.conf"

set -e
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE USER $PG_REP_USER REPLICATION LOGIN CONNECTION LIMIT 100 ENCRYPTED PASSWORD '$PG_REP_PASSWORD';
EOSQL

cat >> ${PGDATA}/postgresql.conf <<EOF
wal_level = replica
archive_mode = on
archive_command = 'cd .'
max_wal_senders = 8
wal_keep_segments = 8
hot_standby = on
EOF