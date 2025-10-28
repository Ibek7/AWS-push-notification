# 🚀 Deployment Guide

This guide provides step-by-step instructions for deploying the AWS Push Notifications System to production.

## 📋 Prerequisites

- AWS Account with appropriate permissions
- Firebase project configured
- Domain name (optional, for custom API endpoints)
- SSL certificate (for HTTPS endpoints)

## 🔧 AWS Infrastructure Setup

### 1. IAM Roles and Policies

Create the necessary IAM roles for Lambda function:

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
    },
    {
      "Effect": "Allow",
      "Action": [
        "sns:Publish",
        "sns:CreatePlatformEndpoint",
        "sns:Subscribe",
        "sns:Unsubscribe"
      ],
      "Resource": "*"
    }
  ]
}
```

### 2. Lambda Function Deployment

```bash
# Package the function
cd Source-Code/Lambda-Function
zip -r ../push-notification-function.zip .

# Create the Lambda function
aws lambda create-function \
  --function-name push-notification-handler \
  --runtime nodejs18.x \
  --role arn:aws:iam::YOUR-ACCOUNT-ID:role/lambda-execution-role \
  --handler index.handler \
  --zip-file fileb://../push-notification-function.zip \
  --timeout 30 \
  --memory-size 256 \
  --environment Variables='{
    "SNS_TOPIC_ARN":"arn:aws:sns:region:account:topic-name",
    "FIREBASE_SERVER_KEY":"your-firebase-server-key"
  }'
```

### 3. SNS Topic and Platform Application

```bash
# Create SNS topic
aws sns create-topic --name push-notifications-prod

# Create platform application for Android
aws sns create-platform-application \
  --name "AndroidPushApp-Prod" \
  --platform GCM \
  --attributes PlatformCredential=YOUR_FIREBASE_SERVER_KEY
```

### 4. API Gateway Setup

```bash
# Create API Gateway
aws apigateway create-rest-api --name push-notification-api

# Create resource and method
# Configure Lambda integration
# Deploy API to stage
```

## 📱 Android Application Deployment

### 1. Production Build Configuration

Update `build.gradle`:

```gradle
android {
    buildTypes {
        release {
            minifyEnabled true
            proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
            buildConfigField "String", "API_ENDPOINT", "\"https://your-api-gateway-url\""
        }
    }
}
```

### 2. Firebase Production Configuration

1. Create production Firebase project
2. Generate new `google-services.json`
3. Update package name if needed
4. Configure FCM server key in AWS

### 3. App Signing

```bash
# Generate keystore
keytool -genkey -v -keystore my-release-key.keystore -alias alias_name -keyalg RSA -keysize 2048 -validity 10000

# Sign the APK
jarsigner -verbose -sigalg SHA1withRSA -digestalg SHA1 -keystore my-release-key.keystore my_application.apk alias_name
```

## 🔒 Security Configuration

### 1. Environment Variables

Set up secure environment variables in Lambda:

```bash
aws lambda update-function-configuration \
  --function-name push-notification-handler \
  --environment Variables='{
    "SNS_TOPIC_ARN":"arn:aws:sns:region:account:topic-name",
    "FIREBASE_SERVER_KEY":"your-firebase-server-key",
    "NODE_ENV":"production"
  }'
```

### 2. API Authentication

Implement API key authentication:

```javascript
exports.handler = async (event) => {
    const apiKey = event.headers['x-api-key'];
    if (apiKey !== process.env.API_KEY) {
        return {
            statusCode: 401,
            body: JSON.stringify({ error: 'Unauthorized' })
        };
    }
    // ... rest of the handler
};
```

## 📊 Monitoring and Logging

### 1. CloudWatch Alarms

```bash
# Create alarm for Lambda errors
aws cloudwatch put-metric-alarm \
  --alarm-name "PushNotification-Errors" \
  --alarm-description "Lambda function errors" \
  --metric-name Errors \
  --namespace AWS/Lambda \
  --statistic Sum \
  --period 300 \
  --threshold 5 \
  --comparison-operator GreaterThanThreshold \
  --dimensions Name=FunctionName,Value=push-notification-handler
```

### 2. Custom Metrics

Add custom metrics to your Lambda function:

```javascript
const AWS = require('aws-sdk');
const cloudwatch = new AWS.CloudWatch();

async function putMetric(metricName, value) {
    const params = {
        Namespace: 'PushNotifications',
        MetricData: [{
            MetricName: metricName,
            Value: value,
            Unit: 'Count'
        }]
    };
    await cloudwatch.putMetricData(params).promise();
}
```

## 🔄 CI/CD Pipeline

### GitHub Actions Workflow

Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy to Production

on:
  push:
    branches: [main]

jobs:
  deploy-lambda:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Node.js
        uses: actions/setup-node@v3
        with:
          node-version: '18'
          
      - name: Install dependencies
        run: |
          cd Source-Code/Lambda-Function
          npm ci
          
      - name: Run tests
        run: |
          cd Source-Code/Lambda-Function
          npm test
          
      - name: Package Lambda
        run: |
          cd Source-Code/Lambda-Function
          zip -r ../../push-notification-function.zip .
          
      - name: Deploy to AWS
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        run: |
          aws lambda update-function-code \
            --function-name push-notification-handler \
            --zip-file fileb://push-notification-function.zip

  build-android:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup JDK
        uses: actions/setup-java@v3
        with:
          java-version: '11'
          distribution: 'temurin'
          
      - name: Setup Android SDK
        uses: android-actions/setup-android@v2
        
      - name: Build APK
        run: |
          cd AWS-Push-Notifications-main/Source-Code/Android-Source-Code
          ./gradlew assembleRelease
          
      - name: Upload APK
        uses: actions/upload-artifact@v3
        with:
          name: app-release
          path: AWS-Push-Notifications-main/Source-Code/Android-Source-Code/app/build/outputs/apk/release/
```

## ✅ Production Checklist

- [ ] AWS resources created and configured
- [ ] Lambda function deployed with correct environment variables
- [ ] SNS topics and platform applications configured
- [ ] API Gateway deployed with proper authentication
- [ ] Firebase project configured for production
- [ ] Android app signed and ready for distribution
- [ ] CloudWatch monitoring and alarms set up
- [ ] CI/CD pipeline configured
- [ ] Load testing completed
- [ ] Security review passed
- [ ] Documentation updated

## 🔧 Troubleshooting

### Common Issues

1. **Lambda timeout errors**
   - Increase timeout limit
   - Optimize function performance

2. **SNS permission errors**
   - Verify IAM role permissions
   - Check topic ARN configuration

3. **Firebase authentication errors**
   - Verify server key configuration
   - Check package name matches

4. **Android app not receiving notifications**
   - Verify FCM token generation
   - Check SNS endpoint subscription

## 📞 Support

For deployment issues:
- Check CloudWatch logs
- Review AWS service limits
- Contact support team

---

🎉 **Congratulations!** Your AWS Push Notifications System is now deployed to production!