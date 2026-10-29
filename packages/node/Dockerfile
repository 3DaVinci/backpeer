# Минимальный образ узла-хранителя для стендов: локального с координатором
# (задача 3.10.1, docker-compose.nodes.yaml), с NAT (3.10.2) и из 100 узлов
# (этап 4). Полноценный образ для NAS и Raspberry Pi — этап 6.
# Сборка из корня репозитория:
#
#   docker build -f packages/node/Dockerfile -t fs-node .
#
# Настройки — переменные FS_NODE_* (docs/ops/node.md, раздел «Docker»).
# Бандл `dart build cli` требует glibc 2.34+, поэтому основа — Debian 12.

ARG DART_VERSION=3.13.7

FROM dart:${DART_VERSION} AS build
# Хук пакета sodium собирает libsodium из исходников.
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY pubspec.yaml pubspec.lock ./
COPY packages ./packages
# Приложению Flutter и замерам нужен Flutter SDK, узлу — нет.
RUN sed -i '/apps\/app/d; /prototypes\/bench/d' pubspec.yaml \
 && dart pub get
WORKDIR /src/packages/node
RUN dart build cli -t bin/node.dart -o /out/node

FROM debian:bookworm-slim
RUN groupadd --gid 10003 fs-node \
 && useradd --uid 10003 --gid 10003 --no-create-home --shell /usr/sbin/nologin fs-node \
 && install -d -o fs-node -g fs-node -m 0700 /var/lib/fs-node
COPY --from=build /out/node/bundle /opt/fs/node
COPY packages/node/docker/entrypoint.sh /usr/local/bin/fs-node-entrypoint
ENV PATH=/opt/fs/node/bin:$PATH \
    FS_NODE_DATA_DIR=/var/lib/fs-node \
    FS_NODE_LOG_FILE=- \
    FS_NODE_LISTEN_PORT_MAPPING=off
USER fs-node
# Ключи, сертификат и фрагменты; без тома узел при пересоздании контейнера
# становится новым узлом.
VOLUME /var/lib/fs-node
EXPOSE 7340/tcp 7340/udp
ENTRYPOINT ["fs-node-entrypoint"]
