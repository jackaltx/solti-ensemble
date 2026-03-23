# CLAUDE.md — openclaw Role

## What This Role Does

Deploys the OpenClaw AI agent daemon. Connects to Matrix as a bot user, uses the Claude API for reasoning, and executes skills (HA control, shell, web queries).

**Designed for:** Raspberry Pi 5 with Hailo-8L AI accelerator
**Runs on:** Any Linux system with Node.js, npm, and systemd

The Hailo accelerator is **not required** and is not used in the agent's core loop. It's available for vision skills if present on the hardware.

## Key Design Decisions

### State Variable: `openclaw_state`
- `present` — install Node.js, npm package, systemd service (no credentials needed)
- `configure` — present + write config with credentials, start service
- `absent` — stop service, remove package and config (leaves data dir intact)
- `backup` — create timestamped tarball in `openclaw_backup_dir`
- `restore` — install + extract backup tarball (requires `RESTORE_FILE` env var)

Run `present` first to verify npm install works, then `configure` once credentials are sourced from `~/.secrets/`.

### Matrix is the only external channel

Do **not** add native Discord, Slack, or Telegram channels. All external services route through Matrix bridges. OpenClaw holds one credential — the Matrix access token. See `docs/pi5-use-cases.md` → "Matrix as Security Boundary".

### Credentials — Environment Variables

**Runtime secrets** are loaded from `~/.secrets/openclaw-{{ inventory_hostname }}.env` via environment variables. Source this file before running configure:

```bash
source ~/.secrets/openclaw-thunker.env
./manage-svc.sh -h thunker openclaw configure
```

**Required env vars:**

- `OPENCLAW_MATRIX_ACCESS_TOKEN` — Bot's Matrix access token
- `OPENCLAW_CLAUDE_API_KEY` — Anthropic API key
- `OPENCLAW_WEB_TOKEN` — Admin UI authentication token

**Required inventory vars:**

- `openclaw_matrix_homeserver` — Matrix homeserver URL
- `openclaw_matrix_user_id` — Bot user ID
- `openclaw_matrix_allowed_rooms` — List of room IDs bot can act in

**Optional (if integrations enabled):**

- `OPENCLAW_HA_TOKEN` (env) + `openclaw_ha_enabled: true`, `openclaw_ha_url` (inventory)
- `OPENCLAW_EMAIL_*` (env) + `openclaw_email_enabled: true` (inventory)
- `OPENCLAW_GITEA_*` (env) + `openclaw_gitea_enabled: true` (inventory)

**Obtaining tokens:**

1. **Matrix token:** Run `mylab/playbooks/matrix/apply-config.yml` (creates user, generates token to `~/.secrets/LabMatrix`)
2. **Claude API:** <https://console.anthropic.com/settings/keys>
3. **HA token:** Home Assistant → Profile → Long-Lived Access Tokens (create read-only token)
4. **Web token:** `uuidgen | tr -d '-'`

### npm package name
Current assumption: `@openclaw/cli`. Update `install.yml` and `openclaw.service.j2`
binary path once the real package name is confirmed.

## File Map

```
defaults/main.yml              — all vars with defaults (credentials default to "")
tasks/main.yml                 — state dispatcher
tasks/install.yml              — nodejs/npm, system user, directories, systemd service
tasks/configure.yml            — assert credentials, write config, start service
tasks/remove.yml               — stop service, remove package/config/user (conditional data cleanup)
tasks/backup.yml               — create timestamped tarball of /etc/openclaw + /var/lib/openclaw
tasks/restore.yml              — extract backup tarball, fix ownership, start service
tasks/verify.yml               — binary, service state, config present (self-contained)
tasks/verify_sane.yml          — behavioral health check: port, memory, CPU, restarts, errors, HTTP
handlers/main.yml              — reload systemd, restart openclaw
templates/openclaw.service.j2  — systemd unit with basic hardening
templates/config.yml.j2        — openclaw config file
```

## Inventory Pattern

```yaml
# mylab/inventory.yml
thunker:
  # Bot identity
  openclaw_matrix_user_id: "@openclaw:jackaltx.com"
  openclaw_matrix_homeserver: "https://matrix-web.jackaltx.com"

  # Room authorization (get room IDs from apply-config.yml output)
  openclaw_matrix_allowed_rooms:
    - "!abc123def456:jackaltx.com"    # HA control room
    - "!xyz789uvw012:jackaltx.com"    # Admin room

  # Integration endpoints
  openclaw_ha_enabled: true
  openclaw_ha_url: "http://homeassistant.local:8123"

  openclaw_email_enabled: false
  openclaw_gitea_enabled: false

  # Web admin interface
  openclaw_web_bind: "0.0.0.0"    # Unifi zone controlled
  openclaw_web_port: 18789
  openclaw_web_alt_port: 18791

  # State control
  openclaw_state: configure   # or "present" until creds are ready
```

Secrets file: `~/.secrets/openclaw-thunker.env`

```bash
# Bot Matrix access token (from apply-config.yml or manual login)
export OPENCLAW_MATRIX_ACCESS_TOKEN="syt_b3BlbmNsYXc_..."

# Claude API key (from Anthropic console)
export OPENCLAW_CLAUDE_API_KEY="sk-ant-api03-..."

# Home Assistant long-lived token (from HA)
export OPENCLAW_HA_TOKEN="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."

# Web admin interface token (generate via uuidgen)
export OPENCLAW_WEB_TOKEN="a3f8e2b9d1c4f7e0b5a2d9c6e1f3b8a4"
```

## Verification

Two separate verification tasks:

| Task | Purpose | When to use |
|------|---------|-------------|
| `verify.yml` | Is it installed and running? | Quick sanity after any deploy |
| `verify_sane.yml` | Is it behaving? Port, memory, restarts, errors, HTTP | After configure, or ad-hoc if suspicious |

`verify_sane` thresholds (override in inventory or extra-vars):
```yaml
openclaw_sane_memory_max_mb: 512   # RSS limit before fail
openclaw_sane_restart_max: 3       # NRestarts before crash-loop fail
openclaw_sane_error_threshold: 5   # journal errors/hour before fail
```

To test the threshold logic (expects a fail):
```bash
ansible-playbook ... -e openclaw_sane_memory_max_mb=1
```

## Usage Commands

```bash
# Install (no credentials needed yet)
./manage-svc.sh -h thunker openclaw deploy

# Deploy config + start service (source secrets first)
source ~/.secrets/openclaw-thunker.env
./manage-svc.sh -h thunker openclaw configure

# Is it installed and running?
./svc-exec.sh -h thunker openclaw verify

# Is it behaving? (port, memory, CPU, restarts, errors, HTTP)
./svc-exec.sh -h thunker openclaw verify_sane

# Backup to timestamped tarball
./svc-exec.sh -h thunker openclaw backup

# Restore from backup (install + extract tarball)
RESTORE_FILE=/var/backups/openclaw/openclaw-thunker-20260315T120000.tar.gz \
  ./manage-svc.sh -h thunker openclaw restore

# Remove package and config (leaves data dir intact)
./manage-svc.sh -h thunker openclaw remove

# Full purge back to pre-claw (remove everything including data)
DELETE_DATA=true ./manage-svc.sh -h thunker openclaw remove
```

## Apply Order

Always run `pi5_mgr` before `openclaw`:

```bash
./manage-svc.sh -h thunker pi5_mgr deploy
./manage-svc.sh -h thunker openclaw configure
```

## Setup Workflow

1. **Add openclaw bot to Matrix inventory:**

   ```yaml
   # Edit mylab/inventory.yml, add to matrix_users:
   - user_id: openclaw
     role: bot
     displayname: "OpenClaw AI Agent"
     password: "GENERATE_STRONG_PASSWORD"
     state: present
   ```

2. **Create Matrix user and get room IDs:**

   ```bash
   ./bin/matrix-playbook.sh playbooks/matrix/apply-config.yml
   # Note the room IDs from output: !abc123:jackaltx.com
   ```

3. **Extract bot token from LabMatrix:**

   ```bash
   source ~/.secrets/LabMatrix
   echo "Bot token: $MATRIX_OPENCLAW_TOKEN"
   ```

4. **Create openclaw secrets file:**

   ```bash
   cat > ~/.secrets/openclaw-thunker.env <<'EOF'
   export OPENCLAW_MATRIX_ACCESS_TOKEN="PASTE_TOKEN_FROM_ABOVE"
   export OPENCLAW_CLAUDE_API_KEY="sk-ant-api03-YOUR_KEY_HERE"
   export OPENCLAW_WEB_TOKEN="$(uuidgen | tr -d '-')"
   export OPENCLAW_HA_TOKEN="YOUR_HA_TOKEN_HERE"
   EOF
   ```

5. **Update inventory with room IDs and config:**

   ```yaml
   # Edit mylab/inventory.yml thunker host_vars:
   openclaw_matrix_allowed_rooms:
     - "!abc123:jackaltx.com"    # Paste room IDs from step 2
   openclaw_ha_enabled: true
   openclaw_ha_url: "http://homeassistant.local:8123"
   ```

6. **Deploy openclaw:**

   ```bash
   source ~/.secrets/openclaw-thunker.env
   ./manage-svc.sh -h thunker openclaw configure
   ```

## TODO Before Production

1. Confirm the real npm package name (`@openclaw/cli` is assumed)
2. Confirm the `openclaw` binary path after install
3. Set HA token to **read-only** scope
4. Configure Anthropic API spending limits
