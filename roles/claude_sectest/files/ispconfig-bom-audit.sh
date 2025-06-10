#!/bin/bash

# ISPConfig3 Database BOM (Bill of Materials) Audit Script
# Migration Verification Version - Extracts key data for migration verification
# Compatible with ispconfig-audit.sh command line interface

SCRIPT_VERSION="2.2"
AUDIT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
HOSTNAME=$(hostname)

# Default values
AUDIT_DIR=""
RETAIN_COMMITS=""
OUTPUT_FILENAME="ispconfig-bom-config.json"

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

# Check if Python3 and required modules are available (keeping original working approach)
check_dependencies() {
    if ! command -v python3 &> /dev/null; then
        echo "ERROR: Python3 is required but not found" >&2
        exit 1
    fi
    
    if ! python3 -c "import pymysql" &> /dev/null; then
        echo "ERROR: Python3 pymysql module is required but not found" >&2
        echo "Install with: apt-get install python3-pymysql" >&2
        exit 1
    fi
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

# Generate the Python migration verification script (simplified from original working version)
generate_migration_script() {
    cat > /tmp/ispconfig-migration-extractor.py << 'EOF'
#!/usr/bin/env python3
import json
import sys
import pymysql
from datetime import datetime
import logging
import os
import re

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class ISPConfigMigrationAudit:
    def __init__(self):
        self.connection_params = self._get_db_credentials()
        self.connection = None
        
    def _parse_ispconfig_config(self, config_file='/usr/local/ispconfig/server/lib/config.inc.php'):
        credentials = {}
        try:
            with open(config_file, 'r') as f:
                content = f.read()
                patterns = {
                    'host': r"\$conf\['db_host'\]\s*=\s*['\"]([^'\"]+)['\"]",
                    'user': r"\$conf\['db_user'\]\s*=\s*['\"]([^'\"]+)['\"]", 
                    'password': r"\$conf\['db_password'\]\s*=\s*['\"]([^'\"]*)['\"]",
                    'database': r"\$conf\['db_database'\]\s*=\s*['\"]([^'\"]+)['\"]"
                }
                for key, pattern in patterns.items():
                    match = re.search(pattern, content)
                    if match:
                        credentials[key] = match.group(1)
                logger.info(f"Successfully parsed ISPConfig config: {config_file}")
                logger.info(f"Found database: {credentials.get('database', 'unknown')}@{credentials.get('host', 'unknown')}")
        except FileNotFoundError:
            logger.warning(f"ISPConfig config file not found: {config_file}")
        except PermissionError:
            logger.warning(f"Permission denied reading ISPConfig config: {config_file}")
        except Exception as e:
            logger.warning(f"Error parsing ISPConfig config: {e}")
        return credentials
    
    def _get_db_credentials(self):
        config_creds = self._parse_ispconfig_config()
        credentials = {
            'host': config_creds.get('host') or 'localhost',
            'user': config_creds.get('user') or 'ispconfig',
            'password': config_creds.get('password') or '',
            'database': config_creds.get('database') or 'dbispconfig',
            'charset': 'utf8mb4',
            'cursorclass': pymysql.cursors.DictCursor
        }
        logger.info(f"Database connection: {credentials['user']}@{credentials['host']}/{credentials['database']}")
        return credentials
        
    def connect(self):
        try:
            self.connection = pymysql.connect(**self.connection_params)
            logger.info("Connected to ISPConfig database successfully")
            return True
        except pymysql.err.OperationalError as e:
            if "Access denied" in str(e):
                logger.error("Database access denied - check credentials")
            else:
                logger.error(f"Database connection failed: {e}")
            return False
        except Exception as e:
            logger.error(f"Database connection failed: {e}")
            return False
    
    def close(self):
        if self.connection:
            self.connection.close()
    
    def execute_query(self, query, params=None):
        try:
            with self.connection.cursor() as cursor:
                cursor.execute(query, params or ())
                return cursor.fetchall()
        except Exception as e:
            logger.error(f"Query failed: {query[:100]}... Error: {e}")
            return []
    
    def generate_migration_report(self):
        if not self.connect():
            return None
        
        try:
            report = {
                'audit_info': {
                    'version': '2.2',
                    'date': datetime.utcnow().isoformat() + 'Z',
                    'hostname': os.uname().nodename,
                    'purpose': 'ISPConfig Migration Verification'
                }
            }
            
            # Web domains with custom configurations
            web_domains = self.execute_query("""
                SELECT w.domain, w.active, w.type, 
                       CASE WHEN w.parent_domain_id = 0 THEN 'MAIN' ELSE 'CHILD' END as domain_type,
                       w.ssl, w.ssl_letsencrypt, w.php,
                       CASE WHEN w.apache_directives IS NOT NULL AND w.apache_directives != '' THEN 'YES' ELSE 'NO' END as has_apache_directives,
                       CASE WHEN w.nginx_directives IS NOT NULL AND w.nginx_directives != '' THEN 'YES' ELSE 'NO' END as has_nginx_directives,
                       CASE WHEN w.custom_php_ini IS NOT NULL AND w.custom_php_ini != '' THEN 'YES' ELSE 'NO' END as has_custom_php,
                       CASE WHEN w.rewrite_rules IS NOT NULL AND w.rewrite_rules != '' THEN 'YES' ELSE 'NO' END as has_rewrites,
                       w.redirect_type, w.system_user,
                       c.company_name as client
                FROM web_domain w
                LEFT JOIN client c ON w.sys_groupid = c.sys_groupid
                ORDER BY w.parent_domain_id, w.domain
            """)
            
            # Mail domains
            mail_domains = self.execute_query("""
                SELECT md.domain, md.active, md.dkim,
                       c.company_name as client
                FROM mail_domain md
                LEFT JOIN client c ON md.sys_groupid = c.sys_groupid
                ORDER BY md.domain
            """)
            
            # Mail users
            mail_users = self.execute_query("""
                SELECT mu.email, mu.access as active, mu.quota,
                       CASE WHEN mu.cc IS NOT NULL AND mu.cc != '' THEN 'YES' ELSE 'NO' END as has_forwarding,
                       CASE WHEN mu.autoresponder = 'y' THEN 'YES' ELSE 'NO' END as has_autoresponder,
                       c.company_name as client
                FROM mail_user mu
                LEFT JOIN client c ON mu.sys_groupid = c.sys_groupid
                ORDER BY mu.email
            """)
            
            # DNS zones
            dns_zones = self.execute_query("""
                SELECT ds.origin as domain, ds.active, 
                       ds.dnssec_wanted, ds.dnssec_initialized,
                       c.company_name as client
                FROM dns_soa ds
                LEFT JOIN client c ON ds.sys_groupid = c.sys_groupid
                ORDER BY ds.origin
            """)
            
            # Databases
            databases = self.execute_query("""
                SELECT wd.database_name, wd.active, wd.database_charset,
                       wd.remote_access, c.company_name as client
                FROM web_database wd
                LEFT JOIN client c ON wd.sys_groupid = c.sys_groupid
                ORDER BY wd.database_name
            """)
            
            # Summary counts
            summary = {
                'web_domains_total': len(web_domains),
                'web_domains_active': len([d for d in web_domains if d['active'] == 'y']),
                'web_domains_with_ssl': len([d for d in web_domains if d['ssl'] == 'y']),
                'web_domains_with_custom_directives': len([d for d in web_domains if d['has_apache_directives'] == 'YES' or d['has_nginx_directives'] == 'YES']),
                'mail_domains_total': len(mail_domains),
                'mail_domains_active': len([d for d in mail_domains if d['active'] == 'y']),
                'mail_users_total': len(mail_users),
                'mail_users_active': len([u for u in mail_users if u['active'] == 'y']),
                'dns_zones_total': len(dns_zones),
                'dns_zones_active': len([z for z in dns_zones if z['active'] == 'Y']),
                'databases_total': len(databases),
                'databases_active': len([d for d in databases if d['active'] == 'y'])
            }
            
            report.update({
                'web_domains': web_domains,
                'mail_domains': mail_domains,
                'mail_users': mail_users,
                'dns_zones': dns_zones,
                'databases': databases,
                'summary': summary
            })
            
            logger.info("Migration report generation completed successfully")
            return report
            
        except Exception as e:
            logger.error(f"Migration report generation failed: {e}")
            return None
        finally:
            self.close()

def main(output_file):
    audit_tool = ISPConfigMigrationAudit()
    report = audit_tool.generate_migration_report()
    
    if report is None:
        logger.error("Failed to generate migration report")
        logger.error("\nCredential troubleshooting:")
        logger.error("1. Check ISPConfig config: /usr/local/ispconfig/server/lib/config.inc.php")
        logger.error("2. Set environment: export ISPCONFIG_DB_PASSWORD='your_password'")
        logger.error("3. Verify database access: mysql -u ispconfig -p dbispconfig")
        sys.exit(1)
    
    json_output = json.dumps(report, indent=2, default=str)
    
    with open(output_file, 'w') as f:
        f.write(json_output)
    
    logger.info(f"Migration report saved to {output_file}")
    return True

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print("Usage: python3 script.py <output_file>", file=sys.stderr)
        sys.exit(1)
    
    success = main(sys.argv[1])
    sys.exit(0 if success else 1)
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

# Check dependencies
check_dependencies

# Setup the audit repository
setup_audit_repo

OUTPUT_FILE="$AUDIT_DIR/$OUTPUT_FILENAME"
echo "Output file: $OUTPUT_FILE"

# Generate the Python script
generate_migration_script

# Run the Python migration extractor
echo "Extracting ISPConfig migration verification data..."
if python3 /tmp/ispconfig-migration-extractor.py "$OUTPUT_FILE"; then
    echo "Migration verification completed successfully!"
    echo "Report saved to: $OUTPUT_FILE"
    echo ""
    echo "Quick Migration Checklist:"
    echo "- Compare summary counts between old and new servers"
    echo "- Verify all domains with custom directives are migrated"
    echo "- Check SSL certificates for all SSL-enabled domains"
    echo "- Confirm DKIM keys for mail domains"
    echo "- Validate DNS zones and DNSSEC settings"
    
    # Read some summary stats from the generated JSON
    if command -v jq &> /dev/null; then
        echo "- Total web domains: $(jq -r '.summary.web_domains_total // "unknown"' "$OUTPUT_FILE")"
        echo "- Total mail users: $(jq -r '.summary.mail_users_total // "unknown"' "$OUTPUT_FILE")"
        echo "- Total databases: $(jq -r '.summary.databases_total // "unknown"' "$OUTPUT_FILE")"
        echo "- Domains with custom directives: $(jq -r '.summary.web_domains_with_custom_directives // "unknown"' "$OUTPUT_FILE")"
    fi
else
    echo "ERROR: Migration verification failed" >&2
    # Clean up temporary files
    rm -f /tmp/ispconfig-migration-extractor.py
    exit 1
fi

# Clean up temporary files
rm -f /tmp/ispconfig-migration-extractor.py

# Finalize git tracking and apply retention
finalize_audit
