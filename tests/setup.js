// Global test setup
process.env.NODE_ENV = 'test';

// AWS SDK Mock setup
const AWSMock = require('aws-sdk-mock');
const AWS = require('aws-sdk');

// Mock AWS services for testing
beforeAll(() => {
  // Configure AWS for testing
  AWS.config.update({
    region: 'us-east-1',
    accessKeyId: 'test-access-key',
    secretAccessKey: 'test-secret-key'
  });
});

afterAll(() => {
  // Restore AWS services
  AWSMock.restore();
});

// Global test utilities
global.testUtils = {
  // Mock FCM token
  mockFcmToken: 'mock-fcm-token-12345',
  
  // Mock device data
  mockDevice: {
    platform: 'android',
    version: '11',
    model: 'Pixel 5'
  },
  
  // Mock notification payload
  mockNotification: {
    title: 'Test Notification',
    body: 'This is a test notification',
    data: {
      type: 'test',
      timestamp: Date.now()
    }
  },
  
  // Wait utility for async tests
  wait: (ms) => new Promise(resolve => setTimeout(resolve, ms))
};