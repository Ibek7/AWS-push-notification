# Common Issues and Solutions

This document contains frequently encountered problems and their proven solutions for the AWS Push Notifications system.

## 📱 Firebase FCM Issues

### Issue: Notifications not being delivered to Android devices
**Symptoms:**
- Lambda function executes successfully
- SNS publishes to topic
- No notifications appear on devices

**Possible Causes & Solutions:**

#### 1. Invalid FCM Token
```bash
# Check token validity
curl -X POST https://fcm.googleapis.com/fcm/send \
  -H "Authorization: key=YOUR_SERVER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "to": "DEVICE_TOKEN",
    "data": {
      "test": "token_validation"
    }
  }'
```

**Solution:** Refresh device tokens periodically in your Android app

#### 2. Incorrect Firebase Configuration
**Check:** Verify `google-services.json` is properly configured
```kotlin
// In your Android app, verify Firebase initialization
FirebaseApp.initializeApp(this)
Log.d("Firebase", "Firebase initialized: ${FirebaseApp.getInstance()}")
```

### Issue: FCM authentication failures
**Error:** `401 Unauthorized` from FCM API

**Solution:**
1. Verify Server Key in AWS Parameter Store:
```bash
aws ssm get-parameter --name "/pushnotifications/firebase/server-key" --with-decryption
```

2. Update Lambda environment variables:
```bash
aws lambda update-function-configuration \
  --function-name sendPushNotification \
  --environment Variables='{FIREBASE_SERVER_KEY=new_key_value}'
```

## 🔧 AWS Lambda Issues

### Issue: Lambda function timeout
**Error:** `Task timed out after 30.00 seconds`

**Immediate Fix:**
```bash
# Increase timeout to 60 seconds
aws lambda update-function-configuration \
  --function-name sendPushNotification \
  --timeout 60
```

**Long-term Solutions:**
1. Optimize code performance
2. Implement proper error handling
3. Use async operations where possible

### Issue: Lambda cold start latency
**Symptoms:** First invocation takes >5 seconds

**Solutions:**
1. **Provisioned Concurrency** (for production):
```bash
aws lambda put-provisioned-concurrency-config \
  --function-name sendPushNotification \
  --qualifier $LATEST \
  --provisioned-concurrency-config ProvisionedConcurrencyConfigs=2
```

2. **Keep functions warm** with scheduled invocations:
```yaml
# CloudWatch Event Rule
WarmUpRule:
  Type: AWS::Events::Rule
  Properties:
    ScheduleExpression: "rate(5 minutes)"
    Targets:
      - Arn: !GetAtt YourLambdaFunction.Arn
        Id: "WarmUpTarget"
        Input: '{"source": "warmup"}'
```

### Issue: Lambda out of memory
**Error:** `Runtime.ExitError: RequestId: xxx Task timed out after xxx seconds`

**Solution:**
```bash
# Increase memory allocation
aws lambda update-function-configuration \
  --function-name sendPushNotification \
  --memory-size 512
```

## 📡 SNS Issues

### Issue: SNS topic subscription failures
**Error:** Messages published but not received

**Diagnostic Steps:**
```bash
# Check topic attributes
aws sns get-topic-attributes --topic-arn arn:aws:sns:region:account:topic-name

# List subscriptions
aws sns list-subscriptions-by-topic --topic-arn arn:aws:sns:region:account:topic-name

# Check delivery status
aws sns get-subscription-attributes --subscription-arn subscription-arn
```

**Common Solutions:**
1. **Invalid endpoint**: Verify Lambda function ARN is correct
2. **Permission issues**: Ensure SNS has permission to invoke Lambda
3. **Dead letter queue**: Check if messages are going to DLQ

### Issue: SNS message delivery failures
**Symptoms:** High number of failed deliveries in CloudWatch

**Investigation:**
```bash
# Check CloudWatch metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/SNS \
  --metric-name NumberOfMessagesFailed \
  --dimensions Name=TopicName,Value=PushNotificationTopic \
  --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

## 🔐 Authentication & Authorization Issues

### Issue: API Gateway 403 Forbidden errors
**Symptoms:** Valid requests being rejected

**Diagnostic Steps:**
1. **Check API Key** (if using API key authentication):
```bash
# Verify API key is active
aws apigateway get-api-key --api-key YOUR_API_KEY_ID --include-value
```

2. **Verify IAM permissions** (if using IAM authentication):
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "execute-api:Invoke"
      ],
      "Resource": "arn:aws:execute-api:region:account:api-id/stage/method/resource"
    }
  ]
}
```

### Issue: CORS errors in web applications
**Error:** `Access to fetch at 'API_URL' from origin 'ORIGIN' has been blocked by CORS policy`

**Solution:** Update API Gateway CORS configuration:
```bash
aws apigateway update-method \
  --rest-api-id YOUR_API_ID \
  --resource-id YOUR_RESOURCE_ID \
  --http-method OPTIONS \
  --patch-ops op=replace,path=/methodResponses/200/responseParameters/method.response.header.Access-Control-Allow-Origin,value="'*'"
```

## 📊 Performance Issues

### Issue: High API response times
**Symptoms:** Response times >3 seconds consistently

**Investigation Checklist:**
1. **Lambda cold starts**: Check X-Ray traces for initialization time
2. **Database connections**: Verify connection pooling
3. **External API calls**: Check Firebase API response times
4. **Memory allocation**: Monitor Lambda memory utilization

**Optimization Strategies:**
```javascript
// Optimize Lambda function
const AWS = require('aws-sdk');

// Reuse connections outside handler
const sns = new AWS.SNS({ region: process.env.AWS_REGION });

exports.handler = async (event) => {
  // Use connection pooling
  // Implement caching where appropriate
  // Use async/await properly
};
```

### Issue: High error rates during peak traffic
**Symptoms:** Error rate spikes during high-volume periods

**Solutions:**
1. **Implement exponential backoff**:
```javascript
const retry = async (fn, retries = 3, delay = 1000) => {
  try {
    return await fn();
  } catch (error) {
    if (retries > 0) {
      await new Promise(resolve => setTimeout(resolve, delay));
      return retry(fn, retries - 1, delay * 2);
    }
    throw error;
  }
};
```

2. **Configure reserved concurrency**:
```bash
aws lambda put-reserved-concurrency-config \
  --function-name sendPushNotification \
  --reserved-concurrency-config ReservedConcurrencyConfig=100
```

## 🔍 Monitoring & Alerting Issues

### Issue: Missing or delayed CloudWatch logs
**Symptoms:** Logs not appearing in CloudWatch Logs

**Solutions:**
1. **Check Lambda execution role**:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:*"
    }
  ]
}
```

2. **Verify log group exists**:
```bash
aws logs describe-log-groups --log-group-name-prefix /aws/lambda/sendPushNotification
```

### Issue: CloudWatch alarms not triggering
**Symptoms:** Issues occurring but no alerts received

**Diagnostic Steps:**
```bash
# Check alarm state
aws cloudwatch describe-alarms --alarm-names YourAlarmName

# Test alarm manually
aws cloudwatch set-alarm-state \
  --alarm-name YourAlarmName \
  --state-value ALARM \
  --state-reason "Manual test"
```

## 🐛 Common Error Messages and Solutions

### Error: "Module not found"
```
Error: Cannot find module 'firebase-admin'
```
**Solution:** Ensure all dependencies are included in deployment package
```bash
cd lambda-function
npm install --production
zip -r ../function.zip .
```

### Error: "Invalid JSON in request body"
```
SyntaxError: Unexpected token } in JSON at position 123
```
**Solution:** Validate JSON payload format
```javascript
// Add proper error handling
try {
  const body = JSON.parse(event.body);
} catch (error) {
  return {
    statusCode: 400,
    body: JSON.stringify({ error: 'Invalid JSON format' })
  };
}
```

### Error: "Rate limit exceeded"
```
Error: FCM rate limit exceeded
```
**Solution:** Implement exponential backoff and batch processing
```javascript
// Batch notifications
const batchSize = 500;
const batches = [];
for (let i = 0; i < tokens.length; i += batchSize) {
  batches.push(tokens.slice(i, i + batchSize));
}
```

## 🔧 Quick Fixes and Workarounds

### Restart Lambda function (force new container)
```bash
# Update function configuration to force restart
aws lambda update-function-configuration \
  --function-name sendPushNotification \
  --description "Restart: $(date)"
```

### Clear Lambda logs when full
```bash
# Delete log streams older than 7 days
aws logs describe-log-streams \
  --log-group-name /aws/lambda/sendPushNotification \
  --query 'logStreams[?creationTime<`'$(date -d '7 days ago' +%s)'000`].logStreamName' \
  --output text | xargs -I {} aws logs delete-log-stream \
  --log-group-name /aws/lambda/sendPushNotification \
  --log-stream-name {}
```

### Force SNS topic recreation
```bash
# Delete and recreate topic (CAUTION: Will lose all subscriptions)
aws sns delete-topic --topic-arn arn:aws:sns:region:account:topic-name
aws sns create-topic --name PushNotificationTopic
```

## 📚 Additional Resources

- [AWS Lambda Troubleshooting Guide](https://docs.aws.amazon.com/lambda/latest/dg/troubleshooting.html)
- [Firebase FCM Troubleshooting](https://firebase.google.com/docs/cloud-messaging/troubleshooting)
- [SNS Troubleshooting Guide](https://docs.aws.amazon.com/sns/latest/dg/sns-troubleshooting.html)
- [API Gateway Troubleshooting](https://docs.aws.amazon.com/apigateway/latest/developerguide/api-gateway-troubleshooting.html)

---

> **Note:** This document is a living document. Please update it when you encounter and resolve new issues.