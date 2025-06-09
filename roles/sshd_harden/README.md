# sshd_harden

An Ansible role that hardens SSH daemon configuration according to security best practices and recommendations from sshaudit.com.

## Description

This role implements comprehensive SSH hardening by:

- Restricting cryptographic algorithms to secure, modern options
- Configuring connection timeouts and authentication limits
- Disabling potentially dangerous features like X11 forwarding and tunneling
- Generating secure SSH key pairs for the root user
- Filtering weak Diffie-Hellman moduli

## Requirements

- Ansible 2.1 or higher
- `community.crypto` collection for SSH key generation
- Target systems with OpenSSH server installed

## Role Variables

This role currently uses static configuration with no user-configurable variables. All hardening settings are applied through the included configuration file.

The following SSH settings are enforced:

**Connection Management:**

- `ClientAliveInterval`: 300 seconds
- `ClientAliveCountMax`: 2
- `LoginGraceTime`: 20 seconds
- `MaxAuthTries`: 3

**Security Restrictions:**

- `X11Forwarding`: disabled
- `AllowAgentForwarding`: disabled
- `AllowTcpForwarding`: disabled
- `PermitTunnel`: disabled
- `PermitRootLogin`: prohibit-password (key-based only)
- `PermitEmptyPasswords`: disabled

**Cryptographic Algorithms:**

- **Key Exchange**: curve25519-sha256, diffie-hellman-group16-sha512, diffie-hellman-group18-sha512
- **Ciphers**: <chacha20-poly1305@openssh.com>, <aes256-gcm@openssh.com>, <aes128-gcm@openssh.com>
- **MACs**: <hmac-sha2-256-etm@openssh.com>, <hmac-sha2-512-etm@openssh.com>
- **Host Key Algorithms**: ssh-ed25519, rsa-sha2-256, rsa-sha2-512

## Dependencies

- `community.crypto` collection

Install with:

```bash
ansible-galaxy collection install community.crypto
```

## Example Playbook

### Basic Usage

```yaml
---
- hosts: servers
  become: yes
  roles:
    - sshd_harden
```

### With Other Security Roles

```yaml
---
- hosts: servers
  become: yes
  roles:
    - firewall_config
    - sshd_harden
    - fail2ban
```

## What This Role Does

1. **Creates SSH Key Pairs**: Generates both RSA 4096-bit and ED25519 key pairs for the root user
2. **Applies Hardening Configuration**: Installs a comprehensive SSH configuration file at `/etc/ssh/sshd_config.d/01-solti.conf`
3. **Filters Weak DH Moduli**: Removes Diffie-Hellman moduli smaller than 3071 bits from `/etc/ssh/moduli`
4. **Validates Configuration**: Tests the SSH configuration before applying changes
5. **Restarts SSH Service**: Safely restarts the SSH daemon when configuration changes

## Security Features

- **Modern Cryptography Only**: Restricts SSH to use only secure, modern algorithms
- **Connection Limits**: Prevents brute force attacks with connection timeouts and attempt limits
- **Disabled Risky Features**: Turns off X11 forwarding, agent forwarding, and tunneling
- **Key-Based Root Access**: Allows root login only with SSH keys, not passwords
- **Weak Moduli Removal**: Eliminates weak Diffie-Hellman parameters

## Files Created/Modified

- `/root/.ssh/id_rsa` and `/root/.ssh/id_rsa.pub` - RSA key pair
- `/root/.ssh/id_ed25519` and `/root/.ssh/id_ed25519.pub` - ED25519 key pair
- `/etc/ssh/sshd_config.d/01-solti.conf` - SSH hardening configuration
- `/etc/ssh/moduli` - Filtered to remove weak DH parameters
- `/etc/ssh/moduli.filtered` - Marker file indicating moduli have been filtered

## Important Notes

- **Backup Created**: The role automatically backs up the original SSH configuration
- **Configuration Validation**: SSH configuration is tested before the service is restarted
- **Root Key Generation**: SSH keys are generated for root user - ensure you have alternative access methods
- **Service Restart**: The SSH service will be restarted when configuration changes are made

## Testing

Test the role using the included test playbook:

```bash
cd tests/
ansible-playbook -i inventory test.yml
```

## Compatibility

This role is designed to work with most Linux distributions that use systemd and OpenSSH. It has been tested on:

- Ubuntu 20.04+
- CentOS/RHEL 8+
- Debian 10+

## License

MIT-0

## Author Information

Created for SSH hardening based on security best practices and sshaudit.com recommendations.
