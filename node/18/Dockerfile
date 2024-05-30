ARG NODE_VERSION

FROM node:${NODE_VERSION}

RUN npm install -g pnpm

COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
ENTRYPOINT ["docker-entrypoint.sh"]

CMD [ "node" ]