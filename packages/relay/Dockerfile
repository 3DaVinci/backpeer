# Образ relay для стендов (задача 4.6.1): стенд из ~100 узлов держит relay
# в той же сети Docker. Боевой relay — этап 8.1.3.
# Сборка из корня репозитория:
#
#   docker build -f packages/relay/Dockerfile -t fs-relay .
#
# Настройки — переменные FS_RELAY_* (docs/ops/relay.md, раздел «Настройки»).

ARG DART_VERSION=3.13.7

FROM dart:${DART_VERSION} AS build
# Relay использует libsodium через core: ху́к пакета sodium собирает её из
# исходников.
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY pubspec.yaml pubspec.lock ./
COPY packages ./packages
# Приложению Flutter и замерам нужен Flutter SDK, relay — нет.
RUN sed -i '/apps\/app/d; /prototypes\/bench/d' pubspec.yaml \
 && dart pub get
WORKDIR /src/packages/relay
RUN dart build cli -t bin/relay.dart -o /out/relay

FROM debian:bookworm-slim
RUN groupadd --gid 10004 fs-relay \
 && useradd --uid 10004 --gid 10004 --no-create-home --shell /usr/sbin/nologin fs-relay \
 && install -d -o fs-relay -g fs-relay -m 0700 /var/lib/fs-relay
COPY --from=build /out/relay/bundle /opt/fs/relay
COPY packages/relay/docker/entrypoint.sh /usr/local/bin/fs-relay-entrypoint
ENV PATH=/opt/fs/relay/bin:$PATH
USER fs-relay
# Ключ relay: без тома при пересоздании контейнера отчёты координатору
# перестанут проверяться.
VOLUME /var/lib/fs-relay
EXPOSE 7350
ENTRYPOINT ["fs-relay-entrypoint"]
