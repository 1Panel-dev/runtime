ARG JAVA_VERSION
ARG JAVA_VARIANT=jdk-noble

FROM eclipse-temurin:${JAVA_VERSION}-${JAVA_VARIANT}

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        fontconfig \
        procps \
        tzdata && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
ENTRYPOINT ["docker-entrypoint.sh"]

WORKDIR /app

CMD ["java", "-version"]
