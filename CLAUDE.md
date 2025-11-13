# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is the **jackaltx.solti_ensemble** Ansible collection - a comprehensive security-focused collection for infrastructure automation, security hardening, and development environment setup. The collection is part of the SOLTI (Systems Oriented Laboratory Testing & Integration) ecosystem and emphasizes defensive security practices.

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
- **dev**: Development/integration branch
- **main**: Production-ready branch
- Feature branches → dev → main (via PR)

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
- Push to **dev** branch: Triggers lint + superlinter
- Create PR to **main**: Triggers full CI with molecule tests across 3 platforms
- All workflows use checkpoint-friendly approach

## Architecture and Code Structure

### Role Organization Patterns

The collection follows a modular architecture with roles organized by functional domains:

**Security & Auditing Pipeline**: 
- `claude_sectest` - Multi-script security auditing with Git versioning and AI analysis integration
- `fail2ban_config` - Advanced intrusion prevention with profile-based configuration
- `sshd_harden` - SSH daemon hardening per security standards

**Infrastructure Pipeline**:
- `mariadb` - Database server with security-focused configuration
- `ispconfig_backup` & `ispconfig_cert_converge` - ISPConfig automation with certificate management
- `nfs-client` - Network storage client management

**Development Tools**:
- `vs_code`, `gitea`, `podman` - Development environment setup
- `wireguard` - VPN client configuration

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

- **Molecule**: Some roles include molecule testing scenarios
- **Cross-Platform**: Supports Debian 12, Ubuntu, Rocky Linux 9, and Raspberry Pi OS
- **Verification**: Roles include handlers and validation tasks for configuration verification

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