# syntax=docker/dockerfile:1
# Olares agent image: wordcraft-cli's headless stdio MCP server behind supergateway (Streamable HTTP).
# Build from the repository root: docker build -f packaging/olares/agent.Dockerfile .
ARG RUST_VERSION=1.99
ARG NODE_VERSION=22-bookworm-slim

FROM rust:${RUST_VERSION}-slim-bookworm AS builder
WORKDIR /src
COPY . .
ARG CARGO_BUILD_JOBS=4
ARG WORDCRAFT_BUILD_SHA=
ARG WORDCRAFT_BUILD_DATE=
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/src/target \
    if [ -f /src/craft-fonts/fonts/manifest.txt ]; then \
        export CRAFT_FONTS_DIR=/src/craft-fonts CRAFT_FONTS_REQUIRED=1; \
    fi \
    && cargo build --release --locked -p wordcraft-cli \
    && install -m 0755 target/release/wordcraft-cli /usr/local/bin/wordcraft-cli

FROM node:${NODE_VERSION} AS runtime
ARG SUPERGATEWAY_VERSION=4.1.0
RUN npm install -g --omit=dev "supergateway@${SUPERGATEWAY_VERSION}" \
    && npm cache clean --force \
    && apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && install -d -o 1000 -g 1000 /data/files
COPY --from=builder /usr/local/bin/wordcraft-cli /usr/local/bin/wordcraft-cli
COPY LICENSE-MIT LICENSE-APACHE NOTICE ATTRIBUTION.md /usr/share/doc/wordcraft/
ENV HOME=/tmp \
    CRAFT_FILES=/data/files \
    MCP_PORT=8090
USER 1000:1000
WORKDIR /data/files
EXPOSE 8090
CMD ["sh", "-c", "exec supergateway --stdio \"wordcraft-cli mcp --automation-read-root $CRAFT_FILES --automation-write-root $CRAFT_FILES\" --outputTransport streamableHttp --stateful --sessionTimeout 1800000 --port $MCP_PORT --healthEndpoint /healthz"]
