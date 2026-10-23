# Образ координатора и подписанта для локального стенда и тестового
# сервера (задачи 2.9.5, 2.9.4; docs/ops/coordinator.md, раздел «Docker»).
# Сборка из корня репозитория:
#
#   docker build -f packages/coordinator/Dockerfile -t fs-coordinator .
#
# Бандлы `dart build cli` (бинарник и lib/ с libsodium и SQLite) требуют
# glibc 2.34+, поэтому основа — Debian 12, а не Alpine.

ARG DART_VERSION=3.13.5

FROM dart:${DART_VERSION} AS build
# Хук пакета sodium собирает libsodium из исходников.
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY pubspec.yaml pubspec.lock ./
COPY packages ./packages
# В рабочем пространстве есть приложение Flutter и замеры: им нужен
# Flutter SDK, координатору — нет.
RUN sed -i '/apps\/app/d; /prototypes\/bench/d' pubspec.yaml \
 && dart pub get
WORKDIR /src/packages/coordinator
RUN dart build cli -t bin/coordinator.dart -o /out/coordinator \
 && dart build cli -t bin/signer.dart -o /out/signer

FROM debian:bookworm-slim
# Фиксированные uid и gid: подписант пускает только uid координатора
# (--allow-uid), тома создаются с этими владельцами.
RUN groupadd --gid 10001 fs-coordinator \
 && useradd --uid 10001 --gid 10001 --no-create-home --shell /usr/sbin/nologin fs-coordinator \
 && groupadd --gid 10002 fs-signer \
 && useradd --uid 10002 --gid 10002 --no-create-home --shell /usr/sbin/nologin fs-signer \
 && install -d -o fs-signer -g fs-signer -m 0700 /var/lib/fs-signer \
 && install -d -o fs-signer -g fs-coordinator -m 2750 /run/fs-signer
COPY --from=build /out/coordinator/bundle /opt/fs/coordinator
COPY --from=build /out/signer/bundle /opt/fs/signer
ENV PATH=/opt/fs/coordinator/bin:/opt/fs/signer/bin:$PATH
USER fs-coordinator
EXPOSE 8080
CMD ["coordinator", "serve"]
