# Ansible Collection - jackaltx.solti_ensemble

A comprehensive collection of Ansible roles for infrastructure automation, security hardening, and development environment setup. Created by jackaltx & Claude AI.

## Collection Overview

This collection provides battle-tested Ansible roles covering everything from security auditing to development tooling. Each role is designed with best practices, security, and maintainability in mind.

## Security & Auditing Roles

### [claude_sectest](roles/claude_sectest/README.md)

**ISPConfig Security Audit Role** - A comprehensive security auditing framework for ISPConfig3 servers featuring multiple specialized audit scripts, Git-based change tracking, and professional Claude AI analysis integration. Implements a "build small scripts, collect all for you" approach covering configuration security, database inventory, DNS records, and intrusion prevention.

### [sshd_harden](roles/sshd_harden/README.md)

**SSH Hardening Role** - Hardens SSH daemon configuration according to sshaudit.com recommendations. Restricts cryptographic algorithms to secure options, configures connection timeouts, disables dangerous features, generates secure key pairs, and filters weak Diffie-Hellman moduli.

## Database & Storage Roles

### [mariadb](roles/mariadb/readme.md)

**MariaDB Database Server** - Automated MariaDB installation and configuration with security-focused setup, database initialization scripts, built-in backup functionality, and support for both Debian 12 and Rocky Linux 9.

### [nfs-client](roles/nfs-client/README.md)

**NFS Client Management** - Manages NFS client installation and mount configuration with support for multiple NFS shares, cross-platform compatibility, and optimized mount options for performance and reliability.

## Development Tools

### [vs_code](roles/vs_code/README.md)

**Visual Studio Code Installation** - Installs Visual Studio Code on Red Hat-based distributions using Microsoft's official repository with GPG verification and automatic updates.

### [gitea](roles/gitea/README.md)

**Gitea Git Service** - Lightweight, self-hosted Git service installation and configuration supporting SSL, multiple databases (SQLite, MySQL, PostgreSQL), user management, and complete lifecycle management.

### [podman](roles/podman/README.md)

**Podman Container Engine** - Daemonless container engine installation with rootless container support, Podman Compose functionality, and secure registry configuration as a Docker alternative.

## Network & VPN

### [wireguard](roles/wireguard/readme.md)

**WireGuard VPN Client** - Modern VPN client installation and configuration for Rocky Linux 9 and Debian 12 with secure key generation, automatic backups, and comprehensive tag-based execution control.

## Utility Scripts & Guides

### [mysql-ispconf-trick](mysql-ispconf-trick.md)

**ISPConfig MySQL Password Extraction** - Handy Ansible tasks to parse and extract MySQL passwords from ISPConfig configuration files for use in database automation tasks.

### [claude-split-format-guide](roles/claude_sectest/guides/claude-split-format-guide.md)

**Multi-file Project Format** - Guide for formatting consolidated files that can be processed by the claude-split.py script to create proper directory structures from Claude AI generated code.

## Security Analysis Guides

The collection includes comprehensive security analysis frameworks:

- **[ISPConfig Audit Guide](roles/claude_sectest/guides/ispconfig_audit_guide.md)** - Professional security analysis criteria
- **[MySQL Hardening Guide](roles/claude_sectest/guides/mysql_hardening_guide.md)** - Database security assessment framework  
- **[Fail2Ban Audit Guide](roles/claude_sectest/guides/fail2ban_audit_guide.md)** - Intrusion prevention analysis
- **[BIND/Named Audit Guide](roles/claude_sectest/guides/named_audit_guide.md)** - DNS security evaluation

## Installation

```bash
ansible-galaxy collection install jackaltx.solti_ensemble
```

## Usage

```yaml
- hosts: servers
  roles:
    - jackaltx.solti_ensemble.sshd_harden
    - jackaltx.solti_ensemble.mariadb
```

## License

MIT-0 - Use freely for any purpose without restriction.

## Authors

- **jackaltx** - Retired but not dead wet-ware dreamer
- **Claude AI** - AI-powered development assistant

## Professional Security Analysis

Many roles in this collection are designed to work with Claude AI for professional security analysis. The audit scripts and guides provide structured output that Claude can analyze to give you expert-level security recommendations.

*Want to try professional AI-powered security analysis? [Sign up for Claude with my referral](https://claude.ai/referral/T7Fxp0WbSQ) if ya want!*
