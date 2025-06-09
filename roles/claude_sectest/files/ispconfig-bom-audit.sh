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
    cat > /tmp/ispconfig-bom-extractor.py << 'EOF'
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

class ISPConfigInventory:
    def __init__(self, host=None, user=None, password=None, database=None):
        self.connection_params = self._get_db_credentials(host, user, password, database)
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
    
    def _get_db_credentials(self, host, user, password, database):
        config_creds = self._parse_ispconfig_config()
        credentials = {
            'host': host or os.getenv('ISPCONFIG_DB_HOST') or config_creds.get('host') or 'localhost',
            'user': user or os.getenv('ISPCONFIG_DB_USER') or config_creds.get('user') or 'ispconfig',
            'password': password or os.getenv('ISPCONFIG_DB_PASSWORD') or config_creds.get('password') or '',
            'database': database or os.getenv('ISPCONFIG_DB_NAME') or config_creds.get('database') or 'dbispconfig',
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
    
    def get_web_domains(self):
        """Extract website domains and configurations with hierarchical structure"""
        query = """
        SELECT 
            w.domain_id, w.domain, w.document_root, w.active, w.type, w.parent_domain_id,
            w.redirect_type, w.redirect_path, w.ssl, w.ssl_letsencrypt,
            w.apache_directives, w.nginx_directives, w.php_open_basedir, w.custom_php_ini,
            w.rewrite_rules, w.proxy_directives, w.vhost_type, w.php, w.subdomain,
            w.directive_snippets_id, w.system_user, w.system_group, w.hd_quota,
            w.traffic_quota, w.cgi, w.ssi, w.suexec, w.perl, w.python, w.ruby,
            w.ssl_state, w.ssl_locality, w.ssl_organisation, w.ssl_country,
            w.allow_override, w.stats_type, w.backup_interval, w.backup_copies,
            c.company_name as client_name, c.client_id,
            parent.domain as parent_domain_name
        FROM web_domain w
        LEFT JOIN client c ON w.sys_groupid = c.sys_groupid
        LEFT JOIN web_domain parent ON w.parent_domain_id = parent.domain_id
        ORDER BY w.parent_domain_id, w.domain
        """
        domains = self.execute_query(query)
        logger.info(f"Found {len(domains)} web domains")
        
        # Build hierarchical structure
        main_domains = {}
        all_domains_flat = []
        
        directive_analysis = {
            'apache_directives_count': 0, 'nginx_directives_count': 0,
            'php_custom_count': 0, 'rewrite_rules_count': 0,
            'proxy_directives_count': 0, 'php_basedir_count': 0
        }
        
        security_analysis = {
            'ssl_enabled_count': 0, 'letsencrypt_count': 0,
            'suexec_disabled_count': 0, 'cgi_enabled_count': 0,
            'custom_directives_count': 0, 'redirect_domains_count': 0
        }
        
        # First pass: categorize and analyze all domains
        for domain in domains:
            # Determine domain category and relevant fields
            domain_category = self._categorize_domain(domain)
            domain['domain_category'] = domain_category
            
            # Add directive analysis flags
            domain['has_apache_directives'] = bool(domain['apache_directives'] and domain['apache_directives'].strip())
            domain['has_nginx_directives'] = bool(domain['nginx_directives'] and domain['nginx_directives'].strip())
            domain['has_php_custom'] = bool(domain['custom_php_ini'] and domain['custom_php_ini'].strip())
            domain['has_rewrite_rules'] = bool(domain['rewrite_rules'] and domain['rewrite_rules'].strip())
            domain['has_proxy_directives'] = bool(domain['proxy_directives'] and domain['proxy_directives'].strip())
            domain['has_php_basedir'] = bool(domain['php_open_basedir'] and domain['php_open_basedir'].strip())
            
            # Add security flags
            domain['ssl_enabled'] = domain['ssl'] == 'y'
            domain['letsencrypt_enabled'] = domain['ssl_letsencrypt'] == 'y'
            domain['suexec_enabled'] = domain['suexec'] == 'y'
            domain['has_redirects'] = bool(domain['redirect_type'] and domain['redirect_type'] != '')
            
            # Count directive usage
            if domain['has_apache_directives']:
                directive_analysis['apache_directives_count'] += 1
            if domain['has_nginx_directives']:
                directive_analysis['nginx_directives_count'] += 1
            if domain['has_php_custom']:
                directive_analysis['php_custom_count'] += 1
            if domain['has_rewrite_rules']:
                directive_analysis['rewrite_rules_count'] += 1
            if domain['has_proxy_directives']:
                directive_analysis['proxy_directives_count'] += 1
            if domain['has_php_basedir']:
                directive_analysis['php_basedir_count'] += 1
            
            # Count security indicators
            if domain['ssl_enabled']:
                security_analysis['ssl_enabled_count'] += 1
            if domain['letsencrypt_enabled']:
                security_analysis['letsencrypt_count'] += 1
            if not domain['suexec_enabled']:
                security_analysis['suexec_disabled_count'] += 1
            if domain['cgi'] == 'y':
                security_analysis['cgi_enabled_count'] += 1
            if domain['has_redirects']:
                security_analysis['redirect_domains_count'] += 1
            if (domain['has_apache_directives'] or domain['has_nginx_directives'] or 
                domain['has_php_custom'] or domain['has_rewrite_rules']):
                security_analysis['custom_directives_count'] += 1
            
            # Filter fields relevant to domain type
            domain['relevant_fields'] = self._get_relevant_fields(domain_category)
            domain['inherited_from_parent'] = self._check_inheritance(domain)
            
            all_domains_flat.append(domain)
            
            # Build hierarchical structure
            if domain_category == 'main_domain':
                domain['subdomains'] = []
                domain['aliases'] = []
                domain['redirects'] = []
                main_domains[domain['domain_id']] = domain
        
        # Second pass: attach children to parents
        for domain in all_domains_flat:
            if domain['parent_domain_id'] and domain['parent_domain_id'] > 0:
                parent_id = domain['parent_domain_id']
                if parent_id in main_domains:
                    category = domain['domain_category']
                    if category == 'subdomain':
                        main_domains[parent_id]['subdomains'].append(domain)
                    elif category == 'alias_domain':
                        main_domains[parent_id]['aliases'].append(domain)
                    elif category == 'redirect':
                        main_domains[parent_id]['redirects'].append(domain)
        
        # Calculate hierarchy statistics
        hierarchy_stats = {
            'main_domains_count': len(main_domains),
            'subdomains_count': sum(len(d['subdomains']) for d in main_domains.values()),
            'aliases_count': sum(len(d['aliases']) for d in main_domains.values()),
            'redirects_count': sum(len(d['redirects']) for d in main_domains.values()),
            'domains_with_children': len([d for d in main_domains.values() 
                                        if len(d['subdomains']) + len(d['aliases']) + len(d['redirects']) > 0])
        }
        
        return {
            'total_count': len(all_domains_flat),
            'active_count': len([d for d in all_domains_flat if d['active'] == 'y']),
            'hierarchy_statistics': hierarchy_stats,
            'directive_analysis': directive_analysis,
            'security_analysis': security_analysis,
            'main_domains': list(main_domains.values()),
            'all_domains_flat': all_domains_flat,
            'domain_relationships': self._analyze_relationships(main_domains)
        }
    
    def _categorize_domain(self, domain):
        """Categorize domain based on ISPConfig usage patterns"""
        if domain['parent_domain_id'] == 0 or domain['parent_domain_id'] is None:
            return 'main_domain'
        elif domain['type'] == 'subdomain':
            return 'subdomain'
        elif domain['type'] == 'alias':
            return 'alias_domain'
        elif domain['redirect_type'] and domain['redirect_type'] != '':
            return 'redirect'
        elif domain['parent_domain_id'] > 0:
            # Fallback for unclear cases
            return 'subdomain'
        else:
            return 'unknown'
    
    def _get_relevant_fields(self, category):
        """Return list of fields relevant to each domain category"""
        base_fields = ['domain_id', 'domain', 'active', 'client_name']
        
        field_sets = {
            'main_domain': base_fields + [
                'document_root', 'system_user', 'system_group', 'ssl', 'ssl_letsencrypt',
                'apache_directives', 'nginx_directives', 'php_open_basedir', 'custom_php_ini',
                'rewrite_rules', 'proxy_directives', 'php', 'cgi', 'ssi', 'suexec',
                'allow_override', 'stats_type', 'backup_interval', 'hd_quota', 'traffic_quota'
            ],
            'subdomain': base_fields + [
                'parent_domain_id', 'parent_domain_name', 'document_root', 'ssl',
                'apache_directives', 'nginx_directives', 'custom_php_ini', 'php',
                'redirect_type', 'redirect_path'
            ],
            'alias_domain': base_fields + [
                'parent_domain_id', 'parent_domain_name', 'redirect_type', 'redirect_path'
            ],
            'redirect': base_fields + [
                'parent_domain_id', 'parent_domain_name', 'redirect_type', 'redirect_path'
            ]
        }
        
        return field_sets.get(category, base_fields)
    
    def _check_inheritance(self, domain):
        """Check what settings are inherited from parent"""
        inheritance_info = {}
        
        if domain['parent_domain_id'] and domain['parent_domain_id'] > 0:
            # These typically inherit from parent unless explicitly overridden
            inheritance_info['inherits_ssl'] = not domain['ssl'] or domain['ssl'] == 'n'
            inheritance_info['inherits_php_settings'] = not domain['custom_php_ini']
            inheritance_info['has_custom_directives'] = bool(
                domain['apache_directives'] or domain['nginx_directives']
            )
            inheritance_info['overrides_parent'] = bool(
                domain['apache_directives'] or domain['nginx_directives'] or 
                domain['custom_php_ini'] or domain['php_open_basedir']
            )
        
        return inheritance_info
    
    def _analyze_relationships(self, main_domains):
        """Analyze domain relationships for security implications"""
        relationships = {
            'inheritance_conflicts': [],
            'ssl_mismatches': [],
            'directive_overrides': [],
            'security_concerns': []
        }
        
        for main_domain in main_domains.values():
            # Check SSL inheritance issues
            if main_domain['ssl'] == 'y':
                for subdomain in main_domain['subdomains']:
                    if subdomain['ssl'] == 'n':
                        relationships['ssl_mismatches'].append({
                            'parent': main_domain['domain'],
                            'child': subdomain['domain'],
                            'issue': 'Parent has SSL, subdomain does not'
                        })
            
            # Check directive overrides
            for subdomain in main_domain['subdomains']:
                if subdomain['inherited_from_parent'].get('overrides_parent'):
                    relationships['directive_overrides'].append({
                        'parent': main_domain['domain'],
                        'child': subdomain['domain'],
                        'overrides': [
                            k for k, v in {
                                'apache_directives': subdomain['apache_directives'],
                                'nginx_directives': subdomain['nginx_directives'],
                                'custom_php_ini': subdomain['custom_php_ini']
                            }.items() if v
                        ]
                    })
        
        return relationships
    
    def get_mail_domains(self):
        query = """
        SELECT md.domain_id, md.domain, md.active, md.server_id,
               c.company_name as client_name, c.client_id
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
        query = """
        SELECT mu.mailuser_id, mu.email, mu.login, mu.maildir, mu.quota,
               mu.cc, mu.forward_in_lda, mu.sender_cc, mu.access,
               md.domain, c.company_name as client_name
        FROM mail_user mu
        LEFT JOIN mail_domain md ON SUBSTRING_INDEX(mu.email, '@', -1) = md.domain
        LEFT JOIN client c ON mu.sys_groupid = c.sys_groupid
        ORDER BY mu.email
        """
        users = self.execute_query(query)
        logger.info(f"Found {len(users)} mail users")
        total_quota = sum([int(u['quota'] or 0) for u in users if u['quota']])
        active_users = [u for u in users if u['access'] == 'y']
        return {
            'total_count': len(users),
            'active_count': len(active_users),
            'total_quota_mb': total_quota,
            'users': users
        }
    
    def get_databases(self):
        query = """
        SELECT wd.database_id, wd.database_name, wd.database_user_id,
               wd.database_charset, wd.remote_access, wd.remote_ips, wd.active,
               c.company_name as client_name, c.client_id
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
        query = """
        SELECT c.client_id, c.company_name, c.contact_name, c.email, c.username,
               c.limit_web_domain, c.limit_web_quota, c.limit_maildomain,
               c.limit_mailbox, c.limit_database, c.locked
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
        query = """
        SELECT z.id, z.origin, z.ns, z.mbox, z.serial, z.refresh, z.retry,
               z.expire, z.minimum, z.ttl, z.active, z.xfer,
               z.dnssec_wanted, z.dnssec_initialized, c.company_name as client_name
        FROM dns_soa z
        LEFT JOIN client c ON z.sys_groupid = c.sys_groupid
        ORDER BY z.origin
        """
        zones = self.execute_query(query)
        logger.info(f"Found {len(zones)} DNS zones")
        return {
            'total_count': len(zones),
            'active_count': len([z for z in zones if z['active'] == 'Y']),
            'dnssec_enabled_count': len([z for z in zones if z['dnssec_wanted'] == 'Y']),
            'zones': zones
        }
    
    def get_directive_snippets(self):
        query = """
        SELECT ds.directive_snippets_id, ds.name, ds.type, ds.snippet,
               ds.customer_viewable, ds.required_php_snippets, ds.active,
               ds.master_directive_snippets_id
        FROM directive_snippets ds
        WHERE ds.active = 'y'
        ORDER BY ds.type, ds.name
        """
        snippets = self.execute_query(query)
        logger.info(f"Found {len(snippets)} directive snippets")
        snippet_types = {}
        for snippet in snippets:
            snippet_type = snippet['type'] or 'unknown'
            if snippet_type not in snippet_types:
                snippet_types[snippet_type] = 0
            snippet_types[snippet_type] += 1
            snippet['has_content'] = bool(snippet['snippet'] and snippet['snippet'].strip())
            snippet['content_length'] = len(snippet['snippet'] or '')
        return {
            'total_count': len(snippets),
            'types': snippet_types,
            'snippets': snippets
        }
    
    def get_ftp_users(self):
        query = """
        SELECT fu.ftp_user_id, fu.username, fu.quota_size, fu.active,
               fu.uid, fu.gid, fu.dir, fu.expires,
               w.domain as parent_domain, c.company_name as client_name
        FROM ftp_user fu
        LEFT JOIN web_domain w ON fu.parent_domain_id = w.domain_id
        LEFT JOIN client c ON fu.sys_groupid = c.sys_groupid
        ORDER BY fu.username
        """
        users = self.execute_query(query)
        logger.info(f"Found {len(users)} FTP users")
        return {
            'total_count': len(users),
            'active_count': len([u for u in users if u['active'] == 'y']),
            'users': users
        }
    
    def get_shell_users(self):
        query = """
        SELECT su.shell_user_id, su.username, su.quota_size, su.active,
               su.puser, su.pgroup, su.shell, su.dir, su.chroot, su.ssh_rsa,
               w.domain as parent_domain, c.company_name as client_name
        FROM shell_user su
        LEFT JOIN web_domain w ON su.parent_domain_id = w.domain_id
        LEFT JOIN client c ON su.sys_groupid = c.sys_groupid
        ORDER BY su.username
        """
        users = self.execute_query(query)
        logger.info(f"Found {len(users)} shell users")
        shell_analysis = {
            'chroot_enabled_count': len([u for u in users if u['chroot'] and u['chroot'] != '']),
            'ssh_key_count': len([u for u in users if u['ssh_rsa'] and u['ssh_rsa'].strip()]),
            'bash_users': len([u for u in users if u['shell'] == '/bin/bash']),
            'restricted_shells': len([u for u in users if u['shell'] and u['shell'] != '/bin/bash'])
        }
        for user in users:
            user['has_ssh_key'] = bool(user['ssh_rsa'] and user['ssh_rsa'].strip())
            user['has_chroot'] = bool(user['chroot'] and user['chroot'].strip())
        return {
            'total_count': len(users),
            'active_count': len([u for u in users if u['active'] == 'y']),
            'security_analysis': shell_analysis,
            'users': users
        }
    
    def get_webdav_users(self):
        query = """
        SELECT wu.webdav_user_id, wu.username, wu.active, wu.dir,
               w.domain as parent_domain, c.company_name as client_name
        FROM webdav_user wu
        LEFT JOIN web_domain w ON wu.parent_domain_id = w.domain_id
        LEFT JOIN client c ON wu.sys_groupid = c.sys_groupid
        ORDER BY wu.username
        """
        users = self.execute_query(query)
        logger.info(f"Found {len(users)} WebDAV users")
        return {
            'total_count': len(users),
            'active_count': len([u for u in users if u['active'] == 'y']),
            'users': users
        }
    
    def get_dns_records(self):
        query = """
        SELECT dr.id, dr.zone, dr.name, dr.type, dr.data, dr.aux, dr.ttl, dr.active,
               ds.origin as zone_name
        FROM dns_rr dr
        LEFT JOIN dns_soa ds ON dr.zone = ds.id
        WHERE dr.active = 'Y'
        ORDER BY ds.origin, dr.type, dr.name
        """
        records = self.execute_query(query)
        logger.info(f"Found {len(records)} DNS records")
        record_types = {}
        for record in records:
            record_type = record['type']
            if record_type not in record_types:
                record_types[record_type] = 0
            record_types[record_type] += 1
        return {
            'total_count': len(records),
            'record_types': record_types,
            'records': records
        }
    
    def get_mail_filters(self):
        query = """
        SELECT mf.filter_id, mf.mailuser_id, mf.rulename, mf.source,
               mf.searchterm, mf.op, mf.action, mf.target, mf.active,
               mu.email as mailuser_email
        FROM mail_user_filter mf
        LEFT JOIN mail_user mu ON mf.mailuser_id = mu.mailuser_id
        ORDER BY mu.email, mf.rulename
        """
        filters = self.execute_query(query)
        logger.info(f"Found {len(filters)} mail filters")
        return {
            'total_count': len(filters),
            'active_count': len([f for f in filters if f['active'] == 'y']),
            'filters': filters
        }
    
    def generate_inventory(self):
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
                'mail_filters': self.get_mail_filters(),
                'databases': self.get_databases(),
                'clients': self.get_clients(),
                'dns_zones': self.get_dns_zones(),
                'dns_records': self.get_dns_records(),
                'directive_snippets': self.get_directive_snippets(),
                'ftp_users': self.get_ftp_users(),
                'shell_users': self.get_shell_users(),
                'webdav_users': self.get_webdav_users()
            }
            
            inventory['summary'] = {
                'total_web_domains': inventory['web_domains']['total_count'],
                'active_web_domains': inventory['web_domains']['active_count'],
                'main_domains': inventory['web_domains']['hierarchy_statistics']['main_domains_count'],
                'subdomains': inventory['web_domains']['hierarchy_statistics']['subdomains_count'],
                'alias_domains': inventory['web_domains']['hierarchy_statistics']['aliases_count'],
                'redirect_domains': inventory['web_domains']['hierarchy_statistics']['redirects_count'],
                'domains_with_children': inventory['web_domains']['hierarchy_statistics']['domains_with_children'],
                'domains_with_apache_directives': inventory['web_domains']['directive_analysis']['apache_directives_count'],
                'domains_with_nginx_directives': inventory['web_domains']['directive_analysis']['nginx_directives_count'],
                'domains_with_custom_php': inventory['web_domains']['directive_analysis']['php_custom_count'],
                'domains_with_rewrite_rules': inventory['web_domains']['directive_analysis']['rewrite_rules_count'],
                'total_mail_domains': inventory['mail_domains']['total_count'],
                'total_mail_users': inventory['mail_users']['total_count'],
                'total_mail_filters': inventory['mail_filters']['total_count'],
                'total_databases': inventory['databases']['total_count'],
                'total_clients': inventory['clients']['total_count'],
                'total_dns_zones': inventory['dns_zones']['total_count'],
                'total_dns_records': inventory['dns_records']['total_count'],
                'total_directive_snippets': inventory['directive_snippets']['total_count'],
                'total_ftp_users': inventory['ftp_users']['total_count'],
                'total_shell_users': inventory['shell_users']['total_count'],
                'total_webdav_users': inventory['webdav_users']['total_count'],
                'security_indicators': {
                    'ssl_enabled_domains': inventory['web_domains']['security_analysis']['ssl_enabled_count'],
                    'letsencrypt_domains': inventory['web_domains']['security_analysis']['letsencrypt_count'],
                    'suexec_disabled_domains': inventory['web_domains']['security_analysis']['suexec_disabled_count'],
                    'cgi_enabled_domains': inventory['web_domains']['security_analysis']['cgi_enabled_count'],
                    'domains_with_custom_directives': inventory['web_domains']['security_analysis']['custom_directives_count'],
                    'redirect_domains': inventory['web_domains']['security_analysis']['redirect_domains_count'],
                    'dnssec_zones': inventory['dns_zones']['dnssec_enabled_count'],
                    'shell_users_with_chroot': inventory['shell_users']['security_analysis']['chroot_enabled_count'],
                    'shell_users_with_ssh_keys': inventory['shell_users']['security_analysis']['ssh_key_count'],
                    'databases_with_remote_access': inventory['databases']['remote_access_count'],
                    'ssl_inheritance_mismatches': len(inventory['web_domains']['domain_relationships']['ssl_mismatches']),
                    'directive_overrides': len(inventory['web_domains']['domain_relationships']['directive_overrides'])
                }
            }
            
            logger.info("BOM inventory generation completed successfully")
            return inventory
            
        except Exception as e:
            logger.error(f"BOM inventory generation failed: {e}")
            return None
        finally:
            self.close()

def main(output_file):
    inventory_tool = ISPConfigInventory(
        host=None,
        user=None,
        password=None,
        database=None
    )
    
    inventory = inventory_tool.generate_inventory()
    
    if inventory is None:
        logger.error("Failed to generate BOM inventory")
        logger.error("\nCredential troubleshooting:")
        logger.error("1. Check ISPConfig config: /usr/local/ispconfig/server/lib/config.inc.php")
        logger.error("2. Set environment: export ISPCONFIG_DB_PASSWORD='your_password'")
        logger.error("3. Verify database access: mysql -u ispconfig -p dbispconfig")
        sys.exit(1)
    
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
