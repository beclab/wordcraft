# syntax=docker/dockerfile:1
# Olares web image: the trunk build of apps/wordcraft-web served by nginx on :8080.
# With ./craft-fonts checked out, the wasm embeds its UI face and the Simplified Chinese face is
# served beside it for apps/wordcraft-web to fetch when the interface is Chinese.
# Build from the repository root: docker build -f packaging/olares/web.Dockerfile .
ARG RUST_VERSION=1.99
ARG NGINX_VERSION=1.28-alpine

# The wasm output is architecture-independent, so multi-arch builds compile it once natively.
FROM --platform=$BUILDPLATFORM rust:${RUST_VERSION}-slim-bookworm AS builder
# Must match the `trunk-version` default of storytold/craft-common-actions' release workflow.
ARG TRUNK_VERSION=0.21.14
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && rustup target add wasm32-unknown-unknown
RUN set -eu; \
    case "$(uname -m)" in \
        x86_64) arch=x86_64 ;; \
        aarch64) arch=aarch64 ;; \
        *) echo 'The web builder supports amd64 and arm64' >&2; exit 1 ;; \
    esac; \
    asset="trunk-${arch}-unknown-linux-musl.tar.gz"; \
    url="https://github.com/trunk-rs/trunk/releases/download/v${TRUNK_VERSION}"; \
    cd /tmp; \
    curl -fsSL --retry 3 -A Wordcraft-dev "$url/$asset" -o "$asset"; \
    curl -fsSL --retry 3 -A Wordcraft-dev "$url/$asset.sha256" -o "$asset.sha256"; \
    printf '%s  %s\n' "$(cat "$asset.sha256")" "$asset" | sha256sum -c -; \
    tar -xzf "$asset" -C /usr/local/bin trunk; \
    rm "$asset" "$asset.sha256"; \
    trunk --version

WORKDIR /src
COPY . .
WORKDIR /src/apps/wordcraft-web
ARG CARGO_BUILD_JOBS=4
ARG WORDCRAFT_BUILD_SHA=
ARG WORDCRAFT_BUILD_DATE=
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/src/target \
    --mount=type=cache,target=/root/.cache/trunk \
    if [ -f /src/craft-fonts/fonts/manifest.txt ]; then \
        export CRAFT_FONTS_DIR=/src/craft-fonts CRAFT_FONTS_REQUIRED=1; \
    fi \
    && trunk build --release --locked \
    && test -s /src/dist/web/index.html \
    && if [ -f /src/craft-fonts/fonts/noto-sans-cjk-sc/NotoSansCJKsc-Regular.otf ]; then \
        mkdir -p /src/dist/web/fonts/noto-sans-cjk-sc \
        && cp /src/craft-fonts/fonts/noto-sans-cjk-sc/NotoSansCJKsc-Regular.otf /src/craft-fonts/fonts/noto-sans-cjk-sc/OFL.txt /src/dist/web/fonts/noto-sans-cjk-sc/ \
        && gzip -9 -k /src/dist/web/fonts/noto-sans-cjk-sc/NotoSansCJKsc-Regular.otf; \
    fi \
    && gzip -9 -k /src/dist/web/*.wasm /src/dist/web/*.js /src/dist/web/index.html

FROM nginx:${NGINX_VERSION} AS runtime
COPY packaging/olares/nginx.conf /etc/nginx/nginx.conf
COPY --from=builder /src/dist/web/ /usr/share/nginx/html/
COPY README.md LICENSE-MIT LICENSE-APACHE NOTICE ATTRIBUTION.md /usr/share/nginx/html/
COPY assets/fonts/OFL-*.txt /usr/share/nginx/html/licenses/
# Bypass the stock entrypoint: this configuration needs no runtime rewriting.
USER nginx
EXPOSE 8080
ENTRYPOINT []
CMD ["nginx", "-g", "daemon off;"]
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
