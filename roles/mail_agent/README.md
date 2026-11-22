# mail_agent

Creates a restricted system user (`mailagent`) with a wrapper script and sudoers rules
that give a remote agent (AI or human) read and limited operational access to the Postfix
and Dovecot mail stack. Designed for the ISPConfig mail environment (Postfix, Dovecot,
rspamd, sieve, clamav).

This role does **not** install Postfix or Dovecot — those must exist before deploying.

---

## Prerequisites

- Postfix installed and running (ISPConfig manages this on a typical VPS)
- Dovecot installed and running
- `ansible.posix` collection installed (`ansible-galaxy collection install ansible.posix`)

---

## Quick Start

```yaml
# inventory/hosts/myserver.yml
all:
  children:
    mylab:
      hosts:
        myserver:
          ansible_host: myserver.example.com
          mail_agent_state: present
          mail_agent_ssh_public_key: "{{ lookup('env', 'MAIL_AGENT_SSH_PUBKEY') }}"
```

```bash
export MAIL_AGENT_SSH_PUBKEY="$(cat ~/.ssh/mail_agent_ed25519.pub)"
./manage-feature.sh -h myserver mail_agent present
```

---

## Variables

| Variable | Default | Required | Description |
|---|---|---|---|
| `mail_agent_state` | `present` | no | `present` or `absent` |
| `mail_agent_user` | `mailagent` | no | System username to create |
| `mail_agent_groups` | `[]` | no | Additional groups to add the user to |
| `mail_agent_ssh_public_key` | `""` | **yes** | SSH public key string for the agent |
| `mail_agent_ssh_source` | `""` | no | Source IP/CIDR for `from=` restriction; empty = key-only, any source |
| `mail_agent_allow_delete` | `false` | no | Expose `delete` action in wrapper (postsuper -d) |
| `mail_agent_allow_restart` | `true` | no | Add `systemctl restart` to sudoers |
| `mail_agent_no_log` | `true` | no | Suppress credential logging (`mylab_nolog` override) |

---

## States

**`present`** — Creates the user, locks home dir to mode 0700, deploys SSH key with
`restrict` option, installs wrapper at `/usr/local/sbin/mail-agent-op`, and writes
`/etc/sudoers.d/mailagent`. All steps are idempotent.

**`absent`** — Removes sudoers rules, wrapper script, user account, and home directory.

---

## Wrapper Commands

The agent connects via SSH and runs: `sudo /usr/local/sbin/mail-agent-op <action> <arg>`

All arguments are validated before execution. The wrapper runs as root via sudo.

| Action | Argument | Underlying command |
|---|---|---|
| `envelope` | queue-id (6–20 alphanumeric) | `postcat -q -e <id>` |
| `hold` | queue-id | `postsuper -h <id>` |
| `release` | queue-id | `postsuper -H <id>` |
| `requeue` | queue-id | `postsuper -r <id>` |
| `delete` | queue-id | `postsuper -d <id>` *(requires `mail_agent_allow_delete: true`)* |
| `userinfo` | user@domain | `doveadm user <addr>` |
| `quota` | user@domain | `doveadm quota get -u <addr>` |
| `recalc` | user@domain | `doveadm quota recalc -u <addr>` |
| `mailboxes` | user@domain | `doveadm mailbox status -u <addr> ...` |
| `kick` | user@domain | `doveadm kick <addr>` |
| `logs` | line-count (1–9999) | `journalctl -n <n> -u 'postfix@*' -u dovecot` |
| `audit` | line-count (1–9999) | sudo journal filtered to `mailagent` commands |
| `queue` | *(none)* | `postqueue -p` — list full mail queue |

---

## Direct Sudo Grants (no wrapper)

The agent can also call these directly via `sudo`:

| Command | Purpose |
|---|---|
| `postfix check` | Validate postfix config |
| `doveconf -n` | Dump non-default dovecot config |
| `doveadm who` | List active IMAP sessions |
| `doveadm log errors` | Recent dovecot error log |
| `systemctl reload postfix` | Reload postfix config |
| `systemctl reload dovecot` | Reload dovecot config |
| `systemctl restart postfix` | Restart postfix *(requires `mail_agent_allow_restart: true`)* |
| `systemctl restart dovecot` | Restart dovecot *(requires `mail_agent_allow_restart: true`)* |

---

## Verify Tasks

All levels run standalone via `tasks_from`:

```bash
./manage-feature.sh -h myserver mail_agent verify           # all levels
./manage-feature.sh -h myserver mail_agent verify_0_install # deployment artifacts only
./manage-feature.sh -h myserver mail_agent verify_1_functional
./manage-feature.sh -h myserver mail_agent verify_2_drift
./manage-feature.sh -h myserver mail_agent verify_3_security
```

| Level | File | Tests |
|---|---|---|
| 0 | `verify_0_install.yml` | User exists, home mode 0700, SSH key present, wrapper/sudoers exist with correct ownership and modes, syntax valid |
| 1 | `verify_1_functional.yml` | postfix/dovecot active, ports 25/587/143/993 listening, wrapper executes full sudo chain, rspamd/clamd status (advisory) |
| 2 | `verify_2_drift.yml` | Wrapper/sudoers ownership+mode, `postfix check` passes, postfix TLS/relay settings surfaced, dovecot SSL/auth config surfaced |
| 3 | `verify_3_security.yml` | SSH key has `restrict`, mailagent isolation (cannot sudo arbitrary commands), dovecot auth failure count (24h advisory), postfix NOQUEUE count (1h advisory), mailagent SSH session log |

---

## Security Model

- **SSH `restrict`**: the key option disables PTY, TCP forwarding, agent forwarding, and X11 for
  this key. The agent gets a connection but no interactive shell capabilities.
- **`from=` restriction**: optional IP/CIDR guard via `mail_agent_ssh_source`. Not set by default.
- **Wrapper arg validation**: all arguments are validated with strict regex before the underlying
  command runs. `qid()` requires 6–20 alphanumerics (also blocks the special `ALL` queue ID).
  `user()` requires a valid email address. `lines()` requires 1–4 digits.
- **Sudoers whitelist**: the agent can only call specific commands as root. Arbitrary shell access
  is not possible through the sudoers grant.

---

## Extending

To add a new wrapper action:

1. Add a case to `templates/mail-agent-op.j2` with the appropriate argument validator
2. If the new command isn't already reachable by root (wrapper runs as root), add a sudoers entry
   to `templates/mailagent.sudoers.j2`
3. Redeploy: `./manage-feature.sh -h myserver mail_agent present`

No other files need changing.
