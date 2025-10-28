const AWS = require('aws-sdk');
const nock = require('nock');

describe('AWS SNS Integration Tests', () => {
  let sns;
  
  beforeAll(() => {
    sns = new AWS.SNS({
      region: 'us-east-1',
      endpoint: 'http://localhost:4566' // LocalStack endpoint for testing
    });
  });
  
  beforeEach(() => {
    nock.cleanAll();
  });
  
  describe('Topic Operations', () => {
    test('should create SNS topic', async () => {
      const topicName = 'test-push-notifications';
      
      nock('http://localhost:4566')
        .post('/')
        .reply(200, `
          <CreateTopicResponse>
            <CreateTopicResult>
              <TopicArn>arn:aws:sns:us-east-1:123456789012:${topicName}</TopicArn>
            </CreateTopicResult>
          </CreateTopicResponse>
        `);
      
      const result = await sns.createTopic({ Name: topicName }).promise();
      expect(result.TopicArn).toContain(topicName);
    });
    
    test('should list existing topics', async () => {
      nock('http://localhost:4566')
        .post('/')
        .reply(200, `
          <ListTopicsResponse>
            <ListTopicsResult>
              <Topics>
                <member>
                  <TopicArn>arn:aws:sns:us-east-1:123456789012:push-notifications</TopicArn>
                </member>
              </Topics>
            </ListTopicsResult>
          </ListTopicsResponse>
        `);
      
      const result = await sns.listTopics().promise();
      expect(result.Topics).toHaveLength(1);
      expect(result.Topics[0].TopicArn).toContain('push-notifications');
    });
  });
  
  describe('Message Publishing', () => {
    const topicArn = 'arn:aws:sns:us-east-1:123456789012:push-notifications';
    
    test('should publish notification message', async () => {
      const message = {
        fcmToken: global.testUtils.mockFcmToken,
        title: 'Integration Test',
        body: 'Testing SNS integration',
        data: { source: 'integration-test' }
      };
      
      nock('http://localhost:4566')
        .post('/')
        .reply(200, `
          <PublishResponse>
            <PublishResult>
              <MessageId>integration-test-message-id</MessageId>
            </PublishResult>
          </PublishResponse>
        `);
      
      const result = await sns.publish({
        TopicArn: topicArn,
        Message: JSON.stringify(message),
        MessageAttributes: {
          'notification_type': {
            DataType: 'String',
            StringValue: 'push'
          }
        }
      }).promise();
      
      expect(result.MessageId).toBe('integration-test-message-id');
    });
    
    test('should handle publish failures', async () => {
      nock('http://localhost:4566')
        .post('/')
        .reply(500, 'Internal Server Error');
      
      await expect(
        sns.publish({
          TopicArn: topicArn,
          Message: 'test message'
        }).promise()
      ).rejects.toThrow();
    });
  });
  
  describe('Subscription Management', () => {
    const topicArn = 'arn:aws:sns:us-east-1:123456789012:push-notifications';
    const lambdaArn = 'arn:aws:lambda:us-east-1:123456789012:function:processNotification';
    
    test('should subscribe Lambda to SNS topic', async () => {
      nock('http://localhost:4566')
        .post('/')
        .reply(200, `
          <SubscribeResponse>
            <SubscribeResult>
              <SubscriptionArn>arn:aws:sns:us-east-1:123456789012:push-notifications:lambda-subscription</SubscriptionArn>
            </SubscribeResult>
          </SubscribeResponse>
        `);
      
      const result = await sns.subscribe({
        TopicArn: topicArn,
        Protocol: 'lambda',
        Endpoint: lambdaArn
      }).promise();
      
      expect(result.SubscriptionArn).toContain('lambda-subscription');
    });
    
    test('should list topic subscriptions', async () => {
      nock('http://localhost:4566')
        .post('/')
        .reply(200, `
          <ListSubscriptionsByTopicResponse>
            <ListSubscriptionsByTopicResult>
              <Subscriptions>
                <member>
                  <SubscriptionArn>arn:aws:sns:us-east-1:123456789012:push-notifications:lambda-sub</SubscriptionArn>
                  <Protocol>lambda</Protocol>
                  <Endpoint>${lambdaArn}</Endpoint>
                </member>
              </Subscriptions>
            </ListSubscriptionsByTopicResult>
          </ListSubscriptionsByTopicResponse>
        `);
      
      const result = await sns.listSubscriptionsByTopic({
        TopicArn: topicArn
      }).promise();
      
      expect(result.Subscriptions).toHaveLength(1);
      expect(result.Subscriptions[0].Protocol).toBe('lambda');
    });
  });
});