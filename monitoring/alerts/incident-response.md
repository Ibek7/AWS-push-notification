# Alerting and Incident Response

## Overview

This document outlines the alerting strategy and incident response procedures for the AWS Push Notifications system.

## Alert Categories

### Critical Alerts (P1)
- **System Down**: API Gateway or Lambda function completely unavailable
- **High Error Rate**: >10% error rate sustained for >5 minutes
- **Data Loss**: SNS messages failing to publish
- **Security Breach**: Unauthorized access detected

### Warning Alerts (P2)
- **Performance Degradation**: Response time >3s for >10 minutes
- **Error Rate Increase**: >5% error rate for >10 minutes
- **Resource Exhaustion**: Lambda concurrent executions >80% of limit
- **Cost Anomaly**: Unexpected billing increases

### Info Alerts (P3)
- **Traffic Spikes**: Unusual request volume
- **Capacity Planning**: Resource utilization trends
- **Maintenance Windows**: Scheduled maintenance notifications

## Alert Channels

### Primary Channels
- **Email**: Immediate notifications to on-call engineers
- **Slack**: Team notifications with context and runbooks
- **PagerDuty**: Escalation for critical alerts
- **SMS**: Backup for critical alerts when email fails

### Integration Setup
```bash
# SNS Topic for critical alerts
aws sns create-topic --name push-notifications-critical

# Email subscription
aws sns subscribe \
  --topic-arn arn:aws:sns:region:account:push-notifications-critical \
  --protocol email \
  --notification-endpoint ops@company.com

# Slack webhook integration
aws sns subscribe \
  --topic-arn arn:aws:sns:region:account:push-notifications-critical \
  --protocol https \
  --notification-endpoint https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK
```

## Incident Response Procedures

### P1 - Critical Incidents

#### Immediate Response (0-15 minutes)
1. **Acknowledge** the alert in monitoring system
2. **Assess** impact using dashboards and logs
3. **Communicate** incident to stakeholders via Slack
4. **Escalate** to senior engineer if needed

#### Investigation (15-60 minutes)
1. **Check** CloudWatch logs for error patterns
2. **Verify** AWS service health dashboard
3. **Review** recent deployments or changes
4. **Identify** root cause using X-Ray traces

#### Resolution (60+ minutes)
1. **Implement** immediate fix or rollback
2. **Validate** system recovery
3. **Document** actions taken
4. **Schedule** post-incident review

### P2 - Warning Incidents

#### Response Process
1. **Monitor** for escalation to P1
2. **Investigate** during business hours
3. **Plan** fix for next maintenance window
4. **Update** monitoring thresholds if needed

## Runbooks

### High Error Rate Investigation
```bash
# Check recent errors in CloudWatch
aws logs filter-log-events \
  --log-group-name /aws/lambda/sendPushNotification \
  --start-time $(date -d '1 hour ago' +%s)000 \
  --filter-pattern "ERROR"

# Check X-Ray for error traces
aws xray get-trace-summaries \
  --time-range-type TimeRangeByStartTime \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --filter-expression "error = true"
```

### Performance Degradation
```bash
# Check Lambda duration metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Duration \
  --dimensions Name=FunctionName,Value=sendPushNotification \
  --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Average,Maximum
```

### SNS Publishing Issues
```bash
# Check SNS metrics
aws cloudwatch get-metric-statistics \
  --namespace AWS/SNS \
  --metric-name NumberOfNotificationsFailed \
  --dimensions Name=TopicName,Value=push-notifications \
  --start-time $(date -d '1 hour ago' -u +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum
```

## Post-Incident Procedures

### Incident Review Template
```markdown
# Incident Report: [YYYY-MM-DD] [Brief Description]

## Summary
- **Start Time**: 
- **End Time**: 
- **Duration**: 
- **Severity**: P1/P2/P3
- **Impact**: 

## Timeline
- **[Time]**: Initial alert triggered
- **[Time]**: Investigation started
- **[Time]**: Root cause identified
- **[Time]**: Fix implemented
- **[Time]**: Service restored

## Root Cause
[Detailed explanation of what caused the incident]

## Actions Taken
[List of all actions taken during the incident]

## Follow-up Actions
- [ ] Action item 1 (Owner: Name, Due: Date)
- [ ] Action item 2 (Owner: Name, Due: Date)

## Lessons Learned
[What we learned and how to prevent similar incidents]
```

## Monitoring Improvements

### Proactive Monitoring
- **Health Checks**: Synthetic monitoring of critical paths
- **Canary Deployments**: Gradual rollout with monitoring
- **Load Testing**: Regular performance validation
- **Security Scanning**: Automated vulnerability detection

### Alert Tuning
- **Regular Review**: Monthly alert threshold review
- **False Positive Reduction**: Adjust thresholds based on patterns
- **Coverage Gaps**: Identify missing monitoring areas
- **Response Time**: Optimize alert-to-response time

## Contact Information

### On-Call Rotation
- **Primary**: [Name] ([Phone]) ([Email])
- **Secondary**: [Name] ([Phone]) ([Email])
- **Escalation**: [Manager] ([Phone]) ([Email])

### Vendor Contacts
- **AWS Support**: [Case creation process]
- **Firebase Support**: [Support contact info]
- **Third-party Services**: [Contact information]