#!/bin/bash

# ISPConfig3 Configuration Security Baseline Audit Script
# Designed for localhost-only installations on Debian 12
# Output: JSON with Git-based change tracking and retention management

SCRIPT_VERSION="2.1"
AUDIT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
HOSTNAME=$(hostname)

# Default values
AUDIT_DIR=""
RETAIN_COMMITS=""
OUTPUT_FILENAME="ispconfig-config.json"

# Usage function
usage() {
    echo "Usage: $0 -d <audit_directory> [--retain <number>]"
    echo ""
    echo "Options:"
    echo "  -d <directory>    Directory to store audit reports (required)"
    echo "  --retain <number> Keep only the last N commits (optional, for development)"
    echo ""
    echo "Examples:"
    echo "  $0 -d /opt/audit/ispconfig-audit                    # Production mode (keep all history)"
    echo "  $0 -d /opt/audit/ispconfig-audit --retain 20       # Development mode (keep last 20 commits)"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d)
            AUDIT_DIR="$2"
            shift 2
            ;;
        --retain)
            RETAIN_COMMITS="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "ERROR: Unknown option $1" >&2
            usage
            ;;
    esac
done

# Validate required arguments
if [[ -z "$AUDIT_DIR" ]]; then
    echo "ERROR: Audit directory (-d) is required" >&2
    usage
fi

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo "ERROR: This script must be run as root" >&2
   exit 1
fi

# Setup audit directory and git repo
setup_audit_repo() {
    echo "Setting up audit repository at: $AUDIT_DIR"
    
    # Create directory if it doesn't exist
    mkdir -p "$AUDIT_DIR"
    cd "$AUDIT_DIR"
    
    # Initialize git repo if not exists
    if [[ ! -d ".git" ]]; then
        git init
        git config user.name "ISPConfig Audit"
        git config user.email "audit@$(hostname)"
        echo "Initialized new git repository for audit tracking"
    fi
}

# Apply retention policy
apply_retention() {
    if [[ -n "$RETAIN_COMMITS" ]]; then
        echo "Applying retention policy: keeping last $RETAIN_COMMITS commits"
        cd "$AUDIT_DIR"
        
        # Count current commits
        COMMIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo "0")
        
        if [[ $COMMIT_COUNT -gt $RETAIN_COMMITS ]]; then
            # Create orphan branch with recent history
            CUTOFF_COMMIT=$(git rev-list HEAD | sed -n "${RETAIN_COMMITS}p")
            
            # Create new branch from the cutoff point
            git checkout --orphan temp_branch "$CUTOFF_COMMIT"
            git commit -m "Retention policy: keeping last $RETAIN_COMMITS commits from $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
            
            # Replace main branch
            git branch -M temp_branch main 2>/dev/null || git branch -M temp_branch master
            
            # Cleanup
            git gc --aggressive --prune=all
            
            echo "Retention applied: pruned old commits, keeping last $RETAIN_COMMITS"
        else
            echo "Retention policy: $COMMIT_COUNT commits (under limit of $RETAIN_COMMITS)"
        fi
    fi
}

# Setup the audit repository
setup_audit_repo

OUTPUT_FILE="$AUDIT_DIR/$OUTPUT_FILENAME"

echo "Starting ISPConfig3 Configuration Security Audit..."
echo "Output file: $OUTPUT_FILE"

# Function to safely read file content and escape for JSON
read_config_file() {
    local file="$1"
    if [[ -r "$file" ]]; then
        # Read file, escape quotes and newlines for JSON
        sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' "$file" | tr -d '\n' | sed 's/\\n$//'
    else
        echo "file_not_readable"
    fi
}

# Function to extract specific config values
extract_config_value() {
    local file="$1"
    local pattern="$2"
    local default="$3"
    
    if [[ -r "$file" ]]; then
        grep -E "$pattern" "$file" | head -1 | awk '{print $2}' | sed 's/[";]//g' || echo "$default"
    else
        echo "$default"
    fi
}

# Initialize JSON
cat > "$OUTPUT_FILE" << EOF
{
  "audit_info": {
    "version": "$SCRIPT_VERSION",
    "date": "$AUDIT_DATE",
    "hostname": "$HOSTNAME",
    "purpose": "Configuration Security Baseline Audit",
    "audit_directory": "$AUDIT_DIR",
    "retention_policy": $([ -n "$RETAIN_COMMITS" ] && echo "\"Last $RETAIN_COMMITS commits\"" || echo "\"Keep all history\"")
  },
  "system_info": {
    "os_release": "$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)",
    "kernel": "$(uname -r)",
    "architecture": "$(uname -m)"
  },
EOF

# =======================================================================================
# =======================================================================================
# =======================================================================================


echo "Discovering Apache configuration..."
# Apache Configuration
if systemctl is-active apache2 >/dev/null 2>&1; then
    APACHE_MAIN_CONFIG="/etc/apache2/apache2.conf"
    
    cat >> "$OUTPUT_FILE" << EOF
  "apache_configuration": {
    "service_active": true,
    "main_config": {
      "file": "$APACHE_MAIN_CONFIG",
      "content": "$(read_config_file "$APACHE_MAIN_CONFIG")"
    },
    "key_settings": {
      "server_tokens": "$(extract_config_value "$APACHE_MAIN_CONFIG" "^ServerTokens" "default")",
      "server_signature": "$(extract_config_value "$APACHE_MAIN_CONFIG" "^ServerSignature" "default")",
      "timeout": "$(extract_config_value "$APACHE_MAIN_CONFIG" "^Timeout" "default")",
      "keep_alive": "$(extract_config_value "$APACHE_MAIN_CONFIG" "^KeepAlive" "default")",
      "max_keep_alive_requests": "$(extract_config_value "$APACHE_MAIN_CONFIG" "^MaxKeepAliveRequests" "default")"
    }
  },
EOF
else
    cat >> "$OUTPUT_FILE" << EOF
  "apache_configuration": {
    "service_active": false,
    "reason": "Apache2 service not running"
  },
EOF
fi

# =======================================================================================
# =======================================================================================
# =======================================================================================

echo "Discovering MySQL/MariaDB configuration..."
# MySQL/MariaDB Configuration
DB_SERVICE=""
if systemctl is-active mysql >/dev/null 2>&1; then
    DB_SERVICE="mysql"
elif systemctl is-active mariadb >/dev/null 2>&1; then
    DB_SERVICE="mariadb"
fi

if [[ -n "$DB_SERVICE" ]]; then
    # Find all MySQL config files
    MYSQL_CONFIGS=$(find /etc/mysql -name "*.cnf" 2>/dev/null | sort)
    
    cat >> "$OUTPUT_FILE" << EOF
  "database_configuration": {
    "service": "$DB_SERVICE",
    "service_active": true,
    "config_files": [
EOF
    
    first_db_config=true
    while IFS= read -r config_file; do
        [[ -z "$config_file" ]] && continue
        if [[ "$first_db_config" == true ]]; then
            first_db_config=false
        else
            echo "," >> "$OUTPUT_FILE"
        fi
        cat >> "$OUTPUT_FILE" << EOF
      {
        "file": "$config_file",
        "content": "$(read_config_file "$config_file")"
      }
EOF
    done <<< "$MYSQL_CONFIGS"
    
    # Find main config file for key settings
    MAIN_DB_CONFIG=""
    for config in "/etc/mysql/mariadb.conf.d/50-server.cnf" "/etc/mysql/mysql.conf.d/mysqld.cnf" "/etc/mysql/my.cnf"; do
        if [[ -f "$config" ]]; then
            MAIN_DB_CONFIG="$config"
            break
        fi
    done
    
    cat >> "$OUTPUT_FILE" << EOF
    ],
    "primary_config_file": "$MAIN_DB_CONFIG",
    "key_settings": {
      "bind_address": "$(extract_config_value "$MAIN_DB_CONFIG" "^bind-address" "not_set")",
      "port": "$(extract_config_value "$MAIN_DB_CONFIG" "^port" "3306")",
      "skip_networking": "$(extract_config_value "$MAIN_DB_CONFIG" "^skip-networking" "not_set")",
      "ssl": "$(extract_config_value "$MAIN_DB_CONFIG" "^ssl" "not_set")"
    },
    "security_analysis": {
      "anonymous_users_count": "$(mysql -e "SELECT COUNT(*) FROM mysql.user WHERE User='';" 2>/dev/null | tail -1 || echo 'check_failed')",
      "root_remote_access_count": "$(mysql -e "SELECT COUNT(*) FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');" 2>/dev/null | tail -1 || echo 'check_failed')",
      "test_database_exists": "$(mysql -e "SELECT COUNT(*) FROM information_schema.SCHEMATA WHERE SCHEMA_NAME='test';" 2>/dev/null | tail -1 || echo 'check_failed')",
      "version": "$(mysql -e "SELECT @@version;" 2>/dev/null | tail -1 || echo 'check_failed')",
      "have_ssl": "$(mysql -e "SELECT @@have_ssl;" 2>/dev/null | tail -1 || echo 'check_failed')",
      "local_infile": "$(mysql -e "SELECT @@local_infile;" 2>/dev/null | tail -1 || echo 'check_failed')"
    }
  },
EOF
else
    cat >> "$OUTPUT_FILE" << EOF
  "database_configuration": {
    "service_active": false,
    "reason": "No MySQL/MariaDB service running"
  },
EOF
fi


# =======================================================================================
# =======================================================================================
# =======================================================================================


echo "Discovering PHP configuration..."
# PHP Configuration - Updated to handle both Apache module and PHP-FPM
PHP_VERSION=$(php -v 2>/dev/null | head -1 | awk '{print $2}' | cut -d- -f1)
if [[ -n "$PHP_VERSION" ]]; then
    # Extract major.minor version for path
    PHP_MAJOR_MINOR=$(echo "$PHP_VERSION" | cut -d. -f1,2)
    PHP_INI_DIR="/etc/php/${PHP_MAJOR_MINOR}"
    PHP_CLI_INI="$PHP_INI_DIR/cli/php.ini"
    
    # Detect if using PHP-FPM or Apache module
    PHP_WEB_INI=""
    PHP_WEB_TYPE="unknown"
    
    # Check for PHP-FPM first (modern setups)
    if systemctl is-active php${PHP_MAJOR_MINOR}-fpm >/dev/null 2>&1; then
        PHP_WEB_INI="$PHP_INI_DIR/fpm/php.ini"
        PHP_WEB_TYPE="php-fpm"
    # Check for Apache module (traditional setups)
    elif [[ -f "$PHP_INI_DIR/apache2/php.ini" ]]; then
        PHP_WEB_INI="$PHP_INI_DIR/apache2/php.ini"
        PHP_WEB_TYPE="apache-module"
    fi
    
    cat >> "$OUTPUT_FILE" << EOF
  "php_configuration": {
    "version": "$PHP_VERSION",
    "web_server_integration": {
      "type": "$PHP_WEB_TYPE",
      "service_active": $([ "$PHP_WEB_TYPE" = "php-fpm" ] && systemctl is-active php${PHP_MAJOR_MINOR}-fpm >/dev/null 2>&1 && echo "true" || echo "false"),
      "config_file": "$PHP_WEB_INI",
      "exists": $([ -f "$PHP_WEB_INI" ] && echo "true" || echo "false"),
      "content": "$(read_config_file "$PHP_WEB_INI")"
    },
    "cli_config": {
      "file": "$PHP_CLI_INI", 
      "exists": $([ -f "$PHP_CLI_INI" ] && echo "true" || echo "false"),
      "content": "$(read_config_file "$PHP_CLI_INI")"
    },
    "key_settings": {
      "expose_php": "$(php -i 2>/dev/null | grep '^expose_php' | awk '{print $3}' || echo 'unknown')",
      "display_errors": "$(php -i 2>/dev/null | grep '^display_errors' | awk '{print $3}' || echo 'unknown')",
      "log_errors": "$(php -i 2>/dev/null | grep '^log_errors' | awk '{print $3}' || echo 'unknown')",
      "allow_url_fopen": "$(php -i 2>/dev/null | grep '^allow_url_fopen' | awk '{print $3}' || echo 'unknown')",
      "allow_url_include": "$(php -i 2>/dev/null | grep '^allow_url_include' | awk '{print $3}' || echo 'unknown')"
    },
    "fpm_analysis": {
      "pools_directory": "$PHP_INI_DIR/fpm/pool.d/",
      "pool_configs": [
$(find "$PHP_INI_DIR/fpm/pool.d/" -name "*.conf" -type f 2>/dev/null | sort | while IFS= read -r pool_file; do
    [[ -z "$pool_file" ]] && continue
    echo "        {"
    echo "          \"pool_file\": \"$pool_file\","
    echo "          \"content\": \"$(read_config_file "$pool_file")\""
    echo -n "        }"
    if [[ "$pool_file" != "$(find "$PHP_INI_DIR/fpm/pool.d/" -name "*.conf" -type f 2>/dev/null | sort | tail -1)" ]]; then
        echo ","
    else
        echo ""
    fi
done)
      ]
    }
  },
EOF
else
    cat >> "$OUTPUT_FILE" << EOF
  "php_configuration": {
    "installed": false,
    "reason": "PHP not found or not executable"
  },
EOF
fi

# =======================================================================================
# =======================================================================================
# =======================================================================================

echo "Discovering SSH configuration..."
# SSH Configuration - Using running config instead of just main file
SSH_CONFIG="/etc/ssh/sshd_config"

# Get the actual running SSH configuration
SSH_RUNNING_CONFIG=$(sshd -T 2>/dev/null)

# Function to extract value from sshd -T output
extract_sshd_value() {
    local directive="$1"
    local default="$2"
    
    if [[ -n "$SSH_RUNNING_CONFIG" ]]; then
        echo "$SSH_RUNNING_CONFIG" | grep -i "^$directive " | awk '{print $2}' | head -1 || echo "$default"
    else
        echo "$default"
    fi
}

# Find all SSH config files for documentation
SSH_CONFIG_FILES=$(find /etc/ssh -name "sshd_config*" -type f 2>/dev/null | sort)

cat >> "$OUTPUT_FILE" << EOF
  "ssh_configuration": {
    "main_config_file": "$SSH_CONFIG",
    "config_files_found": [
$(echo "$SSH_CONFIG_FILES" | while IFS= read -r config_file; do
    [[ -z "$config_file" ]] && continue
    echo "      \"$config_file\""
    if [[ "$config_file" != "$(echo "$SSH_CONFIG_FILES" | tail -1)" ]]; then
        echo ","
    fi
done)
    ],
    "running_config_analysis": {
      "method": "sshd -T",
      "config_accessible": $([ -n "$SSH_RUNNING_CONFIG" ] && echo "true" || echo "false")
    },
    "effective_settings": {
      "port": "$(extract_sshd_value "port" "22")",
      "permitrootlogin": "$(extract_sshd_value "permitrootlogin" "unknown")",
      "passwordauthentication": "$(extract_sshd_value "passwordauthentication" "unknown")",
      "pubkeyauthentication": "$(extract_sshd_value "pubkeyauthentication" "unknown")",
      "x11forwarding": "$(extract_sshd_value "x11forwarding" "unknown")",
      "allowagentforwarding": "$(extract_sshd_value "allowagentforwarding" "unknown")",
      "allowtcpforwarding": "$(extract_sshd_value "allowtcpforwarding" "unknown")",
      "permittunnel": "$(extract_sshd_value "permittunnel" "unknown")",
      "maxauthtries": "$(extract_sshd_value "maxauthtries" "6")",
      "logingracetime": "$(extract_sshd_value "logingracetime" "120")",
      "clientaliveinterval": "$(extract_sshd_value "clientaliveinterval" "0")",
      "clientalivecountmax": "$(extract_sshd_value "clientalivecountmax" "3")",
      "protocol": "$(extract_sshd_value "protocol" "2")",
      "ciphers": "$(extract_sshd_value "ciphers" "default")",
      "macs": "$(extract_sshd_value "macs" "default")",
      "kexalgorithms": "$(extract_sshd_value "kexalgorithms" "default")"
    },
    "security_analysis": {
      "root_login_method": "$(extract_sshd_value "permitrootlogin" "unknown")",
      "password_auth_enabled": "$(extract_sshd_value "passwordauthentication" "unknown")",
      "key_auth_enabled": "$(extract_sshd_value "pubkeyauthentication" "unknown")",
      "forwarding_risks": {
        "x11_forwarding": "$(extract_sshd_value "x11forwarding" "unknown")",
        "agent_forwarding": "$(extract_sshd_value "allowagentforwarding" "unknown")",
        "tcp_forwarding": "$(extract_sshd_value "allowtcpforwarding" "unknown")",
        "tunnel_forwarding": "$(extract_sshd_value "permittunnel" "unknown")"
      },
      "session_security": {
        "auth_attempts_limit": "$(extract_sshd_value "maxauthtries" "6")",
        "login_grace_period": "$(extract_sshd_value "logingracetime" "120")",
        "keepalive_interval": "$(extract_sshd_value "clientaliveinterval" "0")",
        "keepalive_max_count": "$(extract_sshd_value "clientalivecountmax" "3")"
      }
    },
    "config_file_contents": {
      "main_config": {
        "file": "$SSH_CONFIG",
        "content": "$(read_config_file "$SSH_CONFIG")"
      },
      "drop_in_configs": [
$(find /etc/ssh/sshd_config.d -name "*.conf" -type f 2>/dev/null | sort | while IFS= read -r config_file; do
    [[ -z "$config_file" ]] && continue
    echo "        {"
    echo "          \"file\": \"$config_file\","
    echo "          \"content\": \"$(read_config_file "$config_file")\""
    echo -n "        }"
    if [[ "$config_file" != "$(find /etc/ssh/sshd_config.d -name "*.conf" -type f 2>/dev/null | sort | tail -1)" ]]; then
        echo ","
    else
        echo ""
    fi
done)
      ]
    }
  },
EOF


# =======================================================================================
# =======================================================================================
# =======================================================================================

echo "Discovering ISPConfig3 configuration..."
# ISPConfig3 Configuration
ISPCONFIG_BASE="/usr/local/ispconfig"
if [[ -d "$ISPCONFIG_BASE" ]]; then
    cat >> "$OUTPUT_FILE" << EOF
  "ispconfig_configuration": {
    "installation_found": true,
    "base_directory": "$ISPCONFIG_BASE",
    "directory_permissions": {
      "base": "$(stat -c '%a:%U:%G' "$ISPCONFIG_BASE" 2>/dev/null)",
      "interface": "$(stat -c '%a:%U:%G' "$ISPCONFIG_BASE/interface" 2>/dev/null)",
      "server": "$(stat -c '%a:%U:%G' "$ISPCONFIG_BASE/server" 2>/dev/null)"
    }
  },
EOF
else
    cat >> "$OUTPUT_FILE" << EOF
  "ispconfig_configuration": {
    "installation_found": false,
    "reason": "ISPConfig directory not found"
  },
EOF
fi

echo "Discovering mail server configuration..."
# Mail Configuration
POSTFIX_MAIN="/etc/postfix/main.cf"
cat >> "$OUTPUT_FILE" << EOF
  "mail_configuration": {
    "postfix": {
      "service_active": "$(systemctl is-active postfix 2>/dev/null || echo 'inactive')",
      "main_config": {
        "file": "$POSTFIX_MAIN",
        "content": "$(read_config_file "$POSTFIX_MAIN")"
      }
    },
    "dovecot": {
      "service_active": "$(systemctl is-active dovecot 2>/dev/null || echo 'inactive')"
    }
  },
EOF


# =======================================================================================
# =======================================================================================
# =======================================================================================

# Network Services
TOTAL_LINES=$(ss -tlnp | wc -l)
cat >> "$OUTPUT_FILE" << EOF
  "network_services": {
    "listening_services": [
$(ss -tlnp | awk -v total="$TOTAL_LINES" 'NR>1 {
    split($4, addr, ":");
    port = addr[length(addr)];
    if(addr[1] == "*" || addr[1] == "0.0.0.0" || addr[1] == "::") {
        bind_type = "ALL_INTERFACES";
        risk_level = "HIGH"
    } else if(addr[1] == "127.0.0.1" || addr[1] == "::1") {
        bind_type = "LOCALHOST_ONLY";
        risk_level = "LOW"
    } else {
        bind_type = "SPECIFIC_IP";
        risk_level = "MEDIUM"
    }
    printf "      {\"address\":\"%s\",\"port\":\"%s\",\"bind_type\":\"%s\",\"risk_level\":\"%s\",\"process\":\"%s\"}", $4, port, bind_type, risk_level, $7;
    if(NR < total) printf ","
    printf "\n"
}')
    ]
  },
EOF

# =======================================================================================
# =======================================================================================
# =======================================================================================


echo "Finalizing audit report..."
# Close JSON structure
cat >> "$OUTPUT_FILE" << EOF
  "audit_summary": {
    "total_config_files_analyzed": $(grep -c '"file":' "$OUTPUT_FILE"),
    "services_analyzed": ["apache", "mysql/mariadb", "php", "ispconfig", "ssh", "postfix", "dovecot"],
    "focus": "Configuration security baseline - not runtime monitoring"
  }
}
EOF

# Finalize git tracking
finalize_audit() {
    cd "$AUDIT_DIR"
    
    # Check if there are any changes
    if git diff --quiet "$OUTPUT_FILENAME" 2>/dev/null; then
        echo "No configuration changes detected since last audit"
        COMMIT_MSG="Config audit $AUDIT_DATE - No changes"
        git add "$OUTPUT_FILENAME" 2>/dev/null || true
        git commit --allow-empty -m "$COMMIT_MSG" >/dev/null 2>&1
    else
        echo "Configuration changes detected - committing to audit history"
        if git rev-parse --verify HEAD >/dev/null 2>&1; then
            echo "Summary of changes:"
            git diff --stat "$OUTPUT_FILENAME" 2>/dev/null || echo "  (New configuration file)"
        fi
        COMMIT_MSG="Config audit $AUDIT_DATE"
        git add "$OUTPUT_FILENAME"
        git commit -m "$COMMIT_MSG" >/dev/null 2>&1
    fi
    
    # Apply retention policy after committing
    apply_retention
    
    echo ""
    echo "Audit History Summary:"
    echo "- Repository: $AUDIT_DIR"
    echo "- Total commits: $(git rev-list --count HEAD 2>/dev/null || echo "1")"
    if [[ -n "$RETAIN_COMMITS" ]]; then
        echo "- Retention policy: Last $RETAIN_COMMITS commits"
    else
        echo "- Retention policy: Keep all history (production mode)"
    fi
}

echo "Configuration audit completed successfully!"
echo "Report saved to: $OUTPUT_FILE"
echo ""
echo "Quick Summary:"
echo "- Config files found and analyzed: $(grep -c '"file":' "$OUTPUT_FILE")"  
echo "- Services listening on all interfaces: $(ss -tlnp | grep -c '0.0.0.0\|*:')"
echo "- ISPConfig installation: $([ -d "/usr/local/ispconfig" ] && echo "Found" || echo "Not found")"

# Finalize git tracking and apply retention
finalize_audit