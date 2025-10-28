const admin = require('firebase-admin');
const test = require('firebase-functions-test')();

// Mock Firebase service class
class FirebaseService {
  constructor() {
    this.initialized = false;
  }
  
  initialize(serviceAccount) {
    if (!this.initialized) {
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount)
      });
      this.initialized = true;
    }
  }
  
  async sendNotification(fcmToken, payload) {
    const message = {
      token: fcmToken,
      notification: {
        title: payload.title,
        body: payload.body
      },
      data: payload.data || {}
    };
    
    return admin.messaging().send(message);
  }
  
  async sendToMultipleDevices(tokens, payload) {
    const message = {
      tokens: tokens,
      notification: {
        title: payload.title,
        body: payload.body
      },
      data: payload.data || {}
    };
    
    return admin.messaging().sendMulticast(message);
  }
}

describe('Firebase Service Unit Tests', () => {
  let firebaseService;
  
  beforeAll(() => {
    // Mock Firebase Admin SDK
    jest.mock('firebase-admin', () => ({
      initializeApp: jest.fn(),
      credential: {
        cert: jest.fn()
      },
      messaging: () => ({
        send: jest.fn().mockResolvedValue({ messageId: 'mock-message-id' }),
        sendMulticast: jest.fn().mockResolvedValue({
          successCount: 2,
          failureCount: 0,
          responses: [
            { success: true, messageId: 'msg1' },
            { success: true, messageId: 'msg2' }
          ]
        })
      })
    }));
    
    firebaseService = new FirebaseService();
  });
  
  beforeEach(() => {
    jest.clearAllMocks();
  });
  
  describe('Initialization', () => {
    test('should initialize Firebase Admin SDK', () => {
      const mockServiceAccount = {
        type: 'service_account',
        project_id: 'test-project'
      };
      
      firebaseService.initialize(mockServiceAccount);
      expect(firebaseService.initialized).toBe(true);
    });
  });
  
  describe('Single Device Notifications', () => {
    test('should send notification to single device', async () => {
      const mockPayload = {
        title: 'Test Notification',
        body: 'Test message',
        data: { type: 'test' }
      };
      
      const result = await firebaseService.sendNotification(
        global.testUtils.mockFcmToken,
        mockPayload
      );
      
      expect(result).toHaveProperty('messageId');
    });
    
    test('should handle invalid FCM token', async () => {
      const mockPayload = global.testUtils.mockNotification;
      
      admin.messaging().send.mockRejectedValueOnce(
        new Error('Invalid FCM token')
      );
      
      await expect(
        firebaseService.sendNotification('invalid-token', mockPayload)
      ).rejects.toThrow('Invalid FCM token');
    });
  });
  
  describe('Multiple Device Notifications', () => {
    test('should send notification to multiple devices', async () => {
      const tokens = ['token1', 'token2'];
      const mockPayload = global.testUtils.mockNotification;
      
      const result = await firebaseService.sendToMultipleDevices(
        tokens,
        mockPayload
      );
      
      expect(result.successCount).toBe(2);
      expect(result.failureCount).toBe(0);
    });
    
    test('should handle partial failures', async () => {
      admin.messaging().sendMulticast.mockResolvedValueOnce({
        successCount: 1,
        failureCount: 1,
        responses: [
          { success: true, messageId: 'msg1' },
          { success: false, error: { code: 'messaging/invalid-token' } }
        ]
      });
      
      const tokens = ['valid-token', 'invalid-token'];
      const result = await firebaseService.sendToMultipleDevices(
        tokens,
        global.testUtils.mockNotification
      );
      
      expect(result.successCount).toBe(1);
      expect(result.failureCount).toBe(1);
    });
  });
  
  describe('Payload Validation', () => {
    test('should validate notification payload structure', async () => {
      const invalidPayload = {
        // Missing required title
        body: 'Test message'
      };
      
      await expect(
        firebaseService.sendNotification(
          global.testUtils.mockFcmToken,
          invalidPayload
        )
      ).rejects.toThrow();
    });
    
    test('should accept valid payload with data', async () => {
      const validPayload = {
        title: 'Test',
        body: 'Test message',
        data: {
          customKey: 'customValue',
          timestamp: Date.now().toString()
        }
      };
      
      const result = await firebaseService.sendNotification(
        global.testUtils.mockFcmToken,
        validPayload
      );
      
      expect(result).toHaveProperty('messageId');
    });
  });
});

module.exports = FirebaseService;