#!/bin/bash

# Fail2Ban Security Audit Script
# Compatible with ISPConfig audit framework
# Output: JSON with Git-based change tracking and retention management

SCRIPT_VERSION="1.0"
AUDIT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
HOSTNAME=$(hostname)

# Default values
AUDIT_DIR=""
RETAIN_COMMITS=""
OUTPUT_FILENAME="fail2ban-audit.json"

# Usage function
usage() {
    echo "Usage: $0 -d <audit_directory> [--retain <number>]"
    echo ""
    echo "Options:"
    echo "  -d <directory>    Directory to store audit reports (required)"
    echo "  --retain <number> Keep only the last N commits (optional, for development)"
    echo ""
    echo "Examples:"
    echo "  $0 -d /opt/audit/fail2ban-audit                    # Production mode (keep all history)"
    echo "  $0 -d /opt/audit/fail2ban-audit --retain 20       # Development mode (keep last 20 commits)"
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
   echo "WARNING: This script should be run as root for full access to fail2ban logs" >&2
fi

# Check if fail2ban is installed and running
if ! command -v fail2ban-client >/dev/null 2>&1; then
    echo "ERROR: fail2ban-client not found. Is fail2ban installed?" >&2
    exit 1
fi

if ! systemctl is-active fail2ban >/dev/null 2>&1; then
    echo "WARNING: fail2ban service is not active" >&2
fi

# Setup audit directory and git repo
setup_audit_repo() {
    echo "Setting up fail2ban audit repository at: $AUDIT_DIR"
    
    # Create directory if it doesn't exist
    mkdir -p "$AUDIT_DIR"
    cd "$AUDIT_DIR"
    
    # Initialize git repo if not exists
    if [[ ! -d ".git" ]]; then
        git init
        git config user.name "Fail2Ban Audit"
        git config user.email "fail2ban-audit@$(hostname)"
        echo "Initialized new git repository for fail2ban audit tracking"
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

# Function to safely escape JSON strings
escape_json() {
    local input="$1"
    # Escape backslashes, quotes, and newlines for JSON
    echo "$input" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n' | sed 's/\\n$//'
}

# Get fail2ban status
get_fail2ban_status() {
    local status_output
    status_output=$(fail2ban-client status 2>/dev/null || echo "fail2ban_unavailable")
    
    if [[ "$status_output" == "fail2ban_unavailable" ]]; then
        echo "unavailable"
        return
    fi
    
    # Extract jail list
    local jail_list
    jail_list=$(echo "$status_output" | grep "Jail list" | sed -E 's/^[^:]+:[ \t]+//' | sed 's/,//g' || echo "")
    
    echo "$jail_list"
}

# Get jail status details
get_jail_status() {
    local jail="$1"
    local jail_status
    jail_status=$(fail2ban-client status "$jail" 2>/dev/null || echo "jail_unavailable")
    
    if [[ "$jail_status" == "jail_unavailable" ]]; then
        echo "unavailable"
        return
    fi
    
    # Parse jail status output
    local total_failed=$(echo "$jail_status" | grep "Total failed:" | awk '{print $NF}' || echo "0")
    local total_banned=$(echo "$jail_status" | grep "Total banned:" | awk '{print $NF}' || echo "0")
    local currently_failed=$(echo "$jail_status" | grep "Currently failed:" | awk '{print $NF}' || echo "0")
    local currently_banned=$(echo "$jail_status" | grep "Currently banned:" | awk '{print $NF}' || echo "0")
    local banned_ips=$(echo "$jail_status" | grep "Banned IP list:" | sed 's/.*Banned IP list:[ \t]*//' || echo "")
    
    # Create JSON object for jail
    cat << EOF
{
  "total_failed": $total_failed,
  "total_banned": $total_banned,
  "currently_failed": $currently_failed,
  "currently_banned": $currently_banned,
  "banned_ips": "$(escape_json "$banned_ips")",
  "raw_status": "$(escape_json "$jail_status")"
}
EOF
}

# Analyze fail2ban logs
analyze_fail2ban_logs() {
    local log_paths="/var/log/fail2ban*"
    local analysis_period="7" # Last 7 days
    local cutoff_date=$(date -d "$analysis_period days ago" +%Y-%m-%d)
    
    echo "Analyzing fail2ban logs from the last $analysis_period days (since $cutoff_date)"
    
    # Most frequently banned IPs
    local top_banned_ips
    if ls $log_paths >/dev/null 2>&1; then
        top_banned_ips=$(zgrep -h "Ban " $log_paths 2>/dev/null | \
                        awk -v cutoff="$cutoff_date" '$1 >= cutoff {print $NF}' | \
                        sort | uniq -c | sort -nr | head -20 || echo "")
    else
        top_banned_ips=""
    fi
    
    # Banned IPs by service
    local banned_by_service
    if ls $log_paths >/dev/null 2>&1; then
        banned_by_service=$(grep "Ban " $log_paths 2>/dev/null | \
                           awk -v cutoff="$cutoff_date" -F[\ \:] '$1 >= cutoff {print $11,$9}' | \
                           sort | uniq -c | sort -nr | head -30 || echo "")
    else
        banned_by_service=""
    fi
    
    # Generate GeoIP data if available
    local geoip_data=""
    if command -v geoiplookup >/dev/null 2>&1 && [[ -n "$top_banned_ips" ]]; then
        geoip_data=$(echo "$top_banned_ips" | head -10 | awk '{print $2}' | while read ip; do
            if [[ -n "$ip" ]]; then
                local geo=$(geoiplookup -l "$ip" 2>/dev/null | cut -d ':' -f2 || echo "Unknown")
                echo "$ip: $geo"
            fi
        done)
    fi
    
    # Count log files and get date range
    local log_file_count=0
    local oldest_log=""
    local newest_log=""
    
    if ls $log_paths >/dev/null 2>&1; then
        log_file_count=$(ls $log_paths 2>/dev/null | wc -l)
        oldest_log=$(ls -tr $log_paths 2>/dev/null | head -1)
        newest_log=$(ls -t $log_paths 2>/dev/null | head -1)
    fi
    
    # Return structured data
    cat << EOF
{
  "analysis_period_days": $analysis_period,
  "cutoff_date": "$cutoff_date",
  "log_file_count": $log_file_count,
  "oldest_log_file": "$(escape_json "$oldest_log")",
  "newest_log_file": "$(escape_json "$newest_log")",
  "top_banned_ips": "$(escape_json "$top_banned_ips")",
  "banned_by_service": "$(escape_json "$banned_by_service")",
  "geoip_available": $(command -v geoiplookup >/dev/null 2>&1 && echo "true" || echo "false"),
  "geoip_data": "$(escape_json "$geoip_data")"
}
EOF
}

# Get fail2ban configuration summary
get_fail2ban_config() {
    local config_dir="/etc/fail2ban"
    local main_config="$config_dir/fail2ban.conf"
    local jail_config="$config_dir/jail.conf"
    local jail_local="$config_dir/jail.local"
    
    # Check configuration files
    local config_files_found=""
    for config_file in "$main_config" "$jail_config" "$jail_local"; do
        if [[ -f "$config_file" ]]; then
            config_files_found="$config_files_found,$config_file"
        fi
    done
    config_files_found="${config_files_found#,}" # Remove leading comma
    
    # Get jail.d directory contents
    local jail_d_files=""
    if [[ -d "$config_dir/jail.d" ]]; then
        jail_d_files=$(find "$config_dir/jail.d" -name "*.conf" -o -name "*.local" 2>/dev/null | sort | tr '\n' ',' | sed 's/,$//')
    fi
    
    # Get filter.d directory count
    local filter_count=0
    if [[ -d "$config_dir/filter.d" ]]; then
        filter_count=$(find "$config_dir/filter.d" -name "*.conf" 2>/dev/null | wc -l)
    fi
    
    # Get action.d directory count
    local action_count=0
    if [[ -d "$config_dir/action.d" ]]; then
        action_count=$(find "$config_dir/action.d" -name "*.conf" 2>/dev/null | wc -l)
    fi
    
    cat << EOF
{
  "config_directory": "$config_dir",
  "main_config_exists": $([ -f "$main_config" ] && echo "true" || echo "false"),
  "jail_config_exists": $([ -f "$jail_config" ] && echo "true" || echo "false"),
  "jail_local_exists": $([ -f "$jail_local" ] && echo "true" || echo "false"),
  "config_files_found": "$(escape_json "$config_files_found")",
  "jail_d_files": "$(escape_json "$jail_d_files")",
  "filter_count": $filter_count,
  "action_count": $action_count,
  "config_permissions": {
    "config_dir": "$(stat -c '%a:%U:%G' "$config_dir" 2>/dev/null || echo "unknown")",
    "main_config": "$(stat -c '%a:%U:%G' "$main_config" 2>/dev/null || echo "not_found")",
    "jail_local": "$(stat -c '%a:%U:%G' "$jail_local" 2>/dev/null || echo "not_found")"
  }
}
EOF
}

# Setup the audit repository
setup_audit_repo

OUTPUT_FILE="$AUDIT_DIR/$OUTPUT_FILENAME"

echo "Starting Fail2Ban Security Audit..."
echo "Output file: $OUTPUT_FILE"

# Get jail list
JAIL_LIST=$(get_fail2ban_status)

# Initialize JSON
cat > "$OUTPUT_FILE" << EOF
{
  "audit_info": {
    "version": "$SCRIPT_VERSION",
    "date": "$AUDIT_DATE",
    "hostname": "$HOSTNAME",
    "purpose": "Fail2Ban Security Baseline Audit",
    "audit_directory": "$AUDIT_DIR",
    "retention_policy": $([ -n "$RETAIN_COMMITS" ] && echo "\"Last $RETAIN_COMMITS commits\"" || echo "\"Keep all history\"")
  },
  "system_info": {
    "os_release": "$(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)",
    "kernel": "$(uname -r)",
    "architecture": "$(uname -m)"
  },
  "fail2ban_service": {
    "installed": $(command -v fail2ban-client >/dev/null 2>&1 && echo "true" || echo "false"),
    "service_active": "$(systemctl is-active fail2ban 2>/dev/null || echo 'inactive')",
    "service_enabled": "$(systemctl is-enabled fail2ban 2>/dev/null || echo 'unknown')",
    "version": "$(fail2ban-client version 2>/dev/null || echo 'unknown')"
  },
  "jail_overview": {
    "jail_list_raw": "$(escape_json "$JAIL_LIST")",
    "jail_count": $(echo "$JAIL_LIST" | wc -w),
    "jails_active": [
EOF

# Process each jail
if [[ "$JAIL_LIST" != "unavailable" && -n "$JAIL_LIST" ]]; then
    first_jail=true
    for jail in $JAIL_LIST; do
        if [[ "$first_jail" == true ]]; then
            first_jail=false
        else
            echo "," >> "$OUTPUT_FILE"
        fi
        
        echo "Processing jail: $jail"
        cat >> "$OUTPUT_FILE" << EOF
      {
        "jail_name": "$jail",
        "status": $(get_jail_status "$jail")
      }
EOF
    done
fi

cat >> "$OUTPUT_FILE" << EOF
    ]
  },
  "log_analysis": $(analyze_fail2ban_logs),
  "configuration": $(get_fail2ban_config),
  "security_summary": {
    "total_jails_configured": $(echo "$JAIL_LIST" | wc -w),
    "service_operational": $(systemctl is-active fail2ban >/dev/null 2>&1 && echo "true" || echo "false"),
    "log_files_accessible": $(ls /var/log/fail2ban* >/dev/null 2>&1 && echo "true" || echo "false"),
    "geoip_capabilities": $(command -v geoiplookup >/dev/null 2>&1 && echo "true" || echo "false"),
    "configuration_customized": $([ -f "/etc/fail2ban/jail.local" ] && echo "true" || echo "false")
  },
  "audit_metadata": {
    "script_version": "$SCRIPT_VERSION",
    "execution_time": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "data_sources": ["fail2ban-client", "/var/log/fail2ban*", "/etc/fail2ban/"],
    "analysis_scope": "System-wide fail2ban activity and configuration"
  }
}
EOF

# Finalize git tracking
finalize_audit() {
    cd "$AUDIT_DIR"
    
    # Check if there are any changes
    if git diff --quiet "$OUTPUT_FILENAME" 2>/dev/null; then
        echo "No fail2ban changes detected since last audit"
        COMMIT_MSG="Fail2ban audit $AUDIT_DATE - No changes"
        git add "$OUTPUT_FILENAME" 2>/dev/null || true
        git commit --allow-empty -m "$COMMIT_MSG" >/dev/null 2>&1
    else
        echo "Fail2ban changes detected - committing to audit history"
        if git rev-parse --verify HEAD >/dev/null 2>&1; then
            echo "Summary of changes:"
            git diff --stat "$OUTPUT_FILENAME" 2>/dev/null || echo "  (New fail2ban audit file)"
        fi
        COMMIT_MSG="Fail2ban audit $AUDIT_DATE"
        git add "$OUTPUT_FILENAME"
        git commit -m "$COMMIT_MSG" >/dev/null 2>&1
    fi
    
    # Apply retention policy after committing
    apply_retention
    
    echo ""
    echo "Fail2Ban Audit History Summary:"
    echo "- Repository: $AUDIT_DIR"
    echo "- Total commits: $(git rev-list --count HEAD 2>/dev/null || echo "1")"
    if [[ -n "$RETAIN_COMMITS" ]]; then
        echo "- Retention policy: Last $RETAIN_COMMITS commits"
    else
        echo "- Retention policy: Keep all history (production mode)"
    fi
}

echo "Fail2Ban audit completed successfully!"
echo "Report saved to: $OUTPUT_FILE"
echo ""
echo "Quick Summary:"
if [[ "$JAIL_LIST" != "unavailable" ]]; then
    echo "- Active jails: $(echo "$JAIL_LIST" | wc -w)"
    echo "- Jail list: $JAIL_LIST"
else
    echo "- Fail2ban not accessible or not running"
fi
echo "- Service status: $(systemctl is-active fail2ban 2>/dev/null || echo 'inactive')"
echo "- Log analysis: Last 7 days of activity"

# Finalize git tracking and apply retention
finalize_audit
