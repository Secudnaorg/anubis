# Self-contained multi-stage build for Anubis (GottaPhish fork).
#
# Upstream builds the image with `ko` + `make assets`; that asset step embeds
# generated web/wasm/css into the Go binary via go:embed and needs Go + Node +
# Rust (wasm32). This Dockerfile reproduces it so the plain `podman build .`
# JTE pipeline can build the fork. wasm-opt / wasm2js use the repo's pure-Go
# wazero fallback, so no wasmtime/binaryen is required.

# ---- Builder: Go + Node + Rust(wasm32) ----------------------------------
FROM golang:1.26-bookworm AS build

ENV GOTOOLCHAIN=auto \
    PATH=/root/.cargo/bin:/usr/local/go/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# bash/git for the asset scripts, Node 22 for `npm ci` (esbuild/postcss),
# Rust (stable) + the wasm32 target for the wasm crates.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        bash git ca-certificates curl xz-utils build-essential zstd; \
    curl -fsSL https://deb.nodesource.com/setup_22.x | bash -; \
    apt-get install -y --no-install-recommends nodejs; \
    curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile minimal --default-toolchain stable; \
    rustup target add wasm32-unknown-unknown; \
    rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . .

ARG GIT_COMMIT=dev

# `make assets` runs: npm ci + go mod download (deps), go generate (templ),
# cargo wasm build, esbuild (web), postcss (xess). Then build the anubis binary
# (static) with the generated assets embedded.
RUN make assets
RUN CGO_ENABLED=0 go build \
        -ldflags "-s -w -extldflags '-static' -X 'github.com/TecharoHQ/anubis.Version=${GIT_COMMIT}'" \
        -o /out/anubis ./cmd/anubis

# ---- Runtime: distroless static (same base family as the upstream ko image) --
FROM cgr.dev/chainguard/static:latest
COPY --from=build /out/anubis /usr/bin/anubis
EXPOSE 8923 9090
ENTRYPOINT ["/usr/bin/anubis"]
