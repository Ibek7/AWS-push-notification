#!/bin/bash

# X-Ray Tracing Setup Script
# Configures X-Ray tracing for AWS Push Notifications system

set -e

FUNCTION_NAME=${1:-"sendPushNotification"}
API_ID=${2}
STAGE=${3:-"prod"}
REGION=${AWS_REGION:-"us-east-1"}

echo "🔍 Setting up X-Ray tracing..."
echo "Function: $FUNCTION_NAME"
echo "Region: $REGION"

# Enable X-Ray tracing for Lambda function
echo "📡 Enabling X-Ray tracing for Lambda function..."
aws lambda put-function-configuration \
    --function-name "$FUNCTION_NAME" \
    --tracing-config Mode=Active \
    --region "$REGION"

if [ $? -eq 0 ]; then
    echo "✅ X-Ray enabled for Lambda function"
else
    echo "❌ Failed to enable X-Ray for Lambda function"
    exit 1
fi

# Enable X-Ray tracing for API Gateway (if API ID provided)
if [ -n "$API_ID" ]; then
    echo "📡 Enabling X-Ray tracing for API Gateway..."
    aws apigateway put-stage \
        --rest-api-id "$API_ID" \
        --stage-name "$STAGE" \
        --patch-ops op=replace,path=/tracingEnabled,value=true \
        --region "$REGION"
    
    if [ $? -eq 0 ]; then
        echo "✅ X-Ray enabled for API Gateway stage: $STAGE"
    else
        echo "❌ Failed to enable X-Ray for API Gateway"
    fi
fi

# Create X-Ray sampling rules
echo "📋 Creating X-Ray sampling rules..."
aws xray create-sampling-rule \
    --cli-input-json file://sampling-rules.json \
    --region "$REGION" 2>/dev/null || echo "⚠️  Sampling rules may already exist"

# Get X-Ray service map URL
SERVICE_MAP_URL="https://${REGION}.console.aws.amazon.com/xray/home?region=${REGION}#/service-map"

echo ""
echo "🎉 X-Ray tracing setup completed!"
echo ""
echo "🗺️  Service Map: $SERVICE_MAP_URL"
echo "📊 Traces Console: https://${REGION}.console.aws.amazon.com/xray/home?region=${REGION}#/traces"
echo ""
echo "Next steps:"
echo "1. Send some test notifications to generate traces"
echo "2. View the service map to see request flow"
echo "3. Analyze traces for performance bottlenecks"
echo "4. Set up alerts based on trace data"
echo ""