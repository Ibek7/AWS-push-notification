const AWS = require('aws-sdk');

/**
 * Enhanced Lambda function with comprehensive monitoring and observability
 * Includes CloudWatch custom metrics, structured logging, and X-Ray tracing
 */

const sns = new AWS.SNS();
const cloudwatch = new AWS.CloudWatch();

// X-Ray tracing
const AWSXRay = require('aws-xray-sdk-core');
const aws = AWSXRay.captureAWS(require('aws-sdk'));

// Environment variables
const SNS_TOPIC_ARN = process.env.SNS_TOPIC_ARN;
const ENVIRONMENT = process.env.ENVIRONMENT || 'prod';

/**
 * Structured logging helper
 */
const logger = {
  info: (message, data = {}) => {
    console.log(JSON.stringify({
      level: 'INFO',
      message,
      timestamp: new Date().toISOString(),
      environment: ENVIRONMENT,
      ...data
    }));
  },
  
  error: (message, error = {}, data = {}) => {
    console.error(JSON.stringify({
      level: 'ERROR',
      message,
      error: {
        name: error.name,
        message: error.message,
        stack: error.stack
      },
      timestamp: new Date().toISOString(),
      environment: ENVIRONMENT,
      ...data
    }));
  },
  
  warn: (message, data = {}) => {
    console.warn(JSON.stringify({
      level: 'WARN',
      message,
      timestamp: new Date().toISOString(),
      environment: ENVIRONMENT,
      ...data
    }));
  }
};

/**
 * Custom CloudWatch metrics helper
 */
const metrics = {
  async putMetric(metricName, value, unit = 'Count', dimensions = {}) {
    const params = {
      Namespace: 'PushNotifications/Application',
      MetricData: [{
        MetricName: metricName,
        Value: value,
        Unit: unit,
        Timestamp: new Date(),
        Dimensions: Object.entries(dimensions).map(([Name, Value]) => ({ Name, Value }))
      }]
    };
    
    try {
      await cloudwatch.putMetricData(params).promise();
    } catch (error) {
      logger.error('Failed to put custom metric', error, { metricName, value });
    }
  },
  
  async incrementCounter(metricName, dimensions = {}) {
    await this.putMetric(metricName, 1, 'Count', dimensions);
  },
  
  async recordLatency(metricName, startTime, dimensions = {}) {
    const duration = Date.now() - startTime;
    await this.putMetric(metricName, duration, 'Milliseconds', dimensions);
  }
};

/**
 * Input validation with monitoring
 */
function validateInput(body) {
  const errors = [];
  
  if (!body.fcmToken) {
    errors.push('Missing FCM token');
  } else if (typeof body.fcmToken !== 'string' || body.fcmToken.length < 10) {
    errors.push('Invalid FCM token format');
  }
  
  if (!body.title) {
    errors.push('Missing notification title');
  } else if (body.title.length > 100) {
    errors.push('Title too long (max 100 characters)');
  }
  
  if (!body.message) {
    errors.push('Missing notification message');
  } else if (body.message.length > 500) {
    errors.push('Message too long (max 500 characters)');
  }
  
  return errors;
}

/**
 * Main Lambda handler with comprehensive monitoring
 */
exports.handler = async (event, context) => {
  const startTime = Date.now();
  const requestId = context.awsRequestId;
  
  // Add request ID to all logs
  const enrichedLogger = {
    info: (message, data = {}) => logger.info(message, { requestId, ...data }),
    error: (message, error = {}, data = {}) => logger.error(message, error, { requestId, ...data }),
    warn: (message, data = {}) => logger.warn(message, { requestId, ...data })
  };
  
  enrichedLogger.info('Lambda function invoked', {
    eventSource: event.Records ? 'SNS' : 'API Gateway',
    environment: ENVIRONMENT
  });
  
  try {
    // Parse request body
    let body;
    try {
      body = JSON.parse(event.body || '{}');
    } catch (parseError) {
      enrichedLogger.error('Failed to parse request body', parseError);
      await metrics.incrementCounter('ParseErrors');
      
      return {
        statusCode: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
          success: false,
          error: 'Invalid JSON in request body'
        })
      };
    }
    
    // Validate input
    const validationErrors = validateInput(body);
    if (validationErrors.length > 0) {
      enrichedLogger.warn('Input validation failed', { errors: validationErrors });
      await metrics.incrementCounter('ValidationErrors');
      
      return {
        statusCode: 400,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*'
        },
        body: JSON.stringify({
          success: false,
          error: 'Validation failed',
          details: validationErrors
        })
      };
    }
    
    // Create SNS message
    const snsMessage = {
      fcmToken: body.fcmToken,
      title: body.title,
      message: body.message,
      data: body.data || {},
      android: body.android || {},
      timestamp: new Date().toISOString(),
      requestId: requestId
    };
    
    // Publish to SNS with X-Ray tracing
    const snsParams = {
      TopicArn: SNS_TOPIC_ARN,
      Message: JSON.stringify(snsMessage),
      MessageAttributes: {
        'notification_type': {
          DataType: 'String',
          StringValue: 'push'
        },
        'environment': {
          DataType: 'String',
          StringValue: ENVIRONMENT
        },
        'request_id': {
          DataType: 'String',
          StringValue: requestId
        }
      }
    };
    
    const snsStartTime = Date.now();
    const snsResult = await sns.publish(snsParams).promise();
    
    // Record metrics
    await metrics.recordLatency('SNSPublishLatency', snsStartTime);
    await metrics.incrementCounter('NotificationsRequested');
    await metrics.recordLatency('TotalRequestLatency', startTime);
    
    enrichedLogger.info('Notification sent successfully', {
      messageId: snsResult.MessageId,
      fcmToken: body.fcmToken.substring(0, 10) + '...', // Log partial token for privacy
      title: body.title
    });
    
    return {
      statusCode: 200,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({
        success: true,
        messageId: snsResult.MessageId,
        timestamp: new Date().toISOString()
      })
    };
    
  } catch (error) {
    // Record error metrics
    await metrics.incrementCounter('LambdaErrors', {
      errorType: error.name || 'UnknownError'
    });
    
    enrichedLogger.error('Lambda function error', error, {
      fcmToken: body?.fcmToken?.substring(0, 10) + '...' || 'unknown'
    });
    
    return {
      statusCode: 500,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*'
      },
      body: JSON.stringify({
        success: false,
        error: 'Internal server error',
        requestId: requestId
      })
    };
  } finally {
    // Always record total execution time
    const totalDuration = Date.now() - startTime;
    enrichedLogger.info('Lambda execution completed', {
      duration: totalDuration,
      memoryUsed: context.memoryLimitInMB
    });
  }
};