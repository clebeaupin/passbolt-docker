FROM passbolt/passbolt:latest

RUN apk update && \
    apk add postgresql-client && \
    rm -rf /var/cache/apk/*

COPY docker-entrypoint.sh /docker-entrypoint.sh

CMD ["/docker-entrypoint.sh"]
