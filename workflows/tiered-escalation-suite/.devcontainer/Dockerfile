# syntax=docker/dockerfile:1
# Bakes the toolchain scripts/install-prereqs.sh installs on a host (rg, fd, ast-grep,
# jq, tokei, comby, ajv-cli) into a devcontainer image, so opening the deployed target
# repo in a devcontainer gives Surveyor/Transformer/Verifier a ready toolchain with no
# manual installer step. Build context must be the repo root (see ../devcontainer.json)
# so the COPY below can reach scripts/.
#
# To find available Node tags: https://mcr.microsoft.com/en-us/product/devcontainers/javascript-node/tags
# --platform=linux/amd64 pinned: install-prereqs.sh's comby install fetches an
# x86_64-linux-only tarball (no arm64 asset), so building natively for arm64 (e.g. on
# Apple Silicon) would ship a comby binary that can't execute.
FROM --platform=linux/amd64 mcr.microsoft.com/devcontainers/javascript-node:24-bookworm

ARG INSTALL_JAVA=false
ARG INSTALL_WEB=false
ARG DEBIAN_FRONTEND=noninteractive

USER node
ENV PATH="/home/node/.cargo/bin:${PATH}"
ENV CARGO_TARGET_DIR=/home/node/.cargo-target

# install-prereqs.sh's apt branch only gets tokei via `cargo install` or snap; snap
# doesn't run in containers, and Debian bookworm's apt `cargo` (1.63) is too old to
# resolve tokei's dependencies, so bootstrap a current toolchain via rustup instead.
# Kept ahead of the COPY below so editing install-prereqs.sh doesn't bust this layer.
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal

COPY scripts/install-prereqs.sh scripts/preflight.sh /tmp/prereqs/

# Cache mounts: `cargo install tokei` compiles a sizeable dependency tree (worse under
# QEMU emulation on a non-amd64 host); caching the crate registry and build artifacts
# across image rebuilds avoids repeating that whenever this Dockerfile changes.
RUN --mount=type=cache,target=/home/node/.cargo/registry,uid=1000,gid=1000 \
    --mount=type=cache,target=/home/node/.cargo-target,uid=1000,gid=1000 \
    flags=""; \
    [ "$INSTALL_JAVA" = "true" ] && flags="$flags --java"; \
    [ "$INSTALL_WEB" = "true" ] && flags="$flags --web"; \
    bash /tmp/prereqs/install-prereqs.sh $flags
