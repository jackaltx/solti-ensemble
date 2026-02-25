# Matrix-Specific Fail2ban Protection

## Overview

Matrix-specific fail2ban jails to protect Matrix homeservers from protocol abuse, authentication attacks, and federation spam that generic Apache jails don't catch.

## Files Added

- `files/filter.d/apache-matrix-abuse.conf` - Matrix protocol abuse detection
- `files/filter.d/apache-4xx-matrix.conf` - Stricter 4xx detection for Matrix
- `templates/jail.d/matrix.conf` - Matrix jail configuration template

## Detection Patterns

### apache-matrix-abuse

Catches Matrix-specific attack patterns:

1. **Authentication Abuse**
   - 401 errors on `/_matrix/client/*/login`
   - 403 errors on `/_matrix/client/*/register`
   - 429 rate limit errors on auth endpoints

2. **Federation Abuse**
   - 4xx errors on `/_matrix/federation/*`
   - Federation endpoint scanning

3. **Media Upload Spam**
   - 413 (payload too large) on `/_matrix/media/*/upload`
   - 429 (rate limit) on media endpoints
   - 404 errors on media requests (scanning)

4. **Room/API Abuse**
   - 429 errors on `createRoom` or `join` endpoints
   - Repeated errors on Matrix API paths

### apache-4xx-matrix

Stricter 4xx detection specifically for Matrix:
- **Threshold**: 3 failures (vs 6 for generic apache-4xx)
- **Rationale**: Legitimate Matrix clients shouldn't hit 404s

## Usage

### Enable for Matrix Homeserver

In your playbook or inventory:

```yaml
# Enable Matrix-specific protection
fail2ban_matrix_abuse_enabled: true
fail2ban_matrix_4xx_enabled: true

# Optional: Customize log path
fail2ban_matrix_logpath: /var/log/ispconfig/httpd/matrix.jackaltx.com/access.log

# Optional: Tune thresholds
fail2ban_matrix_abuse_maxretry: 10   # Default: 10 failures in 5m
fail2ban_matrix_4xx_maxretry: 3      # Default: 3 failures in 5m

# Optional: Adjust ban times
fail2ban_matrix_abuse_bantime: 1h    # Default: 1 hour
fail2ban_matrix_4xx_bantime: 1h      # Default: 1 hour
```

### Example Playbook

```yaml
---
- name: Deploy Matrix-specific fail2ban protection
  hosts: fleur.lavnet.net
  become: true
  
  vars:
    fail2ban_state: configure
    fail2ban_jail_profile: ispconfig
    
    # Enable Matrix protection
    fail2ban_matrix_abuse_enabled: true
    fail2ban_matrix_4xx_enabled: true
    fail2ban_matrix_logpath: /var/log/ispconfig/httpd/matrix.jackaltx.com/access.log
  
  roles:
    - jackaltx.solti_ensemble.fail2ban_config
```

### Verify Deployment

```bash
# Check jails are active
sudo fail2ban-client status | grep matrix

# View jail status
sudo fail2ban-client status apache-matrix-abuse
sudo fail2ban-client status apache-4xx-matrix

# Test filter against logs
sudo fail2ban-regex /var/log/ispconfig/httpd/matrix.jackaltx.com/access.log \
  /etc/fail2ban/filter.d/apache-matrix-abuse.conf

# Monitor in real-time
sudo tail -f /var/log/fail2ban.log | grep matrix
```

## Default Settings

| Setting | apache-matrix-abuse | apache-4xx-matrix |
|---------|---------------------|-------------------|
| maxretry | 10 | 3 |
| findtime | 5m | 5m |
| bantime | 1h | 1h |
| AbuseIPDB Category | 18 (Brute Force) | 21 (Web App Attack) |

## Integration with Monitoring

The jails automatically:
- Report to AbuseIPDB when enabled
- Log to systemd journal (picked up by Grafana Alloy)
- Work with existing fail2ban → Loki → Grafana pipeline

Query in Grafana/Loki:
```logql
{service_type="fail2ban"} 
| regexp `\[(?P<jail>[^\]]+)\]\s+(?P<action>Ban|Unban)\s+(?P<banned_ip>\d+\.\d+\.\d+\.\d+)` 
| jail =~ ".*matrix.*"
```

## Whitelisting

If your IP is whitelisted in `/etc/fail2ban/jail.local`:

```ini
ignoreip = 127.0.0.1/8 ::1 YOUR.IP.ADDRESS.HERE
```

Testing won't trigger bans. Use a VPN or different network to test.

## Testing

From a non-whitelisted IP:

```bash
# Test 4xx jail (needs 3 x 404 in 5 minutes)
for i in {1..4}; do 
  curl -I https://matrix.jackaltx.com/test-scan-$i
  sleep 2
done

# Check if banned
ssh server "sudo fail2ban-client status apache-4xx-matrix"
```

## Troubleshooting

### Jail not starting

```bash
# Check config syntax
sudo fail2ban-client -t

# Check filter regex
sudo fail2ban-regex /path/to/log /etc/fail2ban/filter.d/apache-matrix-abuse.conf
```

### No matches in logs

- Verify log path is correct
- Check if logs contain Matrix requests
- Ensure Apache is logging to the specified path

### Too many false positives

Increase `maxretry` or `findtime`:

```yaml
fail2ban_matrix_4xx_maxretry: 5    # More lenient
fail2ban_matrix_4xx_findtime: 10m  # Longer window
```

