FROM passbolt/passbolt:latest

RUN apk update && \
    apk add postgresql-client && \
    apk add php5-pdo_pgsql && \
    rm -rf /var/cache/apk/*

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY docker-entrypoint.sh /docker-entrypoint.sh

CMD ["/docker-entrypoint.sh"]
