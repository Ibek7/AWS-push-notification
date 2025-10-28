#!/bin/bash

# Configuration Deployment Script
# Deploys environment-specific configurations to AWS resources

set -e

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$CONFIG_DIR")"

# Default values
ENVIRONMENT=""
CONFIG_FILE=""
DRY_RUN=false
VERBOSE=false
FORCE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Usage information
show_usage() {
    cat << EOF
🚀 Configuration Deployment Script

Usage:
    $0 --env <environment> [options]

Required Arguments:
    --env <environment>     Target environment (dev, staging, prod)

Optional Arguments:
    --config <file>         Custom configuration file path
    --dry-run              Show what would be deployed without making changes
    --force                Skip confirmation prompts
    --verbose              Enable verbose output
    --help                 Show this help message

Examples:
    # Deploy development configuration
    $0 --env dev

    # Deploy with custom config file
    $0 --env prod --config custom-prod.json

    # Dry run to preview changes
    $0 --env staging --dry-run

    # Force deployment without confirmation
    $0 --env prod --force
EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --env)
                ENVIRONMENT="$2"
                shift 2
                ;;
            --config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$ENVIRONMENT" ]]; then
        log_error "Environment is required. Use --env <environment>"
        show_usage
        exit 1
    fi

    # Validate environment
    if [[ ! "$ENVIRONMENT" =~ ^(dev|staging|prod)$ ]]; then
        log_error "Invalid environment: $ENVIRONMENT. Must be dev, staging, or prod"
        exit 1
    fi
}

# Load configuration
load_configuration() {
    if [[ -n "$CONFIG_FILE" ]]; then
        if [[ ! -f "$CONFIG_FILE" ]]; then
            log_error "Custom config file not found: $CONFIG_FILE"
            exit 1
        fi
        CONFIG_PATH="$CONFIG_FILE"
    else
        CONFIG_PATH="$CONFIG_DIR/environments/${ENVIRONMENT}.json"
        if [[ ! -f "$CONFIG_PATH" ]]; then
            log_error "Environment config file not found: $CONFIG_PATH"
            exit 1
        fi
    fi

    log_info "Loading configuration from: $CONFIG_PATH"
    
    # Validate JSON
    if ! jq empty "$CONFIG_PATH" 2>/dev/null; then
        log_error "Invalid JSON in configuration file: $CONFIG_PATH"
        exit 1
    fi

    # Extract key configuration values
    REGION=$(jq -r '.region // "us-east-1"' "$CONFIG_PATH")
    LAMBDA_FUNCTION_NAME=$(jq -r '.lambda.functionName' "$CONFIG_PATH")
    SNS_TOPIC_NAME=$(jq -r '.sns.topicName' "$CONFIG_PATH")
    
    if [[ "$VERBOSE" == "true" ]]; then
        log_info "Configuration loaded:"
        log_info "  Region: $REGION"
        log_info "  Lambda Function: $LAMBDA_FUNCTION_NAME"
        log_info "  SNS Topic: $SNS_TOPIC_NAME"
    fi
}

# Validate AWS access
validate_aws_access() {
    log_info "Validating AWS access..."
    
    if ! aws sts get-caller-identity --region "$REGION" &>/dev/null; then
        log_error "AWS access validation failed. Please check your credentials."
        exit 1
    fi
    
    local account_id=$(aws sts get-caller-identity --query Account --output text --region "$REGION")
    log_success "AWS access validated for account: $account_id"
}

# Deploy Lambda environment variables
deploy_lambda_config() {
    log_info "Deploying Lambda function configuration..."
    
    # Extract environment variables from config
    local env_vars=$(jq -r '.lambda.environment | to_entries | map("\(.key)=\(.value)") | join(",")' "$CONFIG_PATH")
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would update Lambda environment variables:"
        echo "$env_vars" | tr ',' '\n' | sed 's/^/  /'
        return
    fi
    
    # Update Lambda function configuration
    aws lambda update-function-configuration \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --environment "Variables={$env_vars}" \
        --region "$REGION" &>/dev/null
    
    if [[ $? -eq 0 ]]; then
        log_success "Lambda environment variables updated"
    else
        log_error "Failed to update Lambda environment variables"
        exit 1
    fi
}

# Deploy API Gateway configuration
deploy_api_gateway_config() {
    log_info "Deploying API Gateway configuration..."
    
    local api_name=$(jq -r '.apiGateway.restApiName' "$CONFIG_PATH")
    local stage_name=$(jq -r '.apiGateway.stageName' "$CONFIG_PATH")
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would configure API Gateway:"
        log_info "  API Name: $api_name"
        log_info "  Stage: $stage_name"
        return
    fi
    
    # Get API Gateway ID
    local api_id=$(aws apigateway get-rest-apis \
        --query "items[?name=='$api_name'].id" \
        --output text \
        --region "$REGION")
    
    if [[ -n "$api_id" && "$api_id" != "None" ]]; then
        # Configure throttling
        local burst_limit=$(jq -r '.apiGateway.throttling.burstLimit' "$CONFIG_PATH")
        local rate_limit=$(jq -r '.apiGateway.throttling.rateLimit' "$CONFIG_PATH")
        
        aws apigateway put-stage \
            --rest-api-id "$api_id" \
            --stage-name "$stage_name" \
            --patch-ops op=replace,path=/throttle/burstLimit,value="$burst_limit" \
            --patch-ops op=replace,path=/throttle/rateLimit,value="$rate_limit" \
            --region "$REGION" &>/dev/null
        
        log_success "API Gateway throttling configured"
    else
        log_warning "API Gateway not found: $api_name"
    fi
}

# Deploy CloudWatch configuration
deploy_cloudwatch_config() {
    log_info "Deploying CloudWatch configuration..."
    
    local log_retention=$(jq -r '.cloudWatch.logRetentionDays' "$CONFIG_PATH")
    local log_group="/aws/lambda/$LAMBDA_FUNCTION_NAME"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would set log retention to $log_retention days for $log_group"
        return
    fi
    
    # Set log retention
    aws logs put-retention-policy \
        --log-group-name "$log_group" \
        --retention-in-days "$log_retention" \
        --region "$REGION" &>/dev/null
    
    if [[ $? -eq 0 ]]; then
        log_success "CloudWatch log retention set to $log_retention days"
    else
        log_warning "Failed to set log retention (log group may not exist yet)"
    fi
}

# Deploy secrets
deploy_secrets() {
    log_info "Deploying secrets configuration..."
    
    local secret_name=$(jq -r '.firebase.serviceAccountSecretName' "$CONFIG_PATH")
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would verify secret exists: $secret_name"
        return
    fi
    
    # Check if secret exists
    if aws secretsmanager describe-secret \
        --secret-id "$secret_name" \
        --region "$REGION" &>/dev/null; then
        log_success "Secret verified: $secret_name"
    else
        log_warning "Secret not found: $secret_name (may need manual creation)"
    fi
}

# Deployment confirmation
confirm_deployment() {
    if [[ "$FORCE" == "true" ]]; then
        return
    fi
    
    echo ""
    log_warning "About to deploy configuration to $ENVIRONMENT environment"
    log_warning "Region: $REGION"
    log_warning "Lambda Function: $LAMBDA_FUNCTION_NAME"
    echo ""
    read -p "Are you sure you want to proceed? (y/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Deployment cancelled"
        exit 0
    fi
}

# Run post-deployment validation
validate_deployment() {
    log_info "Running post-deployment validation..."
    
    # Check Lambda function status
    local function_state=$(aws lambda get-function-configuration \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --query 'State' \
        --output text \
        --region "$REGION" 2>/dev/null)
    
    if [[ "$function_state" == "Active" ]]; then
        log_success "Lambda function is active"
    else
        log_warning "Lambda function state: $function_state"
    fi
    
    # Test function invocation (dry run)
    log_info "Testing Lambda function invocation..."
    local test_payload='{"test": true}'
    
    aws lambda invoke \
        --function-name "$LAMBDA_FUNCTION_NAME" \
        --payload "$test_payload" \
        --invocation-type DryRun \
        --region "$REGION" \
        /tmp/lambda-test-response.json &>/dev/null
    
    if [[ $? -eq 0 ]]; then
        log_success "Lambda function test invocation successful"
    else
        log_warning "Lambda function test invocation failed"
    fi
    
    # Clean up
    rm -f /tmp/lambda-test-response.json
}

# Generate deployment summary
generate_summary() {
    local end_time=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
    
    cat > "deployment-summary-${ENVIRONMENT}-$(date +%Y%m%d-%H%M%S).txt" << EOF
AWS Push Notifications Configuration Deployment Summary
====================================================

Environment: $ENVIRONMENT
Configuration File: $CONFIG_PATH
Deployment Time: $end_time
Deployed By: $(aws sts get-caller-identity --query Arn --output text 2>/dev/null || echo "Unknown")

Components Deployed:
- Lambda Function: $LAMBDA_FUNCTION_NAME
- SNS Topic: $SNS_TOPIC_NAME
- Region: $REGION

Deployment Status: $([ "$DRY_RUN" == "true" ] && echo "DRY RUN" || echo "COMPLETED")

Next Steps:
1. Monitor CloudWatch logs for any issues
2. Test notification functionality
3. Verify monitoring and alerting
4. Update documentation if needed
EOF
    
    log_success "Deployment summary saved to deployment-summary-${ENVIRONMENT}-$(date +%Y%m%d-%H%M%S).txt"
}

# Main execution
main() {
    echo "🚀 AWS Push Notifications Configuration Deployment"
    echo "================================================="
    
    parse_arguments "$@"
    load_configuration
    validate_aws_access
    
    if [[ "$DRY_RUN" == "false" ]]; then
        confirm_deployment
    fi
    
    # Deploy configurations
    deploy_lambda_config
    deploy_api_gateway_config
    deploy_cloudwatch_config
    deploy_secrets
    
    if [[ "$DRY_RUN" == "false" ]]; then
        validate_deployment
    fi
    
    generate_summary
    
    echo ""
    if [[ "$DRY_RUN" == "true" ]]; then
        log_success "Dry run completed successfully!"
    else
        log_success "Configuration deployment completed successfully!"
    fi
    echo ""
}

# Run main function with all arguments
main "$@"