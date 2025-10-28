#!/bin/bash

# AWS Push Notifications Performance Monitor
# Real-time performance monitoring and analysis tool
# Usage: ./performance-monitor.sh [--duration 5m] [--detailed] [--json] [--alert-thresholds]

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="/tmp/performance-monitor-$(date +%Y%m%d-%H%M%S).log"
JSON_OUTPUT=false
DETAILED=false
DURATION="1m"
ALERT_THRESHOLDS=false

# Performance thresholds
ERROR_RATE_THRESHOLD=5      # Percentage
LATENCY_THRESHOLD=5000      # Milliseconds
THROUGHPUT_MIN=100          # Requests per minute

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default AWS resources
LAMBDA_FUNCTION_NAME="sendPushNotification"
SNS_TOPIC_NAME="PushNotificationTopic"
API_GATEWAY_ID=""  # Will be auto-detected

# Function to print colored output
print_metric() {
    local status=$1
    local metric=$2
    local value=$3
    local unit=$4
    local color
    
    case $status in
        "GOOD") color=$GREEN ;;
        "WARN") color=$YELLOW ;;
        "CRITICAL") color=$RED ;;
        "INFO") color=$BLUE ;;
        *) color=$NC ;;
    esac
    
    printf "${color}[%s]${NC} %-25s: %s %s\n" "$status" "$metric" "$value" "$unit" | tee -a "$LOG_FILE"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --duration)
            DURATION="$2"
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
        --alert-thresholds)
            ALERT_THRESHOLDS=true
            shift
            ;;
        --function-name)
            LAMBDA_FUNCTION_NAME="$2"
            shift 2
            ;;
        --topic-name)
            SNS_TOPIC_NAME="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --duration DURATION     Monitoring duration (default: 1m)"
            echo "  --detailed              Show detailed metrics"
            echo "  --json                  Output in JSON format"
            echo "  --alert-thresholds      Enable alerting based on thresholds"
            echo "  --function-name NAME    Lambda function name"
            echo "  --topic-name NAME       SNS topic name"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Convert duration to seconds for calculations
parse_duration() {
    local duration=$1
    case $duration in
        *s) echo "${duration%s}" ;;
        *m) echo "$((${duration%m} * 60))" ;;
        *h) echo "$((${duration%h} * 3600))" ;;
        *d) echo "$((${duration%d} * 86400))" ;;
        *) echo "60" ;; # Default to 60 seconds
    esac
}

DURATION_SECONDS=$(parse_duration "$DURATION")
START_TIME=$(date -d "$DURATION ago" -u +%Y-%m-%dT%H:%M:%S)
END_TIME=$(date -u +%Y-%m-%dT%H:%M:%S)

# Lambda performance metrics
get_lambda_metrics() {
    echo "=== Lambda Function Performance ($LAMBDA_FUNCTION_NAME) ===" | tee -a "$LOG_FILE"
    
    # Get invocation count
    local invocations=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/Lambda \
        --metric-name Invocations \
        --dimensions Name=FunctionName,Value="$LAMBDA_FUNCTION_NAME" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --period "$DURATION_SECONDS" \
        --statistics Sum \
        --query 'Datapoints[0].Sum' \
        --output text 2>/dev/null || echo "0")
    
    # Get error count
    local errors=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/Lambda \
        --metric-name Errors \
        --dimensions Name=FunctionName,Value="$LAMBDA_FUNCTION_NAME" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --period "$DURATION_SECONDS" \
        --statistics Sum \
        --query 'Datapoints[0].Sum' \
        --output text 2>/dev/null || echo "0")
    
    # Get duration metrics
    local avg_duration=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/Lambda \
        --metric-name Duration \
        --dimensions Name=FunctionName,Value="$LAMBDA_FUNCTION_NAME" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --period "$DURATION_SECONDS" \
        --statistics Average \
        --query 'Datapoints[0].Average' \
        --output text 2>/dev/null || echo "0")
    
    local max_duration=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/Lambda \
        --metric-name Duration \
        --dimensions Name=FunctionName,Value="$LAMBDA_FUNCTION_NAME" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --period "$DURATION_SECONDS" \
        --statistics Maximum \
        --query 'Datapoints[0].Maximum' \
        --output text 2>/dev/null || echo "0")
    
    # Get throttles
    local throttles=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/Lambda \
        --metric-name Throttles \
        --dimensions Name=FunctionName,Value="$LAMBDA_FUNCTION_NAME" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --period "$DURATION_SECONDS" \
        --statistics Sum \
        --query 'Datapoints[0].Sum' \
        --output text 2>/dev/null || echo "0")
    
    # Get concurrent executions
    local concurrent=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/Lambda \
        --metric-name ConcurrentExecutions \
        --dimensions Name=FunctionName,Value="$LAMBDA_FUNCTION_NAME" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --period "$DURATION_SECONDS" \
        --statistics Average \
        --query 'Datapoints[0].Average' \
        --output text 2>/dev/null || echo "0")
    
    # Handle "None" values
    [[ "$invocations" == "None" ]] && invocations=0
    [[ "$errors" == "None" ]] && errors=0
    [[ "$avg_duration" == "None" ]] && avg_duration=0
    [[ "$max_duration" == "None" ]] && max_duration=0
    [[ "$throttles" == "None" ]] && throttles=0
    [[ "$concurrent" == "None" ]] && concurrent=0
    
    # Calculate metrics
    local throughput=0
    local error_rate=0
    
    if [[ $(echo "$invocations > 0" | bc -l) == 1 ]]; then
        throughput=$(echo "scale=2; $invocations * 60 / $DURATION_SECONDS" | bc)
        error_rate=$(echo "scale=2; $errors * 100 / $invocations" | bc)
    fi
    
    # Determine status and display metrics
    local invocation_status="INFO"
    local error_status="GOOD"
    local duration_status="GOOD"
    local throttle_status="GOOD"
    
    if [[ $(echo "$error_rate > $ERROR_RATE_THRESHOLD" | bc -l) == 1 ]]; then
        error_status="CRITICAL"
    elif [[ $(echo "$error_rate > 2" | bc -l) == 1 ]]; then
        error_status="WARN"
    fi
    
    if [[ $(echo "$avg_duration > $LATENCY_THRESHOLD" | bc -l) == 1 ]]; then
        duration_status="CRITICAL"
    elif [[ $(echo "$avg_duration > 3000" | bc -l) == 1 ]]; then
        duration_status="WARN"
    fi
    
    if [[ $(echo "$throttles > 0" | bc -l) == 1 ]]; then
        throttle_status="CRITICAL"
    fi
    
    print_metric "$invocation_status" "Invocations" "${invocations%.*}" "count"
    print_metric "$error_status" "Error Rate" "${error_rate}%" ""
    print_metric "INFO" "Throughput" "${throughput}" "req/min"
    print_metric "$duration_status" "Avg Duration" "${avg_duration%.*}" "ms"
    print_metric "$duration_status" "Max Duration" "${max_duration%.*}" "ms"
    print_metric "$throttle_status" "Throttles" "${throttles%.*}" "count"
    print_metric "INFO" "Concurrent Executions" "${concurrent%.*}" "avg"
    
    # Store metrics for JSON output
    lambda_metrics="{
        \"invocations\": ${invocations%.*},
        \"errors\": ${errors%.*},
        \"error_rate\": $error_rate,
        \"throughput\": $throughput,
        \"avg_duration\": ${avg_duration%.*},
        \"max_duration\": ${max_duration%.*},
        \"throttles\": ${throttles%.*},
        \"concurrent_executions\": ${concurrent%.*}
    }"
}

# SNS performance metrics
get_sns_metrics() {
    echo | tee -a "$LOG_FILE"
    echo "=== SNS Topic Performance ($SNS_TOPIC_NAME) ===" | tee -a "$LOG_FILE"
    
    # Get published messages
    local published=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/SNS \
        --metric-name NumberOfMessagesPublished \
        --dimensions Name=TopicName,Value="$SNS_TOPIC_NAME" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --period "$DURATION_SECONDS" \
        --statistics Sum \
        --query 'Datapoints[0].Sum' \
        --output text 2>/dev/null || echo "0")
    
    # Get failed messages
    local failed=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/SNS \
        --metric-name NumberOfMessagesFailed \
        --dimensions Name=TopicName,Value="$SNS_TOPIC_NAME" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --period "$DURATION_SECONDS" \
        --statistics Sum \
        --query 'Datapoints[0].Sum' \
        --output text 2>/dev/null || echo "0")
    
    # Get delivered notifications
    local delivered=$(aws cloudwatch get-metric-statistics \
        --namespace AWS/SNS \
        --metric-name NumberOfNotificationsDelivered \
        --dimensions Name=TopicName,Value="$SNS_TOPIC_NAME" \
        --start-time "$START_TIME" \
        --end-time "$END_TIME" \
        --period "$DURATION_SECONDS" \
        --statistics Sum \
        --query 'Datapoints[0].Sum' \
        --output text 2>/dev/null || echo "0")
    
    # Handle "None" values
    [[ "$published" == "None" ]] && published=0
    [[ "$failed" == "None" ]] && failed=0
    [[ "$delivered" == "None" ]] && delivered=0
    
    # Calculate metrics
    local failure_rate=0
    local delivery_rate=0
    local publish_rate=0
    
    if [[ $(echo "$published > 0" | bc -l) == 1 ]]; then
        failure_rate=$(echo "scale=2; $failed * 100 / $published" | bc)
        publish_rate=$(echo "scale=2; $published * 60 / $DURATION_SECONDS" | bc)
    fi
    
    if [[ $(echo "$published > 0" | bc -l) == 1 ]]; then
        delivery_rate=$(echo "scale=2; $delivered * 100 / $published" | bc)
    fi
    
    # Determine status
    local publish_status="INFO"
    local failure_status="GOOD"
    local delivery_status="GOOD"
    
    if [[ $(echo "$failure_rate > 5" | bc -l) == 1 ]]; then
        failure_status="CRITICAL"
    elif [[ $(echo "$failure_rate > 2" | bc -l) == 1 ]]; then
        failure_status="WARN"
    fi
    
    if [[ $(echo "$delivery_rate < 95" | bc -l) == 1 ]]; then
        delivery_status="WARN"
    fi
    
    print_metric "$publish_status" "Messages Published" "${published%.*}" "count"
    print_metric "$failure_status" "Messages Failed" "${failed%.*}" "count"
    print_metric "$failure_status" "Failure Rate" "${failure_rate}%" ""
    print_metric "$delivery_status" "Delivery Rate" "${delivery_rate}%" ""
    print_metric "INFO" "Publish Rate" "${publish_rate}" "msg/min"
    
    # Store metrics for JSON output
    sns_metrics="{
        \"published\": ${published%.*},
        \"failed\": ${failed%.*},
        \"delivered\": ${delivered%.*},
        \"failure_rate\": $failure_rate,
        \"delivery_rate\": $delivery_rate,
        \"publish_rate\": $publish_rate
    }"
}

# System health check
get_system_health() {
    echo | tee -a "$LOG_FILE"
    echo "=== System Health Overview ===" | tee -a "$LOG_FILE"
    
    # Check Lambda function status
    local function_state=$(aws lambda get-function --function-name "$LAMBDA_FUNCTION_NAME" --query 'Configuration.State' --output text 2>/dev/null || echo "Unknown")
    local function_status="GOOD"
    
    if [[ "$function_state" != "Active" ]]; then
        function_status="CRITICAL"
    fi
    
    print_metric "$function_status" "Lambda Function State" "$function_state" ""
    
    # Check SNS topic existence
    local topic_exists=$(aws sns list-topics --query "Topics[?contains(TopicArn, '$SNS_TOPIC_NAME')]" --output text)
    local topic_status="GOOD"
    
    if [[ -z "$topic_exists" ]]; then
        topic_status="CRITICAL"
        print_metric "$topic_status" "SNS Topic" "Not Found" ""
    else
        print_metric "$topic_status" "SNS Topic" "Active" ""
    fi
    
    # Check recent errors in logs
    local recent_errors=$(aws logs filter-log-events \
        --log-group-name "/aws/lambda/$LAMBDA_FUNCTION_NAME" \
        --start-time $(date -d '10 minutes ago' +%s)000 \
        --filter-pattern "ERROR" \
        --query 'events | length' 2>/dev/null || echo "0")
    
    local error_status="GOOD"
    if [[ "$recent_errors" -gt 10 ]]; then
        error_status="CRITICAL"
    elif [[ "$recent_errors" -gt 5 ]]; then
        error_status="WARN"
    fi
    
    print_metric "$error_status" "Recent Errors (10m)" "$recent_errors" "count"
}

# Cost analysis
get_cost_metrics() {
    if [[ $DETAILED == true ]]; then
        echo | tee -a "$LOG_FILE"
        echo "=== Cost Analysis (Last 24h) ===" | tee -a "$LOG_FILE"
        
        # Get Lambda cost estimate (approximate)
        local invocations_24h=$(aws cloudwatch get-metric-statistics \
            --namespace AWS/Lambda \
            --metric-name Invocations \
            --dimensions Name=FunctionName,Value="$LAMBDA_FUNCTION_NAME" \
            --start-time $(date -d '24 hours ago' -u +%Y-%m-%dT%H:%M:%S) \
            --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
            --period 86400 \
            --statistics Sum \
            --query 'Datapoints[0].Sum' \
            --output text 2>/dev/null || echo "0")
        
        [[ "$invocations_24h" == "None" ]] && invocations_24h=0
        
        # Rough cost calculation (simplified)
        local lambda_cost=$(echo "scale=4; $invocations_24h * 0.0000002" | bc) # Approximate Lambda cost
        
        print_metric "INFO" "Lambda Invocations (24h)" "${invocations_24h%.*}" "count"
        print_metric "INFO" "Estimated Lambda Cost" "\$${lambda_cost}" ""
    fi
}

# Performance recommendations
get_recommendations() {
    if [[ $DETAILED == true ]]; then
        echo | tee -a "$LOG_FILE"
        echo "=== Performance Recommendations ===" | tee -a "$LOG_FILE"
        
        # Check for cold starts
        local cold_starts=$(aws logs filter-log-events \
            --log-group-name "/aws/lambda/$LAMBDA_FUNCTION_NAME" \
            --start-time $(date -d '1 hour ago' +%s)000 \
            --filter-pattern "INIT_START" \
            --query 'events | length' 2>/dev/null || echo "0")
        
        if [[ "$cold_starts" -gt 0 ]]; then
            echo -e "${YELLOW}⚠️  Detected $cold_starts cold starts in the last hour${NC}" | tee -a "$LOG_FILE"
            echo "   Consider enabling Provisioned Concurrency" | tee -a "$LOG_FILE"
        fi
        
        # Check memory utilization
        local memory_used=$(aws logs filter-log-events \
            --log-group-name "/aws/lambda/$LAMBDA_FUNCTION_NAME" \
            --start-time $(date -d '1 hour ago' +%s)000 \
            --filter-pattern "[timestamp, requestId, \"REPORT\"]" \
            --limit 10 | jq -r '.events[].message' | grep -o "Max Memory Used: [0-9]*" | head -1 | grep -o "[0-9]*" || echo "0")
        
        if [[ "$memory_used" -gt 0 ]]; then
            local memory_config=$(aws lambda get-function-configuration --function-name "$LAMBDA_FUNCTION_NAME" --query 'MemorySize' --output text)
            local memory_utilization=$(echo "scale=2; $memory_used * 100 / $memory_config" | bc)
            
            if [[ $(echo "$memory_utilization < 50" | bc -l) == 1 ]]; then
                echo -e "${YELLOW}⚠️  Memory utilization is low (${memory_utilization}%)${NC}" | tee -a "$LOG_FILE"
                echo "   Consider reducing memory allocation to save costs" | tee -a "$LOG_FILE"
            elif [[ $(echo "$memory_utilization > 90" | bc -l) == 1 ]]; then
                echo -e "${RED}🚨 Memory utilization is high (${memory_utilization}%)${NC}" | tee -a "$LOG_FILE"
                echo "   Consider increasing memory allocation" | tee -a "$LOG_FILE"
            fi
        fi
    fi
}

# Generate alerts if thresholds are enabled
check_alerts() {
    if [[ $ALERT_THRESHOLDS == true ]]; then
        echo | tee -a "$LOG_FILE"
        echo "=== Alert Analysis ===" | tee -a "$LOG_FILE"
        
        # Parse stored metrics (simplified approach)
        local has_alerts=false
        
        # Check error rate
        local current_error_rate=$(echo "$lambda_metrics" | jq -r '.error_rate')
        if [[ $(echo "$current_error_rate > $ERROR_RATE_THRESHOLD" | bc -l) == 1 ]]; then
            echo -e "${RED}🚨 ALERT: Error rate (${current_error_rate}%) exceeds threshold (${ERROR_RATE_THRESHOLD}%)${NC}" | tee -a "$LOG_FILE"
            has_alerts=true
        fi
        
        # Check latency
        local current_latency=$(echo "$lambda_metrics" | jq -r '.avg_duration')
        if [[ $(echo "$current_latency > $LATENCY_THRESHOLD" | bc -l) == 1 ]]; then
            echo -e "${RED}🚨 ALERT: Average latency (${current_latency}ms) exceeds threshold (${LATENCY_THRESHOLD}ms)${NC}" | tee -a "$LOG_FILE"
            has_alerts=true
        fi
        
        # Check throughput
        local current_throughput=$(echo "$lambda_metrics" | jq -r '.throughput')
        if [[ $(echo "$current_throughput < $THROUGHPUT_MIN" | bc -l) == 1 ]] && [[ $(echo "$current_throughput > 0" | bc -l) == 1 ]]; then
            echo -e "${YELLOW}⚠️  WARNING: Throughput (${current_throughput} req/min) below minimum (${THROUGHPUT_MIN} req/min)${NC}" | tee -a "$LOG_FILE"
            has_alerts=true
        fi
        
        if [[ $has_alerts == false ]]; then
            echo -e "${GREEN}✅ All metrics within acceptable thresholds${NC}" | tee -a "$LOG_FILE"
        fi
    fi
}

# Generate JSON output
generate_json_output() {
    if [[ $JSON_OUTPUT == true ]]; then
        cat > "/tmp/performance-metrics.json" << EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "duration": "$DURATION",
  "lambda_function": "$LAMBDA_FUNCTION_NAME",
  "sns_topic": "$SNS_TOPIC_NAME",
  "metrics": {
    "lambda": $lambda_metrics,
    "sns": $sns_metrics
  },
  "log_file": "$LOG_FILE"
}
EOF
        echo | tee -a "$LOG_FILE"
        echo "JSON output saved to: /tmp/performance-metrics.json" | tee -a "$LOG_FILE"
    fi
}

# Main execution
main() {
    echo "AWS Push Notifications Performance Monitor"
    echo "========================================"
    echo "Duration: $DURATION"
    echo "Function: $LAMBDA_FUNCTION_NAME"
    echo "Topic: $SNS_TOPIC_NAME"
    echo "Time Range: $START_TIME to $END_TIME"
    echo "Log File: $LOG_FILE"
    echo
    
    # Check dependencies
    if ! command -v bc &> /dev/null; then
        echo -e "${RED}Error: 'bc' command not found. Please install bc for calculations.${NC}"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        echo -e "${YELLOW}Warning: 'jq' command not found. JSON features may not work.${NC}"
    fi
    
    # Initialize metric storage
    lambda_metrics="{}"
    sns_metrics="{}"
    
    # Run monitoring
    get_lambda_metrics
    get_sns_metrics
    get_system_health
    get_cost_metrics
    get_recommendations
    check_alerts
    generate_json_output
    
    echo | tee -a "$LOG_FILE"
    echo "Performance monitoring completed at $(date)" | tee -a "$LOG_FILE"
    echo "Full log available at: $LOG_FILE"
}

# Run main function
main "$@"