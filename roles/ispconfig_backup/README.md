# ISPConfig Backup Role

A generic, git-based configuration backup and audit role specifically designed for ISPConfig environments. This role provides comprehensive backup and change detection for all ISPConfig-managed services including mail, web, DNS, and security configurations.

## Overview

This role follows the same git-versioning pattern as the fail2ban role, providing:

- **Automated backup** of ISPConfig configuration files
- **Change detection** through file fingerprinting
- **Git-based versioning** for complete audit trail
- **Simple audit comparison** between current and backed-up configurations
- **Flexible target configuration** for different environments

## Features

- **Comprehensive Coverage**: Backs up all ISPConfig service configurations based on real update analysis
- **Git Integration**: Complete version control with timestamps and commit messages
- **Fingerprint-based Auditing**: SHA256 checksums for accurate change detection
- **Flexible Exclusions**: Configurable patterns to exclude logs, temporary files, and backups
- **Simple Workflow**: Separate backup and audit operations
- **Detailed Reporting**: Clear status reporting and optional diff output

## Quick Start

### Basic Usage

```yaml
# Run backup
- hosts: ispconfig_servers
  roles:
    - jackaltx.solti_ensemble.ispconfig_backup

# Run audit only
- hosts: ispconfig_servers
  tasks:
    - include_role:
        name: jackaltx.solti_ensemble.ispconfig_backup
        tasks_from: audit.yml
```

### Pre-Update Workflow

```bash
# 1. Check current state before maintenance
- include_role:
    name: jackaltx.solti_ensemble.ispconfig_backup
    tasks_from: audit.yml

# 2. Take pre-update snapshot
- include_role:
    name: jackaltx.solti_ensemble.ispconfig_backup

# 3. Perform ISPConfig update
# ... run your ISPConfig update ...

# 4. Check what changed
- include_role:
    name: jackaltx.solti_ensemble.ispconfig_backup
    tasks_from: audit.yml
    vars:
      ispconfig_audit_show_differences: true
```

## Configuration

### Default Backup Targets

Based on analysis of actual ISPConfig updates, the role monitors:

#### Mail Services

- `/etc/dovecot` - IMAP/POP3 configuration
- `/etc/postfix` - SMTP configuration and MySQL integration
- `/etc/rspamd` - Anti-spam configuration

#### Web Services

- `/etc/apache2` - Web server and virtual host configuration

#### DNS Services

- `/etc/bind` - DNS server configuration (optional)

#### Security/Monitoring

- `/etc/jailkit` - Chroot environment configuration
- `/etc/awstats` - Web statistics configuration
- `/etc/awffull` - Log analysis configuration
- Individual config files for various security tools

### Customization

```yaml
# Enable/disable optional components
ispconfig_backup_include_bind: true
ispconfig_backup_include_php: false

# Add custom targets
ispconfig_backup_targets:
  - name: "custom_service"
    path: "/etc/custom"
    type: "directory"
    exclude_patterns: ["*.log", "*~"]
```

### Git Configuration

```yaml
ispconfig_backup_git:
  enabled: yes
  repository_path: "/opt/solti-repo/ispconfig-backup"
  commit_msg: "Configuration backup on {{ ansible_date_time.iso8601 }}"
  manage_repository: yes
```

### Audit Options

```yaml
# Show detailed file differences
ispconfig_audit_show_differences: true

# Output format
ispconfig_audit_format: "summary"  # summary|detailed|json
```

## Repository Structure

```
/opt/solti-repo/ispconfig-backup/
├── configs/                    # Actual configuration files
│   ├── dovecot/               # /etc/dovecot backup
│   ├── postfix/               # /etc/postfix backup
│   ├── apache2/               # /etc/apache2 backup
│   └── ...
├── fingerprints/              # SHA256 checksums
│   ├── dovecot.fingerprints
│   ├── postfix.fingerprints
│   └── ...
├── BACKUP_MANIFEST.md         # Backup documentation
└── LAST_AUDIT_REPORT.md      # Latest audit results
```

## Role Variables

### Required Variables

```yaml
# Git repository configuration
ispconfig_backup_git:
  repository_path: "/opt/solti-repo/ispconfig-backup"
```

### Optional Variables

```yaml
# Role behavior
ispconfig_backup_state: present           # present|absent

# Audit behavior
ispconfig_audit_show_differences: false   # Show file diffs
ispconfig_audit_format: "summary"         # Output format

# Optional components
ispconfig_backup_include_bind: true       # Include BIND DNS
ispconfig_backup_include_php: false       # Include PHP configs
```

## Usage Examples

### Backup Only

```yaml
- hosts: ispconfig_servers
  roles:
    - role: ispconfig_backup
      vars:
        ispconfig_backup_state: present
```

### Audit with Differences

```yaml
- hosts: ispconfig_servers
  tasks:
    - include_role:
        name: jackaltx.solti_ensemble.ispconfig_backup
        tasks_from: audit.yml
        vars:
          ispconfig_audit_show_differences: true
```

### Custom Backup Targets

```yaml
- hosts: ispconfig_servers
  roles:
    - role: ispconfig_backup
      vars:
        ispconfig_backup_targets:
          - name: "dovecot"
            path: "/etc/dovecot"
            type: "directory"
            exclude_patterns: ["*.log", "*~"]
          - name: "custom_app"
            path: "/etc/myapp"
            type: "directory"
```

## Audit Output Examples

### Summary View

```
==========================================
ISPConfig Configuration Audit Summary
==========================================
Total targets: 12
Changed: 3
Unchanged: 8
Missing backup: 1
Missing source: 0
==========================================

dovecot: UNCHANGED
postfix: CHANGED (2 new, 5 modified, 0 deleted)
apache2: CHANGED (0 new, 1 modified, 0 deleted)
rspamd: UNCHANGED
```

### With Differences

```
==========================================
Differences for postfix:
==========================================
--- /opt/solti-repo/ispconfig-backup/configs/postfix/main.cf
+++ /etc/postfix/main.cf
@@ -15,7 +15,7 @@
-smtpd_banner = $myhostname ESMTP $mail_name
+smtpd_banner = $myhostname ESMTP $mail_name (Ubuntu)
```

## Integration with ISPConfig Updates

### Recommended Workflow

1. **Pre-Update Check**

   ```yaml
   - include_role:
       name: jackaltx.solti_ensemble.ispconfig_backup
       tasks_from: audit.yml
   ```

2. **Take Snapshot**

   ```yaml
   - include_role:
       name: jackaltx.solti_ensemble.ispconfig_backup
   ```

3. **Perform Update**

   ```bash
   # Run your ISPConfig update process
   ```

4. **Post-Update Analysis**

   ```yaml
   - include_role:
       name: jackaltx.solti_ensemble.ispconfig_backup
       tasks_from: audit.yml
       vars:
         ispconfig_audit_show_differences: true
   ```

5. **Update Baseline** (if changes are expected)

   ```yaml
   - include_role:
       name: jackaltx.solti_ensemble.ispconfig_backup
   ```

## File Exclusions

The role automatically excludes common temporary and log files:

- `*~` - Editor backup files
- `*.tmp` - Temporary files
- `*.log` - Log files
- `*.lock` - Lock files
- Service-specific patterns (sessions, cache, etc.)

## Requirements

- **Git** installed on target systems
- **rsync** for efficient directory copying
- **Ansible 2.9+**
- **Root access** on target systems

## Dependencies

This role integrates with the shared git versioning tasks:

- `shared/git/git_versioning_pre.yml`
- `shared/git/git_versioning_post.yml`

## File Structure

```
ispconfig_backup/
├── defaults/
│   └── main.yml                    # Default variables
├── tasks/
│   ├── main.yml                   # Main task routing
│   ├── backup.yml                 # Backup operations
│   ├── audit.yml                  # Audit operations
│   ├── process_backup_target.yml  # Individual backup processing
│   ├── process_audit_target.yml   # Individual audit processing
│   └── remove.yml                 # Cleanup operations
├── templates/
│   ├── backup_manifest.j2         # Backup documentation
│   └── audit_report.j2           # Audit report template
└── README.md                      # This file
```

## Troubleshooting

### Common Issues

1. **Permission Denied**
   - Ensure ansible user has sudo access
   - Check file permissions on backup repository

2. **Git Repository Issues**
   - Verify git is installed: `which git`
   - Check repository initialization in shared tasks

3. **Missing Fingerprints**
   - Run backup before audit: `ansible-playbook site.yml --tags ispconfig_backup`

### Debug Mode

```bash
# Enable verbose output
ansible-playbook site.yml --tags ispconfig_audit -vv
```

## License

BSD

## Author Information

Originally inspired by the fail2ban role git-versioning pattern. Extended for comprehensive ISPConfig environment monitoring.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Test with your ISPConfig environment
4. Submit a pull request

---

*This role provides the building blocks to monitor any configuration stack with human intelligence to decide what matters during incidents.*
