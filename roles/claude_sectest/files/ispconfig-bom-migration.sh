#!/bin/bash

# ISPConfig3 Database BOM (Bill of Materials) Audit Script
# Migration Verification Version - Extracts key data for migration verification
# Compatible with ispconfig-audit.sh command line interface

SCRIPT_VERSION="2.4"
AUDIT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
HOSTNAME=$(hostname)

# Default values
AUDIT_DIR=""
RETAIN_COMMITS=""
OUTPUT_FILENAME="ispconfig-bom-config.json"

# Global variables for database connection
DB_USER=""
DB_PASSWORD=""
DB_DATABASE=""
DB_HOST=""
DB_AUTH_METHOD=""

# Usage function
usage() {
    echo "Usage: $0 -d <audit_directory> [--retain <number>]"
    echo ""
    echo "Options:"
    echo "  -d <directory>    Directory to store audit reports (required)"
    echo "  --retain <number> Keep only the last N commits (optional, for development)"
    echo ""
    echo "Examples:"
    echo "  $0 -d /opt/audit/ispconfig-bom-audit                    # Production mode (keep all history)"
    echo "  $0 -d /opt/audit/ispconfig-bom-audit --retain 20       # Development mode (keep last 20 commits)"
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

# Parse ISPConfig credentials with robust regex
parse_ispconfig_credentials() {
    local config_file="/usr/local/ispconfig/server/lib/config.inc.php"
    
    if [[ ! -f "$config_file" ]]; then
        echo "ISPConfig config file not found: $config_file" >&2
        return 1
    fi
    
    echo "Parsing ISPConfig credentials from: $config_file"
    
    # Use sed for precise parsing - match only $conf assignments, not define() statements
    DB_USER=$(grep "^\$conf\['db_user'\]" "$config_file" | sed "s/.*= *'//" | sed "s/';.*//")
    DB_PASSWORD=$(grep "^\$conf\['db_password'\]" "$config_file" | sed "s/.*= *'//" | sed "s/';.*//")
    DB_DATABASE=$(grep "^\$conf\['db_database'\]" "$config_file" | sed "s/.*= *'//" | sed "s/';.*//")
    DB_HOST=$(grep "^\$conf\['db_host'\]" "$config_file" | sed "s/.*= *'//" | sed "s/';.*//")
    
    # Debug output (remove password for security)
    echo "Parsed credentials:"
    echo "  DB_USER: '$DB_USER'"
    echo "  DB_DATABASE: '$DB_DATABASE'"
    echo "  DB_HOST: '$DB_HOST'"
    echo "  DB_PASSWORD: [$(echo -n "$DB_PASSWORD" | wc -c) characters]"
    
    # Validate that we got the essential credentials
    if [[ -z "$DB_USER" || -z "$DB_DATABASE" ]]; then
        echo "ERROR: Failed to parse essential database credentials" >&2
        echo "Expected format: \$conf['db_user'] = 'username';" >&2
        return 1
    fi
    
    return 0
}

# Enhanced dependency checking with better error messages
check_dependencies() {
    local missing_tools=()
    
    if ! command -v mysql &> /dev/null; then
        missing_tools+=("mysql-client")
    fi
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo "ERROR: Missing required tools: ${missing_tools[*]}" >&2
        echo "Install with: apt-get install ${missing_tools[*]}" >&2
        exit 1
    fi
    
    # Parse ISPConfig credentials
    if ! parse_ispconfig_credentials; then
        exit 1
    fi
    
    # Test database connectivity
    echo "Testing database connectivity..."
    
    local test_output
    local test_error
    
    # Build connection string
    local mysql_args=()
    mysql_args+=("-u" "$DB_USER")
    
    if [[ -n "$DB_PASSWORD" ]]; then
        mysql_args+=("-p$DB_PASSWORD")
    fi
    
    if [[ -n "$DB_HOST" && "$DB_HOST" != "localhost" ]]; then
        mysql_args+=("-h" "$DB_HOST")
    fi
    
    mysql_args+=("$DB_DATABASE")
    
    # Test connection
    if test_output=$(mysql "${mysql_args[@]}" -e "SELECT 1 as test;" 2>&1); then
        echo "✓ Database connection successful"
        DB_AUTH_METHOD="ispconfig_credentials"
        return 0
    else
        echo "✗ Database connection failed" >&2
        echo "Connection details:" >&2
        echo "  User: $DB_USER" >&2
        echo "  Database: $DB_DATABASE" >&2
        echo "  Host: $DB_HOST" >&2
        echo "" >&2
        echo "MySQL error output:" >&2
        echo "$test_output" >&2
        echo "" >&2
        echo "Troubleshooting steps:" >&2
        echo "1. Verify MySQL service: systemctl status mysql" >&2
        echo "2. Test connection manually: mysql -u '$DB_USER' -p '$DB_DATABASE'" >&2
        echo "3. Check user permissions: SHOW GRANTS FOR '$DB_USER'@'localhost';" >&2
        echo "4. Verify database exists: SHOW DATABASES;" >&2
        exit 1
    fi
}

# Build MySQL command with proper escaping
build_mysql_command() {
    local mysql_cmd="mysql"
    
    mysql_cmd="$mysql_cmd -u '$DB_USER'"
    
    if [[ -n "$DB_PASSWORD" ]]; then
        mysql_cmd="$mysql_cmd -p'$DB_PASSWORD'"
    fi
    
    if [[ -n "$DB_HOST" && "$DB_HOST" != "localhost" ]]; then
        mysql_cmd="$mysql_cmd -h '$DB_HOST'"
    fi
    
    mysql_cmd="$mysql_cmd '$DB_DATABASE'"
    
    echo "$mysql_cmd"
}

# Setup audit directory and git repo
setup_audit_repo() {
    echo "Setting up BOM audit repository at: $AUDIT_DIR"
    
    # Create directory if it doesn't exist
    mkdir -p "$AUDIT_DIR"
    cd "$AUDIT_DIR"
    
    # Initialize git repo if not exists
    if [[ ! -d ".git" ]]; then
        git init
        git config user.name "ISPConfig BOM Audit"
        git config user.email "bom-audit@$(hostname)"
        echo "Initialized new git repository for BOM audit tracking"
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

# Generate the migration verification script inline
generate_migration_script() {
    cat > /tmp/ispconfig-migration-verifier.sql << 'EOF'
-- ISPConfig Migration Verification Report
-- Purpose: Verify complete site migration (web, email, DNS)

-- ==============================================
-- WEB DOMAINS - All domains and their configs
-- ==============================================
SELECT 'WEB_DOMAINS' as section, domain, active, type, 
       CASE WHEN parent_domain_id = 0 THEN 'MAIN' ELSE 'CHILD' END as domain_type,
       ssl, ssl_letsencrypt, php,
       CASE WHEN apache_directives IS NOT NULL AND apache_directives != '' THEN 'YES' ELSE 'NO' END as has_apache_directives,
       CASE WHEN nginx_directives IS NOT NULL AND nginx_directives != '' THEN 'YES' ELSE 'NO' END as has_nginx_directives,
       CASE WHEN custom_php_ini IS NOT NULL AND custom_php_ini != '' THEN 'YES' ELSE 'NO' END as has_custom_php,
       CASE WHEN rewrite_rules IS NOT NULL AND rewrite_rules != '' THEN 'YES' ELSE 'NO' END as has_rewrites,
       redirect_type, system_user,
       c.company_name as client
FROM web_domain w
LEFT JOIN client c ON w.sys_groupid = c.sys_groupid
ORDER BY w.parent_domain_id, w.domain;

-- ==============================================
-- MAIL DOMAINS - All mail domains  
-- ==============================================
SELECT 'MAIL_DOMAINS' as section, domain, active, dkim,
       c.company_name as client
FROM mail_domain md
LEFT JOIN client c ON md.sys_groupid = c.sys_groupid
ORDER BY domain;

-- ==============================================
-- MAIL USERS - All email accounts
-- ==============================================
SELECT 'MAIL_USERS' as section, email, access as active, quota,
       CASE WHEN cc IS NOT NULL AND cc != '' THEN 'YES' ELSE 'NO' END as has_forwarding,
       CASE WHEN autoresponder = 'y' THEN 'YES' ELSE 'NO' END as has_autoresponder,
       c.company_name as client
FROM mail_user mu
LEFT JOIN client c ON mu.sys_groupid = c.sys_groupid
ORDER BY email;

-- ==============================================
-- DNS ZONES - All DNS zones
-- ==============================================
SELECT 'DNS_ZONES' as section, origin as domain, active, 
       dnssec_wanted, dnssec_initialized,
       c.company_name as client
FROM dns_soa ds
LEFT JOIN client c ON ds.sys_groupid = c.sys_groupid
ORDER BY origin;

-- ==============================================
-- DATABASES - All databases
-- ==============================================
SELECT 'DATABASES' as section, database_name, active, database_charset,
       remote_access, c.company_name as client
FROM web_database wd
LEFT JOIN client c ON wd.sys_groupid = c.sys_groupid
ORDER BY database_name;

-- ==============================================
-- DIRECTIVE SNIPPETS - Custom configurations
-- ==============================================
SELECT 'DIRECTIVE_SNIPPETS' as section, name, type, customer_viewable, active
FROM directive_snippets
WHERE active = 'y'
ORDER BY type, name;

-- ==============================================
-- SUMMARY COUNTS - Migration verification totals
-- ==============================================
SELECT 'SUMMARY' as section, 'Web Domains Total' as item, COUNT(*) as count FROM web_domain
UNION ALL
SELECT 'SUMMARY', 'Web Domains Active', COUNT(*) FROM web_domain WHERE active='y'
UNION ALL
SELECT 'SUMMARY', 'Web Domains with SSL', COUNT(*) FROM web_domain WHERE ssl='y'
UNION ALL
SELECT 'SUMMARY', 'Web Domains with Custom Directives', COUNT(*) FROM web_domain 
WHERE (apache_directives IS NOT NULL AND apache_directives != '') 
   OR (nginx_directives IS NOT NULL AND nginx_directives != '')
UNION ALL
SELECT 'SUMMARY', 'Mail Domains Total', COUNT(*) FROM mail_domain
UNION ALL
SELECT 'SUMMARY', 'Mail Domains Active', COUNT(*) FROM mail_domain WHERE active='y'
UNION ALL
SELECT 'SUMMARY', 'Mail Users Total', COUNT(*) FROM mail_user
UNION ALL
SELECT 'SUMMARY', 'Mail Users Active', COUNT(*) FROM mail_user WHERE access='y'
UNION ALL
SELECT 'SUMMARY', 'DNS Zones Total', COUNT(*) FROM dns_soa
UNION ALL
SELECT 'SUMMARY', 'DNS Zones Active', COUNT(*) FROM dns_soa WHERE active='Y'
UNION ALL
SELECT 'SUMMARY', 'Databases Total', COUNT(*) FROM web_database
UNION ALL
SELECT 'SUMMARY', 'Databases Active', COUNT(*) FROM web_database WHERE active='y'
UNION ALL
SELECT 'SUMMARY', 'Clients Total', COUNT(*) FROM client
UNION ALL
SELECT 'SUMMARY', 'Custom Directive Snippets', COUNT(*) FROM directive_snippets WHERE active='y';
EOF
}

# Finalize git tracking
finalize_audit() {
    cd "$AUDIT_DIR"
    
    # Check if there are any changes
    if git diff --quiet "$OUTPUT_FILENAME" 2>/dev/null; then
        echo "No BOM configuration changes detected since last audit"
        COMMIT_MSG="BOM audit $AUDIT_DATE - No changes"
        git add "$OUTPUT_FILENAME" 2>/dev/null || true
        git commit --allow-empty -m "$COMMIT_MSG" >/dev/null 2>&1
    else
        echo "BOM configuration changes detected - committing to audit history"
        if git rev-parse --verify HEAD >/dev/null 2>&1; then
            echo "Summary of changes:"
            git diff --stat "$OUTPUT_FILENAME" 2>/dev/null || echo "  (New BOM configuration file)"
        fi
        COMMIT_MSG="BOM audit $AUDIT_DATE"
        git add "$OUTPUT_FILENAME"
        git commit -m "$COMMIT_MSG" >/dev/null 2>&1
    fi
    
    # Apply retention policy after committing
    apply_retention
    
    echo ""
    echo "BOM Audit History Summary:"
    echo "- Repository: $AUDIT_DIR"
    echo "- Total commits: $(git rev-list --count HEAD 2>/dev/null || echo "1")"
    if [[ -n "$RETAIN_COMMITS" ]]; then
        echo "- Retention policy: Last $RETAIN_COMMITS commits"
    else
        echo "- Retention policy: Keep all history (production mode)"
    fi
}

# Main execution
echo "Starting ISPConfig3 Database BOM Audit..."

# Check dependencies and parse credentials
check_dependencies

# Setup the audit repository
setup_audit_repo

OUTPUT_FILE="$AUDIT_DIR/$OUTPUT_FILENAME"
echo "Output file: $OUTPUT_FILE"

# Generate the migration verification SQL
generate_migration_script

# Build the appropriate MySQL command
MYSQL_CMD=$(build_mysql_command)

# Run the migration verification query with enhanced error checking
echo "Extracting ISPConfig migration verification data..."
echo "Using authentication: $DB_USER@$DB_HOST/$DB_DATABASE"

# Use a more direct approach with proper error capture
mysql_exit_code=0
if mysql -u "$DB_USER" -p"$DB_PASSWORD" "$DB_DATABASE" < /tmp/ispconfig-migration-verifier.sql > "$OUTPUT_FILE" 2>/tmp/mysql_error.log; then
    mysql_exit_code=0
else
    mysql_exit_code=$?
fi

if [[ $mysql_exit_code -eq 0 ]]; then
    echo "✓ Migration verification completed successfully!"
    echo "Report saved to: $OUTPUT_FILE"
    echo ""
    echo "Quick Migration Checklist:"
    echo "- Compare SUMMARY counts between old and new servers"
    echo "- Verify all domains with 'has_apache_directives=YES' are migrated"
    echo "- Check SSL certificates for all ssl='y' domains"
    echo "- Confirm DKIM keys for dkim='y' mail domains"
    echo "- Validate DNS zones and DNSSEC settings"
    
    # Show quick stats if available
    if command -v wc &> /dev/null; then
        echo "- Report contains $(wc -l < "$OUTPUT_FILE") lines of data"
    fi
    
    # Clean up temporary files
    rm -f /tmp/ispconfig-migration-verifier.sql /tmp/mysql_error.log
    
    # Finalize git tracking and apply retention
    finalize_audit
else
    echo "✗ ERROR: Migration verification failed (exit code: $mysql_exit_code)" >&2
    if [[ -f /tmp/mysql_error.log ]]; then
        echo "" >&2
        echo "MySQL Error Details:" >&2
        cat /tmp/mysql_error.log >&2
    fi
    echo "" >&2
    echo "Connection Details:" >&2
    echo "- User: $DB_USER" >&2
    echo "- Database: $DB_DATABASE" >&2
    echo "- Host: $DB_HOST" >&2
    echo "- Password length: $(echo -n "$DB_PASSWORD" | wc -c) characters" >&2
    echo "" >&2
    echo "Troubleshooting:" >&2
    echo "1. Test manual connection: mysql -u '$DB_USER' -p '$DB_DATABASE'" >&2
    echo "2. Verify user permissions: mysql -u root -p -e \"SHOW GRANTS FOR '$DB_USER'@'localhost';\"" >&2
    echo "3. Check database exists: mysql -u root -p -e \"SHOW DATABASES;\" | grep '$DB_DATABASE'" >&2
    echo "4. Verify config file: /usr/local/ispconfig/server/lib/config.inc.php" >&2
    
    # Clean up temporary files
    rm -f /tmp/ispconfig-migration-verifier.sql /tmp/mysql_error.log
    exit 1
fi