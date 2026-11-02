# Образ клиента для стендов (задача 4.6.1): клиенты с бэкапами в сети
# стенда из ~100 узлов. Это CLI из `dart build cli`, без Flutter.
# Сборка из корня репозитория:
#
#   docker build -f packages/cli/Dockerfile -t fs-cli .
#
# Каталог программы (`FS_HOME`) и данные для бэкапа (`/data`) — тома: без
# них пересозданный контейнер теряет учётную запись и индекс.

ARG DART_VERSION=3.13.7

FROM dart:${DART_VERSION} AS build
# Хук пакета sodium собирает libsodium из исходников; SQLite — из core.
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY pubspec.yaml pubspec.lock ./
COPY packages ./packages
# Приложению Flutter и замерам нужен Flutter SDK, CLI — нет.
RUN sed -i '/apps\/app/d; /prototypes\/bench/d' pubspec.yaml \
 && dart pub get
WORKDIR /src/packages/cli
RUN dart build cli -t bin/cli.dart -o /out/cli

FROM debian:bookworm-slim
# `ip` нужен стенду с NAT (задача 3.10.2): точка входа клиента ставит
# маршрут по умолчанию на маршрутизатор, пока контейнер ещё root.
RUN apt-get update \
 && apt-get install -y --no-install-recommends iproute2 \
 && rm -rf /var/lib/apt/lists/*
RUN groupadd --gid 10005 fs-cli \
 && useradd --uid 10005 --gid 10005 --no-create-home --shell /usr/sbin/nologin fs-cli \
 && install -d -o fs-cli -g fs-cli -m 0700 /home/client /data
COPY --from=build /out/cli/bundle /opt/fs/cli
ENV PATH=/opt/fs/cli/bin:$PATH \
    FS_HOME=/home/client
USER fs-cli
WORKDIR /data
VOLUME /home/client
VOLUME /data
ENTRYPOINT ["cli"]
