# X-Ray Tracing Configuration

This directory contains configuration for AWS X-Ray distributed tracing.

## Overview

X-Ray provides distributed tracing capabilities to track requests across the entire AWS Push Notifications system, from API Gateway through Lambda to SNS and Firebase.

## Service Map

```
API Gateway → Lambda Function → SNS Topic → Firebase FCM
     ↓              ↓              ↓            ↓
  X-Ray Trace → X-Ray Segment → X-Ray Sub → External Call
```

## Setup Instructions

### 1. Enable X-Ray in Lambda
```bash
aws lambda put-function-configuration \
  --function-name sendPushNotification \
  --tracing-config Mode=Active
```

### 2. Add X-Ray SDK to Lambda
```javascript
const AWSXRay = require('aws-xray-sdk-core');
const AWS = AWSXRay.captureAWS(require('aws-sdk'));
```

### 3. Enable X-Ray in API Gateway
```bash
aws apigateway put-stage \
  --rest-api-id YOUR_API_ID \
  --stage-name prod \
  --patch-ops op=replace,path=/tracingEnabled,value=true
```

## Tracing Configuration

### Sampling Rules
- **Default**: 1 request per second, 5% of additional requests
- **High Traffic**: Adjust sampling rate based on volume
- **Debug Mode**: 100% sampling for troubleshooting

### Service Segments
- **API Gateway**: HTTP request/response timing
- **Lambda**: Function execution details
- **SNS**: Message publishing performance
- **External**: Firebase FCM API calls

## Analysis Capabilities

### Performance Analysis
- End-to-end latency breakdown
- Service dependency identification
- Bottleneck detection
- Response time percentiles

### Error Tracking
- Exception correlation across services
- Failed request visualization
- Error rate by service
- Root cause analysis

### Service Dependencies
- Visual service map
- Call volume between services
- Success/failure rates
- Performance characteristics

## Custom Annotations

Add custom annotations to traces for enhanced filtering:

```javascript
AWSXRay.getSegment().addAnnotation('notificationType', 'push');
AWSXRay.getSegment().addAnnotation('userSegment', 'premium');
AWSXRay.getSegment().addMetadata('requestDetails', {
  fcmToken: 'partial_token...',
  messageSize: payload.length
});
```

## Trace Analysis Queries

### Common Queries
- `service("sendPushNotification") AND error`
- `responsetime > 5`
- `annotation.notificationType = "push"`
- `service("sendPushNotification") AND http.response.status = 500`

### Performance Monitoring
- Track 95th percentile response times
- Identify slow downstream dependencies
- Monitor cold start impact
- Analyze concurrent execution patterns