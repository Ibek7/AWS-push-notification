# Lambda Function Troubleshooting Runbook

## 🎯 Purpose
This runbook provides step-by-step procedures for diagnosing and resolving AWS Lambda function issues in the Push Notifications system.

## 🚨 Emergency Response

### 🔥 CRITICAL: Lambda Function Not Responding
**Impact:** Complete service outage
**SLA:** Resolve within 15 minutes

#### Immediate Actions (0-5 minutes)
1. **Check Function Status**
   ```bash
   aws lambda get-function --function-name sendPushNotification
   ```

2. **Verify Function Exists and Configuration**
   ```bash
   aws lambda list-functions --query 'Functions[?FunctionName==`sendPushNotification`]'
   ```

3. **Check Recent Invocations**
   ```bash
   aws logs filter-log-events \
     --log-group-name /aws/lambda/sendPushNotification \
     --start-time $(date -d '15 minutes ago' +%s)000 \
     --filter-pattern "ERROR"
   ```

#### Escalation (5-15 minutes)
If function is completely unresponsive:
1. **Attempt Manual Invocation**
   ```bash
   aws lambda invoke \
     --function-name sendPushNotification \
     --payload '{"test": true}' \
     response.json
   ```

2. **Check AWS Service Health**
   - Visit [AWS Service Health Dashboard](https://status.aws.amazon.com/)
   - Check for Lambda service issues in your region

3. **Contact AWS Support** (if service issue confirmed)

## 🔧 Standard Troubleshooting Procedures

### 1. Function Timeout Issues

#### Symptoms
- Error: `Task timed out after X.XX seconds`
- Intermittent failures during high load
- CloudWatch shows duration approaching timeout limit

#### Diagnosis Steps
```bash
# Check current timeout configuration
aws lambda get-function-configuration \
  --function-name sendPushNotification \
  --query 'Timeout'

# Analyze execution duration patterns
aws logs filter-log-events \
  --log-group-name /aws/lambda/sendPushNotification \
  --start-time $(date -d '1 hour ago' +%s)000 \
  --filter-pattern "[timestamp, requestId, \"REPORT\"]"
```

#### Resolution Actions
1. **Immediate Fix (Increase Timeout)**
   ```bash
   aws lambda update-function-configuration \
     --function-name sendPushNotification \
     --timeout 60
   ```

2. **Long-term Optimization**
   - Review code for blocking operations
   - Implement connection pooling
   - Optimize external API calls
   - Consider async processing patterns

### 2. Memory Issues

#### Symptoms
- Function crashes with no error logs
- Memory utilization consistently >90%
- Performance degradation over time

#### Diagnosis
```bash
# Check memory configuration
aws lambda get-function-configuration \
  --function-name sendPushNotification \
  --query 'MemorySize'

# Analyze memory usage from CloudWatch
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name MemoryUtilization \
  --dimensions Name=FunctionName,Value=sendPushNotification \
  --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Maximum,Average
```

#### Resolution
```bash
# Increase memory allocation
aws lambda update-function-configuration \
  --function-name sendPushNotification \
  --memory-size 512

# Monitor after change
watch 'aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name MemoryUtilization \
  --dimensions Name=FunctionName,Value=sendPushNotification \
  --start-time $(date -d "5 minutes ago" -u +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Maximum | jq ".Datapoints[-1].Maximum"'
```

### 3. Cold Start Performance Issues

#### Symptoms
- First invocation takes >5 seconds
- Intermittent slow responses
- Higher P99 latency

#### Diagnosis
```bash
# Check for cold start patterns in X-Ray
aws xray get-trace-summaries \
  --time-range-type TimeRangeByStartTime \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --filter-expression "duration >= 5"
```

#### Resolution Options

**Option 1: Provisioned Concurrency (Production)**
```bash
# Enable provisioned concurrency
aws lambda put-provisioned-concurrency-config \
  --function-name sendPushNotification \
  --qualifier $LATEST \
  --provisioned-concurrency-configs ProvisionedConcurrencyConfigs=2

# Monitor provisioned concurrency utilization
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name ProvisionedConcurrencyUtilization \
  --dimensions Name=FunctionName,Value=sendPushNotification \
  --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average
```

**Option 2: Warming Strategy (Development/Testing)**
```bash
# Create CloudWatch rule for warming
aws events put-rule \
  --name "lambda-warmer-sendPushNotification" \
  --schedule-expression "rate(5 minutes)" \
  --description "Keep Lambda function warm"

# Add target
aws events put-targets \
  --rule "lambda-warmer-sendPushNotification" \
  --targets "Id"="1","Arn"="arn:aws:lambda:region:account:function:sendPushNotification","Input"='{"source":"warmer"}'
```

### 4. Permission and IAM Issues

#### Symptoms
- AccessDenied errors
- Unable to access AWS services
- Missing log entries

#### Diagnosis
```bash
# Check function execution role
aws lambda get-function \
  --function-name sendPushNotification \
  --query 'Configuration.Role'

# Get role details
ROLE_NAME=$(aws lambda get-function --function-name sendPushNotification --query 'Configuration.Role' --output text | cut -d'/' -f2)
aws iam get-role --role-name $ROLE_NAME

# List attached policies
aws iam list-attached-role-policies --role-name $ROLE_NAME
aws iam list-role-policies --role-name $ROLE_NAME
```

#### Resolution
```bash
# Attach required policies (example for CloudWatch Logs)
aws iam attach-role-policy \
  --role-name $ROLE_NAME \
  --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole

# For custom permissions, create inline policy
aws iam put-role-policy \
  --role-name $ROLE_NAME \
  --policy-name CustomPermissions \
  --policy-document file://custom-policy.json
```

### 5. Environment Variable Issues

#### Symptoms
- Configuration-related errors
- Connection failures to external services
- Inconsistent behavior across environments

#### Diagnosis
```bash
# Check current environment variables
aws lambda get-function-configuration \
  --function-name sendPushNotification \
  --query 'Environment.Variables'

# Compare with expected configuration
cat > expected-env.json << EOF
{
  "FIREBASE_SERVER_KEY": "expected_value",
  "SNS_TOPIC_ARN": "arn:aws:sns:region:account:topic",
  "NODE_ENV": "production"
}
EOF
```

#### Resolution
```bash
# Update environment variables
aws lambda update-function-configuration \
  --function-name sendPushNotification \
  --environment Variables='{
    "FIREBASE_SERVER_KEY": "new_value",
    "SNS_TOPIC_ARN": "arn:aws:sns:region:account:topic",
    "NODE_ENV": "production"
  }'

# Verify update
aws lambda get-function-configuration \
  --function-name sendPushNotification \
  --query 'Environment.Variables'
```

## 🔍 Advanced Diagnostics

### X-Ray Trace Analysis
```bash
# Get recent traces with errors
aws xray get-trace-summaries \
  --time-range-type TimeRangeByStartTime \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --filter-expression "error = true OR fault = true"

# Get detailed trace information
TRACE_ID="1-5f4c9f4a-abcd1234"
aws xray batch-get-traces --trace-ids $TRACE_ID
```

### CloudWatch Insights Queries
```bash
# Query for error patterns
aws logs start-query \
  --log-group-name /aws/lambda/sendPushNotification \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --query-string 'fields @timestamp, @message | filter @message like /ERROR/ | sort @timestamp desc | limit 20'
```

### Performance Analysis
```bash
# Get function metrics
for metric in Duration Errors Throttles ConcurrentExecutions; do
  echo "=== $metric ==="
  aws cloudwatch get-metric-statistics \
    --namespace AWS/Lambda \
    --metric-name $metric \
    --dimensions Name=FunctionName,Value=sendPushNotification \
    --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%S) \
    --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
    --period 300 \
    --statistics Sum,Average,Maximum
done
```

## 📊 Health Checks and Monitoring

### Function Health Verification
```bash
# Test function with sample payload
cat > test-payload.json << EOF
{
  "message": "Test notification",
  "tokens": ["test_token"],
  "source": "health_check"
}
EOF

aws lambda invoke \
  --function-name sendPushNotification \
  --payload file://test-payload.json \
  --cli-binary-format raw-in-base64-out \
  output.json

# Check response
cat output.json
```

### Automated Health Monitoring
```bash
# Create health check script
cat > lambda-health-check.sh << 'EOF'
#!/bin/bash
FUNCTION_NAME="sendPushNotification"
THRESHOLD_ERRORS=5
THRESHOLD_DURATION=5000

# Check error rate in last 5 minutes
ERRORS=$(aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Errors \
  --dimensions Name=FunctionName,Value=$FUNCTION_NAME \
  --start-time $(date -d '5 minutes ago' -u +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum \
  --query 'Datapoints[0].Sum' \
  --output text)

if [[ "$ERRORS" != "None" && "$ERRORS" -gt "$THRESHOLD_ERRORS" ]]; then
  echo "ALERT: High error rate detected: $ERRORS errors in last 5 minutes"
  exit 1
fi

echo "Lambda function health check passed"
EOF

chmod +x lambda-health-check.sh
```

## 📝 Incident Response Checklist

### During Incident
- [ ] Acknowledge alert and start timer
- [ ] Check AWS Service Health Dashboard
- [ ] Verify function configuration
- [ ] Check recent deployments
- [ ] Review error logs and patterns
- [ ] Identify root cause
- [ ] Implement fix or workaround
- [ ] Verify resolution
- [ ] Document incident and timeline

### Post-Incident
- [ ] Conduct root cause analysis
- [ ] Update monitoring and alerting
- [ ] Review and update this runbook
- [ ] Share learnings with team
- [ ] Implement preventive measures

## 🔗 Related Resources

- [SNS Issues Runbook](sns-issues.md)
- [Firebase Issues Runbook](firebase-issues.md)
- [Performance Issues Runbook](performance-issues.md)
- [AWS Lambda Developer Guide](https://docs.aws.amazon.com/lambda/latest/dg/)
- [Lambda Monitoring Best Practices](https://docs.aws.amazon.com/lambda/latest/dg/lambda-monitoring.html)

## 📞 Escalation Contacts

- **Development Team Lead**: [Contact Information]
- **Platform Engineering**: [Contact Information]
- **AWS Support**: [Support Case Portal](https://console.aws.amazon.com/support/)

---

> **Last Updated**: $(date)  
> **Next Review**: Add to calendar for monthly review