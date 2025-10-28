# Testing Framework

This directory contains comprehensive testing for the AWS Push Notifications system.

## Test Structure

```
tests/
├── unit/              # Unit tests for individual components
├── integration/       # Integration tests for AWS services
├── e2e/              # End-to-end testing scenarios
└── fixtures/         # Test data and mock responses
```

## Test Categories

### Unit Tests
- Firebase service tests
- Lambda function unit tests
- Android utility function tests
- Configuration validation tests

### Integration Tests
- AWS SNS integration
- Firebase FCM integration
- Lambda-SNS pipeline tests
- CloudWatch logging tests

### End-to-End Tests
- Complete notification flow
- Android app notification handling
- AWS infrastructure validation
- Performance and load testing

## Running Tests

```bash
# Run all tests
npm test

# Run specific test category
npm run test:unit
npm run test:integration
npm run test:e2e

# Run with coverage
npm run test:coverage
```

## Test Configuration

Tests use environment-specific configurations located in `tests/config/`.