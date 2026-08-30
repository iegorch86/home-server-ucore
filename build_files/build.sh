#!/usr/bin/bash

set -ouex pipefail

# The build must tell this image which GHCR repository it belongs to.
: "${IMAGE_REPOSITORY:?IMAGE_REPOSITORY must be set by the image build}"

# Load the human-readable custom software declaration.
source /ctx/software.env

: "${UCORE_EXTRA_PACKAGES:?UCORE_EXTRA_PACKAGES must be set in software.env}"
: "${NETBIRD_PACKAGE:?NETBIRD_PACKAGE must be set in software.env}"


# Copy declarative system files into the image.
cp -avf /ctx/system_files/. /


# jq is needed by install-image-trust.sh.
dnf5 install -y jq


# Trust the exact custom-image repository currently being built.
/ctx/install-image-trust.sh "${IMAGE_REPOSITORY}"


# ============================================================
# Native Fedora host tools
# ============================================================

read -r -a extra_packages <<< "${UCORE_EXTRA_PACKAGES}"

dnf5 install -y "${extra_packages[@]}"


# ============================================================
# NetBird
# ============================================================
#
# NetBird's RPM %post tries to install and start its systemd
# service. That is appropriate on a running host but not while
# composing a bootc image.
#
# Install the RPM payload without package scriptlets.
# Runtime configuration and service activation remain an
# explicit host-side action.

dnf5 --setopt=tsflags=noscripts install -y "${NETBIRD_PACKAGE}"

# The generic image must not connect or auto-enable NetBird.
systemctl disable netbird.service 2>/dev/null || true


# ============================================================
# Build-time validation
# ============================================================

command -v upsc
command -v nut-scanner
command -v powertop
command -v btop
command -v fastfetch
command -v micro
command -v netbird
command -v spf

test -f /usr/share/cockpit/upside/manifest.json
test -f /usr/share/licenses/superfile/LICENSE


# Deliberately NOT done here:
#
# - enable/configure NUT
# - add UPS credentials/hardware-specific settings
# - configure/connect NetBird
# - install/start the NetBird service
# - run powertop --auto-tune


dnf5 clean all
