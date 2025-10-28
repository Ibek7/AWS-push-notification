#!/usr/bin/env node

/**
 * CloudWatch Log Analyzer
 * Analyzes and parses CloudWatch logs for insights and troubleshooting
 */

const AWS = require('aws-sdk');
const fs = require('fs');

const cloudWatchLogs = new AWS.CloudWatchLogs({
  region: process.env.AWS_REGION || 'us-east-1'
});

/**
 * Log analyzer class
 */
class LogAnalyzer {
  constructor() {
    this.logGroups = [
      '/aws/lambda/sendPushNotification',
      '/aws/apigateway/push-notifications'
    ];
  }

  /**
   * Get log events from CloudWatch
   */
  async getLogEvents(logGroupName, options = {}) {
    const {
      hours = 24,
      filterPattern = '',
      maxEvents = 1000
    } = options;

    const startTime = Date.now() - (hours * 60 * 60 * 1000);
    const endTime = Date.now();

    try {
      const params = {
        logGroupName,
        startTime,
        endTime,
        filterPattern,
        limit: maxEvents
      };

      const result = await cloudWatchLogs.filterLogEvents(params).promise();
      return result.events || [];
    } catch (error) {
      console.error(`❌ Error fetching logs from ${logGroupName}:`, error.message);
      return [];
    }
  }

  /**
   * Parse structured log messages
   */
  parseLogMessage(message) {
    try {
      // Try parsing as JSON (structured logs)
      const parsed = JSON.parse(message);
      return {
        structured: true,
        level: parsed.level,
        message: parsed.message,
        timestamp: parsed.timestamp,
        requestId: parsed.requestId,
        data: parsed
      };
    } catch {
      // Parse unstructured logs
      const parts = message.split('\t');
      return {
        structured: false,
        level: this.extractLogLevel(message),
        message: message,
        timestamp: parts[0] || null,
        requestId: parts[1] || null,
        data: { raw: message }
      };
    }
  }

  /**
   * Extract log level from unstructured messages
   */
  extractLogLevel(message) {
    if (message.includes('ERROR')) return 'ERROR';
    if (message.includes('WARN')) return 'WARN';
    if (message.includes('INFO')) return 'INFO';
    if (message.includes('DEBUG')) return 'DEBUG';
    return 'UNKNOWN';
  }

  /**
   * Analyze error patterns
   */
  analyzeErrors(events) {
    const errors = events.filter(event => {
      const parsed = this.parseLogMessage(event.message);
      return parsed.level === 'ERROR';
    });

    const errorCounts = {};
    const errorDetails = [];

    errors.forEach(event => {
      const parsed = this.parseLogMessage(event.message);
      
      // Extract error type
      let errorType = 'Unknown Error';
      if (parsed.structured && parsed.data.error) {
        errorType = parsed.data.error.name || parsed.data.error.message || errorType;
      } else {
        // Extract error from message
        const errorMatch = parsed.message.match(/Error: ([^\\n]+)/);
        if (errorMatch) {
          errorType = errorMatch[1];
        }
      }

      errorCounts[errorType] = (errorCounts[errorType] || 0) + 1;
      
      errorDetails.push({
        timestamp: new Date(event.timestamp).toISOString(),
        requestId: parsed.requestId,
        errorType,
        message: parsed.message,
        logStream: event.logStreamName
      });
    });

    return {
      totalErrors: errors.length,
      errorCounts,
      errorDetails: errorDetails.slice(0, 50) // Limit details
    };
  }

  /**
   * Analyze performance metrics
   */
  analyzePerformance(events) {
    const durations = [];
    const memoryUsage = [];

    events.forEach(event => {
      const parsed = this.parseLogMessage(event.message);
      
      if (parsed.structured && parsed.data.duration) {
        durations.push(parsed.data.duration);
      }
      
      if (parsed.structured && parsed.data.memoryUsed) {
        memoryUsage.push(parsed.data.memoryUsed);
      }
      
      // Extract duration from Lambda reports
      const durationMatch = parsed.message.match(/Duration: ([0-9.]+) ms/);
      if (durationMatch) {
        durations.push(parseFloat(durationMatch[1]));
      }
      
      // Extract memory from Lambda reports
      const memoryMatch = parsed.message.match(/Max Memory Used: ([0-9]+) MB/);
      if (memoryMatch) {
        memoryUsage.push(parseInt(memoryMatch[1]));
      }
    });

    const calculateStats = (arr) => {
      if (arr.length === 0) return null;
      
      const sorted = arr.sort((a, b) => a - b);
      return {
        count: arr.length,
        min: Math.min(...arr),
        max: Math.max(...arr),
        avg: arr.reduce((a, b) => a + b, 0) / arr.length,
        p50: sorted[Math.floor(sorted.length * 0.5)],
        p95: sorted[Math.floor(sorted.length * 0.95)],
        p99: sorted[Math.floor(sorted.length * 0.99)]
      };
    };

    return {
      duration: calculateStats(durations),
      memory: calculateStats(memoryUsage)
    };
  }

  /**
   * Analyze request patterns
   */
  analyzeRequests(events) {
    const requests = [];
    const requestCounts = {};

    events.forEach(event => {
      const parsed = this.parseLogMessage(event.message);
      
      if (parsed.message.includes('Lambda function invoked') || 
          parsed.message.includes('Notification sent successfully')) {
        
        requests.push({
          timestamp: new Date(event.timestamp),
          requestId: parsed.requestId,
          type: parsed.structured ? parsed.data.type : 'unknown'
        });
        
        const hour = new Date(event.timestamp).getHours();
        requestCounts[hour] = (requestCounts[hour] || 0) + 1;
      }
    });

    return {
      totalRequests: requests.length,
      requestsPerHour: requestCounts,
      timeRange: requests.length > 0 ? {
        start: new Date(Math.min(...requests.map(r => r.timestamp))).toISOString(),
        end: new Date(Math.max(...requests.map(r => r.timestamp))).toISOString()
      } : null
    };
  }

  /**
   * Generate comprehensive report
   */
  async generateReport(options = {}) {
    const {
      logGroup = '/aws/lambda/sendPushNotification',
      hours = 24,
      filterPattern = '',
      level = 'ALL'
    } = options;

    console.log(`🔍 Analyzing logs from ${logGroup}...`);
    console.log(`📅 Time range: Last ${hours} hours`);
    console.log(`🔎 Filter: ${filterPattern || 'None'}`);
    console.log(`📊 Level: ${level}`);

    const events = await this.getLogEvents(logGroup, { hours, filterPattern });
    
    if (events.length === 0) {
      return {
        summary: 'No log events found for the specified criteria',
        timestamp: new Date().toISOString()
      };
    }

    console.log(`📝 Found ${events.length} log events`);

    // Filter by log level if specified
    const filteredEvents = level === 'ALL' ? events : events.filter(event => {
      const parsed = this.parseLogMessage(event.message);
      return parsed.level === level;
    });

    const errorAnalysis = this.analyzeErrors(filteredEvents);
    const performanceAnalysis = this.analyzePerformance(filteredEvents);
    const requestAnalysis = this.analyzeRequests(filteredEvents);

    return {
      summary: {
        logGroup,
        timeRange: `${hours} hours`,
        totalEvents: events.length,
        filteredEvents: filteredEvents.length,
        analysisTimestamp: new Date().toISOString()
      },
      errors: errorAnalysis,
      performance: performanceAnalysis,
      requests: requestAnalysis,
      recentEvents: filteredEvents.slice(-10).map(event => ({
        timestamp: new Date(event.timestamp).toISOString(),
        message: event.message.substring(0, 200) + (event.message.length > 200 ? '...' : ''),
        logStream: event.logStreamName
      }))
    };
  }
}

/**
 * Display formatted report
 */
function displayReport(report) {
  console.log('\n' + '='.repeat(80));
  console.log('📊 CLOUDWATCH LOG ANALYSIS REPORT');
  console.log('='.repeat(80));
  
  // Summary
  console.log('\n📋 SUMMARY');
  console.log('-'.repeat(40));
  console.log(`Log Group: ${report.summary.logGroup}`);
  console.log(`Time Range: ${report.summary.timeRange}`);
  console.log(`Total Events: ${report.summary.totalEvents}`);
  console.log(`Filtered Events: ${report.summary.filteredEvents}`);
  
  // Errors
  if (report.errors.totalErrors > 0) {
    console.log('\n❌ ERRORS');
    console.log('-'.repeat(40));
    console.log(`Total Errors: ${report.errors.totalErrors}`);
    console.log('\nTop Error Types:');
    Object.entries(report.errors.errorCounts)
      .sort(([,a], [,b]) => b - a)
      .slice(0, 5)
      .forEach(([type, count]) => {
        console.log(`  ${count}x ${type}`);
      });
  }
  
  // Performance
  if (report.performance.duration) {
    console.log('\n⚡ PERFORMANCE');
    console.log('-'.repeat(40));
    const perf = report.performance.duration;
    console.log(`Executions: ${perf.count}`);
    console.log(`Duration - Avg: ${perf.avg.toFixed(2)}ms, P95: ${perf.p95.toFixed(2)}ms, Max: ${perf.max.toFixed(2)}ms`);
    
    if (report.performance.memory) {
      const mem = report.performance.memory;
      console.log(`Memory - Avg: ${mem.avg.toFixed(0)}MB, Max: ${mem.max}MB`);
    }
  }
  
  // Requests
  console.log('\n📈 REQUESTS');
  console.log('-'.repeat(40));
  console.log(`Total Requests: ${report.requests.totalRequests}`);
  if (report.requests.timeRange) {
    console.log(`Time Range: ${report.requests.timeRange.start} to ${report.requests.timeRange.end}`);
  }
  
  console.log('\n📝 RECENT EVENTS (Last 10)');
  console.log('-'.repeat(40));
  report.recentEvents.forEach(event => {
    console.log(`${event.timestamp}: ${event.message}`);
  });
  
  console.log('\n' + '='.repeat(80));
}

/**
 * Main CLI function
 */
async function main() {
  const args = process.argv.slice(2);
  
  if (args.includes('--help') || args.includes('-h')) {
    console.log(`
🔍 CloudWatch Log Analyzer

Usage:
  node log-analyzer.js [options]

Options:
  --log-group <name>      CloudWatch log group name
  --hours <number>        Hours of logs to analyze (default: 24)
  --filter <pattern>      CloudWatch filter pattern
  --level <level>         Log level filter (ERROR, WARN, INFO, DEBUG, ALL)
  --output <path>         Save report to file
  --function <name>       Lambda function name (shortcut for log group)

Examples:
  # Analyze errors from last 6 hours
  node log-analyzer.js --hours 6 --level ERROR
  
  # Analyze specific function with filter
  node log-analyzer.js --function sendPushNotification --filter "FCM"
  
  # Save detailed report
  node log-analyzer.js --hours 48 --output analysis-report.json
`);
    process.exit(0);
  }

  const logGroupIndex = args.indexOf('--log-group');
  const hoursIndex = args.indexOf('--hours');
  const filterIndex = args.indexOf('--filter');
  const levelIndex = args.indexOf('--level');
  const outputIndex = args.indexOf('--output');
  const functionIndex = args.indexOf('--function');

  const options = {
    hours: hoursIndex !== -1 ? parseInt(args[hoursIndex + 1]) : 24,
    filterPattern: filterIndex !== -1 ? args[filterIndex + 1] : '',
    level: levelIndex !== -1 ? args[levelIndex + 1] : 'ALL'
  };

  if (logGroupIndex !== -1) {
    options.logGroup = args[logGroupIndex + 1];
  } else if (functionIndex !== -1) {
    options.logGroup = `/aws/lambda/${args[functionIndex + 1]}`;
  }

  const outputPath = outputIndex !== -1 ? args[outputIndex + 1] : null;

  try {
    const analyzer = new LogAnalyzer();
    const report = await analyzer.generateReport(options);
    
    displayReport(report);
    
    if (outputPath) {
      fs.writeFileSync(outputPath, JSON.stringify(report, null, 2));
      console.log(`\n💾 Report saved to: ${outputPath}`);
    }
    
  } catch (error) {
    console.error('❌ Error:', error.message);
    process.exit(1);
  }
}

// Run if called directly
if (require.main === module) {
  main();
}

module.exports = LogAnalyzer;