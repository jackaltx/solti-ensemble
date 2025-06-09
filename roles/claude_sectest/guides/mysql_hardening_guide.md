# MySQL/MariaDB Security Hardening Analysis Guide

## Overview
This guide provides comprehensive MySQL/MariaDB security assessment criteria for analyzing database configurations, particularly in ISPConfig and hosting environments.

---

## 1. User Account Security

### Critical Security Controls
- **Anonymous Users**: Must be completely removed
  - `SELECT User,Host FROM mysql.user WHERE User='';` should return 0 rows
  - **Risk Level**: CRITICAL if present

- **Root Remote Access**: Should be localhost-only
  - `SELECT User,Host FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');` should return 0 rows
  - **Risk Level**: CRITICAL if remote root exists

- **Test Database**: Should be removed
  - `SELECT SCHEMA_NAME FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='test';` should return 0 rows
  - **Risk Level**: HIGH if present

### Advanced User Security
- **Empty Password Accounts**: `SELECT User,Host FROM mysql.user WHERE Password='';`
- **Privilege Escalation**: Check for users with ALL PRIVILEGES
- **Application User Privileges**: Principle of least privilege enforcement

---

## 2. Network Security & Binding

### ISPConfig Specific Considerations
- **Default ISPConfig Behavior**: Binds to all interfaces (0.0.0.0:3306)
- **Cluster Requirements**: Multi-server setups may require network access
- **Single Server Setup**: Should bind to localhost only

### Network Security Assessment
```sql
-- Check current binding
SHOW VARIABLES LIKE 'bind_address';
SHOW VARIABLES LIKE 'port';
```

### Configuration Analysis
- **Localhost-Only Binding**: `bind-address = 127.0.0.1`
  - **Risk Level**: LOW
  - **Use Case**: Single-server ISPConfig installations

- **All Interface Binding**: `bind-address = 0.0.0.0` or not set
  - **Risk Level**: HIGH without SSL/TLS
  - **Risk Level**: MEDIUM with proper SSL/TLS + firewall
  - **Use Case**: ISPConfig clusters, multi-server environments

- **Skip Networking**: `skip-networking = 1`
  - **Risk Level**: LOWEST (Unix sockets only)
  - **Use Case**: Single-server with no network DB access needed

---

## 3. SSL/TLS Encryption (Critical Gap in Basic Hardening)

### SSL Status Assessment
```sql
SHOW VARIABLES LIKE 'have_ssl';
SHOW VARIABLES LIKE 'ssl_%';
SHOW STATUS LIKE 'Ssl_%';
```

### SSL Configuration Levels

#### Level 1: SSL Available but Optional
```ini
[mysqld]
ssl-ca=/etc/mysql/ssl/ca-cert.pem
ssl-cert=/etc/mysql/ssl/server-cert.pem
ssl-key=/etc/mysql/ssl/server-key.pem
```
- **Risk Level**: MEDIUM (encryption available but not enforced)

#### Level 2: SSL Required for All Connections
```ini
[mysqld]
require_secure_transport=ON
ssl-ca=/etc/mysql/ssl/ca-cert.pem
ssl-cert=/etc/mysql/ssl/server-cert.pem
ssl-key=/etc/mysql/ssl/server-key.pem
```
- **Risk Level**: LOW (all connections encrypted)

#### Level 3: SSL Required with Client Certificates
```sql
-- Per-user SSL requirements
GRANT ALL ON *.* TO 'user'@'%' REQUIRE SSL;
GRANT ALL ON *.* TO 'user'@'%' REQUIRE X509;
```
- **Risk Level**: LOWEST (mutual authentication)

### SSL Analysis Commands
```sql
-- Check user SSL requirements
SELECT User, Host, ssl_type FROM mysql.user WHERE ssl_type != '';

-- Check current connection encryption
SHOW STATUS LIKE 'Ssl_cipher';
```

---

## 4. Configuration Hardening (From ansible-mysql-hardening Role)

### Core Security Settings
```ini
[mysqld]
# Prevent unauthorized user creation
safe-user-create = 1

# Enforce secure password hashing
secure-auth = 1

# Prevent symbolic link attacks
skip-symbolic-links = 1

# Disable dangerous file operations
local-infile = 0

# Block suspicious user-defined functions
allow-suspicious-udfs = 0

# Require explicit stored procedure privileges
automatic-sp-privileges = 0

# Restrict file operations to safe location
secure-file-priv = /tmp

# Hide database names from unauthorized users
skip-show-database
```

### Advanced Configuration Options
```ini
[mysqld]
# Connection and resource limits
max_connections = 100
max_user_connections = 50
connect_timeout = 10
wait_timeout = 300
interactive_timeout = 300

# Logging for security monitoring
log-error = /var/log/mysql/error.log
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow.log
log_queries_not_using_indexes = 1

# Binary logging with retention
log-bin = /var/log/mysql/mysql-bin.log
expire_logs_days = 10
```

---

## 5. File System Security

### Critical File Permissions
- **Configuration Files**: 640 (root:mysql)
  - `/etc/mysql/my.cnf`
  - `/etc/mysql/conf.d/*.cnf`
  - `/etc/mysql/mariadb.conf.d/*.cnf`

- **Data Directory**: 750 (mysql:mysql)
  - Default: `/var/lib/mysql`
  - Must be owned by mysql user/group

- **Log Files**: 640 (mysql:adm or mysql:mysql)
  - Error log, slow query log, binary logs

- **SSL Certificates**: 600 (mysql:mysql)
  - Private keys must be readable only by mysql user

### ISPConfig Specific Paths
- Check `/usr/local/ispconfig` permissions
- Verify ISPConfig database user file permissions
- Ensure ISPConfig backup directories are secure

---

## 6. Information Disclosure Prevention

### Version Information
```sql
-- Check version exposure
SELECT @@version;
SELECT @@version_comment;
```

### Error Message Control
```ini
[mysqld]
# Limit error information in logs
log_error_verbosity = 2

# Control general query logging (security vs. debugging trade-off)
general_log = 0
```

---

## 7. ISPConfig-Specific Security Considerations

### Multi-Server Setups
- **Database Clustering**: Requires network binding
- **Master-Slave Replication**: SSL encryption essential
- **ISPConfig Panel Access**: Separate from client databases

### Single-Server Setups
- **Localhost Binding**: Recommended for security
- **Unix Socket Priority**: Faster and more secure
- **Firewall Integration**: Block 3306 from external access

### Configuration Recommendations by Setup Type

#### ISPConfig Single Server (Recommended)
```ini
[mysqld]
bind-address = 127.0.0.1
skip-networking = 0
socket = /var/run/mysqld/mysqld.sock
```

#### ISPConfig Multi-Server (Requires Network Access)
```ini
[mysqld]
bind-address = 0.0.0.0
require_secure_transport = ON
ssl-ca = /etc/mysql/ssl/ca-cert.pem
ssl-cert = /etc/mysql/ssl/server-cert.pem
ssl-key = /etc/mysql/ssl/server-key.pem
```

---

## 8. Security Analysis Framework

### Risk Assessment Matrix

| Configuration | Localhost Only | Network + SSL | Network No SSL |
|---------------|----------------|---------------|----------------|
| **Risk Level** | LOW | MEDIUM | CRITICAL |
| **Use Case** | Single server | Multi-server | Never recommended |
| **Required Controls** | Basic hardening | SSL + Firewall | Immediate remediation |

### Critical Security Checks
1. **Anonymous users present** → CRITICAL
2. **Remote root access** → CRITICAL  
3. **Network binding without SSL** → CRITICAL
4. **Test database exists** → HIGH
5. **Weak file permissions** → HIGH
6. **Information disclosure** → MEDIUM
7. **Missing security options** → LOW-MEDIUM

### Analysis Decision Tree
```
Network Binding Check:
├── bind-address = 127.0.0.1 or localhost → LOW RISK
├── bind-address = 0.0.0.0 or missing
    ├── SSL/TLS enabled → MEDIUM RISK
    └── SSL/TLS disabled → CRITICAL RISK
```

---

## 9. Remediation Commands

### Immediate Critical Fixes
```sql
-- Remove anonymous users
DELETE FROM mysql.user WHERE User='';

-- Remove remote root
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');

-- Remove test database
DROP DATABASE IF EXISTS test;

-- Flush privileges
FLUSH PRIVILEGES;
```

### SSL Setup Commands
```bash
# Generate SSL certificates
mysql_ssl_rsa_setup --uid=mysql

# Or manual certificate generation
openssl req -newkey rsa:2048 -days 3600 -nodes -keyout server-key.pem -out server-req.pem
openssl rsa -in server-key.pem -out server-key.pem
openssl x509 -req -in server-req.pem -days 3600 -CA ca-cert.pem -CAkey ca-key.pem -set_serial 01 -out server-cert.pem
```

### Configuration Hardening
```bash
# Apply hardening configuration
cat > /etc/mysql/conf.d/security.cnf << EOF
[mysqld]
safe-user-create = 1
secure-auth = 1
skip-symbolic-links = 1
local-infile = 0
allow-suspicious-udfs = 0
automatic-sp-privileges = 0
secure-file-priv = /tmp
skip-show-database
EOF

systemctl restart mysql
```

---

## 10. Monitoring and Compliance

### Security Monitoring Queries
```sql
-- Check for privilege escalation attempts
SELECT * FROM mysql.user WHERE Super_priv='Y' AND User != 'root';

-- Monitor failed login attempts
SHOW STATUS LIKE 'Aborted_%';

-- Check SSL usage
SHOW STATUS LIKE 'Ssl_accepts';
SHOW STATUS LIKE 'Ssl_finished_accepts';
```

### Compliance Frameworks
- **PCI DSS**: Requires encryption for cardholder data
- **HIPAA**: Mandates encryption in transit and at rest
- **SOC 2**: Database security controls required
- **CIS Benchmarks**: MySQL/MariaDB security guidelines

---

## Analysis Usage Notes

This guide should be used to:
1. **Assess Current State**: Compare audit results against these criteria
2. **Identify Risk Levels**: Use the risk matrix for prioritization
3. **Generate Recommendations**: Provide specific remediation steps
4. **ISPConfig Context**: Consider clustering vs single-server requirements
5. **SSL Gap Analysis**: Specifically flag missing encryption for network-bound databases

**Critical Warning Pattern**: Any network-bound MySQL without SSL/TLS should trigger immediate high-priority recommendations in security analysis.