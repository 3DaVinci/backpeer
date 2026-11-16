# Образ веб-панели оператора Backpeer (docs/ops/admin.md, ADR-017).
# Сборка из корня репозитория:
#
#   docker build -f packages/admin/Dockerfile -t backpeer-admin .
#
# Панель только читает базу координатора; конфиг с операторами и паролем
# роли монтируется в /etc/fs-admin/admin.yaml.

ARG NODE_VERSION=22
ARG DART_VERSION=3.14.0

FROM node:${NODE_VERSION}-bookworm-slim AS web
WORKDIR /web
COPY apps/admin/package.json apps/admin/package-lock.json ./
RUN npm ci --prefer-offline
COPY apps/admin ./
RUN npm run build

FROM dart:${DART_VERSION} AS build
# Хук пакета sodium собирает libsodium из исходников.
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY pubspec.yaml pubspec.lock ./
COPY packages ./packages
# В рабочем пространстве есть приложение Flutter и замеры: им нужен
# Flutter SDK, панели — нет.
RUN sed -i '/apps\/app/d; /prototypes\/bench/d' pubspec.yaml \
 && dart pub get
WORKDIR /src/packages/admin
RUN dart build cli -t bin/admin.dart -o /out/admin

FROM debian:bookworm-slim
RUN groupadd --gid 10006 fs-admin \
 && useradd --uid 10006 --gid 10006 --no-create-home \
      --shell /usr/sbin/nologin fs-admin \
 && install -d -o fs-admin -g fs-admin -m 0700 /var/lib/fs-admin/reports \
 && install -d -o root -g fs-admin -m 0750 /etc/fs-admin
COPY --from=build /out/admin/bundle /opt/fs/admin
COPY --from=web /web/dist /opt/fs/admin-web
ENV PATH=/opt/fs/admin/bin:$PATH
USER fs-admin
EXPOSE 8092
CMD ["admin", "serve", "--config", "/etc/fs-admin/admin.yaml"]
