#!/bin/bash

# ISPConfig3 Database Migration Summary Audit Script
# Simplified version using Python - generates focused migration data
# Compatible with ispconfig-audit.sh command line interface

SCRIPT_VERSION="2.5"
AUDIT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
HOSTNAME=$(hostname)

# Default values
AUDIT_DIR=""
RETAIN_COMMITS=""
OUTPUT_FILENAME="ispconfig-bom-migration.json"

# Usage function
usage() {
    echo "Usage: $0 -d <audit_directory> [--retain <number>]"
    echo ""
    echo "Options:"
    echo "  -d <directory>    Directory to store audit reports (required)"
    echo "  --retain <number> Keep only the last N commits (optional, for development)"
    echo ""
    echo "Examples:"
    echo "  $0 -d /opt/audit/ispconfig-migration-summary                    # Production mode (keep all history)"
    echo "  $0 -d /opt/audit/ispconfig-migration-summary --retain 20       # Development mode (keep last 20 commits)"
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

# Check dependencies
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
    echo "Setting up migration summary audit repository at: $AUDIT_DIR"
    
    # Create directory if it doesn't exist
    mkdir -p "$AUDIT_DIR"
    cd "$AUDIT_DIR"
    
    # Initialize git repo if not exists
    if [[ ! -d ".git" ]]; then
        git init
        git config user.name "ISPConfig Migration Summary Audit"
        git config user.email "migration-audit@$(hostname)"
        echo "Initialized new git repository for migration audit tracking"
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

# Generate the Python migration summary script
generate_migration_summary_script() {
    cat > /tmp/ispconfig-bom-migration.py << 'EOF'
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

class ISPConfigMigrationSummary:
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
        return credentials
        
    def connect(self):
        try:
            self.connection = pymysql.connect(**self.connection_params)
            logger.info("Connected to ISPConfig database successfully")
            return True
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
    
    def generate_migration_summary(self):
        if not self.connect():
            return None
        
        try:
            report = {
                'audit_info': {
                    'version': '2.5',
                    'date': datetime.utcnow().isoformat() + 'Z',
                    'hostname': os.uname().nodename,
                    'purpose': 'ISPConfig Migration Summary'
                }
            }
            
            # Get counts only - no detailed data
            summary_queries = {
                'web_domains_total': "SELECT COUNT(*) as count FROM web_domain",
                'web_domains_active': "SELECT COUNT(*) as count FROM web_domain WHERE active='y'",
                'web_domains_ssl': "SELECT COUNT(*) as count FROM web_domain WHERE ssl='y'",
                'web_domains_custom_directives': """
                    SELECT COUNT(*) as count FROM web_domain 
                    WHERE (apache_directives IS NOT NULL AND apache_directives != '') 
                       OR (nginx_directives IS NOT NULL AND nginx_directives != '')
                """,
                'mail_domains_total': "SELECT COUNT(*) as count FROM mail_domain",
                'mail_domains_active': "SELECT COUNT(*) as count FROM mail_domain WHERE active='y'",
                'mail_domains_dkim': "SELECT COUNT(*) as count FROM mail_domain WHERE dkim='y'",
                'mail_users_total': "SELECT COUNT(*) as count FROM mail_user",
                'mail_users_active': "SELECT COUNT(*) as count FROM mail_user WHERE access='y'",
                'dns_zones_total': "SELECT COUNT(*) as count FROM dns_soa",
                'dns_zones_active': "SELECT COUNT(*) as count FROM dns_soa WHERE active='Y'",
                'dns_zones_dnssec': "SELECT COUNT(*) as count FROM dns_soa WHERE dnssec_wanted='Y'",
                'databases_total': "SELECT COUNT(*) as count FROM web_database",
                'databases_active': "SELECT COUNT(*) as count FROM web_database WHERE active='y'",
                'clients_total': "SELECT COUNT(*) as count FROM client",
                'directive_snippets': "SELECT COUNT(*) as count FROM directive_snippets WHERE active='y'"
            }
            
            summary = {}
            for key, query in summary_queries.items():
                result = self.execute_query(query)
                summary[key] = result[0]['count'] if result else 0
            
            # Get list of domains (names only, not full details)
            web_domains = self.execute_query("SELECT domain FROM web_domain WHERE active='y' ORDER BY domain")
            mail_domains = self.execute_query("SELECT domain FROM mail_domain WHERE active='y' ORDER BY domain")
            dns_zones = self.execute_query("SELECT origin as domain FROM dns_soa WHERE active='Y' ORDER BY origin")
            
            # Get clients list (minimal info)
            clients = self.execute_query("SELECT company_name, contact_name FROM client ORDER BY company_name")
            
            # Special checks for migration validation
            custom_domains = self.execute_query("""
                SELECT domain, 
                       CASE WHEN apache_directives IS NOT NULL AND apache_directives != '' THEN 'apache' ELSE '' END as has_apache,
                       CASE WHEN nginx_directives IS NOT NULL AND nginx_directives != '' THEN 'nginx' ELSE '' END as has_nginx,
                       CASE WHEN custom_php_ini IS NOT NULL AND custom_php_ini != '' THEN 'php' ELSE '' END as has_php,
                       CASE WHEN ssl='y' THEN 'ssl' ELSE '' END as has_ssl
                FROM web_domain 
                WHERE active='y' AND (
                    (apache_directives IS NOT NULL AND apache_directives != '') OR
                    (nginx_directives IS NOT NULL AND nginx_directives != '') OR
                    (custom_php_ini IS NOT NULL AND custom_php_ini != '') OR
                    ssl='y'
                )
                ORDER BY domain
            """)
            
            report.update({
                'summary_counts': summary,
                'domain_lists': {
                    'web_domains': [d['domain'] for d in web_domains],
                    'mail_domains': [d['domain'] for d in mail_domains],
                    'dns_zones': [d['domain'] for d in dns_zones]
                },
                'clients': clients,
                'domains_requiring_attention': custom_domains,
                'migration_checklist': {
                    'total_domains': summary['web_domains_active'],
                    'ssl_domains': summary['web_domains_ssl'],
                    'custom_config_domains': summary['web_domains_custom_directives'],
                    'mail_accounts': summary['mail_users_active'],
                    'dkim_domains': summary['mail_domains_dkim'],
                    'dns_zones': summary['dns_zones_active'],
                    'dnssec_zones': summary['dns_zones_dnssec'],
                    'databases': summary['databases_active']
                }
            })
            
            logger.info("Migration summary generation completed successfully")
            return report
            
        except Exception as e:
            logger.error(f"Migration summary generation failed: {e}")
            return None
        finally:
            self.close()

def main(output_file):
    audit_tool = ISPConfigMigrationSummary()
    report = audit_tool.generate_migration_summary()
    
    if report is None:
        logger.error("Failed to generate migration summary")
        sys.exit(1)
    
    json_output = json.dumps(report, indent=2, default=str)
    
    with open(output_file, 'w') as f:
        f.write(json_output)
    
    logger.info(f"Migration summary saved to {output_file}")
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
        echo "No migration summary changes detected since last audit"
        COMMIT_MSG="Migration summary audit $AUDIT_DATE - No changes"
        git add "$OUTPUT_FILENAME" 2>/dev/null || true
        git commit --allow-empty -m "$COMMIT_MSG" >/dev/null 2>&1
    else
        echo "Migration summary changes detected - committing to audit history"
        if git rev-parse --verify HEAD >/dev/null 2>&1; then
            echo "Summary of changes:"
            git diff --stat "$OUTPUT_FILENAME" 2>/dev/null || echo "  (New migration summary file)"
        fi
        COMMIT_MSG="Migration summary audit $AUDIT_DATE"
        git add "$OUTPUT_FILENAME"
        git commit -m "$COMMIT_MSG" >/dev/null 2>&1
    fi
    
    # Apply retention policy after committing
    apply_retention
    
    echo ""
    echo "Migration Summary Audit History:"
    echo "- Repository: $AUDIT_DIR"
    echo "- Total commits: $(git rev-list --count HEAD 2>/dev/null || echo "1")"
    if [[ -n "$RETAIN_COMMITS" ]]; then
        echo "- Retention policy: Last $RETAIN_COMMITS commits"
    else
        echo "- Retention policy: Keep all history (production mode)"
    fi
}

# Main execution
echo "Starting ISPConfig3 Migration Summary Audit..."

# Check dependencies
check_dependencies

# Setup the audit repository
setup_audit_repo

OUTPUT_FILE="$AUDIT_DIR/$OUTPUT_FILENAME"
echo "Output file: $OUTPUT_FILE"

# Generate the Python script
generate_migration_summary_script

# Run the Python migration summary
echo "Extracting ISPConfig migration summary data..."
if python3 /tmp/ispconfig-bom-migration.py "$OUTPUT_FILE"; then
    echo "✓ Migration summary completed successfully!"
    echo "Report saved to: $OUTPUT_FILE"
    echo ""
    echo "Migration Summary:"
    
    # Show summary stats if jq is available
    if command -v jq &> /dev/null; then
        echo "- Web domains (active): $(jq -r '.summary_counts.web_domains_active // "unknown"' "$OUTPUT_FILE")"
        echo "- Mail users (active): $(jq -r '.summary_counts.mail_users_active // "unknown"' "$OUTPUT_FILE")"
        echo "- Databases (active): $(jq -r '.summary_counts.databases_active // "unknown"' "$OUTPUT_FILE")"
        echo "- Domains with custom config: $(jq -r '.summary_counts.web_domains_custom_directives // "unknown"' "$OUTPUT_FILE")"
        echo "- SSL domains: $(jq -r '.summary_counts.web_domains_ssl // "unknown"' "$OUTPUT_FILE")"
        echo "- DKIM domains: $(jq -r '.summary_counts.mail_domains_dkim // "unknown"' "$OUTPUT_FILE")"
    fi
else
    echo "✗ ERROR: Migration summary failed" >&2
    # Clean up temporary files
    rm -f /tmp/ispconfig-bom-migration.py
    exit 1
fi

# Clean up temporary files
    rm -f /tmp/ispconfig-bom-migration.py

# Finalize git tracking and apply retention
finalize_audit
