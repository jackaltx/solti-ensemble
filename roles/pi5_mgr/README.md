# pi5_mgr — Raspberry Pi 5 Base Configuration

Ansible role for declarative Raspberry Pi 5 fleet management. Handles OS updates, Hailo AI HAT+ driver installation, and automated security updates. Designed to reproduce a known-good Pi 5 configuration from a fresh install.

## Features

- OS update (`apt update + full upgrade`) on every apply
- Hailo AI HAT+ detection and driver installation (`hailo-all`)
- Automatic reboot when driver is installed or removed
- `unattended-upgrades` configuration (security patches only, Hailo packages pinned to manual)
- Declarative `detect | present | absent` control per host via inventory
- Inference benchmark smoke test (`verify_hailo`)
- Chip temperature and throttling monitoring (`verify_hailo_temp`)

## Requirements

- Debian Bookworm or Trixie (Raspberry Pi OS)
- `archive.raspberrypi.com/debian` apt repo already configured (default on Raspberry Pi OS)
- SSH key access + sudo on target host

## Role Variables

```yaml
# State — maps to manage-svc.sh actions
# present   → OS update + Hailo management
# configure → present + configure unattended-upgrades
# absent    → remove hailo-all packages
pi5_mgr_state: present

# Hailo AI HAT control
# detect  → run lspci, install hailo-all if Hailo hardware found
# present → install hailo-all unconditionally
# absent  → remove hailo-all unconditionally
pi5_hailo: detect

# Run apt update + full upgrade on every apply
pi5_os_update: true

# Configure unattended-upgrades (only when pi5_mgr_state == "configure")
pi5_unattended_upgrades: true
pi5_unattended_upgrades_origins:
  - "origin=Debian,codename=${distro_codename}"
  - "origin=Raspbian,codename=${distro_codename}"
  - "origin=Raspberry Pi Foundation,codename=${distro_codename}"
pi5_unattended_upgrades_reboot: false
pi5_unattended_upgrades_reboot_time: "02:00"
```

## Inventory Setup

```yaml
pi5:
  vars:
    pi5_mgr_state: present
    pi5_hailo: detect       # auto-detect by default
    pi5_os_update: true

  hosts:
    thunker:
      ansible_host: thunker.a0a0.org
      pi5_hailo: present    # known Hailo hardware, skip detection

    somepi:
      ansible_host: somepi.a0a0.org
      # pi5_hailo: detect   (inherited from group default)

    nopi:
      ansible_host: nopi.a0a0.org
      pi5_hailo: absent     # explicitly no Hailo
```

## Usage via manage-svc.sh / svc-exec.sh

Thunker has NOPASSWD sudo — no `--become-password-file` needed. Add it for hosts that require a password.

```bash
# Deploy to a single host (OS update + Hailo)
./manage-svc.sh -h thunker pi5_mgr deploy

# Deploy to entire pi5 group
./manage-svc.sh -h pi5 pi5_mgr deploy

# Deploy + configure unattended-upgrades
./manage-svc.sh -h thunker pi5_mgr configure

# Remove Hailo packages
./manage-svc.sh -h thunker pi5_mgr remove

# Quick health check
./svc-exec.sh -h thunker pi5_mgr verify

# Extended diagnostics (firmware version, dmesg, lspci)
./svc-exec.sh -h thunker pi5_mgr verify1

# Inference benchmark (~30s, confirms chip is executing)
./svc-exec.sh -h thunker pi5_mgr verify_hailo

# Chip temperature and throttling state
./svc-exec.sh -h thunker pi5_mgr verify_hailo_temp
```

## Task Entry Points (svc-exec.sh)

| Entry | Purpose | Assert |
|-------|---------|--------|
| `verify` | `/dev/hailo0` present, kernel module loaded, package installed | yes — fails if package installed but device absent |
| `verify1` | Firmware version, dmesg, lspci, unattended-upgrades status | no — diagnostics dump only |
| `verify_hailo` | Inference benchmark using YOLOX-S model (~30s) | yes — fails if benchmark exits non-zero |
| `verify_hailo_temp` | Chip temperature (TS0/TS1) and throttling state | yes — fails if avg temp ≥ 90°C |

## Hailo Detection Logic

When `pi5_hailo: detect`, the role runs `lspci` and checks for `Hailo` in the output. If found, `hailo-all` is installed. If not found, `hailo-all` is removed (if present).

PCIe must be enabled in `/boot/firmware/config.txt` for the device to appear in `lspci`. On Pi 5 with Hailo HAT+:
```
dtparam=pciex1_gen=3
```

After driver installation the host reboots automatically. The `/dev/hailo0` device and `hailo_pci` kernel module appear after reboot.

## Hailo Thermals

The Hailo-8L chip exposes two internal temperature sensors (TS0, TS1) via the `hailo_platform` Python API. The chip also reports whether hardware throttling is active.

**Without a heatsink:** 70–75°C at idle, throttling active. This degrades inference performance under sustained load.

**With a heatsink:** expect 45–55°C at idle, throttling inactive.

Safe operating range: below 85°C sustained. Hard limit: 90°C (role asserts this).

```bash
# Check before and after fitting heatsink
./svc-exec.sh -h thunker pi5_mgr verify_hailo_temp
```

Expected output after heatsink:
```
TS0: ~50°C  TS1: ~51°C  Throttling: False  Status: OK
```

## Inference Benchmark Baseline (Hailo-8L, thunker)

Model: `yolox_s_leaky_h8l_rpi.hef` (Pi-optimised YOLOX-S, installed with `hailo-models`)

| Metric | Value |
|--------|-------|
| FPS (hw_only) | ~33.5 |
| FPS (streaming) | ~33.5 |
| HW latency | ~27.9 ms |

FPS dropping significantly below 33 under repeated runs indicates thermal throttling — fit a heatsink.

## Extending for Future Apps

```bash
# Apply base config first, then app role
./manage-svc.sh -h thunker pi5_mgr deploy
./manage-svc.sh -h thunker home_assistant deploy
```

Create app roles as separate roles in `solti-ensemble/roles/` — do not add application logic to `pi5_mgr`.

## Verification Expected Output

After a successful deploy with Hailo hardware and heatsink:

```
/dev/hailo0              → present
hailo_pci kernel module  → loaded
hailo-all package        → install ok installed
Firmware Version         → 4.23.0 (release)
Benchmark FPS            → ~33.5
Chip temperature         → ~50°C avg, Throttling: False
```
