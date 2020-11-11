#!/usr/bin/env bash



# used to create initial postgres directories and if run as root, ensure ownership to the "postgres" user
docker_create_db_directories() {
	local user; user="$(id -u)"

	mkdir -p "$PGDATA"
	chmod 700 "$PGDATA"

	# ignore failure since it will be fine when using the image provided directory; see also https://github.com/docker-library/postgres/pull/289
	mkdir -p /var/run/postgresql || :
	chmod 775 /var/run/postgresql || :

	# Create the transaction log directory before initdb is run so the directory is owned by the correct user
	if [ -n "$POSTGRES_INITDB_WALDIR" ]; then
		mkdir -p "$POSTGRES_INITDB_WALDIR"
		if [ "$user" = '0' ]; then
			find "$POSTGRES_INITDB_WALDIR" \! -user postgres -exec chown postgres '{}' +
		fi
		chmod 700 "$POSTGRES_INITDB_WALDIR"
	fi

	# allow the container to be started with `--user`
	if [ "$user" = '0' ]; then
		find "$PGDATA" \! -user postgres -exec chown postgres '{}' +
		find /var/run/postgresql \! -user postgres -exec chown postgres '{}' +
	fi
}

# initialize empty PGDATA directory with new database via 'initdb'
# arguments to `initdb` can be passed via POSTGRES_INITDB_ARGS or as arguments to this function
# `initdb` automatically creates the "postgres", "template0", and "template1" dbnames
# this is also where the database user is created, specified by `POSTGRES_USER` env
docker_init_database_dir() {
	# "initdb" is particular about the current user existing in "/etc/passwd", so we use "nss_wrapper" to fake that if necessary
	# see https://github.com/docker-library/postgres/pull/253, https://github.com/docker-library/postgres/issues/359, https://cwrap.org/nss_wrapper.html
	if ! getent passwd "$(id -u)" &> /dev/null && [ -e /usr/lib/libnss_wrapper.so ]; then
		export LD_PRELOAD='/usr/lib/libnss_wrapper.so'
		export NSS_WRAPPER_PASSWD="$(mktemp)"
		export NSS_WRAPPER_GROUP="$(mktemp)"
		echo "postgres:x:$(id -u):$(id -g):PostgreSQL:$PGDATA:/bin/false" > "$NSS_WRAPPER_PASSWD"
		echo "postgres:x:$(id -g):" > "$NSS_WRAPPER_GROUP"
	fi

	if [ -n "$POSTGRES_INITDB_WALDIR" ]; then
		set -- --waldir "$POSTGRES_INITDB_WALDIR" "$@"
	fi

	eval 'initdb --username="$POSTGRES_USER" --pwfile=<(echo "$POSTGRES_PASSWORD") '"$POSTGRES_INITDB_ARGS"' "$@"'

	# unset/cleanup "nss_wrapper" bits
	if [ "${LD_PRELOAD:-}" = '/usr/lib/libnss_wrapper.so' ]; then
		rm -f "$NSS_WRAPPER_PASSWD" "$NSS_WRAPPER_GROUP"
		unset LD_PRELOAD NSS_WRAPPER_PASSWD NSS_WRAPPER_GROUP
	fi
}

# Execute sql script, passed via stdin (or -f flag of pqsl)
# usage: docker_process_sql [psql-cli-args]
#    ie: docker_process_sql --dbname=mydb <<<'INSERT ...'
#    ie: docker_process_sql -f my-file.sql
#    ie: docker_process_sql <my-file.sql
docker_process_sql() {
	local query_runner=( psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --no-password )	
	#local query_runner="psql -v ON_ERROR_STOP=1 --username $POSTGRES_USER --no-password"
    if [ -n "$POSTGRES_DB" ]; then
		query_runner+=( --dbname "$POSTGRES_DB" )
        #query_runner+=" --dbname $POSTGRES_DB"
	fi
    echo query_runner
	"${query_runner[@]}" "$@"
}

# create initial database
# uses environment variables for input: POSTGRES_DB
docker_setup_db() {
	if [ "$POSTGRES_DB" != 'postgres' ]; then
		POSTGRES_DB= docker_process_sql --dbname postgres --set db="$POSTGRES_DB" <<-'EOSQL'
			CREATE DATABASE :"db" ;
		EOSQL
		echo
	fi
	
	POSTGRES_REP_USER= docker_process_sql --dbname postgres --set repl_user="$PG_REP_USER" --set repl_pass="$PG_REP_PASSWORD" <<-'EOSQL'
		CREATE USER :"repl_user" REPLICATION LOGIN CONNECTION LIMIT 100 ENCRYPTED PASSWORD :'repl_pass';
	EOSQL

#	psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
#		CREATE USER $PG_REP_USER REPLICATION LOGIN CONNECTION LIMIT 100 ENCRYPTED PASSWORD '$PG_REP_PASSWORD';
#		EOSQL

}


# start socket-only postgresql server for setting up or running scripts
# all arguments will be passed along as arguments to `postgres` (via pg_ctl)
docker_temp_server_start() {
	if [ "$1" = 'postgres' ]; then
		shift
	fi

	# internal start of server in order to allow setup using psql client
	# does not listen on external TCP/IP and waits until start finishes
	set -- "$@" -c listen_addresses='' -p "${PGPORT:-5432}"

	PGUSER="${PGUSER:-$POSTGRES_USER}" \
	pg_ctl -D "$PGDATA" \
		-o "$(printf '%q ' "$@")" \
		-w start
}

# stop postgresql server after done setting up user and running scripts
docker_temp_server_stop() {
	PGUSER="${PGUSER:-postgres}" \
	pg_ctl -D "$PGDATA" -m fast -w stop
}

# Loads various settings that are used elsewhere in the script
# This should be called before any other functions
docker_setup_env() {
	#file_env 'POSTGRES_PASSWORD'

	#file_env 'POSTGRES_USER' 'postgres'
	#file_env 'POSTGRES_DB' "$POSTGRES_USER"
	#file_env 'POSTGRES_INITDB_ARGS'
	#export POSTGRES_PASSWORD
    #export POSTGRES_DB
    # default authentication method is md5
	#: "${POSTGRES_HOST_AUTH_METHOD:=md5}"

	declare -g DATABASE_ALREADY_EXISTS
	# look specifically for PG_VERSION, as it is expected in the DB dir
	if [ -s "$PGDATA/PG_VERSION" ]; then
		DATABASE_ALREADY_EXISTS='true'
	fi
}

docker_verify_minimum_env() {
	# check password first so we can output the warning before postgres
	# messes it up
	if [ "${#POSTGRES_PASSWORD}" -ge 100 ]; then
		cat >&2 <<-'EOWARN'
			WARNING: The supplied POSTGRES_PASSWORD is 100+ characters.
			  This will not work if used via PGPASSWORD with "psql".
			  https://www.postgresql.org/message-id/flat/E1Rqxp2-0004Qt-PL%40wrigleys.postgresql.org (BUG #6412)
			  https://github.com/docker-library/postgres/issues/507
		EOWARN
	fi
	if [ -z "$POSTGRES_PASSWORD" ] && [ 'trust' != "$POSTGRES_HOST_AUTH_METHOD" ]; then
		# The - option suppresses leading tabs but *not* spaces. :)
		cat >&2 <<-'EOE'
			Error: Database is uninitialized and superuser password is not specified.
			       You must specify POSTGRES_PASSWORD to a non-empty value for the
			       superuser. For example, "-e POSTGRES_PASSWORD=password" on "docker run".
			       You may also use "POSTGRES_HOST_AUTH_METHOD=trust" to allow all
			       connections without a password. This is *not* recommended.
			       See PostgreSQL documentation about "trust":
			       https://www.postgresql.org/docs/current/auth-trust.html
		EOE
		exit 1
	fi
	if [ 'trust' = "$POSTGRES_HOST_AUTH_METHOD" ]; then
		cat >&2 <<-'EOWARN'
			********************************************************************************
			WARNING: POSTGRES_HOST_AUTH_METHOD has been set to "trust". This will allow
			         anyone with access to the Postgres port to access your database without
			         a password, even if POSTGRES_PASSWORD is set. See PostgreSQL
			         documentation about "trust":
			         https://www.postgresql.org/docs/current/auth-trust.html
			         In Docker's default configuration, this is effectively any other
			         container on the same system.
			         It is not recommended to use POSTGRES_HOST_AUTH_METHOD=trust. Replace
			         it with "-e POSTGRES_PASSWORD=password" instead to set a password in
			         "docker run".
			********************************************************************************
		EOWARN
	fi
}

patroni_start() {
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
#	export PATRONI_SUPERUSER_USERNAME="${PATRONI_SUPERUSER_USERNAME:-postgres}"
#	export PATRONI_SUPERUSER_PASSWORD="${PATRONI_SUPERUSER_PASSWORD:-postgres}"
	export PATRONI_SUPERUSER_USERNAME="${PATRONI_SUPERUSER_USERNAME:-exampleuser}"
	export PATRONI_SUPERUSER_PASSWORD="${PATRONI_SUPERUSER_PASSWORD:-examplepass}"

	exec patroni postgres0.yml
}


_main() {
    docker_setup_env
    docker_create_db_directories
    # only run initialization on an empty data directory
		if [ -z "$DATABASE_ALREADY_EXISTS" ]; then
			docker_verify_minimum_env

			# check dir permissions to reduce likelihood of half-initialized database
			ls /docker-entrypoint-initdb.d/ > /dev/null

			docker_init_database_dir
			#pg_setup_hba_conf

			# PGPASSWORD is required for psql when authentication is required for 'local' connections via pg_hba.conf and is otherwise harmless
			# e.g. when '--auth=md5' or '--auth-local=md5' is used in POSTGRES_INITDB_ARGS
			export PGPASSWORD="${PGPASSWORD:-$POSTGRES_PASSWORD}"
			docker_temp_server_start postgres

			docker_setup_db
			#docker_process_init_files /docker-entrypoint-initdb.d/*

			docker_temp_server_stop
			unset PGPASSWORD

			echo
			echo 'PostgreSQL init process complete; ready for start up.'
			echo

			patroni_start
		else
			echo
			echo 'PostgreSQL Database directory appears to contain a database; Skipping initialization'
			echo

			patroni_start
		fi
}

_main postgres

#if [ -f /a.tar.xz ]; then
#    echo "decompressing image..."
#    sudo tar xpJf /a.tar.xz -C / > /dev/null 2>&1
#    sudo rm /a.tar.xz
#    sudo ln -snf dash /bin/sh
#fi

#set -e
#psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --host --dbname "$POSTGRES_DB" <<-EOSQL
#    CREATE USER $PG_REP_USER REPLICATION LOGIN CONNECTION LIMIT 100 ENCRYPTED PASSWORD '$PG_REP_PASSWORD';
#EOSQL
#set -e
#psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --host 127.0.0.1 --dbname postgres <<-EOSQL
#    CREATE DATABASE '$POSTGRES_DB' OWNER '$POSTGRES_USER';
#EOSQL



#chmod -R 0750 $PGDATA && chown -R postgres:postgres $PGHOME

#readonly PATRONI_SCOPE=${PATRONI_SCOPE:-WP}
#PATRONI_NAMESPACE=${PATRONI_NAMESPACE:-/service}
#readonly PATRONI_NAMESPACE=${PATRONI_NAMESPACE%/}
#readonly DOCKER_IP=$(hostname --ip-address)



#export PATRONI_SCOPE
#export PATRONI_NAMESPACE
#export PATRONI_NAME="${PATRONI_NAME:-$(hostname)}"
#export PATRONI_RESTAPI_CONNECT_ADDRESS="$DOCKER_IP:8008"
#export PATRONI_RESTAPI_LISTEN="0.0.0.0:8008"
#export PATRONI_admin_PASSWORD="${PATRONI_admin_PASSWORD:-admin}"
#export PATRONI_admin_OPTIONS="${PATRONI_admin_OPTIONS:-createdb, createrole}"
#export PATRONI_POSTGRESQL_CONNECT_ADDRESS="$DOCKER_IP:5432"
#export PATRONI_POSTGRESQL_LISTEN="0.0.0.0:5432"
#export PATRONI_POSTGRESQL_DATA_DIR="${PATRONI_POSTGRESQL_DATA_DIR:-$PGDATA}"
#export PATRONI_REPLICATION_USERNAME="${PATRONI_REPLICATION_USERNAME:-replicator}"
#export PATRONI_REPLICATION_PASSWORD="${PATRONI_REPLICATION_PASSWORD:-repl123}"
#export PATRONI_SUPERUSER_USERNAME="${PATRONI_SUPERUSER_USERNAME:-postgres}"
#export PATRONI_SUPERUSER_PASSWORD="${PATRONI_SUPERUSER_PASSWORD:-postgres}"
#export PATRONI_SUPERUSER_USERNAME="${PATRONI_SUPERUSER_USERNAME:-exampleuser}"
#export PATRONI_SUPERUSER_PASSWORD="${PATRONI_SUPERUSER_PASSWORD:-examplepass}"

#exec patroni postgres0.yml