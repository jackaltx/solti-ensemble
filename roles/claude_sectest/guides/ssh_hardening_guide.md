# SSH Security Analysis Enhancement Guide

**Purpose**: Companion document for ISPConfig security audits to ensure comprehensive SSH hardening analysis.

**Usage**: Upload this document alongside your `ispconfig-config.json` file when requesting security analysis from Claude.

---

## Critical SSH Hardening Gaps to Always Check

### 1. Authentication Controls
**Check audit JSON for**:
- `MaxAuthTries` setting (should be ≤ 3)
- `LoginGraceTime` setting (should be ≤ 30s)
- `MaxSessions` limit (should be ≤ 10)
- `MaxStartups` configuration

**If missing/weak, recommend**:
```bash
echo "MaxAuthTries 3" >> /etc/ssh/sshd_config
echo "LoginGraceTime 20" >> /etc/ssh/sshd_config
echo "MaxSessions 10" >> /etc/ssh/sshd_config
echo "MaxStartups 10:30:100" >> /etc/ssh/sshd_config
```

### 2. Network Binding Analysis
**Check audit JSON for**:
- `network_services.listening_services` array
- SSH port bindings (look for `0.0.0.0` vs specific IPs)
- Risk levels marked as "HIGH" for ALL_INTERFACES binding

**If SSH binds to all interfaces unnecessarily**:
```bash
# For localhost-only ISPConfig setups:
echo "ListenAddress 127.0.0.1" >> /etc/ssh/sshd_config
# OR for specific server IP:
echo "ListenAddress [SPECIFIC_IP]" >> /etc/ssh/sshd_config
```

### 3. Cryptographic Configuration
**Always check for**:
- Cipher suites in use
- MAC algorithms
- Key exchange methods
- Weak DH parameters

**Modern secure configuration**:
```bash
echo "Ciphers aes256-gcm@openssh.com,chacha20-poly1305@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr" >> /etc/ssh/sshd_config
echo "MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256" >> /etc/ssh/sshd_config
echo "KexAlgorithms curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256" >> /etc/ssh/sshd_config
```

### 4. Information Disclosure Prevention
**Check SSH config for**:
- Banner settings
- MOTD configuration
- Version disclosure settings
- Debian-specific banners

**Hardening commands**:
```bash
echo "PrintMotd no" >> /etc/ssh/sshd_config
echo "PrintLastLog no" >> /etc/ssh/sshd_config
echo "DebianBanner no" >> /etc/ssh/sshd_config  # Debian/Ubuntu only
```

### 5. Forwarding and Tunneling Controls
**Always evaluate need for**:
- TCP forwarding (`AllowTcpForwarding`)
- Agent forwarding (`AllowAgentForwarding`)
- X11 forwarding (`X11Forwarding`)
- Tunneling (`PermitTunnel`)

**Default secure stance**:
```bash
echo "AllowTcpForwarding no" >> /etc/ssh/sshd_config
echo "AllowAgentForwarding no" >> /etc/ssh/sshd_config
echo "X11Forwarding no" >> /etc/ssh/sshd_config
echo "PermitTunnel no" >> /etc/ssh/sshd_config
```

---

## SSH-Specific Analysis Framework

### Risk Assessment Questions
1. **Authentication Security**: Are brute force protections adequate?
2. **Network Exposure**: Is SSH unnecessarily exposed to all interfaces?
3. **Crypto Strength**: Are modern, secure algorithms in use?
4. **Session Management**: Are connection limits preventing DoS?
5. **Information Leakage**: Is SSH revealing unnecessary system information?
6. **Feature Surface**: Are unused/risky features disabled?

### Compliance Mapping
- **CIS SSH Benchmark**: Check against specific CIS controls
- **NIST Guidelines**: Align with NIST 800-53 AC/SC controls
- **OWASP**: Apply secure configuration principles

### Priority Classification
- **P0 (Critical)**: Authentication bypasses, crypto vulnerabilities
- **P1 (High)**: Information disclosure, network overexposure  
- **P2 (Medium)**: Session management, weak crypto
- **P3 (Low)**: Banner management, logging improvements

---

## Analysis Output Requirements

### Always Include in SSH Analysis:
1. **Current SSH Configuration Status**: What's configured vs. defaults
2. **Network Binding Assessment**: Interface exposure analysis
3. **Cryptographic Evaluation**: Algorithm strength assessment
4. **Attack Surface Review**: Enabled features vs. necessity
5. **Specific Remediation Commands**: Ready-to-execute fixes
6. **Risk Quantification**: Before/after security posture

### Integration with Overall Security Assessment:
- Cross-reference SSH findings with database, web server, and mail security
- Identify configuration patterns (e.g., consistent security approach vs. gaps)
- Prioritize fixes based on attack chain implications

---

## Commands for Manual Verification

```bash
# Check current SSH configuration
sudo sshd -T | grep -E "(MaxAuthTries|LoginGraceTime|MaxSessions|MaxStartups|AllowTcp|AllowAgent|X11Forward)"

# Verify network bindings
ss -tlnp | grep :22

# Check crypto configuration  
sudo sshd -T | grep -E "(Ciphers|MACs|KexAlgorithms)"

# Review DH parameters
awk '$5 < 2048' /etc/ssh/moduli | wc -l

# Test configuration validity
sudo sshd -t
```

---

## Version-Specific Considerations

Include OpenSSH version analysis:
- **< 6.0**: Limited cipher support, require basic hardening
- **6.0-6.6**: Moderate crypto options, focus on available algorithms  
- **6.7+**: Full modern crypto support, implement comprehensive hardening
- **7.0+**: Advanced features available (AuthenticationMethods, etc.)
- **8.0+**: Latest algorithms (sntrup4591761x25519-sha512, etc.)

---

**Usage Note**: This document should be referenced in every SSH security analysis to ensure comprehensive coverage beyond basic configuration review. Focus on practical, implementable improvements with measurable security impact.