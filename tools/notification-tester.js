#!/usr/bin/env node

/**
 * Interactive Notification Testing Tool
 * Allows developers to easily test push notifications with various configurations
 */

const readline = require('readline');
const AWS = require('aws-sdk');
const { v4: uuidv4 } = require('uuid');

// Configure AWS SDK
const sns = new AWS.SNS({
  region: process.env.AWS_REGION || 'us-east-1'
});

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout
});

// Configuration
const config = {
  snsTopicArn: process.env.SNS_TOPIC_ARN || 'arn:aws:sns:us-east-1:123456789012:push-notifications',
  apiEndpoint: process.env.API_ENDPOINT || 'https://api.example.com/dev/send-notification'
};

/**
 * Interactive prompt helper
 */
function askQuestion(question, defaultValue = '') {
  return new Promise((resolve) => {
    const prompt = defaultValue ? `${question} (${defaultValue}): ` : `${question}: `;
    rl.question(prompt, (answer) => {
      resolve(answer.trim() || defaultValue);
    });
  });
}

/**
 * Predefined test scenarios
 */
const testScenarios = {
  'basic': {
    title: 'Basic Test Notification',
    message: 'This is a basic test notification',
    data: { type: 'test', priority: 'normal' }
  },
  'urgent': {
    title: '🚨 Urgent Alert',
    message: 'This is an urgent test notification',
    data: { type: 'alert', priority: 'high' },
    android: { priority: 'high', ttl: 3600000 }
  },
  'rich': {
    title: '📱 Rich Notification',
    message: 'This notification includes rich content and custom data',
    data: {
      type: 'rich',
      imageUrl: 'https://example.com/image.jpg',
      actionUrl: 'https://example.com/action',
      customData: JSON.stringify({ userId: 123, sessionId: 'abc123' })
    },
    android: {
      priority: 'high',
      notification: {
        icon: 'notification_icon',
        color: '#FF5722',
        sound: 'default',
        clickAction: 'FLUTTER_NOTIFICATION_CLICK'
      }
    }
  },
  'silent': {
    title: '',
    message: '',
    data: {
      type: 'silent',
      action: 'background_sync',
      timestamp: Date.now().toString()
    },
    android: {
      priority: 'high',
      contentAvailable: true
    }
  }
};

/**
 * Send notification via SNS
 */
async function sendViaSNS(payload) {
  try {
    const message = {
      ...payload,
      timestamp: new Date().toISOString(),
      testId: uuidv4()
    };

    const params = {
      TopicArn: config.snsTopicArn,
      Message: JSON.stringify(message),
      MessageAttributes: {
        'notification_type': {
          DataType: 'String',
          StringValue: 'push'
        },
        'test_mode': {
          DataType: 'String',
          StringValue: 'true'
        }
      }
    };

    const result = await sns.publish(params).promise();
    return { success: true, messageId: result.MessageId };
  } catch (error) {
    return { success: false, error: error.message };
  }
}

/**
 * Send notification via API
 */
async function sendViaAPI(payload) {
  try {
    const fetch = require('node-fetch');
    const response = await fetch(config.apiEndpoint, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(payload)
    });

    const result = await response.json();
    return { success: response.ok, ...result };
  } catch (error) {
    return { success: false, error: error.message };
  }
}

/**
 * Validate FCM token format
 */
function validateFCMToken(token) {
  if (!token || typeof token !== 'string') {
    return false;
  }
  
  // Basic FCM token validation (simplified)
  if (token.length < 140 || token.length > 200) {
    return false;
  }
  
  // Should contain only valid characters
  if (!/^[A-Za-z0-9_:.-]+$/.test(token)) {
    return false;
  }
  
  return true;
}

/**
 * Display test results
 */
function displayResults(result, method) {
  console.log('\n' + '='.repeat(50));
  console.log(`📊 Test Results (via ${method})`);
  console.log('='.repeat(50));
  
  if (result.success) {
    console.log('✅ Status: SUCCESS');
    console.log(`📝 Message ID: ${result.messageId || 'N/A'}`);
    console.log(`⏰ Timestamp: ${new Date().toISOString()}`);
  } else {
    console.log('❌ Status: FAILED');
    console.log(`💥 Error: ${result.error}`);
  }
  
  console.log('='.repeat(50) + '\n');
}

/**
 * Main testing workflow
 */
async function runNotificationTest() {
  console.log('🚀 AWS Push Notification Tester');
  console.log('='.repeat(40));
  
  try {
    // Get FCM token
    const fcmToken = await askQuestion('Enter FCM Token');
    
    if (!validateFCMToken(fcmToken)) {
      console.log('❌ Invalid FCM token format');
      rl.close();
      return;
    }
    
    // Choose test scenario
    console.log('\n📋 Available Test Scenarios:');
    Object.keys(testScenarios).forEach((key, index) => {
      console.log(`${index + 1}. ${key} - ${testScenarios[key].title || 'Silent notification'}`);
    });
    console.log(`${Object.keys(testScenarios).length + 1}. custom - Create custom notification`);
    
    const scenarioChoice = await askQuestion('\nSelect scenario (1-5)', '1');
    const scenarioIndex = parseInt(scenarioChoice) - 1;
    const scenarioKeys = Object.keys(testScenarios);
    
    let payload = { fcmToken };
    
    if (scenarioIndex >= 0 && scenarioIndex < scenarioKeys.length) {
      // Use predefined scenario
      const scenario = testScenarios[scenarioKeys[scenarioIndex]];
      payload = { ...payload, ...scenario };
      console.log(`\n📦 Using ${scenarioKeys[scenarioIndex]} scenario`);
    } else {
      // Custom notification
      console.log('\n📝 Creating custom notification...');
      payload.title = await askQuestion('Title', 'Test Notification');
      payload.message = await askQuestion('Message', 'This is a test message');
      
      const customData = await askQuestion('Custom data (JSON)', '{}');
      try {
        payload.data = JSON.parse(customData);
      } catch {
        payload.data = { custom: customData };
      }
    }
    
    // Choose delivery method
    const method = await askQuestion('Delivery method (sns/api)', 'sns');
    
    console.log('\n🚀 Sending notification...');
    console.log('Payload:', JSON.stringify(payload, null, 2));
    
    let result;
    if (method.toLowerCase() === 'api') {
      result = await sendViaAPI(payload);
    } else {
      result = await sendViaSNS(payload);
    }
    
    displayResults(result, method.toUpperCase());
    
    // Ask for another test
    const again = await askQuestion('Test another notification? (y/n)', 'n');
    if (again.toLowerCase() === 'y') {
      await runNotificationTest();
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
  } finally {
    rl.close();
  }
}

/**
 * Command line usage
 */
function showUsage() {
  console.log(`
🚀 AWS Push Notification Tester

Usage:
  node notification-tester.js                    # Interactive mode
  node notification-tester.js --help             # Show this help
  
Environment Variables:
  AWS_REGION          AWS region (default: us-east-1)
  SNS_TOPIC_ARN       SNS topic ARN for notifications
  API_ENDPOINT        API Gateway endpoint URL

Examples:
  # Interactive testing
  node notification-tester.js
  
  # Set custom configuration
  AWS_REGION=us-west-2 SNS_TOPIC_ARN=arn:aws:sns:us-west-2:123:topic node notification-tester.js
`);
}

// Main execution
if (require.main === module) {
  const args = process.argv.slice(2);
  
  if (args.includes('--help') || args.includes('-h')) {
    showUsage();
    process.exit(0);
  }
  
  // Check required configuration
  if (!config.snsTopicArn.includes('arn:aws:sns')) {
    console.error('❌ Invalid SNS_TOPIC_ARN. Please set a valid SNS topic ARN.');
    process.exit(1);
  }
  
  runNotificationTest().catch(console.error);
}

module.exports = {
  sendViaSNS,
  sendViaAPI,
  validateFCMToken,
  testScenarios
};