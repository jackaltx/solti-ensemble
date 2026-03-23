# OpenClaw Security Surface

## Secrets Exposure Map

### What OpenClaw Can Read (Runtime Access)

OpenClaw process has **read access** to these secrets via `/etc/openclaw/config.yml`:

| Secret | Purpose | Exposure Risk | Mitigation |
|--------|---------|---------------|------------|
| Matrix Access Token | Send/receive Matrix messages | **High** - full bot identity | Rate-limited by Synapse, room allowlist |
| Claude API Key | Call Anthropic API | **High** - API billing risk | Monitor usage, set API spending limits |
| HA Token | Query/control HA devices | **Medium** - depends on HA permissions | Use **read-only** token, limit device scope |
| Web Admin Token | Access control UI | **Medium** - admin interface | Unifi zone restricted, rotate regularly |
| Email Credentials | Send/receive email | **Medium** - phishing vector | Dedicated bot account, SPF/DKIM |
| Gitea Token | Repository access | **Medium** - code access | Read-only scope, limit to specific repos |

**File permissions:**

- `/etc/openclaw/config.yml` — 0640 root:openclaw (openclaw user can read)
- `/var/lib/openclaw/` — 0750 openclaw:openclaw (persistent state)

### What OpenClaw CANNOT Read (Ansible-Only)

These credentials are **never** deployed to the target host:

| Secret | Purpose | Stored In | Used By |
|--------|---------|-----------|---------|
| Matrix Admin Password | Create Matrix users | ~/.secrets/LabMatrix (control node) | apply-config.yml only |
| Vault Encryption Key | Decrypt Ansible vault | ~/.vault_pass (control node) | ansible-playbook |
| SSH Private Key | Connect to hosts | ~/.ssh/id_ed25519 (control node) | Ansible |

### Threat Model

**If openclaw process is compromised:**

- Attacker gains bot's Matrix identity (can impersonate in allowed rooms)
- Attacker can call Claude API (billing impact)
- Attacker can query/control HA (if token not read-only)
- Attacker **cannot** create Matrix users (no admin access)
- Attacker **cannot** SSH to other hosts (no SSH keys)
- Attacker **cannot** decrypt vault secrets (vault key not on host)

**Mitigations:**

1. **Matrix:** Room allowlist, rate limiting, E2EE for sensitive rooms
2. **Claude API:** Anthropic console spending limits, monitor usage
3. **HA:** Use read-only token, restrict device scope, monitor unusual queries
4. **Systemd:** `NoNewPrivileges=true`, `ProtectSystem=strict`, minimal read/write paths
5. **Backup:** Backup includes secrets — encrypt backup tarballs or store offline

### Credential Lifecycle

**Provisioning time** (Ansible control node only):

- `openclaw_bot_password` (inventory) — Used by apply-config.yml to create Matrix user
- Never deployed to target host

**Runtime** (deployed to `/etc/openclaw/config.yml`):

- `OPENCLAW_MATRIX_ACCESS_TOKEN` — Bot's access token (from apply-config.yml)
- `OPENCLAW_CLAUDE_API_KEY` — API key from Anthropic
- `OPENCLAW_HA_TOKEN` — HA long-lived token
- `OPENCLAW_WEB_TOKEN` — Admin UI token
- Optional: `OPENCLAW_EMAIL_*`, `OPENCLAW_GITEA_*`

### Production Upgrade Path

**Phase 1 (current):** `~/.secrets/*.env` → Ansible `lookup('env', ...)`

**Phase 2 (production):** HashiVault → Ansible `lookup('hashi_vault', ...)`

Migration: Change `defaults/main.yml` lookups, no template changes needed.

## Recommendations

### Before Production

1. **HA Token:** Create read-only long-lived token in Home Assistant
2. **Claude API:** Set spending limits in Anthropic console
3. **Matrix:** Use E2EE rooms for sensitive operations
4. **Backup:** Encrypt openclaw backup tarballs (they contain secrets)
5. **Monitoring:** Alert on unusual Claude API usage or HA queries

### Credential Rotation

**High-frequency (monthly):**

- `OPENCLAW_WEB_TOKEN` — Admin UI token

**Medium-frequency (quarterly):**

- `OPENCLAW_HA_TOKEN` — HA access token
- `OPENCLAW_GITEA_TOKEN` — Gitea access token

**Low-frequency (yearly or on breach):**

- `OPENCLAW_MATRIX_ACCESS_TOKEN` — Bot Matrix identity
- `OPENCLAW_CLAUDE_API_KEY` — API key (bill continuity risk)

### Audit Trail

All secrets written to `/etc/openclaw/config.yml` by Ansible configure task.

**Audit command:**

```bash
# Check what secrets are deployed
ssh thunker 'sudo cat /etc/openclaw/config.yml | grep -E "(token|key|password):"'
```

**Verify no secrets in inventory:**

```bash
# Should return nothing (or only placeholders)
grep -i 'claude_api_key\|ha_token\|web_token\|matrix_access' mylab/inventory.yml
```

## See Also

- [CLAUDE.md](../CLAUDE.md) — Role usage and setup workflow
- [docs/reference/env-var-injection.md](../../../docs/reference/env-var-injection.md) — Environment variable pattern
- [mylab/playbooks/matrix/apply-config.yml](../../../mylab/playbooks/matrix/apply-config.yml) — Matrix user creation
