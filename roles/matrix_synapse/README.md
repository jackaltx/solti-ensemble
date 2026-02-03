# Matrix Synapse Role

Ansible role for installing and configuring [Matrix Synapse](https://element-hq.github.io/synapse/) - an open-source Matrix homeserver implementation written in Python.

## Overview

This role provides a production-ready Matrix Synapse installation with:

- Automated installation from official Matrix.org repositories
- Configurable database backend (SQLite or PostgreSQL)
- Support for reverse proxy deployments
- Admin user creation
- Federation support
- Secure credential handling

## Requirements

- Ansible 2.15 or higher
- Debian 12 (Bookworm), Debian 13 (Trixie), or Ubuntu 22.04/24.04
- Root/sudo access on target hosts

## Role Variables

### Server Configuration

```yaml
# The domain name of your Matrix server (used in user IDs)
matrix_server_name: "{{ ansible_fqdn }}"

# Public base URL (for federation and clients)
matrix_public_baseurl: "https://{{ matrix_server_name }}"
```

### Network Configuration

```yaml
# Listening addresses
matrix_bind_addresses:
  - "0.0.0.0"
  - "::1"

# HTTP port (default: 8008)
matrix_port: 8008

# TLS configuration (disable if behind reverse proxy)
matrix_enable_tls: false
matrix_use_x_forwarded: true  # Enable when behind reverse proxy
```

### Database Configuration

```yaml
# SQLite (default, good for testing/small deployments)
matrix_database_type: sqlite3
matrix_database_path: /var/lib/matrix-synapse/homeserver.db

# PostgreSQL (recommended for production)
# matrix_database_type: psycopg2
# matrix_database_host: localhost
# matrix_database_port: 5432
# matrix_database_name: synapse
# matrix_database_user: synapse_user
# matrix_database_password: changeme
```

### Registration & Security

```yaml
# User registration
matrix_enable_registration: false
matrix_enable_registration_without_verification: true

# Shared secret for registration (auto-generated if empty)
matrix_registration_shared_secret: ""
```

### Admin User Creation

```yaml
# Create admin user on first run
matrix_create_admin: false
matrix_admin_username: admin
matrix_admin_password: ""  # Required if matrix_create_admin is true
```

### Federation

```yaml
# Enable federation with other Matrix servers
matrix_enable_federation: true
matrix_trusted_key_servers:
  - server_name: matrix.org
```

### Media Storage

```yaml
matrix_media_store_path: /var/lib/matrix-synapse/media_store
matrix_max_upload_size: "50M"
```

### Service Management

```yaml
matrix_service_enabled: true
matrix_service_state: started
matrix_package_state: present  # Options: present, latest
```

## Dependencies

None.

## Example Playbook

### Basic Deployment (Behind Reverse Proxy)

```yaml
---
- name: Deploy Matrix Synapse
  hosts: matrix_servers
  become: true
  vars:
    matrix_server_name: matrix.example.com
    matrix_enable_tls: false  # Reverse proxy handles SSL
    matrix_use_x_forwarded: true
    matrix_database_type: sqlite3

    # Create admin user
    matrix_create_admin: true
    matrix_admin_username: admin
    matrix_admin_password: "{{ vault_matrix_admin_password }}"

  pre_tasks:
    - name: Ensure ansible temp directory exists with proper permissions
      become: true
      ansible.builtin.file:
        path: /tmp/ansible-tmp
        state: directory
        owner: root
        group: root
        mode: "0777"

  roles:
    - jackaltx.solti_ensemble.matrix_synapse
```

### Production Deployment with PostgreSQL

```yaml
---
- name: Deploy Matrix Synapse (Production)
  hosts: matrix_servers
  become: true
  vars:
    matrix_server_name: matrix.example.com

    # PostgreSQL backend
    matrix_database_type: psycopg2
    matrix_database_host: localhost
    matrix_database_name: synapse
    matrix_database_user: synapse_user
    matrix_database_password: "{{ vault_db_password }}"

    # Security settings
    matrix_enable_registration: false
    matrix_registration_shared_secret: "{{ vault_registration_secret }}"

    # Admin user
    matrix_create_admin: true
    matrix_admin_username: admin
    matrix_admin_password: "{{ vault_admin_password }}"

  pre_tasks:
    - name: Ensure ansible temp directory exists with proper permissions
      become: true
      ansible.builtin.file:
        path: /tmp/ansible-tmp
        state: directory
        owner: root
        group: root
        mode: "0777"

  roles:
    - jackaltx.solti_ensemble.matrix_synapse
```

## Architecture

### Typical Deployment

```
┌─────────────────┐
│  Internet       │
└────────┬────────┘
         │
┌────────▼────────────────┐
│ Reverse Proxy           │
│ (Apache/Nginx/Traefik)  │
│ Port 443 (HTTPS)        │
└────────┬────────────────┘
         │
┌────────▼────────────────┐
│ Matrix Synapse          │
│ Port 8008 (HTTP)        │
│ /var/lib/matrix-synapse │
└────────┬────────────────┘
         │
┌────────▼────────────────┐
│ Database                │
│ (SQLite or PostgreSQL)  │
└─────────────────────────┘
```

### Internal Access Pattern

For internal/LAN access without reverse proxy:

```yaml
# Configuration tuple [protocol, host, port]
matrix_internal:
  protocol: http
  host: 192.168.55.12  # or matrix.a0a0.org
  port: 8008
  base_url: "http://192.168.55.12:8008"
```

## Post-Installation

### Verify Installation

```bash
# Check service status
systemctl status matrix-synapse

# Test API endpoint
curl http://localhost:8008/_matrix/client/versions

# View logs
journalctl -u matrix-synapse -f
```

### Create Additional Users

```bash
# Using registration shared secret
register_new_matrix_user -c /etc/matrix-synapse/homeserver.yaml
```

### Federation Setup

For federation to work, you need:

1. **Reverse proxy** with SSL certificate
2. **DNS records**:
   - `matrix.example.com` → Your server IP
   - `_matrix._tcp.example.com` SRV record → `matrix.example.com:443`
3. **`.well-known` delegation** (optional but recommended)

## Reverse Proxy Configuration

### Nginx Example

```nginx
server {
    listen 443 ssl http2;
    server_name matrix.example.com;

    ssl_certificate /etc/ssl/certs/matrix.crt;
    ssl_certificate_key /etc/ssl/private/matrix.key;

    location /_matrix {
        proxy_pass http://localhost:8008;
        proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header Host $host;

        # Increase timeouts for long-polling
        proxy_read_timeout 600s;
    }
}
```

### Apache Example

```apache
<VirtualHost *:443>
    ServerName matrix.example.com

    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/matrix.crt
    SSLCertificateKeyFile /etc/ssl/private/matrix.key

    ProxyPreserveHost On
    ProxyPass /_matrix http://localhost:8008/_matrix
    ProxyPassReverse /_matrix http://localhost:8008/_matrix

    RequestHeader set X-Forwarded-Proto "https"
    RequestHeader set X-Forwarded-SSL "on"
</VirtualHost>
```

## Testing

The role includes molecule scenarios for testing. See [molecule/](molecule/) directory.

## Handlers

- `restart matrix-synapse`: Restart the Synapse service
- `reload matrix-synapse`: Reload service without full restart
- `validate matrix config`: Validate configuration before applying

## Tags

- `install`: Installation tasks only
- `packages`: Package management
- `config`: Configuration management
- `admin`: Admin user creation
- `users`: User management
- `service`: Service state management

## Security Considerations

1. **Credentials**: Use Ansible Vault for passwords and secrets
2. **Reverse Proxy**: Always use HTTPS for external access
3. **Registration**: Disable public registration in production
4. **Federation**: Carefully consider federation security implications
5. **Updates**: Regularly update Synapse (set `matrix_package_state: latest`)

## Troubleshooting

### Ansible playbook fails with "Permission denied" on /tmp/ansible-tmp

**Symptom**: Playbook fails with error like:
```
Failed to create remote module tmp path at dir /tmp/ansible-tmp
[Errno 13] Permission denied: '/tmp/ansible-tmp/ansible-moduletmp-...'
```

**Cause**: When using `become: true`, Ansible may create `/tmp/ansible-tmp` with restrictive permissions (0700), causing subsequent tasks to fail when switching between users or privilege levels.

**Solution**: Add this pre_task to your playbook (see examples above):
```yaml
pre_tasks:
  - name: Ensure ansible temp directory exists with proper permissions
    become: true
    ansible.builtin.file:
      path: /tmp/ansible-tmp
      state: directory
      owner: root
      group: root
      mode: "0777"
```

**Note**: This is now a standard pattern across all SOLTI playbooks.

### Service won't start

```bash
# Check configuration
/opt/venvs/matrix-synapse/bin/python -m synapse.app.homeserver \
  --config-path=/etc/matrix-synapse/homeserver.yaml \
  --config-path=/etc/matrix-synapse/conf.d/ --generate-keys

# Check logs
journalctl -u matrix-synapse -n 50
```

### Cannot change server_name

**Symptom**: Service fails to start with error:
```
Exception: Found users in database not native to matrix.example.com!
You cannot change a synapse server_name after it's been configured
```

**Cause**: Matrix Synapse does not allow changing `server_name` after users exist in the database.

**Solution**:
- For production: Start with correct `server_name` from the beginning
- For existing installations: Keep the existing `server_name`
- For migration: Export users, delete database, start fresh with new `server_name`

### Federation issues

```bash
# Test federation
curl https://matrix.org/_matrix/federation/v1/query/profile?user_id=@test:matrix.org

# Check your server is reachable
curl https://federationtester.matrix.org/api/report?server_name=example.com
```

## Integration with SOLTI Ecosystem

This role integrates with other SOLTI collections:

- **solti-monitoring**: Add metrics collection for Synapse
- **solti-ensemble.mariadb**: Use MariaDB instead of SQLite
- **solti-ensemble.fail2ban_config**: Protect against brute force attacks

## License

MIT-0 - Use freely for any purpose without restriction.

## Author

- **jackaltx** - Retired but not dead wet-ware dreamer
- **Claude AI** - AI-powered development assistant

## References

- [Synapse Documentation](https://element-hq.github.io/synapse/latest/)
- [Matrix Protocol Specification](https://spec.matrix.org/)
- [Federation Tester](https://federationtester.matrix.org/)
