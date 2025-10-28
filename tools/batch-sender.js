#!/usr/bin/env node

/**
 * Batch Notification Sender
 * Sends multiple notifications efficiently with proper error handling and rate limiting
 */

const AWS = require('aws-sdk');
const fs = require('fs');
const path = require('path');

const sns = new AWS.SNS({
  region: process.env.AWS_REGION || 'us-east-1'
});

/**
 * Batch sender class
 */
class BatchNotificationSender {
  constructor(options = {}) {
    this.snsTopicArn = options.snsTopicArn || process.env.SNS_TOPIC_ARN;
    this.batchSize = options.batchSize || 10;
    this.delayBetweenBatches = options.delayBetweenBatches || 1000; // 1 second
    this.maxRetries = options.maxRetries || 3;
    this.retryDelay = options.retryDelay || 2000; // 2 seconds
  }

  /**
   * Validate notification payload
   */
  validateNotification(notification) {
    const errors = [];
    
    if (!notification.fcmToken) {
      errors.push('Missing fcmToken');
    }
    
    if (!notification.title && !notification.data) {
      errors.push('Must have either title or data');
    }
    
    if (notification.title && notification.title.length > 100) {
      errors.push('Title too long (max 100 characters)');
    }
    
    if (notification.message && notification.message.length > 500) {
      errors.push('Message too long (max 500 characters)');
    }
    
    return errors;
  }

  /**
   * Send single notification with retry logic
   */
  async sendSingleNotification(notification, retryCount = 0) {
    try {
      const message = {
        ...notification,
        timestamp: new Date().toISOString(),
        batchId: notification.batchId || 'manual'
      };

      const params = {
        TopicArn: this.snsTopicArn,
        Message: JSON.stringify(message),
        MessageAttributes: {
          'notification_type': {
            DataType: 'String',
            StringValue: 'push'
          },
          'batch_mode': {
            DataType: 'String',
            StringValue: 'true'
          }
        }
      };

      const result = await sns.publish(params).promise();
      
      return {
        success: true,
        messageId: result.MessageId,
        fcmToken: notification.fcmToken.substring(0, 10) + '...'
      };
      
    } catch (error) {
      if (retryCount < this.maxRetries) {
        console.log(`⚠️  Retrying notification (attempt ${retryCount + 1}/${this.maxRetries})...`);
        await this.delay(this.retryDelay);
        return this.sendSingleNotification(notification, retryCount + 1);
      }
      
      return {
        success: false,
        error: error.message,
        fcmToken: notification.fcmToken.substring(0, 10) + '...'
      };
    }
  }

  /**
   * Process notifications in batches
   */
  async sendBatch(notifications) {
    const results = [];
    const totalBatches = Math.ceil(notifications.length / this.batchSize);
    
    console.log(`📦 Processing ${notifications.length} notifications in ${totalBatches} batches...`);
    
    for (let i = 0; i < notifications.length; i += this.batchSize) {
      const batch = notifications.slice(i, i + this.batchSize);
      const batchNumber = Math.floor(i / this.batchSize) + 1;
      
      console.log(`📤 Processing batch ${batchNumber}/${totalBatches} (${batch.length} notifications)...`);
      
      // Process batch in parallel
      const batchPromises = batch.map(notification => 
        this.sendSingleNotification(notification)
      );
      
      const batchResults = await Promise.all(batchPromises);
      results.push(...batchResults);
      
      // Progress update
      const processed = Math.min(i + this.batchSize, notifications.length);
      const successCount = batchResults.filter(r => r.success).length;
      console.log(`✅ Batch ${batchNumber} completed: ${successCount}/${batch.length} successful`);
      
      // Rate limiting delay between batches
      if (i + this.batchSize < notifications.length) {
        console.log(`⏳ Waiting ${this.delayBetweenBatches}ms before next batch...`);
        await this.delay(this.delayBetweenBatches);
      }
    }
    
    return results;
  }

  /**
   * Generate summary report
   */
  generateSummary(results) {
    const successful = results.filter(r => r.success);
    const failed = results.filter(r => !r.success);
    
    const summary = {
      total: results.length,
      successful: successful.length,
      failed: failed.length,
      successRate: results.length > 0 ? (successful.length / results.length * 100).toFixed(2) : 0,
      timestamp: new Date().toISOString()
    };

    // Group errors
    const errorCounts = {};
    failed.forEach(result => {
      const error = result.error || 'Unknown error';
      errorCounts[error] = (errorCounts[error] || 0) + 1;
    });

    return {
      summary,
      errorCounts,
      failedNotifications: failed.slice(0, 10), // First 10 failures for review
      sampleSuccesses: successful.slice(0, 5)   // First 5 successes for confirmation
    };
  }

  /**
   * Delay helper
   */
  delay(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}

/**
 * Load notifications from file
 */
function loadNotificationsFromFile(filePath) {
  try {
    const content = fs.readFileSync(filePath, 'utf8');
    let notifications;
    
    try {
      const parsed = JSON.parse(content);
      notifications = Array.isArray(parsed) ? parsed : parsed.notifications;
    } catch {
      // Parse CSV format
      const lines = content.split('\n').filter(line => line.trim());
      const headers = lines[0].split(',').map(h => h.trim());
      
      notifications = lines.slice(1).map(line => {
        const values = line.split(',').map(v => v.trim());
        const notification = {};
        headers.forEach((header, index) => {
          notification[header] = values[index];
        });
        return notification;
      });
    }
    
    if (!Array.isArray(notifications)) {
      throw new Error('File must contain an array of notifications');
    }
    
    return notifications;
  } catch (error) {
    throw new Error(`Failed to load notifications from ${filePath}: ${error.message}`);
  }
}

/**
 * Generate sample notification file
 */
function generateSampleFile(count = 10, outputPath = 'sample-notifications.json') {
  const notifications = [];
  
  for (let i = 1; i <= count; i++) {
    notifications.push({
      fcmToken: `sample-token-${i.toString().padStart(3, '0')}-${Math.random().toString(36).substr(2, 9)}`,
      title: `Sample Notification ${i}`,
      message: `This is sample notification number ${i} for testing purposes.`,
      data: {
        type: 'sample',
        notificationId: i,
        timestamp: Date.now()
      }
    });
  }
  
  fs.writeFileSync(outputPath, JSON.stringify(notifications, null, 2));
  console.log(`📄 Generated ${count} sample notifications in ${outputPath}`);
}

/**
 * Display results summary
 */
function displaySummary(report) {
  console.log('\n' + '='.repeat(60));
  console.log('📊 BATCH NOTIFICATION SUMMARY');
  console.log('='.repeat(60));
  
  const { summary, errorCounts, failedNotifications } = report;
  
  console.log(`📝 Total Notifications: ${summary.total}`);
  console.log(`✅ Successful: ${summary.successful} (${summary.successRate}%)`);
  console.log(`❌ Failed: ${summary.failed}`);
  console.log(`⏰ Timestamp: ${summary.timestamp}`);
  
  if (summary.failed > 0) {
    console.log('\n❌ ERROR BREAKDOWN:');
    Object.entries(errorCounts).forEach(([error, count]) => {
      console.log(`  ${count}x ${error}`);
    });
    
    if (failedNotifications.length > 0) {
      console.log('\n🔍 SAMPLE FAILURES:');
      failedNotifications.slice(0, 3).forEach(failure => {
        console.log(`  ${failure.fcmToken}: ${failure.error}`);
      });
    }
  }
  
  console.log('\n' + '='.repeat(60));
}

/**
 * Main CLI function
 */
async function main() {
  const args = process.argv.slice(2);
  
  if (args.includes('--help') || args.includes('-h')) {
    console.log(`
📤 Batch Notification Sender

Usage:
  node batch-sender.js --file <path> [options]
  node batch-sender.js --generate <count> [options]

Options:
  --file <path>              Path to file containing notifications (JSON or CSV)
  --generate <count>         Generate sample notification file
  --batch-size <number>      Notifications per batch (default: 10)
  --delay <ms>              Delay between batches (default: 1000ms)
  --max-retries <number>     Maximum retry attempts (default: 3)
  --output <path>           Save results to file
  --topic-arn <arn>         SNS Topic ARN (or set SNS_TOPIC_ARN env var)

Examples:
  # Send notifications from file
  node batch-sender.js --file notifications.json
  
  # Generate sample file
  node batch-sender.js --generate 100 --output sample.json
  
  # Custom batch configuration
  node batch-sender.js --file notifications.json --batch-size 20 --delay 2000
  
  # Save detailed results
  node batch-sender.js --file notifications.json --output results.json
`);
    process.exit(0);
  }

  const fileIndex = args.indexOf('--file');
  const generateIndex = args.indexOf('--generate');
  const batchSizeIndex = args.indexOf('--batch-size');
  const delayIndex = args.indexOf('--delay');
  const maxRetriesIndex = args.indexOf('--max-retries');
  const outputIndex = args.indexOf('--output');
  const topicArnIndex = args.indexOf('--topic-arn');

  // Generate sample file mode
  if (generateIndex !== -1) {
    const count = parseInt(args[generateIndex + 1]) || 10;
    const outputPath = outputIndex !== -1 ? args[outputIndex + 1] : 'sample-notifications.json';
    generateSampleFile(count, outputPath);
    return;
  }

  // Validate required parameters
  if (fileIndex === -1) {
    console.error('❌ Please specify --file or --generate');
    process.exit(1);
  }

  const filePath = args[fileIndex + 1];
  const snsTopicArn = topicArnIndex !== -1 ? args[topicArnIndex + 1] : process.env.SNS_TOPIC_ARN;

  if (!snsTopicArn) {
    console.error('❌ Please specify SNS Topic ARN via --topic-arn or SNS_TOPIC_ARN environment variable');
    process.exit(1);
  }

  const options = {
    snsTopicArn,
    batchSize: batchSizeIndex !== -1 ? parseInt(args[batchSizeIndex + 1]) : 10,
    delayBetweenBatches: delayIndex !== -1 ? parseInt(args[delayIndex + 1]) : 1000,
    maxRetries: maxRetriesIndex !== -1 ? parseInt(args[maxRetriesIndex + 1]) : 3
  };

  try {
    console.log('📤 AWS Push Notification Batch Sender');
    console.log('=====================================');
    
    // Load notifications
    const notifications = loadNotificationsFromFile(filePath);
    console.log(`📁 Loaded ${notifications.length} notifications from ${filePath}`);
    
    // Validate notifications
    const validationErrors = [];
    notifications.forEach((notification, index) => {
      const errors = new BatchNotificationSender().validateNotification(notification);
      if (errors.length > 0) {
        validationErrors.push(`Notification ${index + 1}: ${errors.join(', ')}`);
      }
    });
    
    if (validationErrors.length > 0) {
      console.error('❌ Validation errors found:');
      validationErrors.slice(0, 5).forEach(error => console.error(`  ${error}`));
      if (validationErrors.length > 5) {
        console.error(`  ... and ${validationErrors.length - 5} more errors`);
      }
      process.exit(1);
    }
    
    console.log('✅ All notifications validated successfully');
    
    // Send notifications
    const sender = new BatchNotificationSender(options);
    const results = await sender.sendBatch(notifications);
    
    // Generate and display summary
    const report = sender.generateSummary(results);
    displaySummary(report);
    
    // Save results if requested
    const outputPath = outputIndex !== -1 ? args[outputIndex + 1] : null;
    if (outputPath) {
      fs.writeFileSync(outputPath, JSON.stringify({ ...report, results }, null, 2));
      console.log(`💾 Detailed results saved to: ${outputPath}`);
    }
    
    // Exit with appropriate code
    process.exit(report.summary.failed > 0 ? 1 : 0);
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    process.exit(1);
  }
}

// Run if called directly
if (require.main === module) {
  main();
}

module.exports = BatchNotificationSender;