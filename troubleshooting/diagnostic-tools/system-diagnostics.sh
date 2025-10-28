#!/bin/bash

# AWS Push Notifications System Diagnostics
# Comprehensive health check for all system components
# Usage: ./system-diagnostics.sh [--env prod|staging|dev] [--detailed] [--json]

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/system-diagnostics-$(date +%Y%m%d-%H%M%S).log"
JSON_OUTPUT=false
DETAILED=false
ENVIRONMENT="prod"

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Status tracking
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

# Default configuration (override with environment specific values)
LAMBDA_FUNCTION_NAME="sendPushNotification"
SNS_TOPIC_NAME="PushNotificationTopic"
LOG_GROUP_NAME="/aws/lambda/sendPushNotification"
FIREBASE_SERVER_KEY_PARAM="/pushnotifications/firebase/server-key"

# Function to print colored output
print_status() {
    local status=$1
    local message=$2
    local color
    
    case $status in
        "PASS") color=$GREEN; ((PASSED_CHECKS++)) ;;
        "FAIL") color=$RED; ((FAILED_CHECKS++)) ;;
        "WARN") color=$YELLOW; ((WARNING_CHECKS++)) ;;
        "INFO") color=$BLUE ;;
        *) color=$NC ;;
    esac
    
    echo -e "${color}[$status]${NC} $message" | tee -a "$LOG_FILE"
    ((TOTAL_CHECKS++))
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --env)
            ENVIRONMENT="$2"
            shift 2
            ;;
        --detailed)
            DETAILED=true
            shift
            ;;
        --json)
            JSON_OUTPUT=true
            shift
            ;;
        --help)
            echo "Usage: $0 [--env prod|staging|dev] [--detailed] [--json]"
            echo "  --env       Environment to check (default: prod)"
            echo "  --detailed  Show detailed information"
            echo "  --json      Output results in JSON format"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Load environment-specific configuration
load_environment_config() {
    local env_file="$SCRIPT_DIR/../../config/${ENVIRONMENT}.json"
    
    if [[ -f "$env_file" ]]; then
        print_status "INFO" "Loading configuration for environment: $ENVIRONMENT"
        
        # Extract configuration using jq if available
        if command -v jq &> /dev/null; then
            LAMBDA_FUNCTION_NAME=$(jq -r '.lambdaFunctionName // "sendPushNotification"' "$env_file")
            SNS_TOPIC_NAME=$(jq -r '.snsTopicName // "PushNotificationTopic"' "$env_file")
            AWS_REGION=$(jq -r '.region // "us-east-1"' "$env_file")
        fi
    else
        print_status "WARN" "Environment config file not found: $env_file"
    fi
}

# Check AWS CLI configuration
check_aws_cli() {
    print_status "INFO" "Checking AWS CLI configuration..."
    
    if ! command -v aws &> /dev/null; then
        print_status "FAIL" "AWS CLI not installed"
        return 1
    fi
    
    if aws sts get-caller-identity &> /dev/null; then
        local account_id=$(aws sts get-caller-identity --query 'Account' --output text)
        local region=$(aws configure get region)
        print_status "PASS" "AWS CLI configured - Account: $account_id, Region: $region"
    else
        print_status "FAIL" "AWS CLI not configured or invalid credentials"
        return 1
    fi
}

# Check Lambda function health
check_lambda_function() {
    print_status "INFO" "Checking Lambda function: $LAMBDA_FUNCTION_NAME"
    
    # Check if function exists
    if aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" &> /dev/null; then
        print_status "PASS" "Lambda function exists"
        
        # Get function configuration
        local config=$(aws lambda get-function-configuration --function-name "$LAMBDA_FUNCTION_NAME")
        local state=$(echo "$config" | jq -r '.State')
        local last_modified=$(echo "$config" | jq -r '.LastModified')
        local timeout=$(echo "$config" | jq -r '.Timeout')
        local memory=$(echo "$config" | jq -r '.MemorySize')
        
        if [[ "$state" == "Active" ]]; then
            print_status "PASS" "Lambda function state: $state"
        else
            print_status "FAIL" "Lambda function state: $state"
        fi
        
        if [[ $DETAILED == true ]]; then
            print_status "INFO" "Function details - Timeout: ${timeout}s, Memory: ${memory}MB, Modified: $last_modified"
        fi
        
        # Test function invocation
        local test_payload='{"test": true, "source": "diagnostics"}'
        if aws lambda invoke \
            --function-name "$LAMBDA_FUNCTION_NAME" \
            --payload "$test_payload" \
            --cli-binary-format raw-in-base64-out \
            /tmp/lambda-test-response.json &> /dev/null; then
            
            local status_code=$(jq -r '.StatusCode // 500' /tmp/lambda-test-response.json 2>/dev/null || echo "500")
            if [[ "$status_code" == "200" ]]; then
                print_status "PASS" "Lambda function responds to test invocation"
            else
                print_status "FAIL" "Lambda function test invocation failed with status: $status_code"
            fi
        else
            print_status "FAIL" "Cannot invoke Lambda function"
        fi
        
    else
        print_status "FAIL" "Lambda function not found: $LAMBDA_FUNCTION_NAME"
        return 1
    fi
}

# Check SNS topic health
check_sns_topic() {
    print_status "INFO" "Checking SNS topic: $SNS_TOPIC_NAME"
    
    # Get topic ARN
    local topic_arn=$(aws sns list-topics --query "Topics[?contains(TopicArn, '$SNS_TOPIC_NAME')].TopicArn" --output text)
    
    if [[ -n "$topic_arn" ]]; then
        print_status "PASS" "SNS topic exists: $topic_arn"
        
        # Check topic attributes
        local attributes=$(aws sns get-topic-attributes --topic-arn "$topic_arn")
        local display_name=$(echo "$attributes" | jq -r '.Attributes.DisplayName // "N/A"')
        
        if [[ $DETAILED == true ]]; then
            print_status "INFO" "Topic display name: $display_name"
        fi
        
        # Check subscriptions
        local subscriptions=$(aws sns list-subscriptions-by-topic --topic-arn "$topic_arn")
        local sub_count=$(echo "$subscriptions" | jq '.Subscriptions | length')
        
        if [[ "$sub_count" -gt 0 ]]; then
            print_status "PASS" "SNS topic has $sub_count subscription(s)"
            
            # Check subscription health
            echo "$subscriptions" | jq -r '.Subscriptions[] | "\(.Protocol):\(.Endpoint):\(.SubscriptionArn)"' | while IFS=: read -r protocol endpoint sub_arn; do
                if [[ "$sub_arn" != "PendingConfirmation" ]]; then
                    print_status "PASS" "Subscription confirmed: $protocol -> ${endpoint:0:50}..."
                else
                    print_status "WARN" "Subscription pending confirmation: $protocol -> ${endpoint:0:50}..."
                fi
            done
        else
            print_status "WARN" "SNS topic has no subscriptions"
        fi
        
        # Test topic publishing
        local test_message='{"test": true, "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'", "source": "diagnostics"}'
        if aws sns publish --topic-arn "$topic_arn" --message "$test_message" --subject "Health Check" &> /dev/null; then
            print_status "PASS" "SNS topic accepts test messages"
        else
            print_status "FAIL" "Cannot publish to SNS topic"
        fi
        
    else
        print_status "FAIL" "SNS topic not found: $SNS_TOPIC_NAME"
        return 1
    fi
}

# Check CloudWatch logs
check_cloudwatch_logs() {
    print_status "INFO" "Checking CloudWatch logs: $LOG_GROUP_NAME"
    
    if aws logs describe-log-groups --log-group-name-prefix "$LOG_GROUP_NAME" --query 'logGroups[0]' &> /dev/null; then
        print_status "PASS" "CloudWatch log group exists"
        
        # Check recent log entries
        local recent_logs=$(aws logs filter-log-events \
            --log-group-name "$LOG_GROUP_NAME" \
            --start-time $(date -d '10 minutes ago' +%s)000 \
            --query 'events | length')
        
        if [[ "$recent_logs" -gt 0 ]]; then
            print_status "PASS" "Recent log entries found: $recent_logs in last 10 minutes"
        else
            print_status "WARN" "No recent log entries found"
        fi
        
        # Check for errors in recent logs
        local error_count=$(aws logs filter-log-events \
            --log-group-name "$LOG_GROUP_NAME" \
            --start-time $(date -d '1 hour ago' +%s)000 \
            --filter-pattern "ERROR" \
            --query 'events | length')
        
        if [[ "$error_count" -eq 0 ]]; then
            print_status "PASS" "No errors in recent logs"
        else
            print_status "WARN" "Found $error_count error(s) in last hour"
        fi
        
    else
        print_status "FAIL" "CloudWatch log group not found"
        return 1
    fi
}

# Check Firebase configuration
check_firebase_config() {
    print_status "INFO" "Checking Firebase configuration"
    
    # Check if server key parameter exists
    if aws ssm get-parameter --name "$FIREBASE_SERVER_KEY_PARAM" --with-decryption &> /dev/null; then
        print_status "PASS" "Firebase server key parameter exists"
        
        # Test FCM API connectivity (without exposing key)
        local server_key=$(aws ssm get-parameter --name "$FIREBASE_SERVER_KEY_PARAM" --with-decryption --query 'Parameter.Value' --output text)
        
        if [[ -n "$server_key" && "$server_key" != "None" ]]; then
            # Test FCM API with dummy token
            local response=$(curl -s -w "%{http_code}" -X POST https://fcm.googleapis.com/fcm/send \
                -H "Authorization: key=$server_key" \
                -H "Content-Type: application/json" \
                -d '{"to":"test_token","data":{"test":"connectivity"}}' 2>/dev/null || echo "000")
            
            local http_code="${response: -3}"
            
            if [[ "$http_code" == "200" ]]; then
                print_status "PASS" "FCM API is accessible and authenticated"
            elif [[ "$http_code" == "400" ]]; then
                print_status "PASS" "FCM API is accessible (400 expected for dummy token)"
            else
                print_status "FAIL" "FCM API connectivity issue - HTTP $http_code"
            fi
        else
            print_status "FAIL" "Firebase server key is empty or invalid"
        fi
        
    else
        print_status "FAIL" "Firebase server key parameter not found"
        return 1
    fi
}

# Check system metrics
check_system_metrics() {
    print_status "INFO" "Checking system metrics"
    
    # Lambda metrics
    local lambda_errors=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/Lambda \
        --metric-name Errors \
        --dimensions Name=FunctionName,Value="$LAMBDA_FUNCTION_NAME" \
        --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%S) \
        --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
        --period 3600 \
        --statistics Sum \
        --query 'Datapoints[0].Sum' \
        --output text 2>/dev/null || echo "None")
    
    if [[ "$lambda_errors" == "None" || "$lambda_errors" == "0" || "$lambda_errors" == "0.0" ]]; then
        print_status "PASS" "No Lambda errors in last hour"
    else
        print_status "WARN" "Lambda errors in last hour: $lambda_errors"
    fi
    
    # SNS metrics
    local sns_failures=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/SNS \
        --metric-name NumberOfMessagesFailed \
        --dimensions Name=TopicName,Value="$SNS_TOPIC_NAME" \
        --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%S) \
        --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
        --period 3600 \
        --statistics Sum \
        --query 'Datapoints[0].Sum' \
        --output text 2>/dev/null || echo "None")
    
    if [[ "$sns_failures" == "None" || "$sns_failures" == "0" || "$sns_failures" == "0.0" ]]; then
        print_status "PASS" "No SNS delivery failures in last hour"
    else
        print_status "WARN" "SNS delivery failures in last hour: $sns_failures"
    fi
}

# Check dependencies
check_dependencies() {
    print_status "INFO" "Checking system dependencies"
    
    # Check required tools
    local tools=("jq" "curl" "bc")
    for tool in "${tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            print_status "PASS" "Tool available: $tool"
        else
            print_status "WARN" "Tool missing: $tool (some features may not work)"
        fi
    done
    
    # Check network connectivity
    if curl -s --max-time 5 https://aws.amazon.com > /dev/null; then
        print_status "PASS" "Internet connectivity to AWS"
    else
        print_status "FAIL" "No internet connectivity to AWS"
    fi
    
    if curl -s --max-time 5 https://fcm.googleapis.com > /dev/null; then
        print_status "PASS" "Internet connectivity to FCM"
    else
        print_status "FAIL" "No internet connectivity to FCM"
    fi
}

# Generate summary report
generate_summary() {
    echo | tee -a "$LOG_FILE"
    echo "=== SYSTEM DIAGNOSTICS SUMMARY ===" | tee -a "$LOG_FILE"
    echo "Environment: $ENVIRONMENT" | tee -a "$LOG_FILE"
    echo "Timestamp: $(date)" | tee -a "$LOG_FILE"
    echo "Total Checks: $TOTAL_CHECKS" | tee -a "$LOG_FILE"
    echo -e "${GREEN}Passed: $PASSED_CHECKS${NC}" | tee -a "$LOG_FILE"
    echo -e "${YELLOW}Warnings: $WARNING_CHECKS${NC}" | tee -a "$LOG_FILE"
    echo -e "${RED}Failed: $FAILED_CHECKS${NC}" | tee -a "$LOG_FILE"
    echo | tee -a "$LOG_FILE"
    
    # Calculate overall health score
    local health_score=$((PASSED_CHECKS * 100 / TOTAL_CHECKS))
    
    if [[ $health_score -ge 90 ]]; then
        echo -e "${GREEN}Overall System Health: EXCELLENT ($health_score%)${NC}" | tee -a "$LOG_FILE"
    elif [[ $health_score -ge 75 ]]; then
        echo -e "${YELLOW}Overall System Health: GOOD ($health_score%)${NC}" | tee -a "$LOG_FILE"
    elif [[ $health_score -ge 60 ]]; then
        echo -e "${YELLOW}Overall System Health: FAIR ($health_score%)${NC}" | tee -a "$LOG_FILE"
    else
        echo -e "${RED}Overall System Health: POOR ($health_score%)${NC}" | tee -a "$LOG_FILE"
    fi
    
    echo | tee -a "$LOG_FILE"
    echo "Detailed log saved to: $LOG_FILE" | tee -a "$LOG_FILE"
    
    # JSON output if requested
    if [[ $JSON_OUTPUT == true ]]; then
        cat > "/tmp/diagnostics-summary.json" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "environment": "$ENVIRONMENT",
  "total_checks": $TOTAL_CHECKS,
  "passed": $PASSED_CHECKS,
  "warnings": $WARNING_CHECKS,
  "failed": $FAILED_CHECKS,
  "health_score": $health_score,
  "log_file": "$LOG_FILE"
}
EOF
        echo "JSON summary saved to: /tmp/diagnostics-summary.json"
    fi
}

# Main execution
main() {
    echo "AWS Push Notifications System Diagnostics"
    echo "========================================"
    echo "Environment: $ENVIRONMENT"
    echo "Detailed mode: $DETAILED"
    echo "Log file: $LOG_FILE"
    echo
    
    # Load environment configuration
    load_environment_config
    
    # Run all checks
    check_dependencies
    check_aws_cli
    check_lambda_function
    check_sns_topic
    check_cloudwatch_logs
    check_firebase_config
    check_system_metrics
    
    # Generate summary
    generate_summary
    
    # Exit with appropriate code
    if [[ $FAILED_CHECKS -gt 0 ]]; then
        exit 1
    elif [[ $WARNING_CHECKS -gt 0 ]]; then
        exit 2
    else
        exit 0
    fi
}

# Run main function
main "$@"