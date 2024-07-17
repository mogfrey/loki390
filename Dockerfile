# This is the Dockerfile for the Loki build image that is used by the CI pipelines.

# Use a multi-stage build to compile necessary tools for s390x architecture
FROM golang:1.22.5-bookworm as builder
ARG TARGETARCH=s390x
ARG TARGETOS=linux
ARG HELM_VER="v3.2.3"
ARG HELM_DOCS_VER="1.11.2"

# Install dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    curl \
    build-essential \
    git \
    unzip

# Build Helm from source
RUN git clone --branch v${HELM_VER} https://github.com/helm/helm.git /helm && \
    cd /helm && \
    make

# Build Helm-docs from source
RUN git clone --branch v${HELM_DOCS_VER} https://github.com/norwoodj/helm-docs.git /helm-docs && \
    cd /helm-docs && \
    make

# Download and build other tools from source
RUN GO111MODULE=on go install github.com/fatih/faillint@v1.12.0
RUN GO111MODULE=on go install golang.org/x/tools/cmd/goimports@v0.7.0
RUN GO111MODULE=on go install github.com/go-delve/delve/cmd/dlv@latest
RUN GO111MODULE=on go install github.com/tcnksm/ghr@9349474
RUN GO111MODULE=on go install github.com/goreleaser/nfpm/v2/cmd/nfpm@v2.11.3
RUN GO111MODULE=on go install gotest.tools/gotestsum@v1.8.2
RUN GO111MODULE=on go install github.com/jsonnet-bundler/jsonnet-bundler/cmd/jb@v0.5.1
RUN GO111MODULE=on go install github.com/monitoring-mixins/mixtool/cmd/mixtool@16dc166166d91e93475b86b9355a4faed2400c18
RUN GO111MODULE=on go install github.com/google/go-jsonnet/cmd/jsonnet@v0.20.0
RUN GO111MODULE=on go install github.com/golang/protobuf/protoc-gen-go@v1.3.1
RUN GO111MODULE=on go install github.com/gogo/protobuf/protoc-gen-gogoslick@v1.3.0
RUN GO111MODULE=on go install golang.org/x/tools/cmd/goyacc@58d531046acdc757f177387bc1725bfa79895d69
RUN GO111MODULE=on go install github.com/mitchellh/gox@9f71238

# Final image
FROM golang:1.22.5-bookworm
COPY --from=builder /go/bin /go/bin
COPY --from=builder /helm/bin/helm /usr/local/bin/helm
COPY --from=builder /helm-docs/bin/helm-docs /usr/local/bin/helm-docs

RUN apt-get update && \
    apt-get install -qy \
    musl gnupg ragel \
    file zip unzip jq gettext \
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

# Copy tools from builder stage
COPY --from=builder /usr/local/bin/helm /usr/bin/helm
COPY --from=builder /usr/local/bin/helm-docs /usr/bin/helm-docs

COPY build.sh /
RUN chmod +x /build.sh
ENTRYPOINT ["/build.sh"]
