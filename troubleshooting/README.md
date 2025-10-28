# Troubleshooting Guide and Runbooks

This directory contains comprehensive troubleshooting documentation and operational runbooks for the AWS Push Notifications system.

## 📚 Documentation Structure

```
troubleshooting/
├── README.md                    # This overview document
├── common-issues.md            # Frequently encountered problems and solutions
├── runbooks/                   # Step-by-step operational procedures
│   ├── lambda-issues.md        # Lambda function troubleshooting
│   ├── sns-issues.md           # SNS topic and messaging issues
│   ├── firebase-issues.md      # Firebase FCM integration problems
│   ├── api-gateway-issues.md   # API Gateway related issues
│   ├── performance-issues.md   # Performance and latency problems
│   └── security-issues.md      # Security and authentication problems
├── diagnostic-tools/           # Automated diagnostic scripts
│   ├── system-diagnostics.sh   # Comprehensive system health check
│   ├── error-analyzer.sh       # Log analysis and error correlation
│   └── performance-profiler.sh # Performance bottleneck identification
└── escalation/                 # Escalation procedures and contacts
    ├── escalation-matrix.md     # When and how to escalate issues
    └── vendor-contacts.md       # AWS and Firebase support contacts
```

## 🚨 Quick Reference - Common Issues

### 🔥 High Priority Issues
- **Service Down**: Complete system unavailability → [Lambda Issues Runbook](runbooks/lambda-issues.md)
- **High Error Rate**: >5% notification failures → [Error Analysis Guide](runbooks/sns-issues.md)
- **Security Breach**: Unauthorized access detected → [Security Incident Response](runbooks/security-issues.md)

### ⚠️ Medium Priority Issues  
- **Performance Degradation**: Slow response times → [Performance Runbook](runbooks/performance-issues.md)
- **FCM Delivery Issues**: Firebase connectivity problems → [Firebase Runbook](runbooks/firebase-issues.md)
- **API Rate Limiting**: Throttling issues → [API Gateway Runbook](runbooks/api-gateway-issues.md)

### 📋 Low Priority Issues
- **Monitoring Gaps**: Missing metrics or logs → [Monitoring Setup](../monitoring/README.md)
- **Configuration Drift**: Environment inconsistencies → [Config Management](../config/README.md)

## 🛠️ Diagnostic Tools Usage

### Quick System Health Check
```bash
# Run comprehensive system diagnostics
./diagnostic-tools/system-diagnostics.sh --env prod

# Analyze recent errors
./diagnostic-tools/error-analyzer.sh --hours 24 --level ERROR

# Profile performance issues
./diagnostic-tools/performance-profiler.sh --function sendPushNotification
```

### Log Analysis Commands
```bash
# Search for specific errors
aws logs filter-log-events \
  --log-group-name /aws/lambda/sendPushNotification \
  --start-time $(date -d '1 hour ago' +%s)000 \
  --filter-pattern "ERROR"

# Check X-Ray traces for errors
aws xray get-trace-summaries \
  --time-range-type TimeRangeByStartTime \
  --start-time $(date -d '1 hour ago' +%s) \
  --end-time $(date +%s) \
  --filter-expression "error = true"
```

## 📞 Emergency Contacts

### On-Call Rotation
- **Primary**: Dev Team Lead (check current rotation)
- **Secondary**: Platform Engineer (check current rotation)  
- **Escalation**: Engineering Manager

### Vendor Support
- **AWS Support**: [Support Case Portal](https://console.aws.amazon.com/support/)
- **Firebase Support**: [Firebase Console](https://console.firebase.google.com/)

## 🎯 Troubleshooting Methodology

### 1. **Identify** 🔍
- Gather symptoms and error messages
- Check monitoring dashboards
- Determine impact scope and severity

### 2. **Isolate** 🎯
- Reproduce the issue if possible
- Check related components
- Review recent changes

### 3. **Investigate** 🕵️
- Analyze logs and traces
- Check resource utilization
- Verify configurations

### 4. **Implement** 🔧
- Apply immediate fixes if available
- Implement workarounds if needed
- Document actions taken

### 5. **Verify** ✅
- Confirm issue resolution
- Monitor for recurrence
- Update documentation

## 📊 Key Metrics to Monitor

### System Health Indicators
- **Error Rate**: <2% for production
- **Response Time**: <3 seconds average
- **Availability**: >99.9% uptime
- **Throughput**: Monitor against baseline

### Alert Thresholds
- **Critical**: Error rate >5%, Response time >10s
- **Warning**: Error rate >2%, Response time >5s
- **Info**: Unusual patterns, capacity planning

## 🔄 Continuous Improvement

### Post-Incident Actions
1. **Document** the incident and resolution
2. **Analyze** root cause and contributing factors
3. **Improve** monitoring, alerting, or procedures
4. **Review** with team and update runbooks

### Regular Maintenance
- **Weekly**: Review open issues and trends
- **Monthly**: Update runbooks and escalation contacts
- **Quarterly**: Conduct disaster recovery drills
- **Annually**: Review and update entire troubleshooting framework

## 📝 Contributing to Troubleshooting Docs

When you encounter and resolve a new issue:

1. **Document the problem** clearly with symptoms
2. **Record the solution** with step-by-step instructions
3. **Add prevention measures** if applicable
4. **Update relevant runbooks** or create new ones
5. **Share knowledge** with the team

## 🔗 Related Documentation

- [Monitoring and Observability](../monitoring/README.md)
- [Security Documentation](../docs/SECURITY.md)
- [Configuration Management](../config/README.md)
- [Developer Tools](../tools/README.md)
- [API Documentation](../docs/API.md)

---

> **Remember**: When in doubt, don't hesitate to escalate. It's better to involve senior engineers early than to risk extended downtime or security issues.