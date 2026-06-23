# CLAUDE.md — pi5_mgr Role

## What This Role Does

Manages Raspberry Pi 5 base configuration: OS updates, Hailo AI HAT+ driver, and unattended-upgrades. Designed as a foundation layer — future Pi 5 app roles (home-assistant, openclaw) build on top of this.

## Key Design Decisions

### State Variable: `pi5_mgr_state` (not `pi5_state`)
The state var is `pi5_mgr_state` to match the `manage-svc.sh` convention of `{role_name}_state`. Roles with hyphens (e.g. `nfs-client`) break this — `pi5_mgr` uses underscores deliberately.

States:
- `present` — OS update + Hailo management
- `configure` — present + write unattended-upgrades config
- `absent` — remove hailo-all packages (OS untouched)

### Hailo: `pi5_hailo: detect | present | absent`
- `detect` is the default — runs `lspci`, installs if Hailo hardware found
- Override with `present` in host_vars for known hardware (skips detection)
- Override with `absent` to explicitly exclude Hailo even if hardware exists
- The reboot handler fires whenever hailo-all is installed or removed

### verify tasks are self-contained
`verify.yml` derives `hailo_present` from the package database (`dpkg-query`), not from a fact set during a prior deploy run. This means it works correctly standalone via `svc-exec.sh` without needing a prior role apply.

### Unattended-upgrades pins Hailo packages
`hailo-all`, `hailort`, `hailort-pcie-driver` are blacklisted in `50unattended-upgrades.j2`. Hailo upgrades must go through Ansible to avoid uncontrolled reboots from a kernel module change.

### Temperature via Python API, not hailortcli
`hailortcli measure-power` returns `HAILO_UNSUPPORTED_OPCODE` on the HAT+ M.2 board.
`hailortcli monitor` shows utilization/FPS but no temperature.
Temperature is read via `hailo_platform.VDevice().get_physical_devices()[0].control.get_chip_temperature()` which exposes `ts0_temperature` and `ts1_temperature` in °C, and `get_throttling_state()` which returns True/False.

## File Map

```
defaults/main.yml              — all vars with defaults
tasks/main.yml                 — state dispatcher
tasks/os_update.yml            — apt update + full upgrade
tasks/os_configure.yml         — unattended-upgrades install + config
tasks/hailo.yml                — lspci detect → install/remove hailo-all
tasks/verify.yml               — svc-exec: /dev/hailo0, module, package (self-contained)
tasks/verify1.yml              — svc-exec: firmware, dmesg, lspci, uu status (diagnostics)
tasks/verify_hailo.yml         — svc-exec: inference benchmark via hailortcli benchmark
tasks/verify_hailo_temp.yml    — svc-exec: chip temp (TS0/TS1) + throttling state
handlers/main.yml              — ansible.builtin.reboot (120s timeout)
templates/50unattended-upgrades.j2 — apt config template
```

## Inventory Pattern

Hosts live in the `pi5` group in `mylab/inventory.yml`. The group sets defaults; host_vars override per-host:

```yaml
pi5:
  vars:
    pi5_mgr_state: present
    pi5_hailo: detect
  hosts:
    thunker:
      pi5_hailo: present   # skip lspci, known hardware
```

`thunker` has NOPASSWD sudo — no `--become-password-file` needed.

## Usage Commands

```bash
# Standard deploy (no password needed on thunker)
./manage-svc.sh -h thunker pi5_mgr deploy

# Full setup including unattended-upgrades
./manage-svc.sh -h thunker pi5_mgr configure

# Verification suite
./svc-exec.sh -h thunker pi5_mgr verify             # pass/fail device check
./svc-exec.sh -h thunker pi5_mgr verify1            # diagnostics dump
./svc-exec.sh -h thunker pi5_mgr verify_hailo       # ~30s inference benchmark
./svc-exec.sh -h thunker pi5_mgr verify_hailo_temp  # chip temp + throttling
```

## When Adding a New Pi 5

1. Add host to `mylab/inventory.yml` under both `mylab.hosts` and `pi5.hosts`
2. Set `pi5_hailo: detect | present | absent` as appropriate
3. Run deploy: `./manage-svc.sh -h <newhost> pi5_mgr deploy`
4. If Hailo installed, host reboots automatically — wait for it
5. Run verify: `./svc-exec.sh -h <newhost> pi5_mgr verify`
6. If Hailo present: run `verify_hailo_temp` before sustained workloads to confirm thermals

## When Adding Future App Roles (home-assistant, openclaw)

- Create a **separate role** in `solti-ensemble/roles/` — do NOT add app logic to `pi5_mgr`
- `pi5_mgr` is base-only: OS + driver layer
- App roles declare their own state var (`home_assistant_state`, etc.)
- Apply order: `pi5_mgr` deploy → app role deploy

## Hailo Packages

`hailo-all` (v5.1.1 on Trixie) pulls in:
- `hailort` — runtime library
- `hailort-pcie-driver` — PCIe kernel module + firmware
- `hailo-models` — AI model examples including `yolox_s_leaky_h8l_rpi.hef`
- `hailo-tappas-core` — inference pipeline framework
- `python3-hailort` — Python bindings (provides `hailo_platform` module)

## Hailo Thermals — Important

The Hailo-8L runs **70–75°C at idle without a heatsink**, with throttling already active.
This was confirmed on thunker using `verify_hailo_temp` before a heatsink was fitted.

Temperature thresholds used in `verify_hailo_temp.yml`:
- Warn: throttling == True (any temp)
- Fail: avg temp ≥ 90°C

After fitting a heatsink, expect ~50°C idle and throttling == False.
Re-run `verify_hailo_temp` after fitting to confirm.

Benchmark baseline (no throttling, with heatsink) — `yolox_s_leaky_h8l_rpi.hef`:
- FPS: ~33.5 (hw_only and streaming)
- HW latency: ~27.9 ms

If benchmark FPS drops significantly below 33.5 on repeated runs, thermals are the likely cause.

## Known Hardware (thunker)

```
Device:      Hailo-8L (HAILO8L architecture)
Serial:      HLDDLBB243201694
PCIe addr:   0001:04:00.0
FW:          4.23.0 (release,app,extended context switch buffer)
OS:          Debian Trixie, kernel 6.12.62+rpt
NVMe:        931.5GB via PCIe (dtparam=pciex1_gen=3 in config.txt)
Sudo:        NOPASSWD — no become-password-file needed
Heatsink:    fitted 2026-03-15 (was throttling at 71°C before)
```
