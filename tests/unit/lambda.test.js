const AWS = require('aws-sdk');
const AWSMock = require('aws-sdk-mock');

describe('Lambda Function Unit Tests', () => {
  let lambda;
  
  beforeEach(() => {
    // Mock SNS service
    AWSMock.mock('SNS', 'publish', (params, callback) => {
      callback(null, {
        MessageId: 'mock-message-id-12345'
      });
    });
    
    lambda = require('../../AWS-Push-Notifications/Source-Code/Lambda-Function/index');
  });
  
  afterEach(() => {
    AWSMock.restore('SNS');
  });
  
  describe('Input Validation', () => {
    test('should validate required parameters', async () => {
      const event = {
        body: JSON.stringify({})
      };
      
      const result = await lambda.handler(event);
      const response = JSON.parse(result.body);
      
      expect(result.statusCode).toBe(400);
      expect(response.error).toContain('Missing required parameters');
    });
    
    test('should validate FCM token format', async () => {
      const event = {
        body: JSON.stringify({
          fcmToken: 'invalid-token',
          title: 'Test',
          message: 'Test message'
        })
      };
      
      const result = await lambda.handler(event);
      expect(result.statusCode).toBe(400);
    });
    
    test('should accept valid notification payload', async () => {
      const event = {
        body: JSON.stringify({
          fcmToken: 'valid-fcm-token-12345',
          title: 'Test Notification',
          message: 'This is a test message',
          data: { type: 'test' }
        })
      };
      
      const result = await lambda.handler(event);
      expect(result.statusCode).toBe(200);
    });
  });
  
  describe('SNS Integration', () => {
    test('should publish to SNS with correct parameters', async () => {
      const mockPublish = jest.fn().mockResolvedValue({
        MessageId: 'test-message-id'
      });
      
      AWSMock.remock('SNS', 'publish', mockPublish);
      
      const event = {
        body: JSON.stringify({
          fcmToken: global.testUtils.mockFcmToken,
          title: 'Test',
          message: 'Test message'
        })
      };
      
      await lambda.handler(event);
      
      expect(mockPublish).toHaveBeenCalledWith(
        expect.objectContaining({
          TopicArn: expect.stringContaining('push-notifications'),
          Message: expect.stringContaining('fcmToken')
        })
      );
    });
  });
  
  describe('Error Handling', () => {
    test('should handle SNS publish errors', async () => {
      AWSMock.remock('SNS', 'publish', (params, callback) => {
        callback(new Error('SNS publish failed'));
      });
      
      const event = {
        body: JSON.stringify({
          fcmToken: global.testUtils.mockFcmToken,
          title: 'Test',
          message: 'Test message'
        })
      };
      
      const result = await lambda.handler(event);
      expect(result.statusCode).toBe(500);
    });
    
    test('should handle malformed JSON', async () => {
      const event = {
        body: 'invalid-json'
      };
      
      const result = await lambda.handler(event);
      expect(result.statusCode).toBe(400);
    });
  });
});