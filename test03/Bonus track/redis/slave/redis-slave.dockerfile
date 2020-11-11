FROM redis:alpine
COPY redis.conf /usr/local/etc/redis/slave.conf
RUN sed -i -e '$aslaveof cache-1 6379' /usr/local/etc/redis/slave.conf &&\
    sed -i -e '$amasterauth redis123' /usr/local/etc/redis/slave.conf
CMD [ "redis-server", "/usr/local/etc/redis/slave.conf" ]