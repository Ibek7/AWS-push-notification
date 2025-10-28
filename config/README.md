# Configuration Templates and Environment Management

This directory contains configuration templates and environment management tools for the AWS Push Notifications system across different deployment environments.

## Directory Structure

```
config/
├── environments/          # Environment-specific configurations
│   ├── dev.json           # Development environment
│   ├── staging.json       # Staging environment
│   └── prod.json          # Production environment
├── templates/             # Configuration templates
│   ├── lambda-env.template    # Lambda environment variables
│   ├── api-gateway.template   # API Gateway configuration
│   └── cloudformation.template # CloudFormation parameters
├── scripts/               # Configuration management scripts
│   ├── deploy-config.sh       # Deploy configurations
│   ├── validate-config.sh     # Validate configurations
│   └── sync-secrets.sh        # Sync secrets across environments
└── schemas/               # Configuration validation schemas
    ├── lambda-config.json     # Lambda configuration schema
    └── api-config.json        # API configuration schema
```

## Environment Management

### Supported Environments
- **Development** (`dev`): Local development and testing
- **Staging** (`staging`): Pre-production testing and validation
- **Production** (`prod`): Live production environment

### Configuration Categories
- **Infrastructure**: AWS resource configurations
- **Application**: Runtime application settings
- **Security**: Authentication and authorization settings
- **Monitoring**: Logging and metrics configurations
- **Integration**: Third-party service configurations

## Usage

### Deploy Configuration
```bash
# Deploy to specific environment
./scripts/deploy-config.sh --env dev

# Deploy with custom config file
./scripts/deploy-config.sh --env prod --config custom-prod.json
```

### Validate Configuration
```bash
# Validate all environments
./scripts/validate-config.sh

# Validate specific environment
./scripts/validate-config.sh --env staging
```

### Sync Secrets
```bash
# Sync secrets from dev to staging
./scripts/sync-secrets.sh --from dev --to staging

# Sync specific secret
./scripts/sync-secrets.sh --secret FCM_SERVER_KEY --env prod
```

## Best Practices

### Configuration Management
1. **Environment Isolation**: Keep configurations separate per environment
2. **Secret Management**: Use AWS Secrets Manager for sensitive data
3. **Version Control**: Track configuration changes in Git
4. **Validation**: Validate configurations before deployment
5. **Documentation**: Document all configuration parameters

### Security Guidelines
1. **No Hardcoded Secrets**: Never commit secrets to version control
2. **Least Privilege**: Grant minimal required permissions
3. **Encryption**: Encrypt sensitive configuration data
4. **Audit Trail**: Log all configuration changes
5. **Regular Rotation**: Rotate secrets and keys regularly

### Deployment Strategy
1. **Infrastructure as Code**: Use CloudFormation/Terraform
2. **Blue-Green Deployment**: Minimize downtime with parallel environments
3. **Rollback Plan**: Always have a rollback strategy
4. **Health Checks**: Validate deployment success
5. **Monitoring**: Monitor configuration changes impact