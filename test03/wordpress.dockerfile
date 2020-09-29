FROM wordpress:php7.4-fpm
MAINTAINER Hirrus <my-email@domain>
#USER root
RUN apt update && apt upgrade -y && apt install -y git &&\
    apt install -y libmcrypt-dev &&\
    apt install -y libpq-dev &&\
    apt install -y wget &&\
    wget -P ~/ https://ru.wordpress.org/wordpress-5.5.1-ru_RU.tar.gz &&\
    cd /usr/src/ &&\
    tar -xzf ~/wordpress-5.5.1-ru_RU.tar.gz &&\
    cp -R /usr/src/wordpress/* /var/www/html/ &&\
    cp /var/www/html/wp-config-sample.php /var/www/html/wp-config.php &&\
    git clone https://github.com/kevinoid/postgresql-for-wordpress ~/postgresql-for-wordpress


# add pgsql plugin to wordpress
RUN sed -i '/chown "$user:$group" wp-config.php/a \\t\t\tcp ~/object-cache.php /var/www/html/wp-content/' /usr/local/bin/docker-entrypoint.sh &&\
    sed -i '/chown "$user:$group" wp-config.php/a \\t\t\tcp ~/postgresql-for-wordpress/pg4wp/db.php /var/www/html/wp-content/' /usr/local/bin/docker-entrypoint.sh &&\
    sed -i '/chown "$user:$group" wp-config.php/a \\t\t\tcp -R ~/postgresql-for-wordpress/pg4wp/* /var/www/html/wp-content/pg4wp/' /usr/local/bin/docker-entrypoint.sh &&\
    sed -i '/chown "$user:$group" wp-config.php/a \\t\t\tmkdir /var/www/html/wp-content/pg4wp' /usr/local/bin/docker-entrypoint.sh &&\
    sed -i '/chown "$user:$group" wp-config.php/a \\t\t\t# added by Hirrus postgresql for wordpress' /usr/local/bin/docker-entrypoint.sh

RUN docker-php-ext-configure pgsql -with-pgsql=/usr/local/pgsql
RUN docker-php-ext-install pgsql pdo_pgsql

# add redis plugin to wordpress
RUN pecl install -o -f redis \
&&  rm -rf /tmp/pear \
&&  docker-php-ext-enable redis
COPY object-cache.php /root/

RUN mv "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

#RUN sed -i 's/;cgi.fix_pathinfo.*/cgi.fix_pathinfo = 1;/' $PHP_INI_DIR/php.ini