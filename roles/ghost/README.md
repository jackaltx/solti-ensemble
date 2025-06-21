# Ghost Ansible Role

This role installs and configures Ghost CMS, a modern publishing platform for blogs and websites.

## Overview

The role manages:

- Installation of Node.js and npm
- Ghost CMS installation and configuration
- Database setup (MySQL/MariaDB or SQLite)
- SSL/TLS configuration
- Service management via systemd
- User and directory management

## Requirements

### Platform Support

- Debian/Ubuntu systems (tested on Debian 12)
- Fedora/RHEL systems
- Systemd-based systems

### Prerequisites

- Systemd
- Database server (MySQL/MariaDB recommended, SQLite for development)
- Valid domain name for production
- SSL certificates (optional but recommended)

## Role Variables

### Required Variables

```yaml
ghost_site_url: "https://example.com"    # Public URL for Ghost site
ghost_admin_email: "admin@example.com"   # Admin user email
```

### Optional Variables

```yaml
# Installation control
ghost_state: 'present'                   # Use 'absent' to remove Ghost
ghost_version: 'latest'                  # Ghost version to install

# Directories and user
ghost_user: 'ghost'                      # System user for Ghost
ghost_group: 'ghost'                     # System group for Ghost
ghost_home: '/var/www/ghost'            # Ghost installation directory
ghost_content_dir: '/var/www/ghost/content'  # Content directory

# Database configuration
ghost_db_type: 'mysql'                  # Database type: mysql, sqlite3
ghost_db_host: 'localhost'              # Database host
ghost_db_port: 3306                     # Database port
ghost_db_name: 'ghost'                  # Database name
ghost_db_user: 'ghost'                  # Database user
ghost_db_password: ''                   # Database password

# SSL/TLS
ghost_ssl: false                         # Enable SSL
ghost_ssl_cert: ''                      # Path to SSL certificate
ghost_ssl_key: ''                       # Path to SSL private key

# Performance
ghost_memory_limit: '512m'              # Node.js memory limit

# Cleanup options (for removal)
ghost_delete_config: false              # Remove config files on uninstall
ghost_delete_data: false                # Remove data directory on uninstall
ghost_delete_database: false            # Remove database on uninstall
```

## File Structure

```
ghost/
├── defaults/
│   └── main.yml              # Default variables
├── files/
│   └── ghost.service.j2      # Systemd service template
├── handlers/
│   └── main.yml             # Service handlers
├── meta/
│   └── main.yml             # Role metadata
├── tasks/
│   ├── main.yml            # Main tasks
│   ├── nodejs.yml          # Node.js installation
│   ├── database.yml        # Database setup
│   ├── ghost.yml           # Ghost installation
│   └── service.yml         # Service configuration
├── templates/
│   ├── config.production.json.j2  # Ghost config template
│   └── ghost.service.j2           # Systemd service template
└── vars/
    └── main.yml           # Role variables
```

## Dependencies

This role has no direct dependencies but works well with:

- `mysql` or `mariadb` role for database setup
- `nginx` role for reverse proxy configuration

## Example Playbook

Basic usage:

```yaml
- hosts: ghost_servers
  roles:
    - role: ghost
      vars:
        ghost_site_url: "https://myblog.example.com"
        ghost_admin_email: "admin@example.com"
        ghost_db_password: "{{ vault_ghost_db_password }}"
```

Advanced configuration:

```yaml
- hosts: ghost_servers
  roles:
    - role: ghost
      vars:
        ghost_site_url: "https://myblog.example.com"
        ghost_admin_email: "admin@example.com"
        ghost_version: "5.75.0"
        ghost_db_type: "mysql"
        ghost_db_host: "db.example.com"
        ghost_db_password: "{{ vault_ghost_db_password }}"
        ghost_ssl: true
        ghost_ssl_cert: "/etc/ssl/certs/ghost.crt"
        ghost_ssl_key: "/etc/ssl/private/ghost.key"
        ghost_memory_limit: "1g"
```

## Handlers

The role includes the following handlers:

- `restart ghost`: Restarts the Ghost service
- `reload systemd`: Reloads systemd daemon configuration

## Security Considerations

- Creates dedicated system user for Ghost
- Configurable SSL/TLS support
- Database password protection
- File permissions management
- Service isolation via systemd

## License

BSD

## Author Information

Based on the collection structure by jackaltx and community contributions.

## Notes

- The role automatically handles Node.js version compatibility
- Supports both development (SQLite) and production (MySQL) configurations
- Includes Ghost CLI for management
- Provides migration support for existing installations
