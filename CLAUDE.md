# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the **jackaltx.solti_ensemble** Ansible collection — a **functional service deployment collection** covering both security hardening and service installation. Part of the SOLTI ecosystem. Roles span three domains:

- **Services**: `mariadb`, `mysql` (MySQL 8), `gitea`, `podman`, `docker` (planned), `ghost` (planned)
- **Security**: `sshd_harden`, `fail2ban_config`, `claude_sectest`, `wireguard`
- **Platform utilities**: `ispconfig_backup`, `ispconfig_cert_converge`, `nfs-client`, `vs_code`

The collection is evolving from security-only toward a broader service deployment library, with molecule testing being added role-by-role (see Testing Framework below).

## Common Commands

### Development and Testing
```bash
# Install collection dependencies
ansible-galaxy install -r requirements.yml

# Run a playbook
ansible-playbook -i inventory.yml playbooks/first.yml

# Test specific roles with molecule (if available)
cd roles/[role_name]
molecule test

# Check syntax of playbooks
ansible-playbook --syntax-check -i inventory.yml playbooks/[playbook].yml

# Run playbook in check mode (dry run)
ansible-playbook --check -i inventory.yml playbooks/[playbook].yml

# Encrypt sensitive data
ansible-vault encrypt_string 'secret_value' --name 'variable_name'

# Edit vault file (requires vault password file at ~/.vault-pass)
ansible-vault edit [encrypted_file]
```

### Collection Management
```bash
# Build collection for distribution
ansible-galaxy collection build

# Install collection locally
ansible-galaxy collection install jackaltx-solti_ensemble-*.tar.gz
```

## Git Workflow

This collection uses a **checkpoint commit workflow** for iterative development:

### Branch Strategy
- **test**: Development/integration branch
- **main**: Production-ready branch
- Feature branches → test → main (via PR)

### Checkpoint Commit Pattern

**During Development:**
```bash
# Make changes to code
# Create checkpoint commit
git add -A
git commit -m "checkpoint: add mariadb ssl support"

# Run molecule test
molecule test -s github

# If test fails, make fixes and create another checkpoint
git add -A
git commit -m "checkpoint: fix ssl certificate path"
molecule test -s github

# Repeat until working
```

**Before PR (Squash Checkpoints):**
```bash
# Count your checkpoint commits
git log --oneline | head -10

# Squash last N commits (where N is number of checkpoints)
git rebase -i HEAD~5

# Mark all checkpoint commits as 'squash' or 'fixup'
# Save and create meaningful final commit message
```

### Why Checkpoint Commits?

1. **Audit trail during development** - See exactly what changed between test runs
2. **Easy rollback** - Can git reset to any checkpoint if needed
3. **Clean history for PR** - Squash before merging to main
4. **Works with CI** - Each push to test triggers validation

### GitHub Actions

See [.github/WORKFLOW_GUIDE.md](.github/WORKFLOW_GUIDE.md) for complete workflow documentation.

**Quick reference:**
- Push to **test** branch: Triggers lint + superlinter
- Create PR to **main**: Triggers full CI with molecule tests across 3 platforms
- All workflows use checkpoint-friendly approach

## Architecture and Code Structure

### Role Organization Patterns

**Service Roles** (install + configure + verify):
- `mariadb` - MariaDB server; Debian, Ubuntu, Rocky; molecule scenario live
- `mysql` - MySQL 8 server; Debian; planned (needed by ghost)
- `gitea` - Self-hosted Git; planned
- `docker` - Docker Engine; Debian/Ubuntu; planned (new role)
- `ghost` - Ghost CMS; Debian; planned, depends on mysql
- `podman` - Rootless Podman; Rocky/RHEL only; molecule scenario live

**Security Roles**:
- `sshd_harden` - SSH daemon hardening
- `fail2ban_config` - Intrusion prevention with profile-based configuration
- `claude_sectest` - Multi-script security auditing with AI analysis integration
- `wireguard` - VPN client configuration

**Platform Utilities**:
- `ispconfig_backup`, `ispconfig_cert_converge` - ISPConfig automation
- `nfs-client` - Network storage client
- `vs_code` - VS Code installation

### Key Architectural Patterns

1. **Profile-Based Configuration**: Many roles (especially `fail2ban_config`) use profile systems where different security profiles can be selected via variables like `fail2ban_jail_profile: "ispconfig"`

2. **Git-Based Versioning**: Security roles implement Git versioning for configuration changes with automatic commits and rollback capabilities

3. **AI Integration Ready**: The `claude_sectest` role generates structured audit data designed for Claude AI analysis, with comprehensive security guides in `roles/claude_sectest/guides/`

4. **State Management**: Roles use standardized state variables (e.g., `fail2ban_state: present|configure|absent`) for lifecycle management

5. **Vault Integration**: Sensitive data is encrypted using Ansible Vault with vault password file at `~/.vault-pass`

### Template and Configuration Management

- **Jinja2 Templates**: Located in `roles/*/templates/` with `.j2` extension
- **Default Variables**: In `roles/*/defaults/main.yml` - always check these for available configuration options
- **Variable Precedence**: Uses profile-based variable loading from `roles/*/vars/profiles.yml` where applicable

### Security Considerations

- **Vault Usage**: All sensitive data (API keys, passwords) must be vault-encrypted
- **Git Versioning**: Configuration changes are automatically versioned in Git repositories
- **Defensive Focus**: All code should enhance security posture, never introduce vulnerabilities
- **Audit Trail**: Many roles include audit logging and reporting capabilities

### Testing Framework

**One scenario per role.** The role's supported platforms dictate the platform list in `molecule.yml`.

```
molecule/
  shared/podman/     ← driver: create.yml / prepare.yml / destroy.yml (reused by all scenarios)
  shared/vars/       ← test-config.yml (project_root, report_root)
  podman-role/       ← Rocky 9 only
  mariadb/           ← Debian 12, Rocky 9, Ubuntu 24
  docker/            ← Debian 12, Ubuntu 24 (planned)
  gitea/             ← TBD (planned)
  mysql/             ← Debian 12 (planned — MySQL 8, needed by ghost)
  ghost/             ← Debian 12, depends on mysql (planned)
```

**Running scenarios:**

```bash
# Setup (once per shell session)
source ~/.secrets/testing-containers-registry.conf gitea
export GITEA_USER="$REGISTRY_USER" GITEA_PASSWD="$CONTAINER_TOKEN"
cd /home/lavender/sandbox/ansible/jackaltx && source solti-venv/bin/activate
cd solti-ensemble

# Run a scenario
molecule test -s podman-role          # Rocky 9: podman role (full cycle)
molecule test -s mariadb              # Debian 12 + Rocky 9 + Ubuntu 24: mariadb role

# Step-by-step (keep containers alive between runs)
molecule create -s mariadb
molecule converge -s mariadb          # repeatable
molecule verify -s mariadb
molecule destroy -s mariadb
```

**Multi-level verify pattern** — `roles/ROLE/tasks/verify.yml` is an auto-discovery orchestrator:

```yaml
- ansible.builtin.find:
    paths: "{{ role_path }}/tasks"
    patterns: "verify_[0-9]*.yml"
  register: _verify_levels
  delegate_to: localhost
  run_once: true
- ansible.builtin.include_tasks: "{{ item }}"
  loop: "{{ _verify_levels.files | map(attribute='path') | sort | list }}"
```

Adding a test level = drop `verify_N_description.yml` in the role's `tasks/` — no edits required.
Levels fail-fast: if verify_0 fails, verify_1 never runs.

| Level | Purpose |
|---|---|
| `verify_0_install.yml` | Service running, binary present, port listening |
| `verify_1_functional.yml` | Does it actually work (SQL round-trip, `podman run`, HTTP health) |
| `verify_2_*` | Auth, edge cases — add as needed |

**Platform notes:**
- Rocky 9 mariadb: package is `mariadb` (not `mariadb-client`)
- Ubuntu needs explicit `tasks/packages_ubuntu.yml` and `vars/ubuntu.yml` (no auto-fallback in `include_tasks`)
- Rootless podman-in-podman: blocked by kernel when host is rootless podman; verify_1 runs `podman run` as root; rootless prerequisites verified in verify_0

**Adding a new role scenario:**
1. `mkdir molecule/ROLENAME`
2. Copy `molecule.yml` from a similar scenario, adjust `platforms:` to what the role supports
3. Write `converge.yml` (include_role + vars), `verify.yml` (calls `tasks_from: verify`)
4. Write `roles/ROLE/tasks/verify.yml` (orchestrator), `verify_0_install.yml`, `verify_1_functional.yml`
5. Add `requirements.yml` if the role needs extra collections

## Important Files and Locations

- `ansible.cfg` - Main Ansible configuration with custom plugins and logging
- `inventory.yml` - Example inventory with VPN client configurations
- `requirements.yml` - Collection dependencies (community.general, community.crypto)
- `docs/automation_best_practice_claude.md` - Automation philosophy emphasizing native application tools
- `roles/shared/git/` - Shared Git versioning tasks used across multiple roles
- `log/ansible.log` - Ansible execution logs (configured in ansible.cfg)

## Variable Patterns

Most roles follow these variable naming patterns:
- `[role]_state`: Controls role lifecycle (present/configure/absent)
- `[role]_config`: Main configuration dictionary
- `[role]_git_versioning`: Git versioning configuration
- Profile-based variables loaded from `vars/profiles.yml` or similar

When modifying roles, always check the `defaults/main.yml` file first to understand available configuration options and expected variable structures.