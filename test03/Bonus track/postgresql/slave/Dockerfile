#FROM postgres:alpine

ARG PGHOME=/home/postgres
ARG PGDATA=$PGHOME/data
ARG LC_ALL=C.UTF-8
ARG LANG=C.UTF-8


FROM postgres:12
MAINTAINER Hirrus <my-email@domain>

ENV LC_ALL=$LC_ALL LANG=$LANG EDITOR=/usr/bin/editor
ENV PGDATA=$PGDATA PATH=$PATH:$PGBIN
ENV PGHOME=/var/lib/postgresql

RUN apt update &&\
    apt upgrade -y &&\
    apt install -y net-tools &&\
    apt install -y iputils-ping &&\
    apt install -y vim curl less jq locales haproxy sudo &&\
    apt install -y python3-pip &&\
    apt install -y python3-psycopg2 &&\
    pip3 install six &&\
    pip3 install patroni[consul] \

    # Clean up all useless packages and some files
    && apt-get purge -y --allow-remove-essential gzip bzip2 util-linux e2fsprogs \
                libmagic1 bsdmainutils login ncurses-bin libmagic-mgc e2fslibs bsdutils \
                exim4-config gnupg-agent dirmngr \
    && apt-get autoremove -y \
    && apt-get clean -y \
    && rm -rf /var/lib/apt/lists/* \
        /root/.cache \
        /var/cache/debconf/* \
        /etc/rc?.d \
        /etc/systemd \
        /docker-entrypoint* \
        /sbin/pam* \
        /sbin/swap* \
        /sbin/unix* \
        /usr/local/bin/gosu \
        /usr/sbin/[acgipr]* \
        /usr/sbin/*user* \
        /usr/share/doc* \
        /usr/share/man \
        /usr/share/info \
        /usr/share/i18n/locales/translit_hangul \
        /usr/share/locale/?? \
        /usr/share/locale/??_?? \
        /usr/share/postgresql/*/man \
        /usr/share/postgresql-common/pg_wrapper \
        /usr/share/vim/vim80/doc \
        /usr/share/vim/vim80/lang \
        /usr/share/vim/vim80/tutor \
#        /var/lib/dpkg/info/* \
    && find /usr/bin -xtype l -delete \
    && find /var/log -type f -exec truncate --size 0 {} \; \
    && find /usr/lib/python3/dist-packages -name '*test*' | xargs rm -fr \
    && find /lib/x86_64-linux-gnu/security -type f ! -name pam_env.so ! -name pam_permit.so ! -name pam_unix.so -delete


#FROM scratch
#COPY --from=builder / /

#ARG PGHOME
#ARG PGDATA
#ARG LC_ALL
#ARG LANG

#ARG PGBIN=/usr/lib/postgresql/12/bin


#COPY patroni*.py docker/entrypoint.sh /
COPY entrypoint.sh /
COPY postgres?.yml $PGHOME/

#WORKDIR $PGDATA

#RUN chmod -R 0750 /var/lib/postgresql/data && chown -R postgres:postgres $PGHOME
#RUN ls -al $PGHOME > $PGHOME/123.txt
WORKDIR $PGHOME

#RUN chown postgres:postrges postgres?.yml

RUN sed -i 's/^\(  connect_address:\|  - host\)/#&/' postgres?.yml \
    && sed -i 's/^  listen: 127.0.0.1/  listen: 0.0.0.0/' postgres?.yml \
    #&& sed -i "s|^\(  data_dir: \).*|\1$PGDATA|" postgres?.yml \
    #&& sed -i "s|^#\(  bin_dir: \).*|\1$PGBIN|" postgres?.yml \
    && sed -i 's/^  - encoding: UTF8/  - locale: en_US.UTF-8\n&/' postgres?.yml \
    #&& sed -i 's/^\(scope\|name\|etcd\|  host\|  authentication\|  pg_hba\|  parameters\):/#&/' postgres?.yml \
    #&& sed -i 's/^    \(replication\|superuser\|rewind\|unix_socket_directories\|\(\(  \)\{0,1\}\(username\|password\)\)\):/#&/' postgres?.yml \
    && sed -i 's/^      parameters:/      pg_hba:\n      - local all all trust\n      - host replication all all md5\n      - host all all all md5\n&\n        max_connections: 100/'  postgres?.yml 
    #&& if [ "$COMPRESS" = "true" ]; then chmod u+s /usr/bin/sudo; fi \
    #&& chmod +s /bin/ping \
    #&& chown -R postgres:postgres $PGHOME /run /etc/haproxy

USER postgres

ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]