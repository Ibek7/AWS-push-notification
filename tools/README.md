# Developer Tools and Utilities

This directory contains tools and utilities to streamline development and operations for the AWS Push Notifications system.

## Available Tools

### Development Tools
- **notification-tester.js**: Interactive notification testing tool
- **token-validator.js**: FCM token validation utility
- **payload-generator.js**: Test payload generation
- **batch-sender.js**: Bulk notification sending tool

### Debugging Tools
- **log-analyzer.js**: CloudWatch log analysis and parsing
- **trace-viewer.js**: X-Ray trace analysis tool
- **error-reporter.js**: Error aggregation and reporting
- **performance-profiler.js**: Performance analysis utility

### Deployment Tools
- **environment-setup.sh**: Environment configuration script
- **health-checker.js**: System health validation
- **smoke-test.js**: Post-deployment validation
- **rollback-helper.sh**: Quick rollback utility

### Monitoring Tools
- **metrics-dashboard.js**: Custom metrics visualization
- **alert-simulator.js**: Alert testing tool
- **capacity-planner.js**: Resource capacity analysis
- **cost-calculator.js**: AWS cost estimation

## Installation

```bash
# Install dependencies
npm install

# Make scripts executable
chmod +x tools/*.sh

# Set up environment variables
cp .env.example .env
# Edit .env with your configuration
```

## Usage Examples

### Test a Single Notification
```bash
node tools/notification-tester.js \
  --token "YOUR_FCM_TOKEN" \
  --title "Test Notification" \
  --message "Testing the notification system"
```

### Validate FCM Tokens
```bash
node tools/token-validator.js \
  --file tokens.txt \
  --output valid-tokens.json
```

### Analyze Recent Errors
```bash
node tools/log-analyzer.js \
  --hours 24 \
  --level ERROR \
  --function sendPushNotification
```

### Run Health Check
```bash
./tools/health-checker.js --environment prod
```

## Configuration

Each tool supports configuration via:
1. Command line arguments
2. Environment variables
3. Configuration files
4. Interactive prompts

See individual tool documentation for specific options.