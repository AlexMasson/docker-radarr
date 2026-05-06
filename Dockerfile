# syntax=docker/dockerfile:1

# --- Stage 1: Build frontend ---
FROM node:20-alpine AS frontend

ARG RADARR_REPO="https://github.com/AlexMasson/Radarr.git"
ARG RADARR_BRANCH="feature/llm-prioritization"

RUN apk add --no-cache git && \
  git clone --depth 1 --branch "${RADARR_BRANCH}" "${RADARR_REPO}" /src

WORKDIR /src

RUN yarn install --frozen-lockfile && \
    yarn build --env production

# --- Stage 2: Build backend ---
FROM mcr.microsoft.com/dotnet/sdk:8.0-alpine AS builder

COPY --from=frontend /src /src

WORKDIR /src/src

RUN dotnet msbuild -restore Radarr.sln \
      -p:SelfContained=True \
      -p:Configuration=Release \
      -p:RuntimeIdentifiers=linux-musl-x64 \
      -t:PublishAllRids \
      /p:TreatWarningsAsErrors=false && \
    mkdir /build && \
    cp -r /src/_output/net8.0/linux-musl-x64/publish/* /build/ && \
    cp -r /src/_output/UI /build/UI

# --- Stage 3: Runtime image (same as upstream linuxserver) ---
FROM ghcr.io/linuxserver/baseimage-alpine:3.23

# set version label
ARG BUILD_DATE
ARG VERSION
LABEL build_version="Custom LLM-prioritization build:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="AlexMasson"

# environment settings
ENV XDG_CONFIG_HOME="/config/xdg" \
  COMPlus_EnableDiagnostics=0 \
  TMPDIR=/run/radarr-temp

RUN \
  echo "**** install packages ****" && \
  apk add -U --upgrade --no-cache \
    icu-libs \
    sqlite-libs \
    xmlstarlet && \
  mkdir -p /app/radarr/bin

# copy built binaries and UI from builder stage (UI goes inside bin/)
COPY --from=builder /build/ /app/radarr/bin/

RUN \
  echo -e "UpdateMethod=docker\nBranch=feature/llm-prioritization\nPackageVersion=${VERSION:-LocalBuild}\nPackageAuthor=AlexMasson (fork)" > /app/radarr/package_info && \
  printf "Custom build version: ${VERSION}\nBuild-date: ${BUILD_DATE}" > /build_version

# copy local files
COPY root/ /

# ports and volumes
EXPOSE 7878

VOLUME /config
