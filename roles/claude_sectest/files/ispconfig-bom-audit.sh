#!/bin/bash

# ISPConfig3 Database BOM (Bill of Materials) Audit Script
# Extracts what ISPConfig thinks exists from the database
# Compatible with ispconfig-audit.sh command line interface

SCRIPT_VERSION="2.1"
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

# Check if Python3 and required modules are available
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

# Generate the Python BOM script inline
generate_python_script() {
    cat > /tmp/ispconfig-bom-extractor.py << 'PYTHON_SCRIPT_EOF'
#!/usr/bin/env python3
"""
ISPConfig Database Inventory Script
Extracts what ISPConfig thinks exists from the database
Part of the ISPConfig BOM Tool suite
"""

import json
import sys
import pymysql
from datetime import datetime
import logging
import os
import re

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class ISPConfigInventory:
    def __init__(self, host=None, user=None, password=None, database=None):
        # Get credentials from ISPConfig config file, environment, or parameters
        self.connection_params = self._get_db_credentials(host, user, password, database)
        self.connection = None
        
    def _parse_ispconfig_config(self, config_file='/usr/local/ispconfig/server/lib/config.inc.php'):
        """Parse ISPConfig configuration file for database credentials"""
        credentials = {}
        
        try:
            with open(config_file, 'r') as f:
                content = f.read()
                
                # Extract database configuration using regex patterns
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
    
    def _get_db_credentials(self, host, user, password, database):
        """Get database credentials from multiple sources in priority order"""
        
        # Start with ISPConfig config file
        config_creds = self._parse_ispconfig_config()
        
        # Build final credentials with precedence: CLI args > ENV vars > config file > defaults
        credentials = {
            'host': (
                host or 
                os.getenv('ISPCONFIG_DB_HOST') or 
                config_creds.get('host') or 
                'localhost'
            ),
            'user': (
                user or 
                os.getenv('ISPCONFIG_DB_USER') or 
                config_creds.get('user') or 
                'ispconfig'
            ),
            'password': (
                password or 
                os.getenv('ISPCONFIG_DB_PASSWORD') or 
                config_creds.get('password') or 
                ''
            ),
            'database': (
                database or 
                os.getenv('ISPCONFIG_DB_NAME') or 
                config_creds.get('database') or 
                'dbispconfig'
            ),
            'charset': 'utf8mb4',
            'cursorclass': pymysql.cursors.DictCursor
        }
        
        # Log credential sources (without password)
        logger.info(f"Database connection: {credentials['user']}@{credentials['host']}/{credentials['database']}")
        
        if password:
            logger.info("Using password from CLI argument")
        elif os.getenv('ISPCONFIG_DB_PASSWORD'):
            logger.info("Using password from environment variable")
        elif config_creds.get('password'):
            logger.info("Using password from ISPConfig config file")
        else:
            logger.warning("No password configured - attempting connection without password")
            
        return credentials
        
    def connect(self):
        """Establish database connection"""
        try:
            self.connection = pymysql.connect(**self.connection_params)
            logger.info("Connected to ISPConfig database successfully")
            return True
        except pymysql.err.OperationalError as e:
            if "Access denied" in str(e):
                logger.error("Database access denied - check credentials")
                logger.error("Credential sources tried: CLI args > ENV vars > ISPConfig config > defaults")
            else:
                logger.error(f"Database connection failed: {e}")
            return False
        except Exception as e:
            logger.error(f"Database connection failed: {e}")
            return False
    
    def close(self):
        """Close database connection"""
        if self.connection:
            self.connection.close()
    
    def execute_query(self, query, params=None):
        """Execute query with error handling"""
        try:
            with self.connection.cursor() as cursor:
                cursor.execute(query, params or ())
                return cursor.fetchall()
        except Exception as e:
            logger.error(f"Query failed: {query[:100]}... Error: {e}")
            return []
    
    def get_web_domains(self):
        """Extract website domains and configurations"""
        query = """
        SELECT 
            w.domain_id,
            w.domain,
            w.document_root,
            w.active,
            w.type,
            w.parent_domain_id,
            w.redirect_type,
            w.redirect_path,
            w.ssl,
            w.ssl_letsencrypt,
            c.company_name as client_name,
            c.client_id
        FROM web_domain w
        LEFT JOIN client c ON w.sys_groupid = c.sys_groupid
        ORDER BY w.domain
        """
        
        domains = self.execute_query(query)
        logger.info(f"Found {len(domains)} web domains")
        
        # Process and categorize domains
        result = {
            'total_count': len(domains),
            'active_count': len([d for d in domains if d['active'] == 'y']),
            'ssl_enabled_count': len([d for d in domains if d['ssl'] == 'y']),
            'letsencrypt_count': len([d for d in domains if d['ssl_letsencrypt'] == 'y']),
            'domains': domains
        }
        
        return result
    
    def get_mail_domains(self):
        """Extract mail domains and configuration"""
        query = """
        SELECT 
            md.domain_id,
            md.domain,
            md.active,
            md.server_id,
            c.company_name as client_name,
            c.client_id
        FROM mail_domain md
        LEFT JOIN client c ON md.sys_groupid = c.sys_groupid
        ORDER BY md.domain
        """
        
        domains = self.execute_query(query)
        logger.info(f"Found {len(domains)} mail domains")
        
        return {
            'total_count': len(domains),
            'active_count': len([d for d in domains if d['active'] == 'y']),
            'domains': domains
        }
    
    def get_mail_users(self):
        """Extract mail users/accounts"""
        query = """
        SELECT 
            mu.mailuser_id,
            mu.email,
            mu.login,
            mu.maildir,
            mu.quota,
            mu.cc,
            mu.forward_in_lda,
            mu.sender_cc,
            mu.access,
            md.domain,
            c.company_name as client_name
        FROM mail_user mu
        LEFT JOIN mail_domain md ON SUBSTRING_INDEX(mu.email, '@', -1) = md.domain
        LEFT JOIN client c ON mu.sys_groupid = c.sys_groupid
        ORDER BY mu.email
        """
        
        users = self.execute_query(query)
        logger.info(f"Found {len(users)} mail users")
        
        # Calculate quota statistics
        total_quota = sum([int(u['quota'] or 0) for u in users if u['quota']])
        active_users = [u for u in users if u['access'] == 'y']
        
        return {
            'total_count': len(users),
            'active_count': len(active_users),
            'total_quota_mb': total_quota,
            'users': users
        }
    
    def get_databases(self):
        """Extract database information"""
        query = """
        SELECT 
            wd.database_id,
            wd.database_name,
            wd.database_user_id,
            wd.database_charset,
            wd.remote_access,
            wd.remote_ips,
            wd.active,
            c.company_name as client_name,
            c.client_id
        FROM web_database wd
        LEFT JOIN client c ON wd.sys_groupid = c.sys_groupid
        ORDER BY wd.database_name
        """
        
        databases = self.execute_query(query)
        logger.info(f"Found {len(databases)} databases")
        
        return {
            'total_count': len(databases),
            'active_count': len([d for d in databases if d['active'] == 'y']),
            'remote_access_count': len([d for d in databases if d['remote_access'] == 'y']),
            'databases': databases
        }
    
    def get_clients(self):
        """Extract client/user information"""
        query = """
        SELECT 
            c.client_id,
            c.company_name,
            c.contact_name,
            c.email,
            c.username,
            c.limit_web_domain,
            c.limit_web_quota,
            c.limit_maildomain,
            c.limit_mailbox,
            c.limit_database,
            c.locked
        FROM client c
        ORDER BY c.company_name
        """
        
        clients = self.execute_query(query)
        logger.info(f"Found {len(clients)} clients")
        
        return {
            'total_count': len(clients),
            'active_count': len([c for c in clients if c['locked'] != 'y']),
            'clients': clients
        }
    
    def get_dns_zones(self):
        """Extract DNS zone information (if BIND is used)"""
        query = """
        SELECT 
            z.id,
            z.origin,
            z.ns,
            z.mbox,
            z.serial,
            z.refresh,
            z.retry,
            z.expire,
            z.minimum,
            z.ttl,
            z.active,
            z.xfer,
            c.company_name as client_name
        FROM dns_soa z
        LEFT JOIN client c ON z.sys_groupid = c.sys_groupid
        ORDER BY z.origin
        """
        
        zones = self.execute_query(query)
        logger.info(f"Found {len(zones)} DNS zones")
        
        return {
            'total_count': len(zones),
            'active_count': len([z for z in zones if z['active'] == 'y']),
            'zones': zones
        }
    
    def generate_inventory(self):
        """Generate complete inventory from ISPConfig database"""
        if not self.connect():
            return None
        
        try:
            inventory = {
                'metadata': {
                    'timestamp': datetime.utcnow().isoformat() + 'Z',
                    'source': 'ispconfig_database',
                    'version': '1.0',
                    'audit_info': {
                        'version': '2.1',
                        'hostname': os.uname().nodename,
                        'purpose': 'ISPConfig Database BOM Audit'
                    }
                },
                'web_domains': self.get_web_domains(),
                'mail_domains': self.get_mail_domains(),
                'mail_users': self.get_mail_users(),
                'databases': self.get_databases(),
                'clients': self.get_clients(),
                'dns_zones': self.get_dns_zones()
            }
            
            # Add summary statistics
            inventory['summary'] = {
                'total_web_domains': inventory['web_domains']['total_count'],
                'active_web_domains': inventory['web_domains']['active_count'],
                'total_mail_domains': inventory['mail_domains']['total_count'],
                'total_mail_users': inventory['mail_users']['total_count'],
                'total_databases': inventory['databases']['total_count'],
                'total_clients': inventory['clients']['total_count'],
                'total_dns_zones': inventory['dns_zones']['total_count']
            }
            
            logger.info("BOM inventory generation completed successfully")
            return inventory
            
        except Exception as e:
            logger.error(f"BOM inventory generation failed: {e}")
            return None
        finally:
            self.close()

def main(output_file):
    # Create inventory instance (password will be read from env or config)
    inventory_tool = ISPConfigInventory(
        host=None,
        user=None,
        password=None,
        database=None
    )
    
    # Generate inventory
    inventory = inventory_tool.generate_inventory()
    
    if inventory is None:
        logger.error("Failed to generate BOM inventory")
        logger.error("\nCredential troubleshooting:")
        logger.error("1. Check ISPConfig config: /usr/local/ispconfig/server/lib/config.inc.php")
        logger.error("2. Set environment: export ISPCONFIG_DB_PASSWORD='your_password'")
        logger.error("3. Verify database access: mysql -u ispconfig -p dbispconfig")
        sys.exit(1)
    
    # Output results
    json_output = json.dumps(inventory, indent=2, default=str)
    
    with open(output_file, 'w') as f:
        f.write(json_output)
    
    logger.info(f"BOM inventory saved to {output_file}")
    return True

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print("Usage: python3 script.py <output_file>", file=sys.stderr)
        sys.exit(1)
    
    success = main(sys.argv[1])
    sys.exit(0 if success else 1)
PYTHON_SCRIPT_EOF
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
generate_python_script

# Run the Python BOM extractor
echo "Extracting ISPConfig database inventory..."
if python3 /tmp/ispconfig-bom-extractor.py "$OUTPUT_FILE"; then
    echo "BOM audit completed successfully!"
    echo "Report saved to: $OUTPUT_FILE"
    echo ""
    echo "Quick Summary:"
    echo "- BOM inventory extracted from ISPConfig database"
    echo "- JSON report includes: web domains, mail domains, users, databases, clients, DNS zones"
    
    # Read some summary stats from the generated JSON
    if command -v jq &> /dev/null; then
        echo "- Total web domains: $(jq -r '.summary.total_web_domains // "unknown"' "$OUTPUT_FILE")"
        echo "- Total mail users: $(jq -r '.summary.total_mail_users // "unknown"' "$OUTPUT_FILE")"
        echo "- Total databases: $(jq -r '.summary.total_databases // "unknown"' "$OUTPUT_FILE")"
        echo "- Total clients: $(jq -r '.summary.total_clients // "unknown"' "$OUTPUT_FILE")"
    fi
else
    echo "ERROR: BOM audit failed" >&2
    # Clean up temporary files
    rm -f /tmp/ispconfig-bom-extractor.py
    exit 1
fi

# Clean up temporary files
rm -f /tmp/ispconfig-bom-extractor.py

# Finalize git tracking and apply retention
finalize_audit
