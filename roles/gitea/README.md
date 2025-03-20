# Gitea Ansible Role

This role manages the installation and configuration of Gitea, a lightweight, self-hosted Git service.

## Overview

The role handles:
- Installation of Gitea package or binary
- Configuration of Gitea service
- User and database setup
- SSL configuration
- Complete lifecycle management (install, configure, remove)

## Requirements

### Platform Support
- Debian/Ubuntu systems (uses apt for package management)
- RedHat/Rocky Linux systems (uses dnf for package management)
- Systemd-based systems

### Prerequisites
- Systemd
- Database server (SQLite by default, can be configured for PostgreSQL or MySQL)
- Proper network connectivity for public access

## Role Variables

### Required Variables

```yaml
gitea_state: 'present'           # Use 'absent' to remove Gitea
gitea_db_type: 'sqlite3'         # Database type: 'sqlite3', 'mysql', 'postgres'
```

### Optional Variables

```yaml
# Installation control
gitea_version: '1.21.3'          # Gitea version to install
gitea_force_reload: false        # Force reinstallation

# Network configuration
gitea_http_domain: 'localhost'   # Domain name for Gitea
gitea_http_port: 3000            # HTTP port
gitea_http_addr: '0.0.0.0'       # Listen address
gitea_root_url: 'http://localhost:3000/'  # Public root URL

# SSL configuration
gitea_protocol: 'http'           # 'http' or 'https'
gitea_cert: ''                   # Path to SSL certificate
gitea_key: ''                    # Path to SSL private key

# User configuration
gitea_user: 'git'                # System user for Gitea
gitea_group: 'git'               # System group for Gitea
gitea_admin_user: 'gitea_admin'  # Admin username
gitea_admin_password: ''         # Admin password (auto-generated if empty)
gitea_admin_email: 'admin@example.com'  # Admin email

# Registration configuration
gitea_disable_registration: true   # Disable user registration
gitea_require_signin: true         # Require signin to view repositories

# Database configuration
gitea_db_host: 'localhost'       # Database host (for MySQL/PostgreSQL)
gitea_db_name: 'gitea'           # Database name
gitea_db_user: 'gitea'           # Database user
gitea_db_password: ''            # Database password (auto-generated if empty)

# Path configuration
gitea_home_path: '/var/lib/gitea'  # Gitea home directory
gitea_data_path: '/var/lib/gitea/data'  # Gitea data directory
gitea_config_path: '/etc/gitea'   # Configuration directory
gitea_log_path: '/var/log/gitea'  # Log directory

# Cleanup options
gitea_delete_config: false        # Remove config files on uninstall
gitea_delete_data: false          # Remove data directory on uninstall
```

## Dependencies

This role has no direct dependencies on other Ansible roles.

## Example Playbook

Basic usage:

```yaml
- hosts: git_servers
  roles:
    - role: gitea
      vars:
        gitea_state: 'present'
        gitea_http_domain: 'git.example.com'
        gitea_root_url: 'https://git.example.com/'
        gitea_http_port: 3000
        gitea_disable_registration: true
```

Advanced configuration with MySQL:

```yaml
- hosts: git_servers
  roles:
    - role: gitea
      vars:
        gitea_state: 'present'
        gitea_http_domain: 'git.example.com'
        gitea_root_url: 'https://git.example.com/'
        gitea_protocol: 'http'  # Using HTTP as we'll have a reverse proxy
        gitea_http_port: 3000
        gitea_db_type: 'mysql'
        gitea_db_host: 'db.example.com'
        gitea_db_name: 'gitea_db'
        gitea_db_user: 'gitea_user'
        gitea_db_password: 'secure_password'
        gitea_disable_registration: true
        gitea_require_signin: true
```

Removal configuration:

```yaml
- hosts: git_servers
  roles:
    - role: gitea
      vars:
        gitea_state: 'absent'
        gitea_delete_config: true
        gitea_delete_data: false  # Keep data for backup
```

## File Structure

```
gitea/
├── defaults/
│   └── main.yml              # Default variables
├── handlers/
│   └── main.yml             # Service handlers
├── tasks/
│   ├── configure.yml       # Configuration tasks
│   ├── install.yml         # Installation tasks
│   ├── main.yml           # Main tasks
│   └── remove.yml         # Removal tasks
├── templates/
│   ├── app.ini.j2         # Main config template
│   └── gitea.service.j2   # Systemd service template
└── vars/
    ├── Debian.yml         # Debian-specific variables
    └── RedHat.yml         # RedHat-specific variables
```

## Handlers

The role includes the following handlers:
- `restart gitea`: Restarts the Gitea service
- `reload systemd`: Reloads systemd daemon

## Security Considerations

- SSL configuration is optional but recommended for production use
- User registration is disabled by default
- Admin password is generated randomly if not specified
- Database password is generated randomly if not specified
- Proper file permissions are applied to sensitive files

## License

MIT

## Author Information

Created by Your Name.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## Notes

- The role automatically handles service restarts when configuration changes
- Supports both SQLite (default) and external databases (MySQL, PostgreSQL)
- Provides flexible SSL configuration options
- Includes comprehensive user management capabilities
