# SNS Issues Troubleshooting Runbook

## 🎯 Purpose
This runbook provides procedures for diagnosing and resolving Amazon SNS (Simple Notification Service) issues in the Push Notifications system.

## 🚨 Emergency Response

### 🔥 CRITICAL: SNS Topic Not Publishing Messages
**Impact:** No notifications being sent
**SLA:** Resolve within 10 minutes

#### Immediate Actions (0-3 minutes)
1. **Verify Topic Status**
   ```bash
   aws sns get-topic-attributes --topic-arn arn:aws:sns:region:account:PushNotificationTopic
   ```

2. **Check Recent Publications**
   ```bash
   aws cloudwatch get-metric-statistics \
     --namespace AWS/SNS \
     --metric-name NumberOfMessagesPublished \
     --dimensions Name=TopicName,Value=PushNotificationTopic \
     --start-time $(date -d '10 minutes ago' -u +%Y-%m-%dT%H:%M:%S) \
     --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
     --period 60 \
     --statistics Sum
   ```

3. **Test Manual Publication**
   ```bash
   aws sns publish \
     --topic-arn arn:aws:sns:region:account:PushNotificationTopic \
     --message "Emergency test message" \
     --subject "Health Check"
   ```

#### Escalation (3-10 minutes)
If topic is unresponsive:
1. Check AWS Service Health for SNS
2. Verify IAM permissions
3. Contact AWS Support if service issue

## 🔧 Standard Troubleshooting Procedures

### 1. Message Delivery Failures

#### Symptoms
- High NumberOfMessagesFailed metric
- Lambda functions not being triggered
- Messages not reaching subscribers

#### Diagnosis Steps
```bash
# Check delivery failure metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/SNS \
  --metric-name NumberOfMessagesFailed \
  --dimensions Name=TopicName,Value=PushNotificationTopic \
  --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum,Maximum

# List all subscriptions
aws sns list-subscriptions-by-topic \
  --topic-arn arn:aws:sns:region:account:PushNotificationTopic

# Check subscription attributes for each subscription
for sub in $(aws sns list-subscriptions-by-topic --topic-arn arn:aws:sns:region:account:PushNotificationTopic --query 'Subscriptions[].SubscriptionArn' --output text); do
  echo "=== Subscription: $sub ==="
  aws sns get-subscription-attributes --subscription-arn $sub
done
```

#### Resolution Actions

**1. Check Dead Letter Queue**
```bash
# If DLQ is configured, check for failed messages
aws sqs receive-message \
  --queue-url https://sqs.region.amazonaws.com/account/push-notification-dlq \
  --max-number-of-messages 10 \
  --wait-time-seconds 1
```

**2. Verify Lambda Subscription**
```bash
# Check if Lambda has permission to be invoked by SNS
aws lambda get-policy --function-name sendPushNotification

# If missing, add permission
aws lambda add-permission \
  --function-name sendPushNotification \
  --statement-id sns-invoke \
  --action lambda:InvokeFunction \
  --principal sns.amazonaws.com \
  --source-arn arn:aws:sns:region:account:PushNotificationTopic
```

**3. Re-subscribe if necessary**
```bash
# Remove broken subscription
aws sns unsubscribe --subscription-arn $BROKEN_SUBSCRIPTION_ARN

# Create new subscription
aws sns subscribe \
  --topic-arn arn:aws:sns:region:account:PushNotificationTopic \
  --protocol lambda \
  --notification-endpoint arn:aws:lambda:region:account:function:sendPushNotification
```

### 2. Permission Issues

#### Symptoms
- AccessDenied errors when publishing
- Subscription failures
- Can't modify topic attributes

#### Diagnosis
```bash
# Check topic policy
aws sns get-topic-attributes \
  --topic-arn arn:aws:sns:region:account:PushNotificationTopic \
  --query 'Attributes.Policy'

# Check IAM permissions for publishing role/user
aws iam simulate-principal-policy \
  --policy-source-arn arn:aws:iam::account:role/lambda-execution-role \
  --action-names sns:Publish \
  --resource-arns arn:aws:sns:region:account:PushNotificationTopic
```

#### Resolution
```bash
# Update topic policy to allow publishing
cat > topic-policy.json << EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sns:Publish",
      "Resource": "arn:aws:sns:region:account:PushNotificationTopic"
    }
  ]
}
EOF

aws sns set-topic-attributes \
  --topic-arn arn:aws:sns:region:account:PushNotificationTopic \
  --attribute-name Policy \
  --attribute-value file://topic-policy.json
```

### 3. Message Throttling

#### Symptoms
- Throttling errors in logs
- Messages being delayed
- High publish request latency

#### Diagnosis
```bash
# Check publish rate and throttling
aws cloudwatch get-metric-statistics \
  --namespace AWS/SNS \
  --metric-name PublishSize \
  --dimensions Name=TopicName,Value=PushNotificationTopic \
  --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum,Average,Maximum

# Check for throttling errors in CloudWatch Logs
aws logs filter-log-events \
  --log-group-name /aws/lambda/sendPushNotification \
  --start-time $(date -d '1 hour ago' +%s)000 \
  --filter-pattern "Throttling"
```

#### Resolution Options

**1. Implement Exponential Backoff**
```javascript
// Add to Lambda function
const publishWithRetry = async (params, maxRetries = 3) => {
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      return await sns.publish(params).promise();
    } catch (error) {
      if (error.code === 'Throttling' && attempt < maxRetries) {
        const delay = Math.pow(2, attempt) * 1000; // Exponential backoff
        await new Promise(resolve => setTimeout(resolve, delay));
        continue;
      }
      throw error;
    }
  }
};
```

**2. Request Rate Limit Increase**
```bash
# Create AWS Support case for SNS rate limit increase
aws support create-case \
  --subject "SNS Rate Limit Increase Request" \
  --service-code "amazon-sns" \
  --severity-code "high" \
  --category-code "performance" \
  --communication-body "Request to increase SNS publish rate limit for topic: arn:aws:sns:region:account:PushNotificationTopic"
```

### 4. Message Size Issues

#### Symptoms
- Messages failing to publish
- InvalidParameter errors
- Truncated message content

#### Diagnosis
```bash
# Check message size metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/SNS \
  --metric-name PublishSize \
  --dimensions Name=TopicName,Value=PushNotificationTopic \
  --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Maximum,Average
```

#### Resolution
```javascript
// Add message size validation in Lambda
const MAX_SNS_MESSAGE_SIZE = 256 * 1024; // 256 KB

const validateMessageSize = (message) => {
  const messageSize = Buffer.byteLength(JSON.stringify(message), 'utf8');
  if (messageSize > MAX_SNS_MESSAGE_SIZE) {
    throw new Error(`Message size ${messageSize} exceeds SNS limit of ${MAX_SNS_MESSAGE_SIZE} bytes`);
  }
  return messageSize;
};

// Compress large messages if needed
const zlib = require('zlib');

const compressMessage = (message) => {
  if (Buffer.byteLength(JSON.stringify(message), 'utf8') > MAX_SNS_MESSAGE_SIZE) {
    return {
      compressed: true,
      data: zlib.gzipSync(JSON.stringify(message)).toString('base64')
    };
  }
  return message;
};
```

### 5. Cross-Region Issues

#### Symptoms
- Messages not delivering across regions
- Regional service failures
- Inconsistent behavior between regions

#### Diagnosis
```bash
# Check topic existence in different regions
for region in us-east-1 us-west-2 eu-west-1; do
  echo "=== Region: $region ==="
  aws sns list-topics --region $region --query 'Topics[?contains(TopicArn, `PushNotificationTopic`)]'
done

# Check cross-region permissions
aws sns get-topic-attributes \
  --topic-arn arn:aws:sns:region:account:PushNotificationTopic \
  --query 'Attributes.Policy' | jq '.Statement[] | select(.Condition.StringEquals.aws:SourceRegion)'
```

#### Resolution
```bash
# Create topic in backup region
aws sns create-topic \
  --name PushNotificationTopic-backup \
  --region us-west-2

# Set up cross-region replication (if needed)
aws sns subscribe \
  --topic-arn arn:aws:sns:us-east-1:account:PushNotificationTopic \
  --protocol sns \
  --notification-endpoint arn:aws:sns:us-west-2:account:PushNotificationTopic-backup \
  --region us-east-1
```

## 🔍 Advanced Diagnostics

### Message Tracing
```bash
# Enable SNS message delivery status logging
aws sns set-topic-attributes \
  --topic-arn arn:aws:sns:region:account:PushNotificationTopic \
  --attribute-name LambdaSuccessFeedbackRoleArn \
  --attribute-value arn:aws:iam::account:role/sns-delivery-status-role

aws sns set-topic-attributes \
  --topic-arn arn:aws:sns:region:account:PushNotificationTopic \
  --attribute-name LambdaSuccessFeedbackSampleRate \
  --attribute-value 100

aws sns set-topic-attributes \
  --topic-arn arn:aws:sns:region:account:PushNotificationTopic \
  --attribute-name LambdaFailureFeedbackRoleArn \
  --attribute-value arn:aws:iam::account:role/sns-delivery-status-role
```

### CloudWatch Insights for SNS Logs
```bash
# Query SNS delivery logs
aws logs start-query \
  --log-group-name sns/region/account/PushNotificationTopic/lambda \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, delivery.statusCode, delivery.dwellTimeMs | filter delivery.statusCode != "200" | sort @timestamp desc'
```

### Performance Analysis
```bash
# Comprehensive SNS metrics analysis
metrics=("NumberOfMessagesPublished" "NumberOfMessagesFailed" "NumberOfNotificationsDelivered" "NumberOfNotificationsFailed")

for metric in "${metrics[@]}"; do
  echo "=== $metric ==="
  aws cloudwatch get-metric-statistics \
    --namespace AWS/SNS \
    --metric-name $metric \
    --dimensions Name=TopicName,Value=PushNotificationTopic \
    --start-time $(date -d '24 hours ago' -u +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 3600 \
    --statistics Sum,Average,Maximum
done
```

## 📊 Health Checks and Monitoring

### SNS Health Verification
```bash
# Test SNS functionality end-to-end
cat > sns-health-check.sh << 'EOF'
#!/bin/bash
TOPIC_ARN="arn:aws:sns:region:account:PushNotificationTopic"
TEST_MESSAGE='{"test": true, "timestamp": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}'

echo "Testing SNS topic: $TOPIC_ARN"

# Publish test message
MESSAGE_ID=$(aws sns publish \
  --topic-arn $TOPIC_ARN \
  --message "$TEST_MESSAGE" \
  --subject "Health Check" \
  --query 'MessageId' \
  --output text)

echo "Published message with ID: $MESSAGE_ID"

# Wait for delivery
sleep 5

# Check if message was processed by checking Lambda logs
aws logs filter-log-events \
  --log-group-name /aws/lambda/sendPushNotification \
  --start-time $(date -d '1 minute ago' +%s)000 \
  --filter-pattern "$MESSAGE_ID"

echo "SNS health check completed"
EOF

chmod +x sns-health-check.sh
```

### Automated Monitoring Script
```bash
cat > sns-monitor.sh << 'EOF'
#!/bin/bash
TOPIC_NAME="PushNotificationTopic"
ERROR_THRESHOLD=5
FAILURE_RATE_THRESHOLD=5  # Percentage

# Check failure rate in last 5 minutes
PUBLISHED=$(aws cloudwatch get-metric-statistics \
  --namespace AWS/SNS \
  --metric-name NumberOfMessagesPublished \
  --dimensions Name=TopicName,Value=$TOPIC_NAME \
  --start-time $(date -d '5 minutes ago' -u +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum \
  --query 'Datapoints[0].Sum' \
  --output text)

FAILED=$(aws cloudwatch get-metric-statistics \
  --namespace AWS/SNS \
  --metric-name NumberOfMessagesFailed \
  --dimensions Name=TopicName,Value=$TOPIC_NAME \
  --start-time $(date -d '5 minutes ago' -u +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum \
  --query 'Datapoints[0].Sum' \
  --output text)

if [[ "$PUBLISHED" != "None" && "$FAILED" != "None" && "$PUBLISHED" -gt 0 ]]; then
  FAILURE_RATE=$(echo "scale=2; ($FAILED / $PUBLISHED) * 100" | bc)
  if (( $(echo "$FAILURE_RATE > $FAILURE_RATE_THRESHOLD" | bc -l) )); then
    echo "ALERT: High SNS failure rate: $FAILURE_RATE% (threshold: $FAILURE_RATE_THRESHOLD%)"
    exit 1
  fi
fi

echo "SNS monitoring check passed"
EOF

chmod +x sns-monitor.sh
```

## 🛠️ Maintenance Procedures

### Regular Health Checks
```bash
# Weekly SNS topic maintenance
cat > weekly-sns-maintenance.sh << 'EOF'
#!/bin/bash
TOPIC_ARN="arn:aws:sns:region:account:PushNotificationTopic"

echo "=== Weekly SNS Maintenance ==="
echo "Topic: $TOPIC_ARN"
echo "Date: $(date)"

# Check topic attributes
echo "1. Checking topic configuration..."
aws sns get-topic-attributes --topic-arn $TOPIC_ARN

# List and verify subscriptions
echo "2. Verifying subscriptions..."
aws sns list-subscriptions-by-topic --topic-arn $TOPIC_ARN

# Check metrics for the past week
echo "3. Analyzing weekly metrics..."
aws cloudwatch get-metric-statistics \
  --namespace AWS/SNS \
  --metric-name NumberOfMessagesPublished \
  --dimensions Name=TopicName,Value=PushNotificationTopic \
  --start-time $(date -d '7 days ago' -u +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 86400 \
  --statistics Sum,Average

echo "Weekly maintenance completed"
EOF

chmod +x weekly-sns-maintenance.sh
```

### Cleanup Procedures
```bash
# Clean up old delivery status logs
aws logs delete-log-group --log-group-name "sns/region/account/PushNotificationTopic/lambda" --retention-in-days 7
```

## 📝 Incident Response Checklist

### During SNS Incident
- [ ] Check AWS Service Health for SNS
- [ ] Verify topic existence and configuration
- [ ] Check subscription health
- [ ] Review recent permission changes
- [ ] Analyze failure patterns
- [ ] Test manual message publishing
- [ ] Check Dead Letter Queue (if configured)
- [ ] Verify Lambda function health
- [ ] Implement workaround if needed
- [ ] Document incident timeline

### Post-Incident Actions
- [ ] Analyze root cause
- [ ] Update monitoring and alerting
- [ ] Review and update topic policies
- [ ] Enhance error handling in applications
- [ ] Update this runbook
- [ ] Conduct team postmortem

## 🔗 Related Resources

- [Lambda Issues Runbook](lambda-issues.md)
- [Firebase Issues Runbook](firebase-issues.md)
- [API Gateway Issues Runbook](api-gateway-issues.md)
- [AWS SNS Developer Guide](https://docs.aws.amazon.com/sns/latest/dg/)
- [SNS Best Practices](https://docs.aws.amazon.com/sns/latest/dg/sns-best-practices.html)

## 📞 Escalation Contacts

- **Development Team Lead**: [Contact Information]
- **Platform Engineering**: [Contact Information]  
- **AWS Support**: [Support Case Portal](https://console.aws.amazon.com/support/)

---

> **Last Updated**: $(date)  
> **Next Review**: Add to calendar for monthly review