# Firebase FCM Issues Troubleshooting Runbook

## 🎯 Purpose
This runbook provides procedures for diagnosing and resolving Firebase Cloud Messaging (FCM) integration issues in the Push Notifications system.

## 🚨 Emergency Response

### 🔥 CRITICAL: FCM Not Delivering Notifications
**Impact:** No notifications reaching mobile devices
**SLA:** Resolve within 20 minutes

#### Immediate Actions (0-5 minutes)
1. **Test FCM API Directly**
   ```bash
   curl -X POST https://fcm.googleapis.com/fcm/send \
     -H "Authorization: key=$(aws ssm get-parameter --name /pushnotifications/firebase/server-key --with-decryption --query 'Parameter.Value' --output text)" \
     -H "Content-Type: application/json" \
     -d '{
       "to": "test_device_token",
       "notification": {
         "title": "Emergency Test",
         "body": "FCM connectivity test"
       }
     }'
   ```

2. **Check Firebase Console Status**
   - Visit [Firebase Status Page](https://status.firebase.google.com/)
   - Check for service disruptions

3. **Verify Server Key**
   ```bash
   # Check if server key is accessible
   aws ssm get-parameter --name /pushnotifications/firebase/server-key --with-decryption
   ```

#### Escalation (5-20 minutes)
If FCM API is unresponsive:
1. Check Firebase project configuration
2. Verify device token validity
3. Contact Firebase Support if service issue

## 🔧 Standard Troubleshooting Procedures

### 1. Authentication and Authorization Issues

#### Symptoms
- 401 Unauthorized errors from FCM API
- Invalid server key messages
- Authentication failures in logs

#### Diagnosis Steps
```bash
# Verify server key is correct and not expired
SERVER_KEY=$(aws ssm get-parameter --name /pushnotifications/firebase/server-key --with-decryption --query 'Parameter.Value' --output text)

# Test server key validity
curl -X POST https://fcm.googleapis.com/fcm/send \
  -H "Authorization: key=$SERVER_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "to": "test",
    "data": {
      "test": "auth_validation"
    }
  }'

# Check Lambda environment variables
aws lambda get-function-configuration \
  --function-name sendPushNotification \
  --query 'Environment.Variables.FIREBASE_SERVER_KEY'
```

#### Resolution Actions

**1. Update Server Key**
```bash
# Get new server key from Firebase Console
# Update in Parameter Store
aws ssm put-parameter \
  --name /pushnotifications/firebase/server-key \
  --value "NEW_SERVER_KEY" \
  --type SecureString \
  --overwrite

# Update Lambda environment variables
aws lambda update-function-configuration \
  --function-name sendPushNotification \
  --environment Variables='{
    "FIREBASE_SERVER_KEY": "NEW_SERVER_KEY"
  }'
```

**2. Migrate to FCM v1 API (Recommended)**
```javascript
// Update Lambda function to use FCM v1 API with service account
const { google } = require('googleapis');

const getAccessToken = async () => {
  const jwtClient = new google.auth.JWT(
    serviceAccount.client_email,
    null,
    serviceAccount.private_key,
    ['https://www.googleapis.com/auth/firebase.messaging'],
    null
  );
  
  const tokens = await jwtClient.authorize();
  return tokens.access_token;
};

const sendNotificationV1 = async (message) => {
  const accessToken = await getAccessToken();
  
  const response = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${accessToken}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ message })
  });
  
  return response.json();
};
```

### 2. Device Token Issues

#### Symptoms
- Notifications not reaching specific devices
- InvalidRegistration errors
- NotRegistered errors in FCM response

#### Diagnosis Steps
```bash
# Test specific device tokens
cat > test-device-tokens.sh << 'EOF'
#!/bin/bash
TOKENS=("device_token_1" "device_token_2" "device_token_3")
SERVER_KEY=$(aws ssm get-parameter --name /pushnotifications/firebase/server-key --with-decryption --query 'Parameter.Value' --output text)

for token in "${TOKENS[@]}"; do
  echo "Testing token: ${token:0:20}..."
  response=$(curl -s -X POST https://fcm.googleapis.com/fcm/send \
    -H "Authorization: key=$SERVER_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"to\": \"$token\",
      \"notification\": {
        \"title\": \"Token Test\",
        \"body\": \"Testing token validity\"
      }
    }")
  
  echo "Response: $response"
  echo "---"
done
EOF

chmod +x test-device-tokens.sh
./test-device-tokens.sh
```

#### Resolution Actions

**1. Token Validation and Cleanup**
```javascript
// Add to Lambda function for token validation
const validateAndCleanTokens = async (tokens) => {
  const validTokens = [];
  const invalidTokens = [];
  
  for (const token of tokens) {
    try {
      const response = await sendToSingleToken(token, testMessage);
      
      if (response.failure === 0) {
        validTokens.push(token);
      } else {
        // Check error details
        const error = response.results[0].error;
        if (error === 'InvalidRegistration' || error === 'NotRegistered') {
          invalidTokens.push(token);
        }
      }
    } catch (error) {
      console.error(`Token validation failed for ${token}:`, error);
      invalidTokens.push(token);
    }
  }
  
  // Remove invalid tokens from database
  if (invalidTokens.length > 0) {
    await removeInvalidTokens(invalidTokens);
  }
  
  return validTokens;
};
```

**2. Implement Token Refresh Logic**
```kotlin
// Android app - implement token refresh
class MyFirebaseMessagingService : FirebaseMessagingService() {
    override fun onNewToken(token: String) {
        super.onNewToken(token)
        
        // Send token to server
        sendTokenToServer(token)
        
        // Store token locally
        getSharedPreferences("fcm", Context.MODE_PRIVATE)
            .edit()
            .putString("token", token)
            .apply()
    }
    
    private fun sendTokenToServer(token: String) {
        // API call to update token on server
        val request = TokenUpdateRequest(token)
        apiService.updateToken(request)
    }
}
```

### 3. Message Payload Issues

#### Symptoms
- Messages sent but not displayed
- Malformed notification content
- Data payload not processed correctly

#### Diagnosis Steps
```bash
# Test different payload formats
cat > test-payloads.sh << 'EOF'
#!/bin/bash
SERVER_KEY=$(aws ssm get-parameter --name /pushnotifications/firebase/server-key --with-decryption --query 'Parameter.Value' --output text)
TEST_TOKEN="your_test_device_token"

echo "=== Testing Notification Payload ==="
curl -X POST https://fcm.googleapis.com/fcm/send \
  -H "Authorization: key=$SERVER_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"to\": \"$TEST_TOKEN\",
    \"notification\": {
      \"title\": \"Test Title\",
      \"body\": \"Test Body\",
      \"icon\": \"ic_notification\",
      \"sound\": \"default\"
    }
  }"

echo -e "\n=== Testing Data Payload ==="
curl -X POST https://fcm.googleapis.com/fcm/send \
  -H "Authorization: key=$SERVER_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"to\": \"$TEST_TOKEN\",
    \"data\": {
      \"title\": \"Data Title\",
      \"body\": \"Data Body\",
      \"custom_key\": \"custom_value\"
    }
  }"

echo -e "\n=== Testing Combined Payload ==="
curl -X POST https://fcm.googleapis.com/fcm/send \
  -H "Authorization: key=$SERVER_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"to\": \"$TEST_TOKEN\",
    \"notification\": {
      \"title\": \"Combined Title\",
      \"body\": \"Combined Body\"
    },
    \"data\": {
      \"action\": \"open_screen\",
      \"screen_id\": \"123\"
    }
  }"
EOF

chmod +x test-payloads.sh
./test-payloads.sh
```

#### Resolution Actions

**1. Validate Payload Format**
```javascript
// Add payload validation to Lambda function
const validateFCMPayload = (payload) => {
  const errors = [];
  
  // Check required fields
  if (!payload.to && !payload.registration_ids) {
    errors.push('Missing recipient (to or registration_ids)');
  }
  
  // Validate notification object
  if (payload.notification) {
    if (!payload.notification.title && !payload.notification.body) {
      errors.push('Notification must have title or body');
    }
    
    // Check for invalid characters
    if (payload.notification.title && payload.notification.title.length > 100) {
      errors.push('Notification title too long (max 100 characters)');
    }
  }
  
  // Validate data payload
  if (payload.data) {
    for (const [key, value] of Object.entries(payload.data)) {
      if (typeof value !== 'string') {
        errors.push(`Data value for key '${key}' must be string`);
      }
    }
  }
  
  return errors;
};
```

**2. Handle Different Message Types**
```kotlin
// Android app - handle different payload types
override fun onMessageReceived(remoteMessage: RemoteMessage) {
    super.onMessageReceived(remoteMessage)
    
    // Handle notification payload
    remoteMessage.notification?.let { notification ->
        showNotification(
            title = notification.title ?: "Default Title",
            body = notification.body ?: "Default Body",
            icon = notification.icon
        )
    }
    
    // Handle data payload
    if (remoteMessage.data.isNotEmpty()) {
        processDataPayload(remoteMessage.data)
    }
    
    // Handle both notification and data
    if (remoteMessage.notification != null && remoteMessage.data.isNotEmpty()) {
        // Show notification and process data
        showNotificationWithAction(remoteMessage.notification!!, remoteMessage.data)
    }
}
```

### 4. Rate Limiting and Quota Issues

#### Symptoms
- 429 Too Many Requests errors
- Quota exceeded messages
- Delivery delays during high volume

#### Diagnosis Steps
```bash
# Check FCM quota usage (via Firebase Console)
# Monitor request patterns
aws logs filter-log-events \
  --log-group-name /aws/lambda/sendPushNotification \
  --start-time $(date -d '1 hour ago' +%s)000 \
  --filter-pattern "429"

# Analyze request volume
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=sendPushNotification \
  --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum,Maximum
```

#### Resolution Actions

**1. Implement Rate Limiting**
```javascript
// Add rate limiting to Lambda function
const rateLimit = new Map();

const checkRateLimit = (clientId, maxRequests = 100, windowMs = 60000) => {
  const now = Date.now();
  const client = rateLimit.get(clientId) || { count: 0, resetTime: now + windowMs };
  
  if (now > client.resetTime) {
    client.count = 0;
    client.resetTime = now + windowMs;
  }
  
  if (client.count >= maxRequests) {
    throw new Error('Rate limit exceeded');
  }
  
  client.count++;
  rateLimit.set(clientId, client);
  
  return true;
};
```

**2. Implement Batch Processing**
```javascript
// Batch notifications for efficiency
const sendNotificationsBatch = async (tokens, message, batchSize = 500) => {
  const batches = [];
  
  for (let i = 0; i < tokens.length; i += batchSize) {
    batches.push(tokens.slice(i, i + batchSize));
  }
  
  const results = [];
  
  for (const batch of batches) {
    try {
      const response = await fcm.sendMulticast({
        tokens: batch,
        notification: message.notification,
        data: message.data
      });
      
      results.push(response);
      
      // Add delay between batches to respect rate limits
      await new Promise(resolve => setTimeout(resolve, 100));
      
    } catch (error) {
      console.error('Batch send failed:', error);
      results.push({ success: 0, failure: batch.length, error });
    }
  }
  
  return results;
};
```

### 5. Network and Connectivity Issues

#### Symptoms
- Connection timeouts to FCM API
- Intermittent delivery failures
- Regional connectivity issues

#### Diagnosis Steps
```bash
# Test FCM API connectivity from different locations
cat > test-fcm-connectivity.sh << 'EOF'
#!/bin/bash
FCM_ENDPOINTS=(
  "https://fcm.googleapis.com"
  "https://android.googleapis.com"
  "https://firebase.googleapis.com"
)

for endpoint in "${FCM_ENDPOINTS[@]}"; do
  echo "Testing connectivity to $endpoint"
  
  # Test DNS resolution
  nslookup $(echo $endpoint | sed 's|https://||')
  
  # Test HTTP connectivity
  curl -I -m 10 $endpoint/health 2>&1 | head -n 1
  
  # Test with specific timeout
  time curl -m 5 -s $endpoint > /dev/null
  
  echo "---"
done
EOF

chmod +x test-fcm-connectivity.sh
./test-fcm-connectivity.sh
```

#### Resolution Actions

**1. Configure Timeouts and Retries**
```javascript
// Configure HTTP client with proper timeouts
const axios = require('axios');

const fcmClient = axios.create({
  baseURL: 'https://fcm.googleapis.com',
  timeout: 10000, // 10 seconds
  retry: 3,
  retryDelay: (retryCount) => {
    return Math.pow(2, retryCount) * 1000; // Exponential backoff
  }
});

// Add retry interceptor
fcmClient.interceptors.response.use(
  (response) => response,
  async (error) => {
    const config = error.config;
    
    if (!config || !config.retry) return Promise.reject(error);
    
    config.retryCount = config.retryCount || 0;
    
    if (config.retryCount >= config.retry) {
      return Promise.reject(error);
    }
    
    config.retryCount++;
    
    const delay = config.retryDelay ? config.retryDelay(config.retryCount) : 1000;
    await new Promise(resolve => setTimeout(resolve, delay));
    
    return fcmClient(config);
  }
);
```

**2. Implement Circuit Breaker Pattern**
```javascript
class CircuitBreaker {
  constructor(threshold = 5, timeout = 60000) {
    this.threshold = threshold;
    this.timeout = timeout;
    this.failureCount = 0;
    this.lastFailureTime = null;
    this.state = 'CLOSED'; // CLOSED, OPEN, HALF_OPEN
  }
  
  async call(operation) {
    if (this.state === 'OPEN') {
      if (Date.now() - this.lastFailureTime > this.timeout) {
        this.state = 'HALF_OPEN';
      } else {
        throw new Error('Circuit breaker is OPEN');
      }
    }
    
    try {
      const result = await operation();
      this.onSuccess();
      return result;
    } catch (error) {
      this.onFailure();
      throw error;
    }
  }
  
  onSuccess() {
    this.failureCount = 0;
    this.state = 'CLOSED';
  }
  
  onFailure() {
    this.failureCount++;
    this.lastFailureTime = Date.now();
    
    if (this.failureCount >= this.threshold) {
      this.state = 'OPEN';
    }
  }
}
```

## 🔍 Advanced Diagnostics

### FCM Response Analysis
```bash
# Create comprehensive FCM response analyzer
cat > analyze-fcm-responses.sh << 'EOF'
#!/bin/bash
LOG_GROUP="/aws/lambda/sendPushNotification"
START_TIME=$(date -d '1 hour ago' +%s)000

echo "=== FCM Response Analysis ==="

# Extract FCM responses from logs
aws logs filter-log-events \
  --log-group-name $LOG_GROUP \
  --start-time $START_TIME \
  --filter-pattern "FCM Response" | \
  jq -r '.events[].message' > fcm_responses.log

# Count response types
echo "Response Summary:"
grep -o '"success":[0-9]*' fcm_responses.log | cut -d: -f2 | awk '{sum+=$1} END {print "Total Success: " sum}'
grep -o '"failure":[0-9]*' fcm_responses.log | cut -d: -f2 | awk '{sum+=$1} END {print "Total Failures: " sum}'

# Extract error patterns
echo -e "\nError Patterns:"
grep -o '"error":"[^"]*"' fcm_responses.log | sort | uniq -c | sort -nr

# Extract canonical IDs (token updates needed)
echo -e "\nCanonical ID Updates:"
grep -o '"canonical_id":"[^"]*"' fcm_responses.log | wc -l
EOF

chmod +x analyze-fcm-responses.sh
./analyze-fcm-responses.sh
```

### Performance Monitoring
```bash
# Monitor FCM API performance
cat > monitor-fcm-performance.sh << 'EOF'
#!/bin/bash
echo "=== FCM Performance Monitoring ==="

# Test FCM API response time
for i in {1..5}; do
  echo "Test $i:"
  time curl -s -X POST https://fcm.googleapis.com/fcm/send \
    -H "Authorization: key=$FIREBASE_SERVER_KEY" \
    -H "Content-Type: application/json" \
    -d '{"to":"test","data":{"test":"performance"}}' > /dev/null
done

# Check Lambda performance metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Duration \
  --dimensions Name=FunctionName,Value=sendPushNotification \
  --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average,Maximum
EOF

chmod +x monitor-fcm-performance.sh
```

## 📊 Health Checks and Monitoring

### FCM Health Verification
```bash
cat > fcm-health-check.sh << 'EOF'
#!/bin/bash
SERVER_KEY=$(aws ssm get-parameter --name /pushnotifications/firebase/server-key --with-decryption --query 'Parameter.Value' --output text)

if [ -z "$SERVER_KEY" ]; then
  echo "ERROR: Cannot retrieve Firebase server key"
  exit 1
fi

echo "Testing FCM API connectivity..."

# Test FCM API with dummy payload
response=$(curl -s -w "%{http_code}" -X POST https://fcm.googleapis.com/fcm/send \
  -H "Authorization: key=$SERVER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"to":"dummy_token","data":{"test":"health_check"}}')

http_code="${response: -3}"
response_body="${response%???}"

if [ "$http_code" == "200" ]; then
  echo "✅ FCM API is accessible"
  
  # Check for authentication errors in response
  if echo "$response_body" | grep -q '"error"'; then
    echo "⚠️  Authentication or payload issues detected"
    echo "Response: $response_body"
  else
    echo "✅ FCM authentication successful"
  fi
else
  echo "❌ FCM API error - HTTP $http_code"
  echo "Response: $response_body"
  exit 1
fi

echo "FCM health check completed"
EOF

chmod +x fcm-health-check.sh
```

### Automated FCM Monitoring
```bash
cat > fcm-monitor.sh << 'EOF'
#!/bin/bash
FAILURE_THRESHOLD=10  # Number of failures to trigger alert
TIME_WINDOW=300      # 5 minutes in seconds

# Check recent FCM failures in Lambda logs
failures=$(aws logs filter-log-events \
  --log-group-name /aws/lambda/sendPushNotification \
  --start-time $(date -d "5 minutes ago" +%s)000 \
  --filter-pattern "FCM.*error" | \
  jq '.events | length')

if [ "$failures" -gt "$FAILURE_THRESHOLD" ]; then
  echo "ALERT: High FCM failure rate detected: $failures failures in last 5 minutes"
  
  # Get error details
  aws logs filter-log-events \
    --log-group-name /aws/lambda/sendPushNotification \
    --start-time $(date -d "5 minutes ago" +%s)000 \
    --filter-pattern "FCM.*error" | \
    jq -r '.events[] | .message' | tail -5
  
  exit 1
fi

echo "FCM monitoring check passed"
EOF

chmod +x fcm-monitor.sh
```

## 📝 Incident Response Checklist

### During FCM Incident
- [ ] Check Firebase Status Page
- [ ] Verify server key and authentication
- [ ] Test FCM API directly
- [ ] Check device token validity
- [ ] Review recent code deployments
- [ ] Analyze error patterns in logs
- [ ] Check rate limiting and quotas
- [ ] Test with different message formats
- [ ] Verify network connectivity
- [ ] Document timeline and actions

### Post-Incident Actions
- [ ] Update monitoring thresholds
- [ ] Review and update payload validation
- [ ] Enhance error handling and retries
- [ ] Update device token management
- [ ] Review rate limiting strategies
- [ ] Update this runbook
- [ ] Conduct team review

## 🔗 Related Resources

- [Lambda Issues Runbook](lambda-issues.md)
- [SNS Issues Runbook](sns-issues.md)
- [Performance Issues Runbook](performance-issues.md)
- [Firebase Documentation](https://firebase.google.com/docs/cloud-messaging/)
- [FCM HTTP v1 API](https://firebase.google.com/docs/reference/fcm/rest/v1/projects.messages)

## 📞 Escalation Contacts

- **Development Team Lead**: [Contact Information]
- **Platform Engineering**: [Contact Information]
- **Firebase Support**: [Firebase Console Support](https://console.firebase.google.com/)

---

> **Last Updated**: $(date)  
> **Next Review**: Add to calendar for monthly review