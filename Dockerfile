# This is the Dockerfile for the Loki build image that is used by the CI pipelines.

FROM golang:1.22.5-bookworm as helm
ARG TARGETARCH
ARG TARGETOS
ARG HELM_VER="v3.2.3"
RUN curl -L "https://get.helm.sh/helm-${HELM_VER}-linux-$TARGETARCH.tar.gz" | tar zx && \
    install -t /usr/local/bin "linux-$TARGETARCH/helm"
RUN BIN=$([ "$TARGETARCH" = "s390x" ] && echo "helm-docs_Linux_s390x" || echo "helm-docs_Linux_x86_64") &&  \
    curl -L "https://github.com/norwoodj/helm-docs/releases/download/v1.11.2/$BIN.tar.gz" | tar zx && \
    install -t /usr/local/bin helm-docs

FROM alpine:3.18.6 as lychee
ARG TARGETARCH
ARG LYCHEE_VER="0.7.0"
RUN apk add --no-cache curl && \
    curl -L -o /tmp/lychee-$LYCHEE_VER.tgz https://github.com/lycheeverse/lychee/releases/download/${LYCHEE_VER}/lychee-${LYCHEE_VER}-x86_64-unknown-linux-gnu.tar.gz && \
    tar -xz -C /tmp -f /tmp/lychee-$LYCHEE_VER.tgz && \
    mv /tmp/lychee /usr/bin/lychee && \
    rm -rf "/tmp/linux-$TARGETARCH" /tmp/lychee-$LYCHEE_VER.tgz

FROM alpine:3.18.6 as golangci
RUN apk add --no-cache curl && \
    cd / && \
    curl -sfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s v1.55.1

FROM alpine:3.18.6 as buf
ARG TARGETOS
RUN apk add --no-cache curl && \
    curl -sSL "https://github.com/bufbuild/buf/releases/download/v1.4.0/buf-$TARGETOS-$(uname -m)" -o "/usr/bin/buf" && \
    chmod +x "/usr/bin/buf"

FROM alpine:3.18.6 as docker
RUN apk add --no-cache docker-cli docker-cli-buildx

FROM golang:1.22.5-bookworm as drone
ARG TARGETARCH
RUN curl -L "https://github.com/drone/drone-cli/releases/download/v1.7.0/drone_linux_$TARGETARCH".tar.gz | tar zx && \
    install -t /usr/local/bin drone

# Install faillint used to lint go imports in CI.
FROM golang:1.22.5-bookworm as faillint
RUN GO111MODULE=on go install github.com/fatih/faillint@v1.12.0
RUN GO111MODULE=on go install golang.org/x/tools/cmd/goimports@v0.7.0

FROM golang:1.22.5-bookworm as delve
RUN GO111MODULE=on go install github.com/go-delve/delve/cmd/dlv@latest

FROM golang:1.22.5-bookworm as ghr
RUN GO111MODULE=on go install github.com/tcnksm/ghr@9349474

FROM golang:1.22.5-bookworm as nfpm
RUN GO111MODULE=on go install github.com/goreleaser/nfpm/v2/cmd/nfpm@v2.11.3

FROM golang:1.22.5-bookworm as gotestsum
RUN GO111MODULE=on go install gotest.tools/gotestsum@v1.8.2

FROM golang:1.22.5-bookworm as jsonnet
RUN GO111MODULE=on go install github.com/jsonnet-bundler/jsonnet-bundler/cmd/jb@v0.5.1
RUN GO111MODULE=on go install github.com/monitoring-mixins/mixtool/cmd/mixtool@16dc166166d91e93475b86b9355a4faed2400c18
RUN GO111MODULE=on go install github.com/google/go-jsonnet/cmd/jsonnet@v0.20.0

FROM aquasec/trivy as trivy

FROM golang:1.22.5-bookworm
RUN apt-get update && \
    apt-get install -qy \
    musl gnupg ragel \
    file zip unzip jq gettext\
    protobuf-compiler libprotobuf-dev \
    libsystemd-dev jq && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install dependencies to cross build Promtail to ARM and ARM64.
RUN dpkg --add-architecture armhf && \
    dpkg --add-architecture arm64 && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    pkg-config \
    gcc-aarch64-linux-gnu libc6-dev-arm64-cross libsystemd-dev:arm64 \
    gcc-arm-linux-gnueabihf libc6-dev-armhf-cross libsystemd-dev:armhf && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

COPY --from=docker /usr/bin/docker /usr/bin/docker
COPY --from=docker /usr/libexec/docker/cli-plugins/docker-buildx /usr/libexec/docker/cli-plugins/docker-buildx
COPY --from=helm /usr/local/bin/helm /usr/bin/helm
COPY --from=helm /usr/local/bin/helm-docs /usr/bin/helm-docs
COPY --from=lychee /usr/bin/lychee /usr/bin/lychee
COPY --from=golangci /bin/golangci-lint /usr/local/bin
COPY --from=buf /usr/bin/buf /usr/bin/buf
COPY --from=drone /usr/local/bin/drone /usr/bin/drone
COPY --from=faillint /go/bin/faillint /usr/bin/faillint
COPY --from=faillint /go/bin/goimports /usr/bin/goimports
COPY --from=delve /go/bin/dlv /usr/bin/dlv
COPY --from=ghr /go/bin/ghr /usr/bin/ghr
COPY --from=nfpm /go/bin/nfpm /usr/bin/nfpm
COPY --from=gotestsum /go/bin/gotestsum /usr/bin/gotestsum
COPY --from=jsonnet /go/bin/jb /usr/bin/jb
COPY --from=jsonnet /go/bin/mixtool /usr/bin/mixtool
COPY --from=jsonnet /go/bin/jsonnet /usr/bin/jsonnet
COPY --from=trivy /usr/local/bin/trivy /usr/bin/trivy

RUN GO111MODULE=on go install github.com/golang/protobuf/protoc-gen-go@v1.3.1
RUN GO111MODULE=on go install github.com/gogo/protobuf/protoc-gen-gogoslick@v1.3.0
RUN GO111MODULE=on go install golang.org/x/tools/cmd/goyacc@58d531046acdc757f177387bc1725bfa79895d69
RUN GO111MODULE=on go install github.com/mitchellh/gox@9f71238 && rm -rf /go/pkg /go/src
ENV GOCACHE=/go/cache
ENV GOTEST="gotestsum --format testname --"

COPY build.sh /
RUN chmod +x /build.sh
ENTRYPOINT ["/build.sh"]
