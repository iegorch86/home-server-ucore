#!/usr/bin/bash

set -ouex pipefail

# Copy declarative system files into the image.
cp -avf /ctx/system_files/. /

# jq is needed by install-image-trust.sh.
dnf5 install -y jq

# Trust both planned custom-image repositories.
/ctx/install-image-trust.sh \
    "ghcr.io/iegorch86/home-server-ucore" \
    "ghcr.io/iegorch86/home-server-ucore-hci"

# Small host-side administration/tooling layer.
dnf5 install -y \
    nut \
    nut-client \
    powertop \
    btop \
    fastfetch

# NetBird client from its official RPM repository.
dnf5 install -y netbird

# The generic image must not connect or auto-enable NetBird.
systemctl disable netbird.service 2>/dev/null || true

# Build-time validation.
command -v upsc
command -v nut-scanner
command -v powertop
command -v btop
command -v htop
command -v fastfetch
command -v netbird

test -f /usr/share/cockpit/upside/manifest.json

# Deliberately NOT done here:
# - enable/configure NUT
# - add UPS credentials/hardware-specific settings
# - configure/connect NetBird
# - run powertop --auto-tune

dnf5 clean all
