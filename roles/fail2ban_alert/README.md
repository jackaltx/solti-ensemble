# fail2ban_alert

Monitors fail2ban ban rate via Loki and dispatches alerts through one or more channels.
Part of the **solti-ensemble** collection.

Built on `_notifier_base` — the shared Python dispatch library that routes a structured event
dict to configured human channels (email, Matrix) and machine channels (Redis pub/sub, AMQP).
This role is the sensor half; `_notifier_base` is the dispatch half.

## Architecture

```
fail2ban-alert.py (sensor)
  ├── queries Loki for ban rate (last 1h)
  ├── compares against threshold
  └── on threshold exceeded:
        notifier.event(source, severity, summary, detail)
        notifier.notify_with_cooldown(ev, config)
              ├── email     → human sees alert
              ├── matrix    → human sees it in a room
              ├── redis     → agent subscribes, decides to act
              └── amqp      → workflow queue, triggers automation
```

The sensor produces a structured event dict. The dispatcher routes it to all enabled channels.
Channels split into two classes:
- **Human** (email, Matrix) — inform an operator
- **Machine** (Redis, AMQP) — feed an agentic pipeline

The same event that tells you "47 bans in the last hour" simultaneously triggers a subscriber
agent to investigate. This is the sensor → dispatcher → agent pattern at the infrastructure layer.

## Prerequisites

- Loki instance running and receiving fail2ban logs (via Alloy/Promtail)
- At least one notification channel configured (see Variables)
- `python3-yaml` and `python3-requests` on the target host (installed by role)

## Quick Start

Minimal inventory entry (email only):

```yaml
# inventory/hosts/mylab.yml
monitor11:
  fail2ban_alert_state: present
  fail2ban_alert_smtp_host: "mail.example.com"
  fail2ban_alert_smtp_port: 587
  fail2ban_alert_smtp_username: "alerts@example.com"
  fail2ban_alert_smtp_password: "{{ lookup('env', 'SMTP_PASS') }}"
  fail2ban_alert_from_address: "alerts@example.com"
  fail2ban_alert_recipients: "ops@example.com"
```

Deploy:

```bash
cd solti-ensemble
./manage-feature.sh -h monitor11 fail2ban_alert present
```

Verify:

```bash
./manage-feature.sh -h monitor11 fail2ban_alert verify
```

## Variables

| Variable | Default | Required | Description |
|----------|---------|----------|-------------|
| `fail2ban_alert_state` | `present` | no | `present` or `absent` |
| `fail2ban_alert_loki_url` | `http://monitor11.a0a0.org:3100` | yes | Loki base URL |
| `fail2ban_alert_threshold` | `25` | no | Bans/hour to trigger alert |
| `fail2ban_alert_cooldown_minutes` | `60` | no | Suppress repeat alerts |
| `fail2ban_alert_smtp_host` | `""` | see channels | SMTP relay hostname |
| `fail2ban_alert_smtp_port` | `587` | no | SMTP port |
| `fail2ban_alert_smtp_username` | `""` | see channels | SMTP auth username |
| `fail2ban_alert_smtp_password` | `""` | see channels | SMTP auth password |
| `fail2ban_alert_from_address` | `""` | see channels | Envelope From address |
| `fail2ban_alert_recipients` | `jack@lavnet.net` | no | Comma-separated To addresses |
| `fail2ban_alert_matrix_enabled` | `false` | no | Enable Matrix channel |
| `fail2ban_alert_matrix_homeserver` | `""` | see channels | Matrix server URL |
| `fail2ban_alert_matrix_token` | `""` | see channels | Access token |
| `fail2ban_alert_matrix_room_id` | `""` | see channels | `!room:server` ID |
| `fail2ban_alert_redis_enabled` | `false` | no | Enable Redis pub/sub channel |
| `fail2ban_alert_redis_url` | `""` | see channels | `redis://host:port/db` |
| `fail2ban_alert_redis_channel` | `solti_events` | no | Pub/sub channel name |
| `fail2ban_alert_amqp_enabled` | `false` | no | Enable AMQP channel |
| `fail2ban_alert_amqp_url` | `""` | see channels | `amqp://user:pass@host/vhost` |
| `fail2ban_alert_amqp_exchange` | `solti_events` | no | Exchange name |
| `fail2ban_alert_amqp_routing_key` | `fail2ban` | no | Routing key |
| `fail2ban_alert_no_log` | `{{ mylab_nolog \| default(true) }}` | no | Suppress secret logging |

At least one channel must be configured — the role asserts this at deploy time.

## States

| State | Effect |
|-------|--------|
| `present` | Creates system user, deploys sensor script + config, installs and starts 5-minute timer |
| `absent` | Stops and removes timer/service, config, state dir, system user |

## Task-as-Entry-Point

Any `.yml` file in `tasks/` is callable directly via `tasks_from`. No playbook required.

```bash
# Full verify chain (all levels in order)
./manage-feature.sh -h monitor11 fail2ban_alert verify

# Individual levels (each runs standalone)
./manage-feature.sh -h monitor11 fail2ban_alert verify_0_install
./manage-feature.sh -h monitor11 fail2ban_alert verify_1_functional
```

The verify orchestrator (`tasks/verify.yml`) uses auto-discovery — dropping a new
`verify_N_*.yml` file in `tasks/` is enough to add a level.

## Verify Levels

| Level | Checks | Fails on |
|-------|--------|----------|
| `verify_0_install` | system user, config dir, state dir, script, timer exists | any artifact missing |
| `verify_1_functional` | timer active, Loki health, manual sensor run | timer not active |

## manage-feature.sh Rules

This role follows the **task-as-entry-point** pattern used across solti-ensemble.
`manage-feature.sh` generates a one-shot playbook from a role + action name:

```bash
# Syntax
./manage-feature.sh [-h HOST] [-y] ROLE ACTION [-- extra-args]

# Examples
./manage-feature.sh -h monitor11 fail2ban_alert present       # deploy
./manage-feature.sh -h monitor11 fail2ban_alert absent        # remove (prompts unless -y)
./manage-feature.sh -h monitor11 fail2ban_alert verify        # full verify chain
./manage-feature.sh -h monitor11 fail2ban_alert verify -- -e "fail2ban_alert_no_log=false"
```

The `-y` flag skips the "are you sure?" prompt for destructive states (`absent`, `purge`).

Extra vars after `--` are passed directly to `ansible-playbook -e`.

**Rule:** operational tasks (verify, status, rotate) go in `tasks/*.yml`, not as new states.
States are for lifecycle only (`present`, `absent`). The generator handles the rest.

## Credential Handling

Short-term: set `fail2ban_alert_smtp_password` in the private inventory repo
(`inventory/hosts/`) which is gitignored from the public collection.

Right-term: Vault push model — `kv/hosts/monitor11/fail2ban_alert/smtp` → role reads
at deploy time. Until Vault is wired, the private inventory is acceptable.

**Never** commit credentials to the public collection repo.

## Installed Artifacts

| Path | Owner | Mode | Purpose |
|------|-------|------|---------|
| `/usr/local/bin/fail2ban-alert.py` | root:root | 0755 | Sensor script |
| `/etc/fail2ban-alert/config.yml` | root:fail2ban-alert | 0640 | Config (contains creds) |
| `/var/lib/fail2ban-alert/` | fail2ban-alert | 0750 | Cooldown state files |
| `/etc/systemd/system/fail2ban-alert.service` | root | 0644 | Oneshot service unit |
| `/etc/systemd/system/fail2ban-alert.timer` | root | 0644 | 5-minute timer |
| `/usr/local/lib/solti/notifier.py` | root | 0644 | Dispatch library (from `_notifier_base`) |

## Adding a Channel

1. Add `fail2ban_alert_<channel>_enabled` and supporting vars to `defaults/main.yml`
2. Add the channel block to `templates/config.yml.j2`
3. Implement the handler in `roles/_notifier_base/files/notifier.py`

The sensor script (`fail2ban-alert.py.j2`) does not change — it calls `notifier.notify_with_cooldown()`
which reads the config and dispatches to all enabled channels.
