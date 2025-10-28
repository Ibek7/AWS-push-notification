# Performance Optimization Strategies

## 🎯 Overview
This document provides detailed, actionable strategies for optimizing the performance of the AWS Push Notifications system across all components.

## 🚀 Lambda Function Optimization

### Memory and CPU Optimization

#### Right-sizing Memory Allocation
```javascript
// Analyze memory usage patterns
const memoryUsed = process.memoryUsage();
console.log('Memory usage:', {
  rss: Math.round(memoryUsed.rss / 1024 / 1024) + 'MB',
  heapUsed: Math.round(memoryUsed.heapUsed / 1024 / 1024) + 'MB',
  heapTotal: Math.round(memoryUsed.heapTotal / 1024 / 1024) + 'MB',
  external: Math.round(memoryUsed.external / 1024 / 1024) + 'MB'
});
```

**Optimization Commands:**
```bash
# Monitor memory utilization
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name MemoryUtilization \
  --dimensions Name=FunctionName,Value=sendPushNotification \
  --start-time $(date -d '24 hours ago' -u +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 3600 \
  --statistics Average,Maximum

# Right-size based on 95th percentile usage + 10% buffer
OPTIMAL_MEMORY=$(echo "scale=0; actual_memory_95th_percentile * 1.1" | bc)
aws lambda update-function-configuration \
  --function-name sendPushNotification \
  --memory-size $OPTIMAL_MEMORY
```

#### CPU Performance Optimization
```javascript
// Optimize CPU-intensive operations
const cluster = require('cluster');
const numCPUs = require('os').cpus().length;

// For batch processing, use worker threads
const { Worker, isMainThread, parentPort, workerData } = require('worker_threads');

const processNotificationsBatch = async (notifications) => {
  const batchSize = Math.ceil(notifications.length / numCPUs);
  const workers = [];
  
  for (let i = 0; i < numCPUs; i++) {
    const start = i * batchSize;
    const end = start + batchSize;
    const batch = notifications.slice(start, end);
    
    if (batch.length > 0) {
      workers.push(new Promise((resolve, reject) => {
        const worker = new Worker(__filename, {
          workerData: { batch }
        });
        
        worker.on('message', resolve);
        worker.on('error', reject);
      }));
    }
  }
  
  return Promise.all(workers);
};
```

### Cold Start Optimization

#### Provisioned Concurrency Setup
```bash
# Enable provisioned concurrency for production
aws lambda put-provisioned-concurrency-config \
  --function-name sendPushNotification \
  --qualifier $LATEST \
  --provisioned-concurrency-config ProvisionedConcurrencyConfigs=5

# Monitor provisioned concurrency utilization
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name ProvisionedConcurrencyUtilization \
  --dimensions Name=FunctionName,Value=sendPushNotification \
  --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average,Maximum
```

#### Code Optimization for Cold Starts
```javascript
// Move initialization outside handler
const AWS = require('aws-sdk');
const admin = require('firebase-admin');

// Initialize AWS services outside handler
const sns = new AWS.SNS({ 
  region: process.env.AWS_REGION,
  maxRetries: 3,
  retryDelayOptions: {
    customBackoff: function(retryCount) {
      return Math.pow(2, retryCount) * 100; // Exponential backoff
    }
  }
});

// Initialize Firebase once
if (!admin.apps.length) {
  admin.initializeApp({
    credential: admin.credential.cert({
      projectId: process.env.FIREBASE_PROJECT_ID,
      clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
      privateKey: process.env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n')
    })
  });
}

// Connection pooling
const https = require('https');
const agent = new https.Agent({
  keepAlive: true,
  maxSockets: 50,
  maxFreeSockets: 10,
  timeout: 60000,
  freeSocketTimeout: 30000
});

// Handler function
exports.handler = async (event) => {
  // Handler logic here
};
```

### Memory Leak Prevention
```javascript
// Implement proper cleanup
const activeConnections = new Set();
const timers = new Set();

const cleanupResources = () => {
  // Clear all timers
  timers.forEach(timer => clearTimeout(timer));
  timers.clear();
  
  // Close active connections
  activeConnections.forEach(connection => {
    if (connection && connection.destroy) {
      connection.destroy();
    }
  });
  activeConnections.clear();
  
  // Force garbage collection if available
  if (global.gc) {
    global.gc();
  }
};

// Cleanup on exit
process.on('beforeExit', cleanupResources);
process.on('SIGTERM', cleanupResources);
```

## 📡 SNS Optimization

### Message Delivery Optimization

#### Batch Publishing
```javascript
const publishBatch = async (messages, batchSize = 10) => {
  const batches = [];
  for (let i = 0; i < messages.length; i += batchSize) {
    batches.push(messages.slice(i, i + batchSize));
  }
  
  const results = await Promise.allSettled(
    batches.map(async (batch) => {
      const publishPromises = batch.map(message => 
        sns.publish({
          TopicArn: process.env.SNS_TOPIC_ARN,
          Message: JSON.stringify(message),
          MessageAttributes: {
            'MessageType': {
              DataType: 'String',
              StringValue: 'PushNotification'
            }
          }
        }).promise()
      );
      
      return Promise.all(publishPromises);
    })
  );
  
  return results;
};
```

#### Delivery Retry Configuration
```bash
# Configure SNS delivery policy with optimized retries
aws sns set-topic-attributes \
  --topic-arn arn:aws:sns:region:account:PushNotificationTopic \
  --attribute-name DeliveryPolicy \
  --attribute-value '{
    "default": {
      "defaultHealthyRetryPolicy": {
        "minDelayTarget": 1,
        "maxDelayTarget": 60,
        "numRetries": 3,
        "numMaxDelayRetries": 5,
        "backoffFunction": "exponential"
      }
    }
  }'
```

### SNS Topic Optimization
```bash
# Enable delivery status logging for monitoring
aws sns set-topic-attributes \
  --topic-arn arn:aws:sns:region:account:PushNotificationTopic \
  --attribute-name LambdaSuccessFeedbackRoleArn \
  --attribute-value arn:aws:iam::account:role/sns-delivery-status-role

aws sns set-topic-attributes \
  --topic-arn arn:aws:sns:region:account:PushNotificationTopic \
  --attribute-name LambdaSuccessFeedbackSampleRate \
  --attribute-value 10

# Configure dead letter queue for failed messages
aws sns set-topic-attributes \
  --topic-arn arn:aws:sns:region:account:PushNotificationTopic \
  --attribute-name RedrivePolicy \
  --attribute-value '{
    "deadLetterTargetArn": "arn:aws:sqs:region:account:push-notification-dlq"
  }'
```

## 🔥 Firebase FCM Optimization

### Message Payload Optimization

#### Efficient Payload Structure
```javascript
// Optimized FCM message structure
const createOptimizedMessage = (deviceTokens, notification, data = {}) => {
  // Validate payload size (FCM limit: 4KB)
  const validatePayloadSize = (payload) => {
    const size = Buffer.byteLength(JSON.stringify(payload), 'utf8');
    if (size > 4096) {
      throw new Error(`Payload size ${size} exceeds FCM limit of 4096 bytes`);
    }
    return size;
  };

  // Minimize payload size
  const optimizedNotification = {
    title: notification.title.substring(0, 100), // Limit title length
    body: notification.body.substring(0, 500),   // Limit body length
    ...(notification.icon && { icon: notification.icon }),
    ...(notification.sound && { sound: notification.sound })
  };

  // Compress data payload if needed
  const optimizedData = Object.fromEntries(
    Object.entries(data).map(([key, value]) => [
      key,
      typeof value === 'string' ? value : JSON.stringify(value)
    ])
  );

  const message = {
    notification: optimizedNotification,
    data: optimizedData,
    android: {
      priority: 'high',
      ttl: 3600000, // 1 hour TTL
      notification: {
        channel_id: 'high_importance_channel'
      }
    },
    apns: {
      payload: {
        aps: {
          badge: 1,
          sound: 'default'
        }
      }
    }
  };

  validatePayloadSize(message);
  return message;
};
```

#### Batch Processing for FCM
```javascript
const sendBatchNotifications = async (tokens, message, batchSize = 500) => {
  const batches = [];
  for (let i = 0; i < tokens.length; i += batchSize) {
    batches.push(tokens.slice(i, i + batchSize));
  }

  const results = [];
  
  for (const batch of batches) {
    try {
      const multicastMessage = {
        ...message,
        tokens: batch
      };
      
      const response = await admin.messaging().sendMulticast(multicastMessage);
      results.push({
        batch: batch.length,
        success: response.successCount,
        failure: response.failureCount,
        responses: response.responses
      });
      
      // Process failed tokens
      if (response.failureCount > 0) {
        const failedTokens = [];
        response.responses.forEach((resp, idx) => {
          if (!resp.success) {
            failedTokens.push({
              token: batch[idx],
              error: resp.error
            });
          }
        });
        
        // Remove invalid tokens
        await removeInvalidTokens(failedTokens);
      }
      
      // Rate limiting protection
      await new Promise(resolve => setTimeout(resolve, 100));
      
    } catch (error) {
      console.error('Batch send failed:', error);
      results.push({
        batch: batch.length,
        success: 0,
        failure: batch.length,
        error: error.message
      });
    }
  }
  
  return results;
};
```

### Token Management Optimization
```javascript
// Efficient token validation and cleanup
const validateAndCleanTokens = async (tokens) => {
  const validTokens = [];
  const invalidTokens = [];
  const canonicalTokens = new Map();
  
  // Use FCM's multicast for batch validation
  const testMessage = {
    data: { test: 'validation' },
    tokens: tokens.slice(0, 500) // FCM batch limit
  };
  
  try {
    const response = await admin.messaging().sendMulticast(testMessage, true); // dry run
    
    response.responses.forEach((resp, idx) => {
      const token = tokens[idx];
      
      if (resp.success) {
        validTokens.push(token);
      } else if (resp.error) {
        const errorCode = resp.error.code;
        
        if (errorCode === 'messaging/invalid-registration-token' || 
            errorCode === 'messaging/registration-token-not-registered') {
          invalidTokens.push(token);
        } else if (errorCode === 'messaging/invalid-argument' && 
                   resp.error.message.includes('canonical')) {
          // Extract canonical token from error message
          const canonical = extractCanonicalToken(resp.error.message);
          if (canonical) {
            canonicalTokens.set(token, canonical);
          }
        }
      }
    });
    
    // Update database with canonical tokens
    if (canonicalTokens.size > 0) {
      await updateCanonicalTokens(canonicalTokens);
    }
    
    // Remove invalid tokens
    if (invalidTokens.length > 0) {
      await removeInvalidTokens(invalidTokens);
    }
    
  } catch (error) {
    console.error('Token validation failed:', error);
  }
  
  return validTokens;
};
```

## 🌐 API Gateway Optimization

### Caching Configuration
```bash
# Enable API Gateway caching
aws apigateway put-method \
  --rest-api-id YOUR_API_ID \
  --resource-id YOUR_RESOURCE_ID \
  --http-method POST \
  --authorization-type NONE \
  --request-parameters method.request.header.Authorization=false

# Configure cache settings
aws apigateway put-integration \
  --rest-api-id YOUR_API_ID \
  --resource-id YOUR_RESOURCE_ID \
  --http-method POST \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri arn:aws:apigateway:region:lambda:path/2015-03-31/functions/arn:aws:lambda:region:account:function:sendPushNotification/invocations \
  --cache-key-parameters method.request.header.Authorization

# Set cache TTL
aws apigateway update-stage \
  --rest-api-id YOUR_API_ID \
  --stage-name prod \
  --patch-ops op=replace,path=/cacheClusterEnabled,value=true \
  --patch-ops op=replace,path=/cacheClusterSize,value=0.5 \
  --patch-ops op=replace,path=/cacheTtlInSeconds,value=300
```

### Request Throttling
```bash
# Configure throttling limits
aws apigateway put-method \
  --rest-api-id YOUR_API_ID \
  --resource-id YOUR_RESOURCE_ID \
  --http-method POST \
  --throttle-burst-limit 2000 \
  --throttle-rate-limit 1000
```

## 💾 Database and Storage Optimization

### Connection Pooling
```javascript
// Implement connection pooling for database connections
const mysql = require('mysql2/promise');

const pool = mysql.createPool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
  acquireTimeout: 60000,
  timeout: 60000,
  enableKeepAlive: true,
  keepAliveInitialDelay: 0
});

// Optimized database queries
const getUserTokens = async (userId) => {
  const query = `
    SELECT device_token 
    FROM user_devices 
    WHERE user_id = ? 
      AND is_active = 1 
      AND last_seen > DATE_SUB(NOW(), INTERVAL 30 DAY)
    ORDER BY last_seen DESC
    LIMIT 10
  `;
  
  const [rows] = await pool.execute(query, [userId]);
  return rows.map(row => row.device_token);
};
```

### Caching Strategy
```javascript
// Multi-level caching implementation
const Redis = require('redis');
const client = Redis.createClient({
  host: process.env.REDIS_HOST,
  port: process.env.REDIS_PORT,
  retryDelayOnFailover: 100,
  enableReadyCheck: false,
  maxRetriesPerRequest: null
});

// Memory cache for frequently accessed data
const memoryCache = new Map();
const MEMORY_CACHE_TTL = 60000; // 1 minute

const getCachedData = async (key) => {
  // Check memory cache first
  const memoryData = memoryCache.get(key);
  if (memoryData && Date.now() - memoryData.timestamp < MEMORY_CACHE_TTL) {
    return memoryData.value;
  }
  
  // Check Redis cache
  try {
    const redisData = await client.get(key);
    if (redisData) {
      const parsed = JSON.parse(redisData);
      // Update memory cache
      memoryCache.set(key, {
        value: parsed,
        timestamp: Date.now()
      });
      return parsed;
    }
  } catch (error) {
    console.error('Redis cache error:', error);
  }
  
  return null;
};

const setCachedData = async (key, data, ttl = 300) => {
  // Set in memory cache
  memoryCache.set(key, {
    value: data,
    timestamp: Date.now()
  });
  
  // Set in Redis cache
  try {
    await client.setex(key, ttl, JSON.stringify(data));
  } catch (error) {
    console.error('Redis cache set error:', error);
  }
};
```

## 📊 Monitoring and Observability Optimization

### Custom Metrics for Performance Tracking
```javascript
// Custom CloudWatch metrics
const AWS = require('aws-sdk');
const cloudwatch = new AWS.CloudWatch();

const putCustomMetric = async (metricName, value, unit = 'Count', dimensions = []) => {
  try {
    await cloudwatch.putMetricData({
      Namespace: 'PushNotifications/Performance',
      MetricData: [{
        MetricName: metricName,
        Value: value,
        Unit: unit,
        Dimensions: dimensions,
        Timestamp: new Date()
      }]
    }).promise();
  } catch (error) {
    console.error('Failed to put custom metric:', error);
  }
};

// Track performance metrics
const trackNotificationLatency = async (startTime, endTime, notificationCount) => {
  const latency = endTime - startTime;
  
  await Promise.all([
    putCustomMetric('NotificationLatency', latency, 'Milliseconds'),
    putCustomMetric('NotificationThroughput', notificationCount / (latency / 1000), 'Count/Second'),
    putCustomMetric('NotificationBatchSize', notificationCount, 'Count')
  ]);
};
```

### X-Ray Tracing Optimization
```javascript
// AWS X-Ray integration for performance tracing
const AWSXRay = require('aws-xray-sdk-core');
const AWS = AWSXRay.captureAWS(require('aws-sdk'));

// Create subsegments for detailed tracing
const processNotificationWithTracing = async (notification) => {
  const segment = AWSXRay.getSegment();
  
  // Token validation subsegment
  const tokenSubsegment = segment.addNewSubsegment('token_validation');
  try {
    const validTokens = await validateTokens(notification.tokens);
    tokenSubsegment.addMetadata('tokenCount', validTokens.length);
    tokenSubsegment.close();
  } catch (error) {
    tokenSubsegment.addError(error);
    tokenSubsegment.close(error);
    throw error;
  }
  
  // FCM sending subsegment
  const fcmSubsegment = segment.addNewSubsegment('fcm_send');
  try {
    const result = await sendFCMNotification(validTokens, notification);
    fcmSubsegment.addMetadata('successCount', result.successCount);
    fcmSubsegment.addMetadata('failureCount', result.failureCount);
    fcmSubsegment.close();
    return result;
  } catch (error) {
    fcmSubsegment.addError(error);
    fcmSubsegment.close(error);
    throw error;
  }
};
```

## 🔧 Automated Performance Testing

### Load Testing Script
```bash
#!/bin/bash
# Load testing for push notification system

ENDPOINT="https://your-api-gateway-endpoint.com/send-notification"
API_KEY="your-api-key"
CONCURRENT_USERS=100
DURATION="5m"

# Use Artillery for load testing
cat > artillery-config.yml << EOF
config:
  target: '$ENDPOINT'
  phases:
    - duration: 60
      arrivalRate: 10
      name: "Warm up"
    - duration: 300
      arrivalRate: $CONCURRENT_USERS
      name: "Load test"
  defaults:
    headers:
      x-api-key: '$API_KEY'
      content-type: 'application/json'

scenarios:
  - name: "Send notification"
    weight: 100
    flow:
      - post:
          url: "/send-notification"
          json:
            message: "Load test notification"
            tokens: ["test_token_{{ \$randomString() }}"]
            priority: "normal"
EOF

artillery run artillery-config.yml
```

## 🎯 Performance Optimization Checklist

### Lambda Function Optimization
- [ ] Right-size memory allocation based on profiling
- [ ] Enable provisioned concurrency for consistent performance
- [ ] Optimize code for cold start reduction
- [ ] Implement connection pooling
- [ ] Use async/await patterns efficiently
- [ ] Minimize package size and dependencies
- [ ] Implement proper error handling and retries

### SNS Optimization
- [ ] Configure optimal delivery retry policies
- [ ] Implement batch publishing for multiple messages
- [ ] Set up dead letter queues for failed messages
- [ ] Enable delivery status logging
- [ ] Optimize message size and structure
- [ ] Use message attributes efficiently

### Firebase FCM Optimization
- [ ] Implement batch processing for multiple tokens
- [ ] Optimize payload size and structure
- [ ] Implement token validation and cleanup
- [ ] Use appropriate TTL values
- [ ] Handle canonical ID updates
- [ ] Implement rate limiting protection

### API Gateway Optimization
- [ ] Enable response caching where appropriate
- [ ] Configure throttling limits
- [ ] Optimize request/response transformation
- [ ] Use compression for large responses
- [ ] Implement proper error responses

### Database and Storage Optimization
- [ ] Implement connection pooling
- [ ] Use appropriate indexes
- [ ] Implement multi-level caching
- [ ] Optimize query patterns
- [ ] Regular performance monitoring

### Monitoring and Observability
- [ ] Set up comprehensive performance monitoring
- [ ] Implement custom metrics for business logic
- [ ] Configure appropriate alerting thresholds
- [ ] Use distributed tracing for complex flows
- [ ] Regular performance analysis and optimization

---

> **Next Steps**: After implementing these optimizations, monitor the impact using the metrics and tools provided in the [Monitoring Guide](monitoring-guide.md).