# ISPConfig Security Audit Role

**Version**: 1.1  
**Authors**: jackaltx & Claude AI  
**License**: MIT-0  

A comprehensive Ansible role for automated security auditing of ISPConfig3 servers. This role executes multiple specialized audit scripts to assess configuration security, database inventory, DNS records, and intrusion prevention systems.

## Overview

This role implements a "build small scripts, collect all for you" approach to security auditing. Rather than creating monolithic audit tools, we've developed focused scripts that each examine specific aspects of your ISPConfig installation:

- **Configuration Security**: System-level security settings
- **Database BOM (Bill of Materials)**: What ISPConfig thinks exists
- **DNS Security Records**: SPF, DKIM, DMARC, MX validation
- **Fail2Ban Analysis**: Intrusion prevention effectiveness

Each script maintains its own Git repository for change tracking and produces JSON output for professional analysis.

## Features

- **Git-based Change Tracking**: Every audit run is committed with timestamps
- **Retention Policies**: Configurable history retention for development vs production
- **Professional Analysis Ready**: JSON output optimized for Claude AI security analysis
- **Multi-Script Orchestration**: Run all audits with a single playbook
- **Automated Collection**: Results automatically fetched to your local machine

## Requirements

- **Target System**: Debian-based ISPConfig3 server
- **Privileges**: Root access required for comprehensive auditing
- **Dependencies**: Git (automatically installed)
- **Python**: python3-pymysql (for database BOM audit)

## Role Variables

### Core Configuration

```yaml
# Audit script to execute
audit_script_filename: ispconfig-audit.sh

# Remote audit directory (separate per script type)
audit_directory: /opt/audit/ispconfig-audit

# Local collection directory
audit_local_directory: ~/audit

# Output filename on remote system
audit_output_filename: ispconfig-config.json

# Filename root for local collection
audit_output_filename_root: ispconfig-config

# Development mode: limit Git history retention
audit_retention_commits: 0  # 0 = keep all (production), >0 = retain last N commits
```

### Script Execution Control

```yaml
# Display script output during execution
audit_show_output: true

# Execution method: 'script' (recommended) or 'copy_and_run'
audit_execution_method: script
```

## Available Audit Scripts

### 1. ISPConfig Configuration Audit (`ispconfig-audit.sh`)

Examines system-level security configuration:

- Apache/Nginx security settings
- MySQL/MariaDB hardening
- PHP security configuration
- SSH hardening analysis
- Mail server security
- Network service binding analysis

### 2. Database BOM Audit (`ispconfig-bom-audit.sh`)

Extracts comprehensive inventory from ISPConfig database:

- Web domains and virtual hosts
- Mail domains and users
- Database instances and users
- DNS zones and records
- Client configurations and limits
- Security relationship analysis

### 3. DNS Security Audit (`ispconfig-named-audit.sh`)

Validates email security DNS records:

- SPF record validation
- DKIM selector discovery
- DMARC policy analysis
- MX record verification
- Geographic and security analysis

### 4. Fail2Ban Security Audit (`fail2ban-audit.sh`)

Analyzes intrusion prevention effectiveness:

- Jail configuration assessment
- Ban statistics and trends
- Log analysis and attack patterns
- Service protection coverage
- Performance impact analysis

## Example Playbook

```yaml
---
- name: Comprehensive ISPConfig Security Audit
  hosts: ispconfig_servers
  become: true

  tasks:
    # Install Python MySQL library for BOM audit
    - name: Install Python MySQL library for BOM audit
      ansible.builtin.apt:
        name: python3-pymysql
        state: present

    # Configuration Security Audit
    - name: Run ISPConfig Configuration Security Audit
      ansible.builtin.include_role:
        name: jackaltx.solti_ensemble.claude_sectest
      vars:
        audit_directory: /opt/audit/ispconfig-audit
        audit_script_filename: ispconfig-audit.sh
        audit_retention_commits: 10
        audit_output_filename_root: ispconfig-config
        audit_output_filename: "{{ audit_output_filename_root }}.json"

    # Database BOM Audit
    - name: Run ISPConfig Database BOM Audit
      ansible.builtin.include_role:
        name: jackaltx.solti_ensemble.claude_sectest
      vars:
        audit_directory: /opt/audit/ispconfig-bom-audit
        audit_script_filename: ispconfig-bom-audit.sh
        audit_retention_commits: 10
        audit_output_filename_root: ispconfig-bom-config
        audit_output_filename: "{{ audit_output_filename_root }}.json"

    # DNS Security Audit
    - name: Run ISPConfig DNS Security Audit
      ansible.builtin.include_role:
        name: jackaltx.solti_ensemble.claude_sectest
      vars:
        audit_directory: /opt/audit/ispconfig-named-audit
        audit_script_filename: ispconfig-named-audit.sh
        audit_retention_commits: 10
        audit_output_filename_root: ispconfig-named-audit
        audit_output_filename: "{{ audit_output_filename_root }}.json"

    # Fail2Ban Security Audit
    - name: Run Fail2Ban Security Audit
      ansible.builtin.include_role:
        name: jackaltx.solti_ensemble.claude_sectest
      vars:
        audit_directory: /opt/audit/fail2ban-audit
        audit_script_filename: fail2ban-audit.sh
        audit_retention_commits: 10
        audit_output_filename_root: fail2ban-audit
        audit_output_filename: "{{ audit_output_filename_root }}.json"
```

## Design Philosophy: "Build Small Scripts, Collect All for You"

### The Original Challenge

The role began with a simple prompt found in `tasks/main.yml`:

> *"write a module to do the following: assume it will be run as root, copy the file: ispconfig-audit.sh to the remote in /usr/local/bin/ as executable. Run the script /usr/local/bin/ispconfig-audit.sh -d /opt/audit/ispconfig-audit, transfer the output from the remote at /opt/audit/ispconfig-audit/ispconfig-config.json to my local machine at "~/{{ ansible host }}-ispconfig-audit-{{ epoch time }}.json""*

### The Evolution

What started as a simple "copy script, run script, fetch results" requirement evolved into a comprehensive audit framework:

1. **Focused Scripts**: Each script tackles one specific domain (config, database, DNS, security)
2. **Consistent Interface**: All scripts share the same CLI options and output patterns
3. **Git Integration**: Every script maintains its own change history
4. **Professional Output**: JSON formatted for AI-powered security analysis

### Benefits of This Approach

- **Maintainability**: Small, focused scripts are easier to debug and enhance
- **Reusability**: Scripts can be run independently outside Ansible
- **Scalability**: New audit types can be added without modifying existing scripts
- **Analysis Ready**: Structured output enables automated security assessment

## Professional Security Analysis

### Using the Guides Directory

The `guides/` directory contains comprehensive analysis frameworks:

- **`ispconfig_audit_guide.md`**: Configuration security analysis criteria
- **`mysql_hardening_guide.md`**: Database security assessment framework
- **`fail2ban_audit_guide.md`**: Intrusion prevention analysis guidelines
- **`named_audit_guide.md`**: DNS security evaluation criteria

### Claude AI Integration

These guides are specifically designed to help Claude AI provide professional security analysis:

```markdown
Please analyze these ISPConfig audit results using the analysis frameworks 
in the guides directory. Focus on:

1. Critical security vulnerabilities requiring immediate action
2. Configuration best practices compliance
3. Industry standard alignment (CIS, NIST, PCI DSS)
4. Specific remediation commands with explanations

[Attach audit JSON files and relevant guide markdown]
```

### Sample Analysis Request

```
I've run comprehensive security audits on my ISPConfig3 server using the 
claude_sectest Ansible role. Please analyze these results and provide 
prioritized security recommendations.

Audit files included:
- ispconfig-config.json (system configuration security)
- ispconfig-bom-config.json (database inventory analysis)
- ispconfig-named-audit.json (DNS security records)
- fail2ban-audit.json (intrusion prevention analysis)

Please use the analysis frameworks from the guides directory to:
1. Identify critical security gaps requiring immediate attention
2. Provide specific configuration changes with exact commands
3. Assess compliance with security frameworks (CIS, NIST)
4. Recommend optimization opportunities

[Attach all JSON files and relevant guide markdown files]
```

## Output Management

### Local File Naming Convention

```
~/audit/
├── hostname-ispconfig-config-1733756789.json
├── hostname-ispconfig-bom-config-1733756823.json
├── hostname-ispconfig-named-audit-1733756845.json
└── hostname-fail2ban-audit-1733756867.json
```

### Remote Git Repositories

```
/opt/audit/
├── ispconfig-audit/          # Configuration audit history
├── ispconfig-bom-audit/      # Database BOM history  
├── ispconfig-named-audit/    # DNS security history
└── fail2ban-audit/           # Fail2Ban analysis history
```

## Development and Production Modes

### Development Mode

```yaml
audit_retention_commits: 20  # Keep last 20 audit runs
```

- Faster Git operations
- Reduced disk usage
- Good for testing and development

### Production Mode

```yaml
audit_retention_commits: 0   # Keep complete history
```

- Complete audit trail
- Compliance requirements
- Long-term trend analysis

## Dependencies

The role automatically handles most dependencies, but some require manual installation:

```yaml
- name: Install Python MySQL library for BOM audit
  ansible.builtin.apt:
    name: python3-pymysql
    state: present
```

## License

MIT-0 - Use freely for any purpose without restriction.

## Contributing

This role is part of an ongoing security research project. Contributions welcome:

1. **New Audit Scripts**: Following the established CLI pattern
2. **Analysis Guides**: Enhanced security analysis frameworks  
3. **Integration Examples**: Additional use cases and playbooks
4. **Performance Optimizations**: Faster execution or better resource usage

## Support

For issues, questions, or contributions:

- Review the `guides/` directory for analysis frameworks
- Check existing audit scripts in `files/` for patterns
- Test with development retention policies before production use

---

*This role demonstrates the power of combining focused automation (Ansible) with specialized security tools and AI-powered analysis for comprehensive infrastructure security assessment.*
