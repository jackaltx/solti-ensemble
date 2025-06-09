# vs_code

An Ansible role that installs Visual Studio Code on Red Hat-based Linux distributions (RHEL, CentOS, Fedora, Rocky Linux, AlmaLinux).

## Description

This role automates the installation of Microsoft Visual Studio Code by:

- Adding Microsoft's official repository and GPG key
- Installing the latest version of VS Code from the official repository
- Ensuring the system package cache is updated

## Requirements

- Ansible 2.1 or higher
- Target systems running Red Hat-based distributions (RHEL, CentOS, Fedora, Rocky Linux, AlmaLinux)
- Internet connectivity to download packages from Microsoft's repository
- `dnf` package manager (standard on modern Red Hat-based systems)

## Role Variables

This role currently uses no configurable variables. It installs the latest available version of VS Code from Microsoft's official repository.

## Dependencies

None.

## Example Playbook

### Basic Usage

```yaml
---
- hosts: workstations
  become: yes
  roles:
    - vs_code
```

### Installing on Multiple Host Groups

```yaml
---
- hosts: developers
  become: yes
  roles:
    - vs_code

- hosts: testing_machines
  become: yes
  roles:
    - vs_code
```

### Combined with Other Development Tools

```yaml
---
- hosts: dev_workstations
  become: yes
  roles:
    - git_config
    - nodejs
    - vs_code
    - docker
```

## What This Role Does

1. **Imports Microsoft GPG Key**: Adds Microsoft's official GPG key for package verification
2. **Sets Up Repository**: Installs the VS Code repository configuration file
3. **Installs VS Code**: Uses dnf to install the latest version of Visual Studio Code
4. **Updates Package Cache**: Ensures the latest package information is available

## Files Created

- `/etc/yum.repos.d/vscode.repo` - Repository configuration file for VS Code updates

## Repository Configuration

The role configures the official Microsoft Visual Studio Code repository:

```ini
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
```

## Post-Installation

After the role completes:

- VS Code will be available in the system PATH as `code`
- Users can launch VS Code from the command line or application menu
- Future updates will be available through the system package manager (`dnf update`)

## Platform Support

**Supported Distributions:**

- Red Hat Enterprise Linux 8+
- CentOS 8+
- Rocky Linux 8+
- AlmaLinux 8+
- Fedora 32+

**Package Manager:**

- Uses `dnf` (modern replacement for `yum`)

## Testing

Test the role using the included test playbook:

```bash
cd tests/
ansible-playbook -i inventory test.yml
```

## Usage Notes

- **Root Privileges Required**: This role requires `become: yes` as it installs system packages
- **Internet Access**: Target machines need internet connectivity to download from Microsoft's repository
- **Automatic Updates**: Once installed, VS Code will receive updates through normal system updates
- **GPG Verification**: All packages are cryptographically verified using Microsoft's GPG key

## Common Use Cases

- **Developer Workstation Setup**: Automated provisioning of development environments
- **Lab Environment Configuration**: Setting up consistent coding environments for training
- **CI/CD Agent Preparation**: Installing VS Code on build agents for testing purposes
- **Classroom/Workshop Setup**: Rapid deployment across multiple student machines

## Security Features

- Uses official Microsoft repository (not third-party sources)
- GPG signature verification ensures package integrity
- Always installs the latest version with security updates

## License

BSD

## Author Information

Role for automated Visual Studio Code installation on Red Hat-based Linux systems.
