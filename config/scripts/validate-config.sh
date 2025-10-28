#!/bin/bash

# Configuration Validation Script
# Validates configuration files and environment settings

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Validation results
VALIDATION_ERRORS=0
VALIDATION_WARNINGS=0

# Validate JSON syntax
validate_json_syntax() {
    local file=$1
    log_info "Validating JSON syntax: $(basename "$file")"
    
    if ! jq empty "$file" 2>/dev/null; then
        log_error "Invalid JSON syntax in $file"
        ((VALIDATION_ERRORS++))
        return 1
    fi
    
    log_success "JSON syntax valid"
    return 0
}

# Validate required fields
validate_required_fields() {
    local file=$1
    local env=$(basename "$file" .json)
    
    log_info "Validating required fields for $env environment"
    
    local required_fields=(
        ".environment"
        ".region"
        ".lambda.functionName"
        ".lambda.runtime"
        ".lambda.timeout"
        ".lambda.memorySize"
        ".sns.topicName"
        ".cloudWatch.logRetentionDays"
        ".firebase.projectId"
        ".tags.Environment"
    )
    
    for field in "${required_fields[@]}"; do
        local value=$(jq -r "$field // empty" "$file")
        if [[ -z "$value" || "$value" == "null" ]]; then
            log_error "Missing required field: $field"
            ((VALIDATION_ERRORS++))
        fi
    done
    
    # Environment-specific validations
    if [[ "$env" == "prod" ]]; then
        local prod_fields=(
            ".security.wafEnabled"
            ".deployment.approvalRequired"
            ".monitoring.pagerDutyEnabled"
        )
        
        for field in "${prod_fields[@]}"; do
            local value=$(jq -r "$field // empty" "$file")
            if [[ "$value" != "true" ]]; then
                log_warning "Production should have $field enabled"
                ((VALIDATION_WARNINGS++))
            fi
        done
    fi
}

# Validate configuration values
validate_configuration_values() {
    local file=$1
    local env=$(basename "$file" .json)
    
    log_info "Validating configuration values for $env environment"
    
    # Memory size validation
    local memory=$(jq -r '.lambda.memorySize' "$file")
    if [[ "$memory" -lt 128 || "$memory" -gt 10240 ]]; then
        log_error "Invalid memory size: $memory (must be 128-10240 MB)"
        ((VALIDATION_ERRORS++))
    fi
    
    # Timeout validation
    local timeout=$(jq -r '.lambda.timeout' "$file")
    if [[ "$timeout" -lt 1 || "$timeout" -gt 900 ]]; then
        log_error "Invalid timeout: $timeout (must be 1-900 seconds)"
        ((VALIDATION_ERRORS++))
    fi
    
    # Log retention validation
    local retention=$(jq -r '.cloudWatch.logRetentionDays' "$file")
    local valid_retentions=(1 3 5 7 14 30 60 90 120 150 180 365 400 545 731 1827 3653)
    if [[ ! " ${valid_retentions[@]} " =~ " ${retention} " ]]; then
        log_error "Invalid log retention: $retention days"
        ((VALIDATION_ERRORS++))
    fi
    
    # Environment naming consistency
    local config_env=$(jq -r '.environment' "$file")
    if [[ "$config_env" != "$env" ]]; then
        log_error "Environment mismatch: file=$env, config=$config_env"
        ((VALIDATION_ERRORS++))
    fi
}

# Validate environment consistency
validate_environment_consistency() {
    log_info "Validating cross-environment consistency"
    
    local envs=(dev staging prod)
    local base_structure=""
    
    for env in "${envs[@]}"; do
        local file="$CONFIG_DIR/environments/${env}.json"
        if [[ ! -f "$file" ]]; then
            log_warning "Environment file missing: $env.json"
            ((VALIDATION_WARNINGS++))
            continue
        fi
        
        local structure=$(jq -r 'paths(scalars) as $p | $p | join(".")' "$file" | sort)
        
        if [[ -z "$base_structure" ]]; then
            base_structure="$structure"
        else
            local diff=$(diff <(echo "$base_structure") <(echo "$structure") || true)
            if [[ -n "$diff" ]]; then
                log_warning "Structure differences found between environments"
                echo "$diff"
                ((VALIDATION_WARNINGS++))
            fi
        fi
    done
}

# Validate templates
validate_templates() {
    log_info "Validating configuration templates"
    
    local template_dir="$CONFIG_DIR/templates"
    
    for template in "$template_dir"/*.template; do
        if [[ -f "$template" ]]; then
            log_info "Checking template: $(basename "$template")"
            
            # Check for unreplaced placeholders
            local placeholders=$(grep -o '{{[^}]*}}' "$template" | sort -u || true)
            if [[ -n "$placeholders" ]]; then
                log_success "Template placeholders found: $(echo "$placeholders" | wc -l)"
            else
                log_warning "No placeholders found in template"
                ((VALIDATION_WARNINGS++))
            fi
        fi
    done
}

# Generate validation report
generate_report() {
    local report_file="validation-report-$(date +%Y%m%d-%H%M%S).txt"
    
    cat > "$report_file" << EOF
Configuration Validation Report
==============================

Validation Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Total Errors: $VALIDATION_ERRORS
Total Warnings: $VALIDATION_WARNINGS

Status: $([ $VALIDATION_ERRORS -eq 0 ] && echo "PASSED" || echo "FAILED")

Files Validated:
$(find "$CONFIG_DIR/environments" -name "*.json" -exec basename {} \; | sort)

Templates Validated:
$(find "$CONFIG_DIR/templates" -name "*.template" -exec basename {} \; | sort)

Recommendations:
- Fix all errors before deployment
- Review warnings for best practices
- Keep configurations synchronized across environments
- Regularly validate after changes
EOF
    
    log_success "Validation report saved: $report_file"
}

# Main validation function
main() {
    echo "🔍 Configuration Validation"
    echo "=========================="
    
    # Validate environment configs
    for env_file in "$CONFIG_DIR/environments"/*.json; do
        if [[ -f "$env_file" ]]; then
            echo ""
            validate_json_syntax "$env_file"
            validate_required_fields "$env_file"
            validate_configuration_values "$env_file"
        fi
    done
    
    echo ""
    validate_environment_consistency
    validate_templates
    generate_report
    
    echo ""
    echo "📊 Validation Summary:"
    echo "====================="
    echo "Errors: $VALIDATION_ERRORS"
    echo "Warnings: $VALIDATION_WARNINGS"
    
    if [[ $VALIDATION_ERRORS -eq 0 ]]; then
        log_success "All validations passed! ✅"
        exit 0
    else
        log_error "Validation failed with $VALIDATION_ERRORS errors ❌"
        exit 1
    fi
}

# Show usage
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    cat << EOF
🔍 Configuration Validation Script

Usage:
    $0 [--help]

This script validates:
- JSON syntax in configuration files
- Required field presence
- Configuration value ranges
- Cross-environment consistency
- Template placeholder presence

Examples:
    # Run full validation
    $0
    
    # Show this help
    $0 --help
EOF
    exit 0
fi

main "$@"