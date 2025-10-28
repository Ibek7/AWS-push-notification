const admin = require('firebase-admin');
const nock = require('nock');

describe('Firebase FCM Integration Tests', () => {
  let messaging;
  
  beforeAll(async () => {
    // Mock Firebase credentials for testing
    const mockServiceAccount = {
      type: 'service_account',
      project_id: 'test-project',
      private_key_id: 'test-key-id',
      private_key: '-----BEGIN PRIVATE KEY-----\ntest-private-key\n-----END PRIVATE KEY-----\n',
      client_email: 'test@test-project.iam.gserviceaccount.com',
      client_id: 'test-client-id',
      auth_uri: 'https://accounts.google.com/o/oauth2/auth',
      token_uri: 'https://oauth2.googleapis.com/token'
    };
    
    if (!admin.apps.length) {
      admin.initializeApp({
        credential: admin.credential.cert(mockServiceAccount)
      });
    }
    
    messaging = admin.messaging();
  });
  
  describe('Token Validation', () => {
    test('should validate FCM token format', async () => {
      // Mock FCM API response for token validation
      nock('https://fcm.googleapis.com')
        .post('/v1/projects/test-project/messages:send')
        .reply(200, {
          name: 'projects/test-project/messages/valid-message-id'
        });
      
      const validToken = 'valid-fcm-token-12345-abcdef';
      const message = {
        token: validToken,
        notification: {
          title: 'Test',
          body: 'Token validation test'
        }
      };
      
      const result = await messaging.send(message);
      expect(result).toContain('valid-message-id');
    });
    
    test('should reject invalid FCM tokens', async () => {
      nock('https://fcm.googleapis.com')
        .post('/v1/projects/test-project/messages:send')
        .reply(400, {
          error: {
            code: 400,
            message: 'Invalid FCM token',
            status: 'INVALID_ARGUMENT'
          }
        });
      
      const invalidToken = 'invalid-token';
      const message = {
        token: invalidToken,
        notification: global.testUtils.mockNotification
      };
      
      await expect(messaging.send(message)).rejects.toThrow();
    });
  });
  
  describe('Message Delivery', () => {
    test('should deliver notification successfully', async () => {
      nock('https://fcm.googleapis.com')
        .post('/v1/projects/test-project/messages:send')
        .reply(200, {
          name: 'projects/test-project/messages/delivery-success-id'
        });
      
      const message = {
        token: global.testUtils.mockFcmToken,
        notification: {
          title: 'Integration Test Notification',
          body: 'Testing FCM message delivery'
        },
        data: {
          type: 'integration-test',
          timestamp: Date.now().toString()
        },
        android: {
          priority: 'high',
          notification: {
            sound: 'default',
            channelId: 'push_notifications'
          }
        }
      };
      
      const result = await messaging.send(message);
      expect(result).toContain('delivery-success-id');
    });
    
    test('should handle delivery failures gracefully', async () => {
      nock('https://fcm.googleapis.com')
        .post('/v1/projects/test-project/messages:send')
        .reply(500, {
          error: {
            code: 500,
            message: 'Internal server error',
            status: 'INTERNAL'
          }
        });
      
      const message = {
        token: global.testUtils.mockFcmToken,
        notification: global.testUtils.mockNotification
      };
      
      await expect(messaging.send(message)).rejects.toThrow();
    });
  });
  
  describe('Multicast Messages', () => {
    test('should send to multiple tokens', async () => {
      nock('https://fcm.googleapis.com')
        .post('/v1/projects/test-project/messages:send')
        .times(3)
        .reply(200, (uri, requestBody) => ({
          name: `projects/test-project/messages/multicast-${Date.now()}`
        }));
      
      const tokens = [
        'token-1-12345',
        'token-2-67890',
        'token-3-abcdef'
      ];
      
      const message = {
        tokens: tokens,
        notification: {
          title: 'Multicast Test',
          body: 'Testing multicast delivery'
        }
      };
      
      const result = await messaging.sendMulticast(message);
      expect(result.successCount).toBe(3);
      expect(result.failureCount).toBe(0);
    });
    
    test('should handle partial multicast failures', async () => {
      // Mock successful responses for 2 tokens, failure for 1
      nock('https://fcm.googleapis.com')
        .post('/v1/projects/test-project/messages:send')
        .times(2)
        .reply(200, {
          name: 'projects/test-project/messages/success-id'
        })
        .post('/v1/projects/test-project/messages:send')
        .reply(400, {
          error: {
            code: 400,
            message: 'Invalid token',
            status: 'INVALID_ARGUMENT'
          }
        });
      
      const tokens = ['valid-token-1', 'valid-token-2', 'invalid-token'];
      const message = {
        tokens: tokens,
        notification: global.testUtils.mockNotification
      };
      
      const result = await messaging.sendMulticast(message);
      expect(result.successCount).toBe(2);
      expect(result.failureCount).toBe(1);
    });
  });
  
  describe('Topic Messaging', () => {
    test('should send to topic subscribers', async () => {
      nock('https://fcm.googleapis.com')
        .post('/v1/projects/test-project/messages:send')
        .reply(200, {
          name: 'projects/test-project/messages/topic-message-id'
        });
      
      const message = {
        topic: 'news',
        notification: {
          title: 'Breaking News',
          body: 'Important news update'
        },
        data: {
          category: 'news',
          priority: 'high'
        }
      };
      
      const result = await messaging.send(message);
      expect(result).toContain('topic-message-id');
    });
  });
});