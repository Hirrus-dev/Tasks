#!/bin/sh

if [ -f /a.tar.xz ]; then
    echo "decompressing image..."
    sudo tar xpJf /a.tar.xz -C / > /dev/null 2>&1
    sudo rm /a.tar.xz
    sudo ln -snf dash /bin/sh
fi

chmod -R 0750 $PGDATA && chown -R postgres:postgres $PGHOME

readonly PATRONI_SCOPE=${PATRONI_SCOPE:-WP}
PATRONI_NAMESPACE=${PATRONI_NAMESPACE:-/service}
readonly PATRONI_NAMESPACE=${PATRONI_NAMESPACE%/}
readonly DOCKER_IP=$(hostname --ip-address)



export PATRONI_SCOPE
export PATRONI_NAMESPACE
export PATRONI_NAME="${PATRONI_NAME:-$(hostname)}"
export PATRONI_RESTAPI_CONNECT_ADDRESS="$DOCKER_IP:8008"
export PATRONI_RESTAPI_LISTEN="0.0.0.0:8008"
export PATRONI_admin_PASSWORD="${PATRONI_admin_PASSWORD:-admin}"
export PATRONI_admin_OPTIONS="${PATRONI_admin_OPTIONS:-createdb, createrole}"
export PATRONI_POSTGRESQL_CONNECT_ADDRESS="$DOCKER_IP:5432"
export PATRONI_POSTGRESQL_LISTEN="0.0.0.0:5432"
export PATRONI_POSTGRESQL_DATA_DIR="${PATRONI_POSTGRESQL_DATA_DIR:-$PGDATA}"
export PATRONI_REPLICATION_USERNAME="${PATRONI_REPLICATION_USERNAME:-replicator}"
export PATRONI_REPLICATION_PASSWORD="${PATRONI_REPLICATION_PASSWORD:-repl123}"
#export PATRONI_SUPERUSER_USERNAME="${PATRONI_SUPERUSER_USERNAME:-postgres}"
#export PATRONI_SUPERUSER_PASSWORD="${PATRONI_SUPERUSER_PASSWORD:-postgres}"
export PATRONI_SUPERUSER_USERNAME="${PATRONI_SUPERUSER_USERNAME:-exampleuser}"
export PATRONI_SUPERUSER_PASSWORD="${PATRONI_SUPERUSER_PASSWORD:-examplepass}"

sleep 60
exec patroni postgres1.yml