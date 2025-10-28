#!/bin/bash

# System Health Checker
# Validates the health and configuration of AWS Push Notifications system

set -e

# Configuration
ENVIRONMENT=${1:-"prod"}
REGION=${AWS_REGION:-"us-east-1"}
FUNCTION_NAME="sendPushNotification"
TOPIC_NAME="push-notifications"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Health check results
HEALTH_CHECKS=()
FAILED_CHECKS=0

# Add health check result
add_check_result() {
    local service=$1
    local status=$2
    local message=$3
    
    HEALTH_CHECKS+=("$service|$status|$message")
    
    if [ "$status" = "FAIL" ]; then
        ((FAILED_CHECKS++))
        log_error "$service: $message"
    elif [ "$status" = "WARN" ]; then
        log_warning "$service: $message"
    else
        log_success "$service: $message"
    fi
}

# Check AWS CLI configuration
check_aws_config() {
    log_info "Checking AWS CLI configuration..."
    
    if ! command -v aws &> /dev/null; then
        add_check_result "AWS CLI" "FAIL" "AWS CLI not installed"
        return
    fi
    
    if ! aws sts get-caller-identity &> /dev/null; then
        add_check_result "AWS CLI" "FAIL" "AWS credentials not configured"
        return
    fi
    
    local account_id=$(aws sts get-caller-identity --query Account --output text)
    add_check_result "AWS CLI" "PASS" "Configured for account: $account_id"
}

# Check Lambda function
check_lambda_function() {
    log_info "Checking Lambda function: $FUNCTION_NAME..."
    
    local function_config
    if ! function_config=$(aws lambda get-function-configuration --function-name "$FUNCTION_NAME" --region "$REGION" 2>/dev/null); then
        add_check_result "Lambda Function" "FAIL" "Function $FUNCTION_NAME not found"
        return
    fi
    
    local runtime=$(echo "$function_config" | jq -r '.Runtime')
    local state=$(echo "$function_config" | jq -r '.State')
    local last_update=$(echo "$function_config" | jq -r '.LastModified')
    
    if [ "$state" != "Active" ]; then
        add_check_result "Lambda Function" "FAIL" "Function state: $state"
        return
    fi
    
    add_check_result "Lambda Function" "PASS" "Active ($runtime, updated: $last_update)"
    
    # Check function configuration
    local timeout=$(echo "$function_config" | jq -r '.Timeout')
    local memory=$(echo "$function_config" | jq -r '.MemorySize')
    
    if [ "$timeout" -lt 30 ]; then
        add_check_result "Lambda Timeout" "WARN" "Timeout is ${timeout}s (consider increasing for reliability)"
    else
        add_check_result "Lambda Timeout" "PASS" "${timeout}s timeout configured"
    fi
    
    if [ "$memory" -lt 256 ]; then
        add_check_result "Lambda Memory" "WARN" "Memory is ${memory}MB (consider increasing for performance)"
    else
        add_check_result "Lambda Memory" "PASS" "${memory}MB memory allocated"
    fi
}

# Check SNS topic
check_sns_topic() {
    log_info "Checking SNS topic: $TOPIC_NAME..."
    
    local topic_arn
    if ! topic_arn=$(aws sns list-topics --region "$REGION" --query "Topics[?contains(TopicArn, '$TOPIC_NAME')].TopicArn" --output text); then
        add_check_result "SNS Topic" "FAIL" "Failed to list SNS topics"
        return
    fi
    
    if [ -z "$topic_arn" ]; then
        add_check_result "SNS Topic" "FAIL" "Topic $TOPIC_NAME not found"
        return
    fi
    
    add_check_result "SNS Topic" "PASS" "Topic exists: $topic_arn"
    
    # Check subscriptions
    local subscriptions
    if subscriptions=$(aws sns list-subscriptions-by-topic --topic-arn "$topic_arn" --region "$REGION" 2>/dev/null); then
        local sub_count=$(echo "$subscriptions" | jq '.Subscriptions | length')
        if [ "$sub_count" -eq 0 ]; then
            add_check_result "SNS Subscriptions" "WARN" "No subscriptions found for topic"
        else
            add_check_result "SNS Subscriptions" "PASS" "$sub_count subscriptions configured"
        fi
    fi
}

# Check API Gateway
check_api_gateway() {
    log_info "Checking API Gateway..."
    
    local apis
    if ! apis=$(aws apigateway get-rest-apis --region "$REGION" 2>/dev/null); then
        add_check_result "API Gateway" "WARN" "Failed to list APIs (may not exist)"
        return
    fi
    
    local api_count=$(echo "$apis" | jq '.items | length')
    if [ "$api_count" -eq 0 ]; then
        add_check_result "API Gateway" "WARN" "No REST APIs found"
        return
    fi
    
    add_check_result "API Gateway" "PASS" "$api_count REST APIs found"
}

# Check CloudWatch logs
check_cloudwatch_logs() {
    log_info "Checking CloudWatch logs..."
    
    local log_group="/aws/lambda/$FUNCTION_NAME"
    local log_info
    
    if ! log_info=$(aws logs describe-log-groups --log-group-name-prefix "$log_group" --region "$REGION" 2>/dev/null); then
        add_check_result "CloudWatch Logs" "FAIL" "Failed to check log groups"
        return
    fi
    
    local group_count=$(echo "$log_info" | jq '.logGroups | length')
    if [ "$group_count" -eq 0 ]; then
        add_check_result "CloudWatch Logs" "WARN" "Log group $log_group not found"
        return
    fi
    
    local retention=$(echo "$log_info" | jq -r '.logGroups[0].retentionInDays // "Never expires"')
    add_check_result "CloudWatch Logs" "PASS" "Log group exists (retention: $retention days)"
    
    # Check recent log events
    local recent_logs
    if recent_logs=$(aws logs filter-log-events --log-group-name "$log_group" --start-time $(($(date +%s) * 1000 - 3600000)) --region "$REGION" 2>/dev/null); then
        local event_count=$(echo "$recent_logs" | jq '.events | length')
        if [ "$event_count" -eq 0 ]; then
            add_check_result "Recent Activity" "WARN" "No log events in the last hour"
        else
            add_check_result "Recent Activity" "PASS" "$event_count log events in the last hour"
        fi
    fi
}

# Check X-Ray tracing
check_xray_tracing() {
    log_info "Checking X-Ray tracing..."
    
    local function_config
    if function_config=$(aws lambda get-function-configuration --function-name "$FUNCTION_NAME" --region "$REGION" 2>/dev/null); then
        local tracing_mode=$(echo "$function_config" | jq -r '.TracingConfig.Mode // "PassThrough"')
        
        if [ "$tracing_mode" = "Active" ]; then
            add_check_result "X-Ray Tracing" "PASS" "Tracing enabled"
        else
            add_check_result "X-Ray Tracing" "WARN" "Tracing not enabled (mode: $tracing_mode)"
        fi
    else
        add_check_result "X-Ray Tracing" "WARN" "Cannot check tracing configuration"
    fi
}

# Check IAM permissions (basic check)
check_iam_permissions() {
    log_info "Checking IAM permissions..."
    
    # Test basic permissions
    if aws sts get-caller-identity &> /dev/null; then
        add_check_result "IAM - Basic" "PASS" "Basic AWS access working"
    else
        add_check_result "IAM - Basic" "FAIL" "No AWS access"
        return
    fi
    
    # Test Lambda permissions
    if aws lambda list-functions --max-items 1 --region "$REGION" &> /dev/null; then
        add_check_result "IAM - Lambda" "PASS" "Lambda read access working"
    else
        add_check_result "IAM - Lambda" "WARN" "Limited Lambda access"
    fi
    
    # Test SNS permissions
    if aws sns list-topics --region "$REGION" &> /dev/null; then
        add_check_result "IAM - SNS" "PASS" "SNS read access working"
    else
        add_check_result "IAM - SNS" "WARN" "Limited SNS access"
    fi
}

# Test function invocation
test_function_invocation() {
    log_info "Testing Lambda function invocation..."
    
    local test_payload='{"body": "{\"fcmToken\":\"test-token\",\"title\":\"Health Check\",\"message\":\"System health validation\"}"}'
    local invocation_result
    
    if invocation_result=$(aws lambda invoke --function-name "$FUNCTION_NAME" --payload "$test_payload" --region "$REGION" /tmp/lambda-response.json 2>&1); then
        local status_code=$(echo "$invocation_result" | jq -r '.StatusCode // 0')
        
        if [ "$status_code" -eq 200 ]; then
            add_check_result "Function Test" "PASS" "Test invocation successful"
        else
            add_check_result "Function Test" "WARN" "Test invocation returned status: $status_code"
        fi
    else
        add_check_result "Function Test" "FAIL" "Cannot invoke function: $invocation_result"
    fi
    
    # Clean up
    rm -f /tmp/lambda-response.json
}

# Display summary
display_summary() {
    echo ""
    echo "=========================================="
    echo "🏥 HEALTH CHECK SUMMARY"
    echo "=========================================="
    echo "Environment: $ENVIRONMENT"
    echo "Region: $REGION"
    echo "Timestamp: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
    echo ""
    
    local total_checks=${#HEALTH_CHECKS[@]}
    local passed_checks=$((total_checks - FAILED_CHECKS))
    
    echo "📊 Results: $passed_checks/$total_checks checks passed"
    
    if [ $FAILED_CHECKS -eq 0 ]; then
        echo "✅ System Status: HEALTHY"
    elif [ $FAILED_CHECKS -le 2 ]; then
        echo "⚠️  System Status: DEGRADED"
    else
        echo "❌ System Status: UNHEALTHY"
    fi
    
    echo ""
    echo "📋 Detailed Results:"
    echo "===================="
    
    for check in "${HEALTH_CHECKS[@]}"; do
        IFS='|' read -r service status message <<< "$check"
        
        case $status in
            "PASS")
                echo "✅ $service: $message"
                ;;
            "WARN")
                echo "⚠️  $service: $message"
                ;;
            "FAIL")
                echo "❌ $service: $message"
                ;;
        esac
    done
    
    echo ""
    
    if [ $FAILED_CHECKS -gt 0 ]; then
        echo "🔧 Recommended Actions:"
        echo "======================"
        echo "1. Review failed checks and fix configuration issues"
        echo "2. Check AWS service health: https://status.aws.amazon.com/"
        echo "3. Review CloudWatch logs for detailed error information"
        echo "4. Verify IAM permissions and resource configurations"
        echo ""
        exit 1
    else
        echo "🎉 All systems operational!"
        echo ""
        exit 0
    fi
}

# Main execution
echo "🚀 Starting AWS Push Notifications Health Check..."
echo "Environment: $ENVIRONMENT"
echo "Region: $REGION"
echo ""

# Required tools check
if ! command -v jq &> /dev/null; then
    log_error "jq is required but not installed. Please install jq."
    exit 1
fi

# Run all health checks
check_aws_config
check_lambda_function
check_sns_topic
check_api_gateway
check_cloudwatch_logs
check_xray_tracing
check_iam_permissions

# Optional: Test function invocation (can be disabled with --no-test)
if [[ ! " $* " =~ " --no-test " ]]; then
    test_function_invocation
fi

# Display results
display_summary