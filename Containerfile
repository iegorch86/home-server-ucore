# Exact upstream digest is supplied by GitHub Actions.
# This moving tag is only the local-build fallback.
ARG UCORE_IMAGE=ghcr.io/ublue-os/ucore:lts

# UPSide stays reproducibly pinned to an exact release commit.
# Renovate tracks the release tag + matching commit and raises a PR for updates.
# renovate: datasource=github-tags packageName=deviationist/cockpit-upside versioning=semver
ARG UPSIDE_VERSION=1.0.6
ARG UPSIDE_COMMIT=0761c8cc5aa566feec05d722c220ecd5f40bb9a3

FROM scratch AS ctx
COPY build_files /
COPY system_files /system_files
COPY cosign.pub /cosign.pub

# Build UPSide separately so Node.js/npm/git/build dependencies never remain
# in the final uCore image.
FROM registry.fedoraproject.org/fedora:44 AS upside-builder
ARG UPSIDE_VERSION
ARG UPSIDE_COMMIT

RUN dnf install -y \
        git \
        make \
        nodejs \
        npm \
        tar \
    && git clone https://github.com/deviationist/cockpit-upside.git /src/upside \
    && cd /src/upside \
    && test "$(git rev-parse "refs/tags/${UPSIDE_VERSION}^{commit}")" = "${UPSIDE_COMMIT}" \
    && git checkout --detach "${UPSIDE_COMMIT}" \
    && make \
    && mkdir -p /out/usr/share/cockpit/upside \
    && cp -a dist/. /out/usr/share/cockpit/upside/ \
    && test -f /out/usr/share/cockpit/upside/manifest.json \
    && dnf clean all


# Final uCore image.
FROM ${UCORE_IMAGE}

COPY --from=upside-builder \
    /out/usr/share/cockpit/upside/ \
    /usr/share/cockpit/upside/

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build.sh

RUN bootc container lint
