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
import argparse
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
                    'host': r"\$conf\['db'\]\['host'\]\s*=\s*['\"]([^'\"]+)['\"]",
                    'user': r"\$conf\['db'\]\['user'\]\s*=\s*['\"]([^'\"]+)['\"]", 
                    'password': r"\$conf\['db'\]\['password'\]\s*=\s*['\"]([^'\"]*)['\"]",
                    'database': r"\$conf\['db'\]\['database'\]\s*=\s*['\"]([^'\"]+)['\"]"
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
                    'version': '1.0'
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
            
            logger.info("Inventory generation completed successfully")
            return inventory
            
        except Exception as e:
            logger.error(f"Inventory generation failed: {e}")
            return None
        finally:
            self.close()

def main():
    parser = argparse.ArgumentParser(description='Generate ISPConfig database inventory')
    parser.add_argument('--host', help='Database host (or set ISPCONFIG_DB_HOST)')
    parser.add_argument('--user', help='Database user (or set ISPCONFIG_DB_USER)')
    parser.add_argument('--database', help='Database name (or set ISPCONFIG_DB_NAME)')
    parser.add_argument('--config', default='/usr/local/ispconfig/server/lib/config.inc.php',
                       help='ISPConfig config file path')
    parser.add_argument('-d', help='Output JSON file (default: stdout)')
    parser.add_argument('--pretty', action='store_true', help='Pretty print JSON')
    
    # Remove password argument - use environment or config file only
    args = parser.parse_args()
    
    # Create inventory instance (password will be read from env or config)
    inventory_tool = ISPConfigInventory(
        host=args.host,
        user=args.user,
        password=None,  # Force reading from env/config
        database=args.database
    )
    
    # Generate inventory
    inventory = inventory_tool.generate_inventory()
    
    if inventory is None:
        logger.error("Failed to generate inventory")
        logger.error("\nCredential troubleshooting:")
        logger.error("1. Check ISPConfig config: /usr/local/ispconfig/server/lib/config.inc.php")
        logger.error("2. Set environment: export ISPCONFIG_DB_PASSWORD='your_password'")
        logger.error("3. Verify database access: mysql -u ispconfig -p dbispconfig")
        sys.exit(1)
    
    # Output results
    json_output = json.dumps(inventory, indent=2 if args.pretty else None, default=str)
    
    if args.output:
        with open(args.output, 'w') as f:
            f.write(json_output)
        logger.info(f"Inventory saved to {args.output}")
    else:
        print(json_output)

if __name__ == '__main__':
    main()
