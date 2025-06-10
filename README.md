# Ansible Collection - jackaltx.solti_ensemble

A comprehensive collection of Ansible roles for infrastructure automation, security hardening, and development environment setup. Part of the SOLTI (Systems Oriented Laboratory Testing & Integration) ecosystem.

## Collection Overview

This collection provides battle-tested Ansible roles covering everything from security auditing to development tooling. Each role is designed with best practices, security, and maintainability in mind, featuring advanced testing frameworks and AI-powered analysis capabilities.

## Architecture Overview

The collection provides integrated automation with clear patterns:

### Security & Auditing Pipeline

- **claude_sectest**: Multi-script security auditing with Git-based change tracking and Claude AI analysis
- **sshd_harden**: SSH daemon hardening with modern cryptographic algorithms

### Infrastructure & Database Pipeline  

- **mariadb**: Database server with security-focused setup and backup functionality
- **nfs-client**: Storage integration for distributed deployments with optimized performance

### Development & Platform Pipeline

- **vs_code**: Development environment setup with official repositories
- **gitea**: Self-hosted Git service with complete lifecycle management
- **podman**: Rootless container engine as Docker alternative
- **wireguard**: Modern VPN client with secure key management

## Security & Auditing Roles

### [claude_sectest](roles/claude_sectest/README.md)

**ISPConfig Security Audit Role (v1.1)** - A comprehensive security auditing framework for ISPConfig3 servers featuring multiple specialized audit scripts, Git-based change tracking, and professional Claude AI analysis integration. Implements a "build small scripts, collect all for you" approach covering configuration security, database inventory, DNS records, and intrusion prevention systems.

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

## Security Analysis Guides

The collection includes comprehensive security analysis frameworks in the claude_sectest role:

- **[ISPConfig Audit Guide](roles/claude_sectest/guides/ispconfig_audit_guide.md)** - Professional security analysis criteria
- **[MySQL Hardening Guide](roles/claude_sectest/guides/mysql_hardening_guide.md)** - Database security assessment framework  
- **[Fail2Ban Audit Guide](roles/claude_sectest/guides/fail2ban_audit_guide.md)** - Intrusion prevention analysis
- **[BIND/Named Audit Guide](roles/claude_sectest/guides/named_audit_guide.md)** - DNS security evaluation
- **[SSH Hardening Guide](roles/claude_sectest/guides/ssh_hardening_guide.md)** - SSH security enhancement companion

## Testing Framework

### Multi-Environment Testing

- **Molecule Integration**: Container and VM-based testing scenarios
- **Cross-Platform Validation**: Debian, Ubuntu, Rocky Linux support
- **Git-Based Versioning**: Configuration change tracking and rollback capabilities

### Verification Levels

- **Component Testing**: Individual role functionality
- **Integration Testing**: Role interaction validation  
- **System Testing**: Complete stack verification

## AI-Powered Security Analysis

Many roles in this collection are designed to work with Claude AI for professional security analysis. The audit scripts and security guides provide structured output that Claude can analyze to deliver expert-level security recommendations, compliance assessments, and specific remediation steps.

**Key Benefits:**

- **Professional Expertise**: Trained on security standards (PCI DSS, NIST, CIS)
- **Cost-Effective**: $20/month vs $200/hour security consultants
- **24/7 Availability**: Get analysis anytime, not just business hours
- **Actionable Results**: Specific commands and priority-ranked recommendations

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

## Part of the SOLTI Ecosystem

This collection is part of the broader SOLTI (Systems Oriented Laboratory Testing & Integration) framework:

- **solti-monitoring**: System monitoring and metrics collection
- **solti-ensemble**: Support tools and shared utilities (this collection)
- **solti-conductor**: Proxmox management and orchestration
- **solti-containers**: Testing containers
- **solti-score**: Documentation and playbooks

## License

MIT-0 - Use freely for any purpose without restriction.

## Authors

- **jackaltx** - Retired but not dead wet-ware dreamer
- **Claude AI** - AI-powered development assistant

*Want to try professional AI-powered security analysis? [Sign up for Claude with my referral](https://claude.ai/referral/T7Fxp0WbSQ) if ya want!*
