#!/bin/bash

# ISPConfig3 DNS Security Records Audit Script
# Validates SPF, DKIM, DMARC, and MX records for domains
# Output: JSON with Git-based change tracking and retention management

SCRIPT_VERSION="1.03"
AUDIT_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
HOSTNAME=$(hostname)

# Default values
AUDIT_DIR=""
RETAIN_COMMITS=""
OUTPUT_FILENAME="ispconfig-named-audit.json"

# Usage function
usage() {
    echo "Usage: $0 -d <audit_directory> [--retain <number>] [--domains-file <file>] [--ispconfig-db]"
    echo ""
    echo "Options:"
    echo "  -d <directory>     Directory to store audit reports (required)"
    echo "  --retain <number>  Keep only the last N commits (optional, for development)"
    echo "  --domains-file <file>  Read domains from file (one per line)"
    echo "  --ispconfig-db     Extract domains from ISPConfig database (default)"
    echo ""
    echo "Examples:"
    echo "  $0 -d /opt/audit/ispconfig-named-audit                      # ISPConfig DB mode"
    echo "  $0 -d /opt/audit/ispconfig-named-audit --retain 20         # Development mode"
    echo "  $0 -d /opt/audit/ispconfig-named-audit --domains-file /tmp/domains.txt"
    exit 1
}

# Default mode
DOMAIN_SOURCE="ispconfig-db"
DOMAINS_FILE=""

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
        --domains-file)
            DOMAINS_FILE="$2"
            DOMAIN_SOURCE="file"
            shift 2
            ;;
        --ispconfig-db)
            DOMAIN_SOURCE="ispconfig-db"
            shift
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

# Check if running as root (needed for ISPConfig database access)
if [[ $EUID -ne 0 && "$DOMAIN_SOURCE" == "ispconfig-db" ]]; then
   echo "ERROR: This script must be run as root for ISPConfig database access" >&2
   exit 1
fi

# Setup audit directory and git repo
setup_audit_repo() {
    echo "Setting up DNS audit repository at: $AUDIT_DIR"
    
    # Create directory if it doesn't exist
    mkdir -p "$AUDIT_DIR"
    cd "$AUDIT_DIR"
    
    # Initialize git repo if not exists
    if [[ ! -d ".git" ]]; then
        git init
        git config user.name "ISPConfig DNS Audit"
        git config user.email "dns-audit@$(hostname)"
        echo "Initialized new git repository for DNS audit tracking"
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

# Check required tools
check_dependencies() {
    local missing_tools=()
    
    for tool in dig host nslookup; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo "ERROR: Missing required tools: ${missing_tools[*]}" >&2
        echo "Install with: apt-get install dnsutils" >&2
        exit 1
    fi
}

# Get domains from ISPConfig database
get_ispconfig_domains() {
    echo "Extracting domains from ISPConfig database..." >&2
    
    # Try to get domains from mail_domain and web_domain tables
    local domains=()
    
    # Mail domains (active only)
    if command -v mysql &> /dev/null; then
        while IFS= read -r domain; do
            [[ -n "$domain" ]] && domains+=("$domain")
        # done < <(mysql -N -e "SELECT DISTINCT domain FROM mail_domain WHERE active='y' UNION SELECT DISTINCT domain FROM web_domain WHERE active='y' AND parent_domain_id=0;" dbispconfig 2>/dev/null || echo "")
        done < <(mysql -N -e "SELECT DISTINCT domain FROM mail_domain WHERE active='y';" dbispconfig 2>/dev/null)
    fi
    
    # If database query failed, try to find domains from existing BOM audit
    if [[ ${#domains[@]} -eq 0 ]]; then
        echo "Database query failed, checking for existing BOM audit..." >&2
        local bom_file
        for bom_file in "/opt/audit/ispconfig-bom-audit/ispconfig-bom-config.json" \
                        "$AUDIT_DIR/../ispconfig-bom-audit/ispconfig-bom-config.json" \
                        "/tmp/ispconfig-bom-config.json"; do
            if [[ -f "$bom_file" ]] && command -v jq &> /dev/null; then
                echo "Found BOM audit file: $bom_file" >&2
                while IFS= read -r domain; do
                    [[ -n "$domain" ]] && domains+=("$domain")
                done < <(jq -r '.mail_domains.domains[].domain // empty, .web_domains.main_domains[].domain // empty' "$bom_file" 2>/dev/null)
                break
            fi
        done
    fi
    
    # Fallback: scan common locations for domain hints
    if [[ ${#domains[@]} -eq 0 ]]; then
        echo "No domains found via database or BOM audit, scanning configuration files..." >&2
        local config_domains=()
        
        # Check Postfix main.cf for virtual domains
        if [[ -f "/etc/postfix/main.cf" ]]; then
            while IFS= read -r line; do
                if [[ "$line" =~ virtual_mailbox_domains.*=.*([a-zA-Z0-9.-]+\.[a-zA-Z]{2,}) ]]; then
                    local extracted_domain="${BASH_REMATCH[1]}"
                    [[ -n "$extracted_domain" ]] && config_domains+=("$extracted_domain")
                fi
            done < "/etc/postfix/main.cf"
        fi
        
        # Check Apache vhosts
        if [[ -d "/etc/apache2/sites-enabled" ]]; then
            while IFS= read -r file; do
                [[ -f "$file" ]] || continue
                while IFS= read -r line; do
                    if [[ "$line" =~ ServerName[[:space:]]+([a-zA-Z0-9.-]+\.[a-zA-Z]{2,}) ]]; then
                        local extracted_domain="${BASH_REMATCH[1]}"
                        [[ -n "$extracted_domain" ]] && config_domains+=("$extracted_domain")
                    fi
                done < "$file"
            done < <(find /etc/apache2/sites-enabled -name "*.conf" -type f)
        fi
        
        domains=("${config_domains[@]}")
    fi
    
    # Remove duplicates and sort
    printf '%s\n' "${domains[@]}" | sort -u
}

# Get domains from file
get_file_domains() {
    if [[ ! -f "$DOMAINS_FILE" ]]; then
        echo "ERROR: Domains file not found: $DOMAINS_FILE" >&2
        exit 1
    fi
    
    echo "Reading domains from file: $DOMAINS_FILE" >&2
    grep -v '^#' "$DOMAINS_FILE" | grep -v '^

# Escape string for JSON
json_escape() {
    local input="$1"
    printf '%s\n' "$input" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n' | sed 's/\\n$//'
}

# Test SPF record
test_spf() {
    local domain="$1"
    local spf_record
    local spf_status="fail"
    local spf_mechanisms=()
    local spf_errors=()
    
    # Query TXT records for SPF
    spf_record=$(dig +short TXT "$domain" | grep -E '^"v=spf1' | sed 's/"//g' | head -1)
    
    if [[ -n "$spf_record" ]]; then
        spf_status="pass"
        
        # Parse SPF mechanisms
        IFS=' ' read -ra mechanisms <<< "$spf_record"     
        for mechanism in "${mechanisms[@]}"; do
            case "$mechanism" in
                v=spf1) ;;  # Version, skip
                ~all|-all|+all|?all) spf_mechanisms+=("$mechanism") ;;
                mx|a) spf_mechanisms+=("$mechanism") ;;  # Standalone mx and a mechanisms
                include:*|a:*|mx:*|ip4:*|ip6:*|exists:*|redirect:*) spf_mechanisms+=("$mechanism") ;;
                *) spf_errors+=("Unknown mechanism: $mechanism") ;;
            esac
        done
        
        # Check for common issues
        if [[ "$spf_record" == *"+all"* ]]; then
            spf_errors+=("WARNING: +all allows any server to send")
        fi
        
        if [[ "$spf_record" != *"all"* ]]; then
            spf_errors+=("WARNING: No 'all' mechanism found")
        fi
    else
        spf_errors+=("No SPF record found")
    fi
    
    cat << EOF
    {
      "domain": "$domain",
      "record": "$(json_escape "$spf_record")",
      "status": "$spf_status",
      "mechanisms": [$(printf '"%s",' "${spf_mechanisms[@]}" | sed 's/,$//')]",
      "errors": [$(printf '"%s",' "${spf_errors[@]}" | sed 's/,$//')]
    }
EOF
}

# Test DKIM record
test_dkim() {
    local domain="$1"
    local dkim_status="fail"
    local dkim_selectors=("default" "mail" "dkim" "selector1" "selector2" "s1" "s2")
    local found_selectors=()
    local dkim_errors=()
    
    # Test common DKIM selectors
    for selector in "${dkim_selectors[@]}"; do
        local dkim_record
        dkim_record=$(dig +short TXT "${selector}._domainkey.${domain}" 2>/dev/null)
        
        if [[ -n "$dkim_record" && "$dkim_record" == *"v=DKIM1"* ]]; then
            found_selectors+=("$selector")
            dkim_status="pass"
        fi
    done
    
    if [[ ${#found_selectors[@]} -eq 0 ]]; then
        dkim_errors+=("No DKIM records found for common selectors")
    fi
    
    cat << EOF
    {
      "domain": "$domain",
      "status": "$dkim_status",
      "selectors_found": [$(printf '"%s",' "${found_selectors[@]}" | sed 's/,$//')]",
      "selectors_tested": [$(printf '"%s",' "${dkim_selectors[@]}" | sed 's/,$//')]",
      "errors": [$(printf '"%s",' "${dkim_errors[@]}" | sed 's/,$//')]
    }
EOF
}

# Test DMARC record
test_dmarc() {
    local domain="$1"
    local dmarc_record
    local dmarc_status="fail"
    local dmarc_policy=""
    local dmarc_errors=()
    
    # Query DMARC record
    dmarc_record=$(dig +short TXT "_dmarc.$domain" | grep -E '^"v=DMARC1' | sed 's/"//g' | head -1)
    
    if [[ -n "$dmarc_record" ]]; then
        dmarc_status="pass"
        
        # Extract policy
        if [[ "$dmarc_record" =~ p=([^;]+) ]]; then
            dmarc_policy="${BASH_REMATCH[1]}"
        fi
        
        # Check for common issues
        case "$dmarc_policy" in
            "none") dmarc_errors+=("INFO: Policy is 'none' - monitoring only") ;;
            "quarantine"|"reject") ;;  # Good policies
            *) dmarc_errors+=("WARNING: Unknown policy: $dmarc_policy") ;;
        esac
    else
        dmarc_errors+=("No DMARC record found")
    fi
    
    cat << EOF
    {
      "domain": "$domain",
      "record": "$(json_escape "$dmarc_record")",
      "status": "$dmarc_status",
      "policy": "$dmarc_policy",
      "errors": [$(printf '"%s",' "${dmarc_errors[@]}" | sed 's/,$//')]
    }
EOF
}

# Test MX record
test_mx() {
    local domain="$1"
    local mx_records
    local mx_status="fail"
    local mx_hosts=()
    local mx_errors=()
    
    # Query MX records
    mx_records=$(dig +short MX "$domain" 2>/dev/null)
    
    if [[ -n "$mx_records" ]]; then
        mx_status="pass"
        
        while IFS= read -r mx_line; do
            if [[ -n "$mx_line" ]]; then
                local priority="${mx_line%% *}"
                local host="${mx_line#* }"
                host="${host%.}"  # Remove trailing dot
                mx_hosts+=("{\"priority\":$priority,\"host\":\"$host\"}")
                
                # Test if MX host resolves
                if ! dig +short A "$host" &>/dev/null && ! dig +short AAAA "$host" &>/dev/null; then
                    mx_errors+=("MX host $host does not resolve")
                fi
            fi
        done <<< "$mx_records"
    else
        mx_errors+=("No MX records found")
    fi
    
    cat << EOF
    {
      "domain": "$domain",
      "status": "$mx_status",
      "hosts": [$(printf '%s,' "${mx_hosts[@]}" | sed 's/,$//')]",
      "errors": [$(printf '"%s",' "${mx_errors[@]}" | sed 's/,$//')]
    }
EOF
}

# Finalize git tracking
finalize_audit() {
    cd "$AUDIT_DIR"
    
    # Check if there are any changes
    if git diff --quiet "$OUTPUT_FILENAME" 2>/dev/null; then
        echo "No DNS configuration changes detected since last audit"
        COMMIT_MSG="DNS audit $AUDIT_DATE - No changes"
        git add "$OUTPUT_FILENAME" 2>/dev/null || true
        git commit --allow-empty -m "$COMMIT_MSG" >/dev/null 2>&1
    else
        echo "DNS configuration changes detected - committing to audit history"
        if git rev-parse --verify HEAD >/dev/null 2>&1; then
            echo "Summary of changes:"
            git diff --stat "$OUTPUT_FILENAME" 2>/dev/null || echo "  (New DNS audit file)"
        fi
        COMMIT_MSG="DNS audit $AUDIT_DATE"
        git add "$OUTPUT_FILENAME"
        git commit -m "$COMMIT_MSG" >/dev/null 2>&1
    fi
    
    # Apply retention policy after committing
    apply_retention
    
    echo ""
    echo "DNS Audit History Summary:"
    echo "- Repository: $AUDIT_DIR"
    echo "- Total commits: $(git rev-list --count HEAD 2>/dev/null || echo "1")"
    if [[ -n "$RETAIN_COMMITS" ]]; then
        echo "- Retention policy: Last $RETAIN_COMMITS commits"
    else
        echo "- Retention policy: Keep all history (production mode)"
    fi
}

# Main execution
echo "Starting ISPConfig3 DNS Security Audit..."

# Check dependencies
check_dependencies

# Setup the audit repository
setup_audit_repo

OUTPUT_FILE="$AUDIT_DIR/$OUTPUT_FILENAME"
echo "Output file: $OUTPUT_FILE"

# Get domains list
echo "Getting domains to test..." >&2
case "$DOMAIN_SOURCE" in
    "file")
        domains_array=($(get_file_domains))
        ;;
    "ispconfig-db")
        domains_array=($(get_ispconfig_domains))
        ;;
esac

if [[ ${#domains_array[@]} -eq 0 ]]; then
    echo "ERROR: No domains found to test" >&2
    exit 1
fi

echo "Found ${#domains_array[@]} domains to test: ${domains_array[*]}" >&2

# Initialize JSON output
cat > "$OUTPUT_FILE" << EOF
{
  "audit_info": {
    "version": "$SCRIPT_VERSION",
    "date": "$AUDIT_DATE",
    "hostname": "$HOSTNAME",
    "purpose": "DNS Security Records Validation",
    "audit_directory": "$AUDIT_DIR",
    "retention_policy": $([ -n "$RETAIN_COMMITS" ] && echo "\"Last $RETAIN_COMMITS commits\"" || echo "\"Keep all history\""),
    "domain_source": "$DOMAIN_SOURCE",
    "domains_file": "$([ -n "$DOMAINS_FILE" ] && echo "$DOMAINS_FILE" || echo "null")"
  },
  "dns_validation": {
    "domains_tested": ${#domains_array[@]},
    "spf_records": [
EOF

# Test SPF records
echo "Testing SPF records..." >&2
first_spf=true
for domain in "${domains_array[@]}"; do
    [[ "$first_spf" == true ]] && first_spf=false || echo "," >> "$OUTPUT_FILE"
    test_spf "$domain" >> "$OUTPUT_FILE"
done

cat >> "$OUTPUT_FILE" << EOF
    ],
    "dkim_records": [
EOF

# Test DKIM records
echo "Testing DKIM records..." >&2
first_dkim=true
for domain in "${domains_array[@]}"; do
    [[ "$first_dkim" == true ]] && first_dkim=false || echo "," >> "$OUTPUT_FILE"
    test_dkim "$domain" >> "$OUTPUT_FILE"
done

cat >> "$OUTPUT_FILE" << EOF
    ],
    "dmarc_records": [
EOF

# Test DMARC records
echo "Testing DMARC records..." >&2
first_dmarc=true
for domain in "${domains_array[@]}"; do
    [[ "$first_dmarc" == true ]] && first_dmarc=false || echo "," >> "$OUTPUT_FILE"
    test_dmarc "$domain" >> "$OUTPUT_FILE"
done

cat >> "$OUTPUT_FILE" << EOF
    ],
    "mx_records": [
EOF

# Test MX records
echo "Testing MX records..." >&2
first_mx=true
for domain in "${domains_array[@]}"; do
    [[ "$first_mx" == true ]] && first_mx=false || echo "," >> "$OUTPUT_FILE"
    test_mx "$domain" >> "$OUTPUT_FILE"
done

# Calculate summary statistics
spf_pass_count=$(grep -c '"status": "pass"' "$OUTPUT_FILE" | head -1 || echo "0")
dkim_pass_count=0
dmarc_pass_count=0
mx_pass_count=0

# Since we can't easily count across sections, we'll calculate during the loop
# For now, we'll use a simpler approach and count after completion
echo "Calculating validation summary..."

cat >> "$OUTPUT_FILE" << EOF
    ],
    "validation_summary": {
      "total_domains": ${#domains_array[@]},
      "spf_tests": {
        "total": ${#domains_array[@]},
        "pass": $(jq '[.dns_validation.spf_records[] | select(.status == "pass")] | length' "$OUTPUT_FILE" 2>/dev/null || echo "0"),
        "fail": $(jq '[.dns_validation.spf_records[] | select(.status == "fail")] | length' "$OUTPUT_FILE" 2>/dev/null || echo "0")
      },
      "dkim_tests": {
        "total": ${#domains_array[@]},
        "pass": $(jq '[.dns_validation.dkim_records[] | select(.status == "pass")] | length' "$OUTPUT_FILE" 2>/dev/null || echo "0"),
        "fail": $(jq '[.dns_validation.dkim_records[] | select(.status == "fail")] | length' "$OUTPUT_FILE" 2>/dev/null || echo "0")
      },
      "dmarc_tests": {
        "total": ${#domains_array[@]},
        "pass": $(jq '[.dns_validation.dmarc_records[] | select(.status == "pass")] | length' "$OUTPUT_FILE" 2>/dev/null || echo "0"),
        "fail": $(jq '[.dns_validation.dmarc_records[] | select(.status == "fail")] | length' "$OUTPUT_FILE" 2>/dev/null || echo "0")
      },
      "mx_tests": {
        "total": ${#domains_array[@]},
        "pass": $(jq '[.dns_validation.mx_records[] | select(.status == "pass")] | length' "$OUTPUT_FILE" 2>/dev/null || echo "0"),
        "fail": $(jq '[.dns_validation.mx_records[] | select(.status == "fail")] | length' "$OUTPUT_FILE" 2>/dev/null || echo "0")
      }
    },
    "domains_list": [$(printf '"%s",' "${domains_array[@]}" | sed 's/,$//')]
  }
}
EOF

echo "DNS audit completed successfully!"
echo "Report saved to: $OUTPUT_FILE"
echo ""
echo "Quick Summary:"
echo "- Domains tested: ${#domains_array[@]}"
echo "- SPF records found: $(jq -r '.dns_validation.validation_summary.spf_tests.pass // "unknown"' "$OUTPUT_FILE" 2>/dev/null)"
echo "- DKIM records found: $(jq -r '.dns_validation.validation_summary.dkim_tests.pass // "unknown"' "$OUTPUT_FILE" 2>/dev/null)"
echo "- DMARC records found: $(jq -r '.dns_validation.validation_summary.dmarc_tests.pass // "unknown"' "$OUTPUT_FILE" 2>/dev/null)"
echo "- MX records found: $(jq -r '.dns_validation.validation_summary.mx_tests.pass // "unknown"' "$OUTPUT_FILE" 2>/dev/null)"

# Show failed domains if any
if command -v jq &> /dev/null; then
    local failed_spf=$(jq -r '.dns_validation.spf_records[] | select(.status == "fail") | .domain' "$OUTPUT_FILE" 2>/dev/null)
    if [[ -n "$failed_spf" ]]; then
        echo ""
        echo "Domains without SPF records:"
        echo "$failed_spf" | sed 's/^/  - /'
    fi
fi

# Finalize git tracking and apply retention
finalize_audit | sort -u
}

# Escape string for JSON
json_escape() {
    local input="$1"
    printf '%s\n' "$input" | sed 's/\\/\\\\/g; s/"/\\"/g; s/$/\\n/' | tr -d '\n' | sed 's/\\n$//'
}

# Test SPF record
test_spf() {
    local domain="$1"
    local spf_record
    local spf_status="fail"
    local spf_mechanisms=()
    local spf_errors=()
    
    # Query TXT records for SPF
    spf_record=$(dig +short TXT "$domain" | grep -E '^"v=spf1' | sed 's/"//g' | head -1)
    
    if [[ -n "$spf_record" ]]; then
        spf_status="pass"
        
        # Parse SPF mechanisms
        IFS=' ' read -ra mechanisms <<< "$spf_record"
        for mechanism in "${mechanisms[@]}"; do
            case "$mechanism" in
                v=spf1) ;;  # Version, skip
                ~all|-all|+all|?all) spf_mechanisms+=("$mechanism") ;;
                include:*|a:*|mx:*|ip4:*|ip6:*|exists:*|redirect:*) spf_mechanisms+=("$mechanism") ;;
                *) spf_errors+=("Unknown mechanism: $mechanism") ;;
            esac
        done
        
        # Check for common issues
        if [[ "$spf_record" == *"+all"* ]]; then
            spf_errors+=("WARNING: +all allows any server to send")
        fi
        
        if [[ "$spf_record" != *"all"* ]]; then
            spf_errors+=("WARNING: No 'all' mechanism found")
        fi
    else
        spf_errors+=("No SPF record found")
    fi
    
    cat << EOF
    {
      "domain": "$domain",
      "record": "$(json_escape "$spf_record")",
      "status": "$spf_status",
      "mechanisms": [$(printf '"%s",' "${spf_mechanisms[@]}" | sed 's/,$//')]",
      "errors": [$(printf '"%s",' "${spf_errors[@]}" | sed 's/,$//')]
    }
EOF
}

# Test DKIM record
test_dkim() {
    local domain="$1"
    local dkim_status="fail"
    local dkim_selectors=("default" "mail" "dkim" "selector1" "selector2" "s1" "s2")
    local found_selectors=()
    local dkim_errors=()
    
    # Test common DKIM selectors
    for selector in "${dkim_selectors[@]}"; do
        local dkim_record
        dkim_record=$(dig +short TXT "${selector}._domainkey.${domain}" 2>/dev/null)
        
        if [[ -n "$dkim_record" && "$dkim_record" == *"v=DKIM1"* ]]; then
            found_selectors+=("$selector")
            dkim_status="pass"
        fi
    done
    
    if [[ ${#found_selectors[@]} -eq 0 ]]; then
        dkim_errors+=("No DKIM records found for common selectors")
    fi
    
    cat << EOF
    {
      "domain": "$domain",
      "status": "$dkim_status",
      "selectors_found": [$(printf '"%s",' "${found_selectors[@]}" | sed 's/,$//')]",
      "selectors_tested": [$(printf '"%s",' "${dkim_selectors[@]}" | sed 's/,$//')]",
      "errors": [$(printf '"%s",' "${dkim_errors[@]}" | sed 's/,$//')]
    }
EOF
}

# Test DMARC record
test_dmarc() {
    local domain="$1"
    local dmarc_record
    local dmarc_status="fail"
    local dmarc_policy=""
    local dmarc_errors=()
    
    # Query DMARC record
    dmarc_record=$(dig +short TXT "_dmarc.$domain" | grep -E '^"v=DMARC1' | sed 's/"//g' | head -1)
    
    if [[ -n "$dmarc_record" ]]; then
        dmarc_status="pass"
        
        # Extract policy
        if [[ "$dmarc_record" =~ p=([^;]+) ]]; then
            dmarc_policy="${BASH_REMATCH[1]}"
        fi
        
        # Check for common issues
        case "$dmarc_policy" in
            "none") dmarc_errors+=("INFO: Policy is 'none' - monitoring only") ;;
            "quarantine"|"reject") ;;  # Good policies
            *) dmarc_errors+=("WARNING: Unknown policy: $dmarc_policy") ;;
        esac
    else
        dmarc_errors+=("No DMARC record found")
    fi
    
    cat << EOF
    {
      "domain": "$domain",
      "record": "$(json_escape "$dmarc_record")",
      "status": "$dmarc_status",
      "policy": "$dmarc_policy",
      "errors": [$(printf '"%s",' "${dmarc_errors[@]}" | sed 's/,$//')]
    }
EOF
}

# Test MX record
test_mx() {
    local domain="$1"
    local mx_records
    local mx_status="fail"
    local mx_hosts=()
    local mx_errors=()
    
    # Query MX records
    mx_records=$(dig +short MX "$domain" 2>/dev/null)
    
    if [[ -n "$mx_records" ]]; then
        mx_status="pass"
        
        while IFS= read -r mx_line; do
            if [[ -n "$mx_line" ]]; then
                local priority="${mx_line%% *}"
                local host="${mx_line#* }"
                host="${host%.}"  # Remove trailing dot
                mx_hosts+=("{\"priority\":$priority,\"host\":\"$host\"}")
                
                # Test if MX host resolves
                if ! dig +short A "$host" &>/dev/null && ! dig +short AAAA "$host" &>/dev/null; then
                    mx_errors+=("MX host $host does not resolve")
                fi
            fi
        done <<< "$mx_records"
    else
        mx_errors+=("No MX records found")
    fi
    
    cat << EOF
    {
      "domain": "$domain",
      "status": "$mx_status",
      "hosts": [$(printf '%s,' "${mx_hosts[@]}" | sed 's/,$//')]",
      "errors": [$(printf '"%s",' "${mx_errors[@]}" | sed 's/,$//')]
    }
EOF
}

# Finalize git tracking
finalize_audit() {
    cd "$AUDIT_DIR"
    
    # Check if there are any changes
    if git diff --quiet "$OUTPUT_FILENAME" 2>/dev/null; then
        echo "No DNS configuration changes detected since last audit"
        COMMIT_MSG="DNS audit $AUDIT_DATE - No changes"
        git add "$OUTPUT_FILENAME" 2>/dev/null || true
        git commit --allow-empty -m "$COMMIT_MSG" >/dev/null 2>&1
    else
        echo "DNS configuration changes detected - committing to audit history"
        if git rev-parse --verify HEAD >/dev/null 2>&1; then
            echo "Summary of changes:"
            git diff --stat "$OUTPUT_FILENAME" 2>/dev/null || echo "  (New DNS audit file)"
        fi
        COMMIT_MSG="DNS audit $AUDIT_DATE"
        git add "$OUTPUT_FILENAME"
        git commit -m "$COMMIT_MSG" >/dev/null 2>&1
    fi
    
    # Apply retention policy after committing
    apply_retention
    
    echo ""
    echo "DNS Audit History Summary:"
    echo "- Repository: $AUDIT_DIR"
    echo "- Total commits: $(git rev-list --count HEAD 2>/dev/null || echo "1")"
    if [[ -n "$RETAIN_COMMITS" ]]; then
        echo "- Retention policy: Last $RETAIN_COMMITS commits"
    else
        echo "- Retention policy: Keep all history (production mode)"
    fi
}

# Main execution
echo "Starting ISPConfig3 DNS Security Audit..."

# Check dependencies
check_dependencies

# Setup the audit repository
setup_audit_repo

OUTPUT_FILE="$AUDIT_DIR/$OUTPUT_FILENAME"
echo "Output file: $OUTPUT_FILE"

# Get domains list
echo "Getting domains to test..."
case "$DOMAIN_SOURCE" in
    "file")
        domains_array=($(get_file_domains))
        ;;
    "ispconfig-db")
        domains_array=($(get_ispconfig_domains))
        ;;
esac

if [[ ${#domains_array[@]} -eq 0 ]]; then
    echo "ERROR: No domains found to test" >&2
    exit 1
fi

echo "Found ${#domains_array[@]} domains to test: ${domains_array[*]}"

# Initialize JSON output
cat > "$OUTPUT_FILE" << EOF
{
  "audit_info": {
    "version": "$SCRIPT_VERSION",
    "date": "$AUDIT_DATE",
    "hostname": "$HOSTNAME",
    "purpose": "DNS Security Records Validation",
    "audit_directory": "$AUDIT_DIR",
    "retention_policy": $([ -n "$RETAIN_COMMITS" ] && echo "\"Last $RETAIN_COMMITS commits\"" || echo "\"Keep all history\""),
    "domain_source": "$DOMAIN_SOURCE",
    "domains_file": "$([ -n "$DOMAINS_FILE" ] && echo "$DOMAINS_FILE" || echo "null")"
  },
  "dns_validation": {
    "domains_tested": ${#domains_array[@]},
    "spf_records": [
EOF

# Test SPF records
echo "Testing SPF records..."
first_spf=true
for domain in "${domains_array[@]}"; do
    [[ "$first_spf" == true ]] && first_spf=false || echo "," >> "$OUTPUT_FILE"
    test_spf "$domain" >> "$OUTPUT_FILE"
done

cat >> "$OUTPUT_FILE" << EOF
    ],
    "dkim_records": [
EOF

# Test DKIM records
echo "Testing DKIM records..."
first_dkim=true
for domain in "${domains_array[@]}"; do
    [[ "$first_dkim" == true ]] && first_dkim=false || echo "," >> "$OUTPUT_FILE"
    test_dkim "$domain" >> "$OUTPUT_FILE"
done

cat >> "$OUTPUT_FILE" << EOF
    ],
    "dmarc_records": [
EOF

# Test DMARC records
echo "Testing DMARC records..."
first_dmarc=true
for domain in "${domains_array[@]}"; do
    [[ "$first_dmarc" == true ]] && first_dmarc=false || echo "," >> "$OUTPUT_FILE"
    test_dmarc "$domain" >> "$OUTPUT_FILE"
done

cat >> "$OUTPUT_FILE" << EOF
    ],
    "mx_records": [
EOF

# Test MX records
echo "Testing MX records..."
first_mx=true
for domain in "${domains_array[@]}"; do
    [[ "$first_mx" == true ]] && first_mx=false || echo "," >> "$OUTPUT_FILE"
    test_mx "$domain" >> "$OUTPUT_FILE"
done

# Calculate summary statistics
spf_pass_count=$(grep -c '"status": "pass"' "$OUTPUT_FILE" | head -1 || echo "0")
dkim_pass_count=0
dmarc_pass_count=0
mx_pass_count=0

# Since we can't easily count across sections, we'll calculate during the loop
# For now, we'll use a simpler approach and count after completion
echo "Calculating validation summary..."

cat >> "$OUTPUT_FILE" << EOF
    ],
    "validation_summary": {
      "total_domains": ${#domains_array[@]},
      "spf_tests": {
        "total": ${#domains_array[@]},
        "pass": $(jq '[.dns_validation.spf_records[] | select(.status == "pass")] | length' "$OUTPUT_FILE" 2>/dev/null || echo "0"),
        "fail": $(jq '[.dns_validation.spf_records[] | select(.status == "fail")] | length' "$OUTPUT_FILE" 2>/dev/null || echo "0")
      },
      "dkim_tests": {
        "total": ${#domains_array[@]},
        "pass": $(jq '[.dns_validation.dkim_records[] | select(.status == "pass")] | length' "$OUTPUT_FILE" 2>/dev/null || echo "0"),
        "fail": $(jq '[.dns_validation.dkim_records[] | select(.status == "fail")] | length' "$OUTPUT_FILE" 2>/dev/null || echo "0")
      },
      "dmarc_tests": {
        "total": ${#domains_array[@]},
        "pass": $(jq '[.dns_validation.dmarc_records[] | select(.status == "pass")] | length' "$OUTPUT_FILE" 2>/dev/null || echo "0"),
        "fail": $(jq '[.dns_validation.dmarc_records[] | select(.status == "fail")] | length' "$OUTPUT_FILE" 2>/dev/null || echo "0")
      },
      "mx_tests": {
        "total": ${#domains_array[@]},
        "pass": $(jq '[.dns_validation.mx_records[] | select(.status == "pass")] | length' "$OUTPUT_FILE" 2>/dev/null || echo "0"),
        "fail": $(jq '[.dns_validation.mx_records[] | select(.status == "fail")] | length' "$OUTPUT_FILE" 2>/dev/null || echo "0")
      }
    },
    "domains_list": [$(printf '"%s",' "${domains_array[@]}" | sed 's/,$//')]
  }
}
EOF

echo "DNS audit completed successfully!"
echo "Report saved to: $OUTPUT_FILE"
echo ""
echo "Quick Summary:"
echo "- Domains tested: ${#domains_array[@]}"
echo "- SPF records found: $(jq -r '.dns_validation.validation_summary.spf_tests.pass // "unknown"' "$OUTPUT_FILE" 2>/dev/null)"
echo "- DKIM records found: $(jq -r '.dns_validation.validation_summary.dkim_tests.pass // "unknown"' "$OUTPUT_FILE" 2>/dev/null)"
echo "- DMARC records found: $(jq -r '.dns_validation.validation_summary.dmarc_tests.pass // "unknown"' "$OUTPUT_FILE" 2>/dev/null)"
echo "- MX records found: $(jq -r '.dns_validation.validation_summary.mx_tests.pass // "unknown"' "$OUTPUT_FILE" 2>/dev/null)"

# Show failed domains if any
if command -v jq &> /dev/null; then
    local failed_spf=$(jq -r '.dns_validation.spf_records[] | select(.status == "fail") | .domain' "$OUTPUT_FILE" 2>/dev/null)
    if [[ -n "$failed_spf" ]]; then
        echo ""
        echo "Domains without SPF records:"
        echo "$failed_spf" | sed 's/^/  - /'
    fi
fi

# Finalize git tracking and apply retention
finalize_audit
