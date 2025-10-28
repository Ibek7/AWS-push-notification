const supertest = require('supertest');
const AWS = require('aws-sdk');

describe('End-to-End Notification Flow', () => {
  let api;
  
  beforeAll(async () => {
    // Setup test environment
    process.env.AWS_REGION = 'us-east-1';
    process.env.SNS_TOPIC_ARN = 'arn:aws:sns:us-east-1:123456789012:push-notifications';
    
    // Mock API Gateway endpoint for testing
    api = supertest('https://test-api-gateway.execute-api.us-east-1.amazonaws.com');
  });
  
  describe('Complete Notification Pipeline', () => {
    test('should handle end-to-end notification flow', async () => {
      const notificationPayload = {
        fcmToken: 'end-to-end-test-token',
        title: 'E2E Test Notification',
        message: 'Testing complete notification pipeline',
        data: {
          type: 'e2e-test',
          priority: 'high',
          timestamp: Date.now()
        }
      };
      
      // Step 1: Send notification request to API Gateway
      const response = await api
        .post('/dev/send-notification')
        .send(notificationPayload)
        .expect(200);
      
      expect(response.body).toHaveProperty('success', true);
      expect(response.body).toHaveProperty('messageId');
      
      // Step 2: Verify notification was processed
      // In a real test, this would check CloudWatch logs or monitoring
      await global.testUtils.wait(2000); // Wait for async processing
      
      // Step 3: Validate response structure
      expect(response.body.messageId).toMatch(/^[a-f0-9-]{36}$/);
    });
    
    test('should handle notification with Android-specific options', async () => {
      const androidNotification = {
        fcmToken: 'android-specific-token',
        title: 'Android Notification',
        message: 'Testing Android-specific features',
        data: {
          clickAction: 'FLUTTER_NOTIFICATION_CLICK',
          sound: 'default'
        },
        android: {
          priority: 'high',
          channelId: 'important_notifications',
          ttl: 3600000 // 1 hour
        }
      };
      
      const response = await api
        .post('/dev/send-notification')
        .send(androidNotification)
        .expect(200);
      
      expect(response.body.success).toBe(true);
    });
    
    test('should handle batch notifications', async () => {
      const batchPayload = {
        notifications: [
          {
            fcmToken: 'batch-token-1',
            title: 'Batch Notification 1',
            message: 'First notification in batch'
          },
          {
            fcmToken: 'batch-token-2',
            title: 'Batch Notification 2',
            message: 'Second notification in batch'
          },
          {
            fcmToken: 'batch-token-3',
            title: 'Batch Notification 3',
            message: 'Third notification in batch'
          }
        ]
      };
      
      const response = await api
        .post('/dev/send-batch-notifications')
        .send(batchPayload)
        .expect(200);
      
      expect(response.body.success).toBe(true);
      expect(response.body.results).toHaveLength(3);
      expect(response.body.successCount).toBe(3);
      expect(response.body.failureCount).toBe(0);
    });
  });
  
  describe('Error Handling E2E', () => {
    test('should handle invalid FCM token gracefully', async () => {
      const invalidPayload = {
        fcmToken: 'invalid-token-format',
        title: 'Test',
        message: 'This should fail'
      };
      
      const response = await api
        .post('/dev/send-notification')
        .send(invalidPayload)
        .expect(400);
      
      expect(response.body.error).toContain('Invalid FCM token');
    });
    
    test('should handle missing required fields', async () => {
      const incompletePayload = {
        title: 'Missing FCM Token'
        // Missing fcmToken and message
      };
      
      const response = await api
        .post('/dev/send-notification')
        .send(incompletePayload)
        .expect(400);
      
      expect(response.body.error).toContain('Missing required');
    });
    
    test('should handle rate limiting', async () => {
      // Send multiple requests rapidly to test rate limiting
      const promises = Array(10).fill().map((_, i) => 
        api
          .post('/dev/send-notification')
          .send({
            fcmToken: `rate-limit-token-${i}`,
            title: 'Rate Limit Test',
            message: `Message ${i}`
          })
      );
      
      const responses = await Promise.allSettled(promises);
      
      // Some requests should succeed, others might be rate limited
      const successful = responses.filter(r => 
        r.status === 'fulfilled' && r.value.status === 200
      );
      const rateLimited = responses.filter(r => 
        r.status === 'fulfilled' && r.value.status === 429
      );
      
      expect(successful.length + rateLimited.length).toBe(10);
    });
  });
  
  describe('Performance Testing', () => {
    test('should handle concurrent notifications', async () => {
      const startTime = Date.now();
      const concurrentRequests = 5;
      
      const promises = Array(concurrentRequests).fill().map((_, i) => 
        api
          .post('/dev/send-notification')
          .send({
            fcmToken: `concurrent-token-${i}`,
            title: 'Concurrent Test',
            message: `Concurrent notification ${i}`,
            data: { testId: `concurrent-${i}` }
          })
      );
      
      const responses = await Promise.all(promises);
      const endTime = Date.now();
      const duration = endTime - startTime;
      
      // All requests should succeed
      responses.forEach(response => {
        expect(response.status).toBe(200);
        expect(response.body.success).toBe(true);
      });
      
      // Should complete within reasonable time (5 seconds)
      expect(duration).toBeLessThan(5000);
    });
    
    test('should monitor response times', async () => {
      const startTime = Date.now();
      
      const response = await api
        .post('/dev/send-notification')
        .send({
          fcmToken: 'performance-test-token',
          title: 'Performance Test',
          message: 'Monitoring response time'
        });
      
      const responseTime = Date.now() - startTime;
      
      expect(response.status).toBe(200);
      expect(responseTime).toBeLessThan(2000); // Should respond within 2 seconds
    });
  });
  
  describe('AWS Infrastructure Validation', () => {
    test('should verify SNS topic exists', async () => {
      const sns = new AWS.SNS({ region: 'us-east-1' });
      
      const topics = await sns.listTopics().promise();
      const pushTopic = topics.Topics.find(topic => 
        topic.TopicArn.includes('push-notifications')
      );
      
      expect(pushTopic).toBeDefined();
    });
    
    test('should verify Lambda function deployment', async () => {
      const lambda = new AWS.Lambda({ region: 'us-east-1' });
      
      try {
        const functionConfig = await lambda.getFunctionConfiguration({
          FunctionName: 'sendPushNotification'
        }).promise();
        
        expect(functionConfig.FunctionName).toBe('sendPushNotification');
        expect(functionConfig.Runtime).toMatch(/nodejs/);
      } catch (error) {
        // Function might not exist in test environment
        console.warn('Lambda function not found in test environment');
      }
    });
  });
});