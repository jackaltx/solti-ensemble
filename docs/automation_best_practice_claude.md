# Automation Best Practices: Application Configuration Management

## Core Principle: Respect Native Configuration Tools

When automating application deployment and configuration, always prefer the application's native installation and configuration tools over manual file manipulation.

## The Rule

**Identify applications that provide their own generators, installers, or configuration CLIs. Use these tools as the primary configuration method rather than manually managing configuration files, services, and directory structures.**

## Why This Matters

### System Reliability

- **Consistency**: Native tools implement the "official" way to configure the application
- **Updates**: Application updates often include migration logic in their native tools
- **Edge Cases**: Native tools handle OS-specific quirks, permission requirements, and dependency management
- **Validation**: Built-in tools often validate configurations before applying them

### Maintenance Burden

- **Brittleness**: Manual file management breaks when applications change their internal structure
- **Technical Debt**: Hand-crafted configurations require ongoing maintenance as the application evolves
- **Support**: Using supported configuration methods means community help and documentation apply
- **Debugging**: Issues are easier to troubleshoot when following standard patterns

### Development Efficiency

- **Less Code**: Native tools eliminate the need for complex templating and service management
- **Fewer Bugs**: Reduces custom code that needs testing and maintenance
- **Faster Development**: Leverages existing, tested functionality

## Examples of Applications with Native Configuration Tools

### Web Applications & CMS

- **Ghost**: `ghost install`, `ghost config`, `ghost setup`
- **WordPress**: `wp core install`, `wp config create`
- **Drupal**: `drush site-install`, `drush config-import`
- **Django**: `manage.py migrate`, `manage.py collectstatic`
- **Rails**: `rails new`, `rails generate`, `rake db:setup`

### Databases

- **MySQL**: `mysql_secure_installation`, `mysqladmin`
- **PostgreSQL**: `initdb`, `createdb`, `pg_ctl`
- **MongoDB**: `mongod --config-file`
- **Redis**: `redis-server`, built-in configuration validation

### Infrastructure Tools

- **Docker**: `docker
