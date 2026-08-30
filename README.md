# Home Server uCore
[![Build signed Home Server uCore images](https://github.com/iegorch86/home-server-ucore/actions/workflows/build.yml/badge.svg)](https://github.com/iegorch86/home-server-ucore/actions/workflows/build.yml)

A small downstream [Universal Blue uCore](https://github.com/ublue-os/ucore) image with a few practical tools for home-server administration.

> [!IMPORTANT]
> This is **not a fork of Fedora CoreOS or uCore**, and it is not a separate Linux distribution.
>
> The kernel, Fedora CoreOS base, bootc/rpm-ostree stack, storage stack, virtualization stack, container stack, drivers and core uCore functionality remain upstream.

The project exists because I wanted a few small utilities available natively on my own uCore home server and decided to make the resulting image available for anybody who finds the same combination useful.

```text
Fedora CoreOS
      |
Universal Blue uCore
      |
Home Server uCore
      |
small host-admin tool layer
```

## What is added

| Tool | Purpose |
|---|---|
| NUT | Native UPS monitoring and shutdown integration |
| UPSide | Cockpit interface for NUT |
| PowerTOP | Power diagnostics |
| NetBird | Alternative to Tailscale  mesh-VPN client |
| Micro | Friendly terminal text editor |
| Superfile | Terminal file manager ('spf'- to start it) |
| btop | System/resource monitoring |
| fastfetch | Quick system information |
| VirtUI Manager | Terminal libvirt/QEMU virtual machine manager — uCore HCI only |

The custom host-side software layer is declared in
[`build_files/software.env`](build_files/software.env).

That file is the first place to look if you want to see, add, remove, or
change software included by this project.
Some software is image-specific. Entries marked **HCI only** are built only
into `home-server-ucore-hci` and are not included in the regular uCore image.

Normal Fedora packages are installed from the Fedora/uCore package sources.
External projects such as UPSide and Superfile are pinned to both a release
version and an exact upstream commit and are monitored for updates by Renovate.

Everything else remains as close as possible to upstream uCore.

## Images

uCore image:

```text
ghcr.io/iegorch86/home-server-ucore:lts
```

Based on:

```text
ghcr.io/ublue-os/ucore:lts
```

uCore HCI image:

```text
ghcr.io/iegorch86/home-server-ucore-hci:lts
```

Based on:

```text
ghcr.io/ublue-os/ucore-hci:lts
```

## Kernel scope

This project does not maintain or select its own kernel.

LTS images includes kernel published by the upstream uCore LTS.

Kernel regressions and kernel issues belong upstream.

## UPS support

The primary reason this project exists is to make native UPS integration easier on an immutable uCore server.

The image includes:

```text
nut
nut-client
UPSide
```

Nothing hardware-specific is baked in:

```text
UPS model
USB VID/PID
serial number
ups.conf
upsd.conf
upsd.users
UPS passwords
shutdown thresholds
battery thresholds
```

Those settings belong to the individual server. A system with no UPS should work normally.

## UPSide

[UPSide](https://github.com/deviationist/cockpit-upside) is installed as a system-wide Cockpit extension and uses NUT as its backend.

UPSide is compiled in a separate build stage so Node.js, npm and its other build dependencies do not remain in the final operating-system image.

[UPSide Config and troubleshooting](/docs/nut-upside-coreos-troubleshooting.md)

## PowerTOP

PowerTOP is included for diagnostics.

```bash
sudo powertop
```

This image intentionally does **not** enable:

```bash
powertop --auto-tune
```

If you want PowerTOP tuning on your own server, configure it locally.

## NetBird

uCore already includes Tailscale.

This image additionally provides the native [NetBird](https://github.com/netbirdio/netbird) client for users who prefer NetBird to operate their own NetBird infrastructure.

The image does not contain a NetBird account, setup key or management-server configuration.

NetBird is installed but deliberately left disabled/unconfigured.

## What belongs in this image?

Small host-side administration, diagnostic or hardware-management utilities.

Examples:

```text
small CLI diagnostics
network administration tools
hardware monitoring tools
small storage/admin helpers
similar lightweight utilities
```

The goal is to keep the custom layer small.

## What does NOT belong here?

Large applications and services that work well as containers will not be baked into the operating-system image.

Examples:

```text
Jellyfin
Plex
Asterisk
databases
media automation stacks
download stacks
application servers
large monitoring platforms
```

Those applications belong in Podman/Docker containers.

This project is not intended to become an all-in-one home-server distribution.

## NVIDIA images

NVIDIA variants are not currently built because they are not needed for the systems this project is being developed and tested on.

If you need the same small toolset on an upstream uCore NVIDIA image, open a feature request, or create fork, corresponding build-matrix variant can be added later.

## Installation

For an existing compatible bootc/uCore installation:

```bash
sudo bootc switch \
    ghcr.io/iegorch86/home-server-ucore:lts
```

Then reboot.

## Updates

Scheduled GitHub Actions runs inspect the exact upstream digest.

If upstream did not change, no scheduled rebuild is made.

If upstream changed:

```text
build
rechunk
publish
sign
verify
```

Normal repository changes and manual runs still build.

## Image signing

Published images are signed with Cosign.

The workflow signs the exact digest read back from GHCR after upload and verifies the resulting signature.

## Issue policy

Open an issue here when the problem is caused by something this repository adds.

Examples:

- NUT failed to install in this custom image
- UPSide is missing or packaged incorrectly
- NetBird integration is broken
- one of the added utilities is missing
- the custom GitHub Actions workflow failed
- image signing/verification maintained by this repository is broken

If the same problem happens on plain upstream uCore, it does not belong to this repository.

Examples:

- kernel regressions
- memory leaks
- hardware drivers
- Fedora CoreOS problems
- bootc problems
- rpm-ostree problems
- ZFS
- Podman
- Cockpit itself
- libvirt/KVM
- uCore base services

Report those to the project that actually maintains the component.

### Upstream issue trackers

- [Universal Blue uCore](https://github.com/ublue-os/ucore/issues)
- [Fedora CoreOS](https://github.com/coreos/fedora-coreos-tracker/issues)
- [bootc](https://github.com/bootc-dev/bootc/issues)
- [Cockpit](https://github.com/cockpit-project/cockpit/issues)
- [Network UPS Tools](https://github.com/networkupstools/nut/issues)
- [UPSide](https://github.com/deviationist/cockpit-upside/issues)
- [NetBird](https://github.com/netbirdio/netbird/issues)
- [Micro](https://github.com/micro-editor/micro/issues)
- [SuperFile](https://github.com/yorukot/superfile/issues)
- [VirtUI-Manager](https://github.com/aginies/virtui-manager/issues)

## Feature requests

Small feature requests are welcome.

If it is a small host-administration utility that makes sense directly on a server OS, it can be considered.

If it is an application/service that naturally belongs in a container, it will normally stay out of this image.

## Architectures

Currently supported:

```text
x86_64 / amd64
```

ARM64 is intentionally not published because it is not currently tested here.

## Upstream

This project depends on:

- [Fedora CoreOS](https://fedoraproject.org/coreos/)
- [Universal Blue uCore](https://github.com/ublue-os/ucore)
- [Universal Blue image-template](https://github.com/ublue-os/image-template)
- [Network UPS Tools](https://github.com/networkupstools/nut)
- [UPSide](https://github.com/deviationist/cockpit-upside)
- [NetBird](https://github.com/netbirdio/netbird)
- [Micro](https://github.com/micro-editor/MICRO)
- [SuperFile](https://github.com/yorukot/superfile)
- [VirtUI-Manager](https://github.com/aginies/virtui-manager)

The operating-system engineering belongs upstream.

This repository intentionally remains only a thin home-server convenience layer.
