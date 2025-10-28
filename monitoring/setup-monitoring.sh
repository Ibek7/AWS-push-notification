#!/bin/bash

# AWS Push Notifications Monitoring Setup Script
# This script deploys monitoring infrastructure and configures observability

set -e

# Configuration
ENVIRONMENT=${1:-prod}
STACK_NAME="push-notifications-monitoring-${ENVIRONMENT}"
EMAIL=${2:-"admin@example.com"}
LAMBDA_FUNCTION_NAME=${3:-"sendPushNotification"}
SNS_TOPIC_NAME=${4:-"push-notifications"}

echo "🔍 Setting up monitoring for AWS Push Notifications..."
echo "Environment: $ENVIRONMENT"
echo "Alert Email: $EMAIL"
echo "Lambda Function: $LAMBDA_FUNCTION_NAME"
echo "SNS Topic: $SNS_TOPIC_NAME"

# Check if AWS CLI is configured
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    echo "❌ AWS CLI not configured or no valid credentials"
    exit 1
fi

# Deploy CloudWatch monitoring stack
echo "📊 Deploying CloudWatch monitoring stack..."
aws cloudformation deploy \
    --template-file cloudwatch-stack.yaml \
    --stack-name "$STACK_NAME" \
    --parameter-overrides \
        Environment="$ENVIRONMENT" \
        LambdaFunctionName="$LAMBDA_FUNCTION_NAME" \
        SNSTopicName="$SNS_TOPIC_NAME" \
        NotificationEmail="$EMAIL" \
    --capabilities CAPABILITY_IAM \
    --region "${AWS_REGION:-us-east-1}"

if [ $? -eq 0 ]; then
    echo "✅ CloudWatch stack deployed successfully"
else
    echo "❌ CloudWatch stack deployment failed"
    exit 1
fi

# Enable X-Ray tracing for Lambda function
echo "🔍 Enabling X-Ray tracing..."
aws lambda put-function-configuration \
    --function-name "$LAMBDA_FUNCTION_NAME" \
    --tracing-config Mode=Active \
    --region "${AWS_REGION:-us-east-1}" || echo "⚠️  X-Ray configuration failed (function may not exist)"

# Create additional log groups with retention
echo "📝 Setting up log groups..."
LOG_GROUPS=(
    "/aws/lambda/${LAMBDA_FUNCTION_NAME}"
    "/aws/apigateway/push-notifications"
    "/aws/sns/${SNS_TOPIC_NAME}"
)

for log_group in "${LOG_GROUPS[@]}"; do
    aws logs create-log-group \
        --log-group-name "$log_group" \
        --region "${AWS_REGION:-us-east-1}" 2>/dev/null || echo "Log group $log_group already exists"
    
    aws logs put-retention-policy \
        --log-group-name "$log_group" \
        --retention-in-days 30 \
        --region "${AWS_REGION:-us-east-1}" || echo "⚠️  Failed to set retention for $log_group"
done

# Get dashboard URL
DASHBOARD_URL=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query 'Stacks[0].Outputs[?OutputKey==`DashboardURL`].OutputValue' \
    --output text \
    --region "${AWS_REGION:-us-east-1}")

# Get alert topic ARN
ALERT_TOPIC_ARN=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query 'Stacks[0].Outputs[?OutputKey==`AlertTopicArn`].OutputValue' \
    --output text \
    --region "${AWS_REGION:-us-east-1}")

echo ""
echo "🎉 Monitoring setup completed successfully!"
echo ""
echo "📊 Dashboard URL: $DASHBOARD_URL"
echo "🚨 Alert Topic ARN: $ALERT_TOPIC_ARN"
echo ""
echo "Next steps:"
echo "1. Check your email ($EMAIL) to confirm SNS subscription"
echo "2. Visit the dashboard to view real-time metrics"
echo "3. Test the alerting by triggering some errors"
echo "4. Configure custom metrics as needed"
echo ""

# Create monitoring summary file
cat > monitoring-summary.txt << EOF
AWS Push Notifications Monitoring Setup Summary
=============================================

Environment: $ENVIRONMENT
Deployment Date: $(date)
Stack Name: $STACK_NAME

Resources Created:
- CloudWatch Dashboard: ${ENVIRONMENT}-push-notifications-dashboard
- SNS Alert Topic: $ALERT_TOPIC_ARN
- Lambda Error Rate Alarm
- Lambda Duration Alarm
- Lambda Throttle Alarm
- SNS Failure Alarm
- Application Error Alarm
- Custom Metric Filters for FCM failures and success rate

Dashboard URL: $DASHBOARD_URL

Alert Configuration:
- Email: $EMAIL
- Critical Thresholds:
  * Lambda Error Rate: > 10 errors in 10 minutes
  * Lambda Duration: > 10 seconds average over 15 minutes
  * SNS Failures: > 5 failures in 10 minutes
  * Application Errors: > 5 errors in 10 minutes

Log Groups:
$(printf '%s\n' "${LOG_GROUPS[@]}")

X-Ray Tracing: Enabled for $LAMBDA_FUNCTION_NAME
Log Retention: 30 days for all log groups
EOF

echo "📋 Summary saved to: monitoring-summary.txt"