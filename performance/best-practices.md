# Development and Operational Best Practices

## 🎯 Overview
This document outlines comprehensive best practices for developing, deploying, and operating the AWS Push Notifications system to ensure high performance, reliability, and maintainability.

## 🚀 Development Best Practices

### Code Quality and Structure

#### Function Design Principles
```javascript
// ✅ GOOD: Single responsibility principle
const validateNotificationPayload = (payload) => {
  if (!payload.message || !payload.tokens) {
    throw new Error('Missing required fields: message, tokens');
  }
  
  if (!Array.isArray(payload.tokens) || payload.tokens.length === 0) {
    throw new Error('Tokens must be a non-empty array');
  }
  
  if (payload.message.length > 500) {
    throw new Error('Message too long (max 500 characters)');
  }
  
  return true;
};

const sendNotifications = async (payload) => {
  validateNotificationPayload(payload);
  
  const validTokens = await validateTokens(payload.tokens);
  const result = await deliverNotifications(validTokens, payload.message);
  
  return result;
};

// ❌ BAD: Multiple responsibilities in one function
const processEverything = async (payload) => {
  // Validation, token processing, delivery, logging all mixed together
};
```

#### Error Handling Best Practices
```javascript
// ✅ GOOD: Comprehensive error handling with context
const sendPushNotification = async (event) => {
  const startTime = Date.now();
  let notificationCount = 0;
  
  try {
    // Input validation
    const payload = validateInput(event);
    notificationCount = payload.tokens.length;
    
    // Log operation start
    console.log('Starting notification send', {
      requestId: event.requestId,
      tokenCount: notificationCount,
      messageLength: payload.message.length
    });
    
    // Process notifications
    const result = await processNotifications(payload);
    
    // Log success metrics
    console.log('Notification send completed', {
      requestId: event.requestId,
      duration: Date.now() - startTime,
      successCount: result.successCount,
      failureCount: result.failureCount
    });
    
    return {
      statusCode: 200,
      body: JSON.stringify({
        success: true,
        processed: notificationCount,
        delivered: result.successCount,
        failed: result.failureCount
      })
    };
    
  } catch (error) {
    // Structured error logging
    console.error('Notification send failed', {
      requestId: event.requestId,
      duration: Date.now() - startTime,
      tokenCount: notificationCount,
      error: error.message,
      stack: error.stack
    });
    
    // Return appropriate error response
    const statusCode = error.name === 'ValidationError' ? 400 : 500;
    
    return {
      statusCode,
      body: JSON.stringify({
        success: false,
        error: error.message,
        requestId: event.requestId
      })
    };
  }
};
```

#### Async/Await Best Practices
```javascript
// ✅ GOOD: Proper async/await usage with concurrency
const processNotificationsBatch = async (notifications) => {
  const BATCH_SIZE = 10;
  const results = [];
  
  // Process in controlled batches for better performance
  for (let i = 0; i < notifications.length; i += BATCH_SIZE) {
    const batch = notifications.slice(i, i + BATCH_SIZE);
    
    // Process batch concurrently
    const batchPromises = batch.map(async (notification) => {
      try {
        return await sendSingleNotification(notification);
      } catch (error) {
        console.error('Single notification failed', {
          notificationId: notification.id,
          error: error.message
        });
        return { success: false, error: error.message };
      }
    });
    
    const batchResults = await Promise.allSettled(batchPromises);
    results.push(...batchResults);
    
    // Rate limiting - small delay between batches
    if (i + BATCH_SIZE < notifications.length) {
      await new Promise(resolve => setTimeout(resolve, 100));
    }
  }
  
  return results;
};

// ❌ BAD: Sequential processing
const processNotificationsSequential = async (notifications) => {
  const results = [];
  for (const notification of notifications) {
    const result = await sendSingleNotification(notification); // Blocking
    results.push(result);
  }
  return results;
};
```

### Configuration Management

#### Environment-Specific Configuration
```javascript
// config/environment.js
const environments = {
  development: {
    logLevel: 'debug',
    fcmTimeout: 30000,
    batchSize: 5,
    retryAttempts: 2,
    enableDetailedLogging: true
  },
  staging: {
    logLevel: 'info',
    fcmTimeout: 15000,
    batchSize: 50,
    retryAttempts: 3,
    enableDetailedLogging: true
  },
  production: {
    logLevel: 'warn',
    fcmTimeout: 10000,
    batchSize: 100,
    retryAttempts: 5,
    enableDetailedLogging: false
  }
};

const getConfig = () => {
  const env = process.env.NODE_ENV || 'development';
  return {
    ...environments[env],
    // Override with environment variables
    fcmTimeout: process.env.FCM_TIMEOUT || environments[env].fcmTimeout,
    batchSize: process.env.BATCH_SIZE || environments[env].batchSize
  };
};

module.exports = getConfig();
```

#### Secrets Management
```javascript
// ✅ GOOD: Secure secrets management
const AWS = require('aws-sdk');
const ssm = new AWS.SSM();

const getSecret = async (parameterName) => {
  try {
    const parameter = await ssm.getParameter({
      Name: parameterName,
      WithDecryption: true
    }).promise();
    
    return parameter.Parameter.Value;
  } catch (error) {
    console.error(`Failed to retrieve parameter ${parameterName}:`, error);
    throw new Error(`Configuration error: ${parameterName} not found`);
  }
};

// Cache secrets to avoid repeated API calls
const secretCache = new Map();
const SECRET_CACHE_TTL = 300000; // 5 minutes

const getCachedSecret = async (parameterName) => {
  const cached = secretCache.get(parameterName);
  
  if (cached && Date.now() - cached.timestamp < SECRET_CACHE_TTL) {
    return cached.value;
  }
  
  const value = await getSecret(parameterName);
  secretCache.set(parameterName, {
    value,
    timestamp: Date.now()
  });
  
  return value;
};

// ❌ BAD: Hardcoded secrets
const firebaseKey = "AIzaSyBxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"; // Never do this!
```

### Testing Best Practices

#### Unit Testing
```javascript
// tests/notification.test.js
const { validateNotificationPayload } = require('../src/validation');

describe('validateNotificationPayload', () => {
  test('should accept valid payload', () => {
    const validPayload = {
      message: 'Test message',
      tokens: ['token1', 'token2']
    };
    
    expect(() => validateNotificationPayload(validPayload)).not.toThrow();
  });
  
  test('should reject payload without message', () => {
    const invalidPayload = {
      tokens: ['token1', 'token2']
    };
    
    expect(() => validateNotificationPayload(invalidPayload))
      .toThrow('Missing required fields: message, tokens');
  });
  
  test('should reject payload with empty tokens array', () => {
    const invalidPayload = {
      message: 'Test message',
      tokens: []
    };
    
    expect(() => validateNotificationPayload(invalidPayload))
      .toThrow('Tokens must be a non-empty array');
  });
  
  test('should reject payload with message too long', () => {
    const invalidPayload = {
      message: 'x'.repeat(501),
      tokens: ['token1']
    };
    
    expect(() => validateNotificationPayload(invalidPayload))
      .toThrow('Message too long (max 500 characters)');
  });
});
```

#### Integration Testing
```javascript
// tests/integration/notification.integration.test.js
const AWS = require('aws-sdk-mock');
const { handler } = require('../../src/lambda');

describe('Notification Integration Tests', () => {
  beforeEach(() => {
    // Mock AWS services
    AWS.mock('SNS', 'publish', (params, callback) => {
      callback(null, { MessageId: 'mock-message-id' });
    });
  });
  
  afterEach(() => {
    AWS.restore();
  });
  
  test('should process notification end-to-end', async () => {
    const event = {
      body: JSON.stringify({
        message: 'Integration test message',
        tokens: ['test-token-1', 'test-token-2']
      })
    };
    
    const result = await handler(event);
    
    expect(result.statusCode).toBe(200);
    expect(JSON.parse(result.body).success).toBe(true);
  });
});
```

## 🛠️ Operational Best Practices

### Deployment Strategies

#### Blue-Green Deployment
```bash
#!/bin/bash
# Blue-Green deployment script

FUNCTION_NAME="sendPushNotification"
ALIAS_NAME="LIVE"

echo "Starting blue-green deployment for $FUNCTION_NAME"

# Deploy new version
NEW_VERSION=$(aws lambda publish-version \
  --function-name $FUNCTION_NAME \
  --description "Deployment $(date)" \
  --query 'Version' \
  --output text)

echo "Published new version: $NEW_VERSION"

# Test new version
echo "Testing new version..."
aws lambda invoke \
  --function-name $FUNCTION_NAME:$NEW_VERSION \
  --payload '{"test": true}' \
  --cli-binary-format raw-in-base64-out \
  /tmp/test-response.json

if [ $? -eq 0 ]; then
  echo "New version test passed"
  
  # Update alias to new version
  aws lambda update-alias \
    --function-name $FUNCTION_NAME \
    --name $ALIAS_NAME \
    --function-version $NEW_VERSION
  
  echo "Deployment completed successfully"
else
  echo "New version test failed - rolling back"
  exit 1
fi
```

#### Canary Deployment
```bash
# Canary deployment with gradual traffic shift
aws lambda update-alias \
  --function-name sendPushNotification \
  --name LIVE \
  --function-version $NEW_VERSION \
  --routing-config AdditionalVersionWeights="{\"$NEW_VERSION\": 0.1}"

# Monitor for 10 minutes
sleep 600

# Check error rates
ERROR_RATE=$(aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Errors \
  --dimensions Name=FunctionName,Value=sendPushNotification \
  --start-time $(date -d '10 minutes ago' -u +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 600 \
  --statistics Sum \
  --query 'Datapoints[0].Sum' \
  --output text)

if [ "$ERROR_RATE" == "None" ] || [ "$ERROR_RATE" -lt 5 ]; then
  echo "Canary looks good, proceeding with full deployment"
  
  # Shift 100% traffic to new version
  aws lambda update-alias \
    --function-name sendPushNotification \
    --name LIVE \
    --function-version $NEW_VERSION
else
  echo "Canary showing errors, rolling back"
  
  # Remove canary traffic
  aws lambda update-alias \
    --function-name sendPushNotification \
    --name LIVE \
    --function-version $PREVIOUS_VERSION
fi
```

### Monitoring and Alerting

#### CloudWatch Alarms Setup
```bash
# High error rate alarm
aws cloudwatch put-metric-alarm \
  --alarm-name "PushNotification-HighErrorRate" \
  --alarm-description "Alert when error rate exceeds 5%" \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 300 \
  --threshold 10 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=FunctionName,Value=sendPushNotification \
  --evaluation-periods 2 \
  --alarm-actions arn:aws:sns:region:account:alerts-topic

# High duration alarm
aws cloudwatch put-metric-alarm \
  --alarm-name "PushNotification-HighLatency" \
  --alarm-description "Alert when duration exceeds 10 seconds" \
  --metric-name Duration \
  --namespace AWS/Lambda \
  --statistic Average \
  --period 300 \
  --threshold 10000 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=FunctionName,Value=sendPushNotification \
  --evaluation-periods 2 \
  --alarm-actions arn:aws:sns:region:account:alerts-topic
```

#### Custom Dashboards
```javascript
// CloudWatch dashboard configuration
const dashboardBody = {
  widgets: [
    {
      type: "metric",
      properties: {
        metrics: [
          ["AWS/Lambda", "Invocations", "FunctionName", "sendPushNotification"],
          [".", "Errors", ".", "."],
          [".", "Duration", ".", "."],
          [".", "Throttles", ".", "."]
        ],
        period: 300,
        stat: "Sum",
        region: "us-east-1",
        title: "Lambda Metrics"
      }
    },
    {
      type: "metric",
      properties: {
        metrics: [
          ["AWS/SNS", "NumberOfMessagesPublished", "TopicName", "PushNotificationTopic"],
          [".", "NumberOfMessagesFailed", ".", "."]
        ],
        period: 300,
        stat: "Sum",
        region: "us-east-1",
        title: "SNS Metrics"
      }
    }
  ]
};

// Create dashboard
aws cloudwatch put-dashboard \
  --dashboard-name "PushNotifications" \
  --dashboard-body file://dashboard.json
```

### Security Best Practices

#### IAM Least Privilege
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
      "Resource": "arn:aws:logs:*:*:log-group:/aws/lambda/sendPushNotification:*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "sns:Publish"
      ],
      "Resource": "arn:aws:sns:*:*:PushNotificationTopic"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter"
      ],
      "Resource": "arn:aws:ssm:*:*:parameter/pushnotifications/*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "xray:PutTraceSegments",
        "xray:PutTelemetryRecords"
      ],
      "Resource": "*"
    }
  ]
}
```

#### Input Validation and Sanitization
```javascript
// Comprehensive input validation
const validateAndSanitizeInput = (event) => {
  // Check content type
  const contentType = event.headers['content-type'] || event.headers['Content-Type'];
  if (!contentType || !contentType.includes('application/json')) {
    throw new ValidationError('Content-Type must be application/json');
  }
  
  // Parse and validate JSON
  let body;
  try {
    body = JSON.parse(event.body);
  } catch (error) {
    throw new ValidationError('Invalid JSON format');
  }
  
  // Validate required fields
  const requiredFields = ['message', 'tokens'];
  for (const field of requiredFields) {
    if (!body[field]) {
      throw new ValidationError(`Missing required field: ${field}`);
    }
  }
  
  // Sanitize message content
  if (typeof body.message !== 'string') {
    throw new ValidationError('Message must be a string');
  }
  
  // Remove potentially harmful content
  body.message = body.message
    .replace(/[<>]/g, '') // Remove HTML tags
    .substring(0, 500); // Limit length
  
  // Validate tokens array
  if (!Array.isArray(body.tokens)) {
    throw new ValidationError('Tokens must be an array');
  }
  
  if (body.tokens.length === 0) {
    throw new ValidationError('Tokens array cannot be empty');
  }
  
  if (body.tokens.length > 1000) {
    throw new ValidationError('Too many tokens (max 1000)');
  }
  
  // Validate token format
  body.tokens = body.tokens.filter(token => {
    if (typeof token !== 'string') return false;
    if (token.length < 10 || token.length > 4096) return false;
    if (!/^[a-zA-Z0-9_-]+$/.test(token)) return false;
    return true;
  });
  
  if (body.tokens.length === 0) {
    throw new ValidationError('No valid tokens found');
  }
  
  return body;
};

class ValidationError extends Error {
  constructor(message) {
    super(message);
    this.name = 'ValidationError';
  }
}
```

### Performance Monitoring

#### Application Performance Monitoring (APM)
```javascript
// Custom performance metrics
const performanceMonitor = {
  startTime: null,
  metrics: {},
  
  start(operation) {
    this.startTime = Date.now();
    this.metrics[operation] = {
      start: this.startTime
    };
  },
  
  end(operation) {
    if (this.metrics[operation]) {
      this.metrics[operation].duration = Date.now() - this.metrics[operation].start;
      this.metrics[operation].end = Date.now();
    }
  },
  
  async recordMetrics() {
    const cloudwatch = new AWS.CloudWatch();
    
    const metricData = Object.entries(this.metrics).map(([operation, data]) => ({
      MetricName: `${operation}Duration`,
      Value: data.duration,
      Unit: 'Milliseconds',
      Dimensions: [
        {
          Name: 'Operation',
          Value: operation
        }
      ]
    }));
    
    if (metricData.length > 0) {
      await cloudwatch.putMetricData({
        Namespace: 'PushNotifications/Performance',
        MetricData: metricData
      }).promise();
    }
  }
};

// Usage in Lambda function
exports.handler = async (event) => {
  performanceMonitor.start('total');
  
  try {
    performanceMonitor.start('validation');
    const payload = validateAndSanitizeInput(event);
    performanceMonitor.end('validation');
    
    performanceMonitor.start('tokenValidation');
    const validTokens = await validateTokens(payload.tokens);
    performanceMonitor.end('tokenValidation');
    
    performanceMonitor.start('notificationSend');
    const result = await sendNotifications(validTokens, payload.message);
    performanceMonitor.end('notificationSend');
    
    performanceMonitor.end('total');
    
    // Record metrics asynchronously
    performanceMonitor.recordMetrics().catch(console.error);
    
    return {
      statusCode: 200,
      body: JSON.stringify(result)
    };
    
  } catch (error) {
    performanceMonitor.end('total');
    performanceMonitor.recordMetrics().catch(console.error);
    throw error;
  }
};
```

## 📋 Best Practices Checklist

### Development Checklist
- [ ] Functions follow single responsibility principle
- [ ] Comprehensive error handling implemented
- [ ] Input validation and sanitization in place
- [ ] Secrets managed securely (no hardcoding)
- [ ] Environment-specific configuration
- [ ] Unit tests cover core functionality
- [ ] Integration tests verify end-to-end flows
- [ ] Code follows team style guidelines
- [ ] Documentation is up to date

### Deployment Checklist
- [ ] Blue-green or canary deployment strategy
- [ ] Automated testing in CI/CD pipeline
- [ ] Infrastructure as code (CloudFormation/Terraform)
- [ ] Database migration scripts tested
- [ ] Rollback procedures documented
- [ ] Performance baseline established
- [ ] Security scanning completed

### Operations Checklist
- [ ] Monitoring and alerting configured
- [ ] Log aggregation and analysis setup
- [ ] Performance metrics tracked
- [ ] Capacity planning performed
- [ ] Disaster recovery procedures tested
- [ ] Security monitoring enabled
- [ ] Cost monitoring and optimization
- [ ] Regular security updates applied

### Security Checklist
- [ ] IAM roles follow least privilege principle
- [ ] All secrets stored securely
- [ ] Input validation prevents injection attacks
- [ ] HTTPS/TLS encryption enabled
- [ ] Security headers configured
- [ ] Regular security audits performed
- [ ] Vulnerability scanning automated
- [ ] Incident response plan documented

### Performance Checklist
- [ ] Performance targets defined and monitored
- [ ] Caching strategies implemented
- [ ] Connection pooling configured
- [ ] Batch processing for bulk operations
- [ ] Rate limiting and throttling implemented
- [ ] Regular performance testing
- [ ] Capacity planning based on metrics
- [ ] Cost optimization ongoing

---

> **Remember**: Best practices are guidelines that should be adapted to your specific context and requirements. Regularly review and update these practices based on lessons learned and industry evolution.