# GitHub Actions supplies the selected upstream image through the build matrix.
# These values are the normal local-build defaults.
ARG UCORE_IMAGE=ghcr.io/ublue-os/ucore:lts
ARG IMAGE_REPOSITORY=ghcr.io/iegorch86/home-server-ucore-lts


FROM scratch AS ctx

COPY build_files /
COPY system_files /system_files
COPY cosign.pub /cosign.pub


# ============================================================
# UPSide builder
# ============================================================
#
# Build UPSide separately so Node.js/npm/git/build dependencies
# never remain in the final uCore image.

FROM registry.fedoraproject.org/fedora:44 AS upside-builder

COPY build_files/software.env /tmp/software.env

RUN dnf install -y \
        git \
        make \
        nodejs \
        npm \
        tar \
    && . /tmp/software.env \
    && git clone https://github.com/deviationist/cockpit-upside.git /src/upside \
    && cd /src/upside \
    && test "$(git rev-parse "refs/tags/${UPSIDE_VERSION}^{commit}")" = "${UPSIDE_COMMIT}" \
    && git checkout --detach "${UPSIDE_COMMIT}" \
    && make \
    && mkdir -p /out/usr/share/cockpit/upside \
    && cp -a dist/. /out/usr/share/cockpit/upside/ \
    && test -f /out/usr/share/cockpit/upside/manifest.json \
    && dnf clean all


# ============================================================
# Superfile builder
# ============================================================
#
# Build Superfile separately so Go/git/build dependencies
# never remain in the final uCore image.

FROM registry.fedoraproject.org/fedora:44 AS superfile-builder

COPY build_files/software.env /tmp/software.env

RUN dnf install -y \
        git \
        golang \
    && . /tmp/software.env \
    && git clone https://github.com/yorukot/superfile.git /src/superfile \
    && cd /src/superfile \
    && test "$(git rev-parse "refs/tags/v${SUPERFILE_VERSION}^{commit}")" = "${SUPERFILE_COMMIT}" \
    && git checkout --detach "${SUPERFILE_COMMIT}" \
    && bash ./build.sh \
    && install -Dm0755 ./bin/spf /out/usr/bin/spf \
    && install -Dm0644 ./LICENSE /out/usr/share/licenses/superfile/LICENSE \
    && dnf clean all


# ============================================================
# Final uCore / uCore HCI image
# ============================================================

FROM ${UCORE_IMAGE}

ARG IMAGE_REPOSITORY


# UPSide Cockpit extension
COPY --from=upside-builder \
    /out/usr/share/cockpit/upside/ \
    /usr/share/cockpit/upside/


# Superfile binary + license
COPY --from=superfile-builder \
    /out/usr/bin/spf \
    /usr/bin/spf

COPY --from=superfile-builder \
    /out/usr/share/licenses/superfile/ \
    /usr/share/licenses/superfile/


RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache \
    --mount=type=cache,dst=/var/log \
    --mount=type=tmpfs,dst=/tmp \
    IMAGE_REPOSITORY="${IMAGE_REPOSITORY}" \
    /ctx/build.sh


RUN bootc container lint
