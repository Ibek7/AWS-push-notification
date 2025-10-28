#!/usr/bin/env node

/**
 * FCM Token Validator
 * Validates Firebase Cloud Messaging tokens for format and connectivity
 */

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

/**
 * FCM Token validation utility
 */
class FCMTokenValidator {
  constructor(serviceAccountPath) {
    this.initialized = false;
    if (serviceAccountPath && fs.existsSync(serviceAccountPath)) {
      this.initializeFirebase(serviceAccountPath);
    }
  }

  /**
   * Initialize Firebase Admin SDK
   */
  initializeFirebase(serviceAccountPath) {
    try {
      const serviceAccount = require(path.resolve(serviceAccountPath));
      
      if (!admin.apps.length) {
        admin.initializeApp({
          credential: admin.credential.cert(serviceAccount)
        });
      }
      
      this.messaging = admin.messaging();
      this.initialized = true;
      console.log('✅ Firebase Admin SDK initialized');
    } catch (error) {
      console.warn('⚠️  Firebase initialization failed:', error.message);
      console.log('🔧 Token format validation only will be available');
    }
  }

  /**
   * Validate token format (basic validation)
   */
  validateTokenFormat(token) {
    const errors = [];
    
    if (!token || typeof token !== 'string') {
      errors.push('Token must be a non-empty string');
      return { valid: false, errors };
    }
    
    // FCM tokens are typically 140-200 characters
    if (token.length < 140) {
      errors.push('Token too short (minimum 140 characters)');
    } else if (token.length > 200) {
      errors.push('Token too long (maximum 200 characters)');
    }
    
    // FCM tokens contain specific character sets
    if (!/^[A-Za-z0-9_:.-]+$/.test(token)) {
      errors.push('Token contains invalid characters');
    }
    
    // FCM tokens typically start with certain patterns
    if (!token.match(/^[A-Za-z0-9_-]+:[A-Za-z0-9_-]+/)) {
      errors.push('Token does not match expected FCM format');
    }
    
    return {
      valid: errors.length === 0,
      errors
    };
  }

  /**
   * Test token connectivity with Firebase
   */
  async validateTokenConnectivity(token) {
    if (!this.initialized) {
      return {
        valid: null,
        error: 'Firebase not initialized - connectivity test unavailable'
      };
    }

    try {
      // Try to send a dry-run message to test token validity
      const message = {
        token: token,
        notification: {
          title: 'Test',
          body: 'Token validation test'
        },
        data: {
          test: 'true'
        },
        android: {
          priority: 'high'
        }
      };

      // Use validateOnly flag to test without actually sending
      const result = await this.messaging.send(message, true);
      
      return {
        valid: true,
        messageId: result
      };
    } catch (error) {
      const errorCode = error.code || 'unknown';
      const errorMessage = error.message || 'Unknown error';
      
      return {
        valid: false,
        error: `${errorCode}: ${errorMessage}`,
        errorCode
      };
    }
  }

  /**
   * Validate single token with full validation
   */
  async validateToken(token) {
    const formatValidation = this.validateTokenFormat(token);
    
    if (!formatValidation.valid) {
      return {
        token: token.substring(0, 20) + '...',
        formatValid: false,
        connectivityValid: null,
        errors: formatValidation.errors,
        status: 'INVALID_FORMAT'
      };
    }

    const connectivityValidation = await this.validateTokenConnectivity(token);
    
    return {
      token: token.substring(0, 20) + '...',
      formatValid: true,
      connectivityValid: connectivityValidation.valid,
      errors: connectivityValidation.error ? [connectivityValidation.error] : [],
      errorCode: connectivityValidation.errorCode,
      status: connectivityValidation.valid === true ? 'VALID' : 
              connectivityValidation.valid === false ? 'INVALID_TOKEN' : 'UNKNOWN'
    };
  }

  /**
   * Validate multiple tokens from array
   */
  async validateTokens(tokens, options = {}) {
    const { batchSize = 10, delay = 100 } = options;
    const results = [];
    
    console.log(`🔍 Validating ${tokens.length} tokens...`);
    
    for (let i = 0; i < tokens.length; i += batchSize) {
      const batch = tokens.slice(i, i + batchSize);
      const batchResults = await Promise.all(
        batch.map(token => this.validateToken(token))
      );
      
      results.push(...batchResults);
      
      // Progress indicator
      const progress = Math.min(i + batchSize, tokens.length);
      console.log(`📊 Progress: ${progress}/${tokens.length} (${Math.round(progress/tokens.length*100)}%)`);
      
      // Rate limiting delay
      if (i + batchSize < tokens.length && delay > 0) {
        await new Promise(resolve => setTimeout(resolve, delay));
      }
    }
    
    return results;
  }

  /**
   * Generate validation report
   */
  generateReport(results) {
    const total = results.length;
    const valid = results.filter(r => r.status === 'VALID').length;
    const invalidFormat = results.filter(r => r.status === 'INVALID_FORMAT').length;
    const invalidToken = results.filter(r => r.status === 'INVALID_TOKEN').length;
    const unknown = results.filter(r => r.status === 'UNKNOWN').length;

    const report = {
      summary: {
        total,
        valid,
        invalid: invalidFormat + invalidToken,
        invalidFormat,
        invalidToken,
        unknown,
        validPercentage: total > 0 ? Math.round((valid / total) * 100) : 0
      },
      details: results,
      timestamp: new Date().toISOString()
    };

    return report;
  }
}

/**
 * Load tokens from file
 */
function loadTokensFromFile(filePath) {
  try {
    const content = fs.readFileSync(filePath, 'utf8');
    
    // Try parsing as JSON first
    try {
      const json = JSON.parse(content);
      if (Array.isArray(json)) {
        return json;
      } else if (json.tokens && Array.isArray(json.tokens)) {
        return json.tokens;
      } else {
        throw new Error('JSON does not contain token array');
      }
    } catch (jsonError) {
      // Parse as line-separated tokens
      return content
        .split('\n')
        .map(line => line.trim())
        .filter(line => line.length > 0);
    }
  } catch (error) {
    throw new Error(`Failed to load tokens from ${filePath}: ${error.message}`);
  }
}

/**
 * Save results to file
 */
function saveResults(results, outputPath) {
  try {
    fs.writeFileSync(outputPath, JSON.stringify(results, null, 2));
    console.log(`💾 Results saved to: ${outputPath}`);
  } catch (error) {
    console.error(`❌ Failed to save results: ${error.message}`);
  }
}

/**
 * Display summary
 */
function displaySummary(report) {
  console.log('\n' + '='.repeat(60));
  console.log('📋 VALIDATION SUMMARY');
  console.log('='.repeat(60));
  console.log(`📊 Total Tokens: ${report.summary.total}`);
  console.log(`✅ Valid: ${report.summary.valid} (${report.summary.validPercentage}%)`);
  console.log(`❌ Invalid: ${report.summary.invalid}`);
  console.log(`  📝 Format Issues: ${report.summary.invalidFormat}`);
  console.log(`  🔗 Connectivity Issues: ${report.summary.invalidToken}`);
  console.log(`  ❓ Unknown Status: ${report.summary.unknown}`);
  console.log('='.repeat(60));

  if (report.summary.invalid > 0) {
    console.log('\n🔍 Sample Invalid Tokens:');
    const invalidTokens = report.details
      .filter(r => r.status !== 'VALID')
      .slice(0, 5);
    
    invalidTokens.forEach(result => {
      console.log(`  ${result.token} - ${result.status}: ${result.errors.join(', ')}`);
    });
  }
}

/**
 * Main CLI function
 */
async function main() {
  const args = process.argv.slice(2);
  
  if (args.includes('--help') || args.includes('-h')) {
    console.log(`
🔍 FCM Token Validator

Usage:
  node token-validator.js --file <path> [options]
  node token-validator.js --token <token> [options]

Options:
  --file <path>              Path to file containing tokens (JSON array or line-separated)
  --token <token>            Single token to validate
  --service-account <path>   Path to Firebase service account JSON file
  --output <path>            Output file for results (default: validation-results.json)
  --batch-size <number>      Batch size for validation (default: 10)
  --delay <ms>              Delay between batches in milliseconds (default: 100)
  --format-only             Only validate format, skip connectivity test

Examples:
  # Validate tokens from file
  node token-validator.js --file tokens.txt --service-account firebase-key.json
  
  # Validate single token
  node token-validator.js --token "TOKEN_HERE" --service-account firebase-key.json
  
  # Format validation only
  node token-validator.js --file tokens.txt --format-only
`);
    process.exit(0);
  }

  const fileIndex = args.indexOf('--file');
  const tokenIndex = args.indexOf('--token');
  const serviceAccountIndex = args.indexOf('--service-account');
  const outputIndex = args.indexOf('--output');
  const batchSizeIndex = args.indexOf('--batch-size');
  const delayIndex = args.indexOf('--delay');
  const formatOnly = args.includes('--format-only');

  if (fileIndex === -1 && tokenIndex === -1) {
    console.error('❌ Please specify --file or --token');
    process.exit(1);
  }

  const serviceAccountPath = serviceAccountIndex !== -1 ? args[serviceAccountIndex + 1] : null;
  const outputPath = outputIndex !== -1 ? args[outputIndex + 1] : 'validation-results.json';
  const batchSize = batchSizeIndex !== -1 ? parseInt(args[batchSizeIndex + 1]) : 10;
  const delay = delayIndex !== -1 ? parseInt(args[delayIndex + 1]) : 100;

  try {
    const validator = new FCMTokenValidator(formatOnly ? null : serviceAccountPath);
    let tokens = [];

    if (fileIndex !== -1) {
      const filePath = args[fileIndex + 1];
      tokens = loadTokensFromFile(filePath);
      console.log(`📁 Loaded ${tokens.length} tokens from ${filePath}`);
    } else {
      tokens = [args[tokenIndex + 1]];
    }

    if (tokens.length === 0) {
      console.error('❌ No tokens found to validate');
      process.exit(1);
    }

    const results = await validator.validateTokens(tokens, { batchSize, delay });
    const report = validator.generateReport(results);

    displaySummary(report);
    saveResults(report, outputPath);

  } catch (error) {
    console.error('❌ Error:', error.message);
    process.exit(1);
  }
}

// Run if called directly
if (require.main === module) {
  main();
}

module.exports = FCMTokenValidator;