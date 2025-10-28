# Monitoring and Observability

This directory contains monitoring, logging, and observability configurations for the AWS Push Notifications system.

## Components

### CloudWatch
- **Dashboards**: Visual monitoring of key metrics
- **Alarms**: Automated alerting for critical events
- **Log Groups**: Centralized logging for all services
- **Custom Metrics**: Application-specific monitoring

### X-Ray Tracing
- **Distributed Tracing**: End-to-end request tracking
- **Performance Analysis**: Latency and bottleneck identification
- **Service Maps**: Visual representation of service interactions

### Application Insights
- **Error Tracking**: Automated error detection and reporting
- **Performance Monitoring**: Real-time performance metrics
- **User Analytics**: Usage patterns and engagement metrics

## Setup Instructions

1. **Deploy CloudWatch Resources**:
   ```bash
   aws cloudformation deploy \
     --template-file cloudwatch-stack.yaml \
     --stack-name push-notifications-monitoring \
     --capabilities CAPABILITY_IAM
   ```

2. **Configure X-Ray Tracing**:
   ```bash
   # Enable X-Ray in Lambda functions
   aws lambda put-function-configuration \
     --function-name sendPushNotification \
     --tracing-config Mode=Active
   ```

3. **Set Up Log Aggregation**:
   ```bash
   # Create log groups with retention policies
   aws logs create-log-group \
     --log-group-name /aws/lambda/sendPushNotification \
     --retention-in-days 30
   ```

## Monitoring Strategy

### Key Metrics
- **Notification Success Rate**: % of successfully delivered notifications
- **Response Time**: End-to-end notification latency
- **Error Rate**: Failed notifications and error types
- **Throughput**: Notifications processed per minute/hour
- **Cost**: AWS resource utilization and billing

### Alert Thresholds
- **Critical**: Error rate > 5%, Response time > 5s
- **Warning**: Error rate > 2%, Response time > 3s
- **Info**: Unusual traffic patterns, cost anomalies

### Dashboard Views
- **Operations**: Real-time system health and performance
- **Business**: User engagement and notification effectiveness
- **Cost**: Resource utilization and billing optimization