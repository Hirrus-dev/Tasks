#!/bin/bash

if [ ! -s "$PGDATA/PG_VERSION" ]; then
#gosu postgres echo "$PG_MASTER_HOST:*:replication:$PG_REP_USER:$PG_REP_PASSWORD" > ~/.pgpass
gosu postgres bash -c 'echo "$PG_MASTER_HOST:*:replication:$PG_REP_USER:$PG_REP_PASSWORD" > ~/.pgpass'

gosu postgres bash -c 'chmod 0600 ~/.pgpass'

until ping -c 1 -W 1 ${PG_MASTER_HOST:?missing environment variable. PG_MASTER_HOST must be set}
    do
        echo "Waiting for master to ping..."
        sleep 1s
done
until gosu postgres pg_basebackup -h ${PG_MASTER_HOST} -D ${PGDATA} -U ${PG_REP_USER} -P -Xs -R
#until pg_basebackup -h ${PG_MASTER_HOST} -D ${PGDATA} -U ${PG_REP_USER} -vP -W -R
    do
        echo "Waiting for master to connect..."
        sleep 1s
done

echo "host replication all 0.0.0.0/0 md5" >> "$PGDATA/pg_hba.conf"

set -e

#chown postgres. ${PGDATA} -R
chmod 700 ${PGDATA} -R
fi

exec "$@"