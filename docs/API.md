# 📚 API Documentation

## Overview

The AWS Push Notifications system provides RESTful APIs for managing push notifications, device tokens, and topic subscriptions.

## Base URL
```
https://your-api-gateway-url.amazonaws.com/prod
```

## Authentication

All API requests require an API key in the header:
```http
x-api-key: your-api-key-here
```

## Endpoints

### 📱 Device Management

#### Register Device
Register a new device with FCM token.

```http
POST /device/register
```

**Request Body:**
```json
{
  "deviceToken": "string",
  "platform": "android",
  "userId": "string",
  "deviceInfo": {
    "model": "string",
    "osVersion": "string",
    "appVersion": "string"
  }
}
```

**Response:**
```json
{
  "success": true,
  "deviceId": "device_12345",
  "snsEndpointArn": "arn:aws:sns:us-east-1:123456789:endpoint/GCM/...",
  "registeredAt": "2025-10-28T10:30:00Z"
}
```

#### Update Device Token
Update FCM token for existing device.

```http
PUT /device/{deviceId}/token
```

**Request Body:**
```json
{
  "deviceToken": "new_fcm_token_here"
}
```

### 🔔 Notification Management

#### Send Individual Notification
Send notification to specific device.

```http
POST /notification/send
```

**Request Body:**
```json
{
  "target": {
    "type": "device",
    "deviceToken": "fcm_token_here"
  },
  "notification": {
    "title": "string",
    "body": "string",
    "icon": "string",
    "sound": "default",
    "badge": 1,
    "clickAction": "OPEN_ACTIVITY"
  },
  "data": {
    "customKey": "customValue",
    "action": "navigate",
    "screen": "details"
  },
  "options": {
    "priority": "high",
    "timeToLive": 3600,
    "collapseKey": "string"
  }
}
```

**Response:**
```json
{
  "success": true,
  "messageId": "msg_12345",
  "deliveryStatus": "sent",
  "timestamp": "2025-10-28T10:30:00Z"
}
```

#### Send Topic Notification
Send notification to all subscribers of a topic.

```http
POST /notification/topic
```

**Request Body:**
```json
{
  "topic": "news_updates",
  "notification": {
    "title": "Breaking News",
    "body": "Important update for all users",
    "icon": "news_icon"
  },
  "condition": "('news_updates' in topics && 'premium' in topics) || 'admin' in topics"
}
```

#### Schedule Notification
Schedule notification for future delivery.

```http
POST /notification/schedule
```

**Request Body:**
```json
{
  "target": {
    "type": "topic",
    "topic": "reminders"
  },
  "notification": {
    "title": "Scheduled Reminder",
    "body": "Don't forget your appointment"
  },
  "schedule": {
    "deliveryTime": "2025-10-28T15:00:00Z",
    "timezone": "America/New_York"
  }
}
```

### 📋 Topic Management

#### Create Topic
Create a new notification topic.

```http
POST /topic
```

**Request Body:**
```json
{
  "name": "product_updates",
  "displayName": "Product Updates",
  "description": "Notifications about new features and updates"
}
```

#### Subscribe to Topic
Subscribe device to topic.

```http
POST /topic/{topicName}/subscribe
```

**Request Body:**
```json
{
  "deviceToken": "fcm_token_here"
}
```

#### Unsubscribe from Topic
Unsubscribe device from topic.

```http
DELETE /topic/{topicName}/subscribe
```

**Request Body:**
```json
{
  "deviceToken": "fcm_token_here"
}
```

#### List Topic Subscribers
Get list of devices subscribed to topic.

```http
GET /topic/{topicName}/subscribers
```

**Query Parameters:**
- `page`: Page number (default: 1)
- `limit`: Items per page (default: 50, max: 100)

**Response:**
```json
{
  "topic": "product_updates",
  "totalSubscribers": 1247,
  "page": 1,
  "limit": 50,
  "subscribers": [
    {
      "deviceId": "device_12345",
      "subscribedAt": "2025-10-20T08:15:00Z",
      "platform": "android",
      "active": true
    }
  ]
}
```

### 📊 Analytics and Monitoring

#### Get Notification Statistics
Retrieve delivery statistics.

```http
GET /analytics/notifications
```

**Query Parameters:**
- `from`: Start date (ISO 8601)
- `to`: End date (ISO 8601)
- `topic`: Filter by topic (optional)
- `platform`: Filter by platform (optional)

**Response:**
```json
{
  "period": {
    "from": "2025-10-21T00:00:00Z",
    "to": "2025-10-28T23:59:59Z"
  },
  "metrics": {
    "totalSent": 15432,
    "delivered": 15118,
    "failed": 314,
    "deliveryRate": 98.0,
    "avgDeliveryTime": 1.2
  },
  "breakdown": {
    "byPlatform": {
      "android": 15432,
      "ios": 0
    },
    "byTopic": {
      "push_notifications": 12890,
      "news_updates": 2542
    }
  }
}
```

#### Get Device Analytics
Retrieve device registration and activity statistics.

```http
GET /analytics/devices
```

**Response:**
```json
{
  "activeDevices": 1247,
  "totalRegistrations": 1389,
  "platforms": {
    "android": 1247,
    "ios": 0
  },
  "topicSubscriptions": {
    "push_notifications": 1247,
    "news_updates": 892,
    "product_updates": 456
  }
}
```

## Error Responses

All endpoints return standardized error responses:

```json
{
  "success": false,
  "error": {
    "code": "INVALID_TOKEN",
    "message": "The provided FCM token is invalid",
    "details": "Token format does not match expected pattern"
  },
  "timestamp": "2025-10-28T10:30:00Z",
  "requestId": "req_12345"
}
```

### Common Error Codes

| Code | Description |
|------|-------------|
| `INVALID_TOKEN` | FCM token is malformed or invalid |
| `DEVICE_NOT_FOUND` | Device ID does not exist |
| `TOPIC_NOT_FOUND` | Topic name does not exist |
| `RATE_LIMIT_EXCEEDED` | Too many requests |
| `INVALID_PAYLOAD` | Request body validation failed |
| `UNAUTHORIZED` | Invalid or missing API key |
| `DELIVERY_FAILED` | Notification could not be delivered |

## Rate Limits

| Endpoint | Limit |
|----------|-------|
| `/notification/send` | 1000 requests/minute |
| `/notification/topic` | 100 requests/minute |
| `/device/register` | 500 requests/minute |
| `/topic/*` | 200 requests/minute |
| Analytics endpoints | 50 requests/minute |

## SDKs and Client Libraries

### JavaScript/Node.js
```bash
npm install aws-push-notifications-client
```

```javascript
const PushClient = require('aws-push-notifications-client');

const client = new PushClient({
  apiKey: 'your-api-key',
  baseUrl: 'https://your-api-gateway-url.amazonaws.com/prod'
});

// Send notification
await client.sendNotification({
  target: { type: 'device', deviceToken: 'fcm_token' },
  notification: {
    title: 'Hello!',
    body: 'Test notification'
  }
});
```

### Python
```bash
pip install aws-push-notifications-python
```

```python
from aws_push_notifications import PushClient

client = PushClient(
    api_key='your-api-key',
    base_url='https://your-api-gateway-url.amazonaws.com/prod'
)

# Send notification
response = client.send_notification({
    'target': {'type': 'device', 'deviceToken': 'fcm_token'},
    'notification': {
        'title': 'Hello!',
        'body': 'Test notification'
    }
})
```

## Testing

Use the provided test endpoints to validate your integration:

```http
POST /test/notification
```

This endpoint accepts the same payload as `/notification/send` but doesn't actually deliver notifications. Use it for integration testing.

## Webhooks

Configure webhooks to receive delivery status updates:

```http
POST /webhooks
```

**Request Body:**
```json
{
  "url": "https://your-app.com/webhook/notifications",
  "events": ["delivered", "failed", "clicked"],
  "secret": "webhook_secret_for_verification"
}
```

Your webhook will receive:
```json
{
  "event": "delivered",
  "messageId": "msg_12345",
  "deviceId": "device_12345",
  "timestamp": "2025-10-28T10:30:15Z",
  "metadata": {
    "deliveryTime": 1.2,
    "attempts": 1
  }
}
```