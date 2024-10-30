# S3 to RabbitMQ Lambda (test)

This project demonstrates a serverless application that processes S3 file uploads and sends notifications to RabbitMQ, running locally using LocalStack. Built for testing AWS Lambda functions that integrate with RabbitMQ in the eu-west-1 region.

## Prerequisites

- Docker and Docker Compose
- Go 1.x
- Node.js and npm
- PowerShell
- AWS CLI
- Serverless Framework (`npm install -g serverless`)

## Project Structure

```
.
├── build.ps1            # Builds the Go Lambda function with dependency checks
├── cleanup.ps1          # Comprehensive environment cleanup script
├── docker-compose.yml   # Local development environment configuration
├── init.ps1            # Environment initialization with prerequisite checks
├── main.go             # Lambda function code
├── go.mod              # Go module definition
├── serverless.yml      # Serverless Framework configuration
├── test.ps1           # Integration test script
├── .gitignore         # Source control exclusions
└── README.md          # This documentation
```

## Quick Start

```powershell
# Clean any existing deployment
.\cleanup.ps1

# Run full test suite (includes build, deploy, and verification)
.\test.ps1
```

## Detailed Setup

1. Clean Environment (if needed):
```powershell
.\cleanup.ps1
```

2. Initialize Environment:
```powershell
.\init.ps1
```
This will:
- Check for required tools and dependencies
- Initialize Go modules
- Download required dependencies
- Set up LocalStack endpoints
- Configure AWS region and credentials
- Create necessary directories
- Install npm dependencies

3. Build the Lambda:
```powershell
.\build.ps1
```
This will:
- Verify Go modules
- Download and verify dependencies
- Build the Lambda function
- Create the bootstrap binary

4. Start Local Services:
```powershell
docker-compose up -d
```

5. Deploy:
```powershell
serverless deploy --stage local
```

## Component Configuration

### LocalStack (eu-west-1)
- Endpoint: http://localhost:4566
- Services: 
  - S3 (file storage)
  - Lambda (serverless computing)
  - CloudFormation (infrastructure)
  - IAM (permissions)
  - CloudWatch (logs)
  - SSM (parameter storage)
  - Events (event handling)

### RabbitMQ
- Management UI: http://localhost:15672
- AMQP Port: 5672
- Credentials: guest/guest
- Queue: s3_uploads (durable, non-exclusive)
- Health Check: Enabled with 5s interval

### Lambda Function
- Runtime: provided.al2
- Handler: main
- Memory: 1024MB
- Timeout: 6 seconds
- Region: eu-west-1

## Testing

### Automated Testing
```powershell
.\test.ps1
```

The test script performs:
1. Environment cleanup
2. Dependency verification
3. Build process validation
4. Service health checks
5. Lambda deployment
6. S3 trigger verification
7. RabbitMQ message validation
8. Log verification

### Manual Testing

1. Upload a test file:
```powershell
# Create test content
$content = @{
    "timestamp" = Get-Date -Format "o"
    "message" = "Test message"
} | ConvertTo-Json

# Save and upload
$content | Out-File -FilePath .\test.json -Encoding utf8
aws --endpoint-url=http://localhost:4566 --region eu-west-1 s3 cp test.json s3://test-bucket/uploads/test.json
```

2. Verify in RabbitMQ:
- Open http://localhost:15672
- Login with guest/guest
- Check "s3_uploads" queue

3. Check Lambda logs:
```powershell
aws --endpoint-url=http://localhost:4566 --region eu-west-1 logs describe-log-streams `
    --log-group-name /aws/lambda/s3-to-rabbitmq-processor-local-processUpload
```

## Message Format

Messages in RabbitMQ:
```json
{
    "bucket": "test-bucket",
    "key": "uploads/test.json",
    "size": 123,
    "eventTime": "2024-10-29T08:27:15Z",
    "processedAt": "2024-10-29T08:27:15Z"
}
```

## Development Workflow

1. Make code changes to `main.go`

2. Clean and rebuild:
```powershell
.\cleanup.ps1
.\test.ps1
```

## Troubleshooting

### Common Issues

1. Missing Dependencies
   - Run `.\init.ps1` to verify and install dependencies
   - Check Go modules with `go mod tidy`
   - Verify npm packages with `npm install`

2. Build Failures
   - Check `go.mod` and `go.sum` are present and valid
   - Verify GOOS and GOARCH settings in build.ps1
   - Ensure bootstrap binary is created

3. Deployment Issues
   - Verify LocalStack is running: `docker-compose ps`
   - Check LocalStack logs: `docker-compose logs localstack`
   - Verify region configuration (eu-west-1)

4. Runtime Issues
   - Check Lambda logs in LocalStack
   - Verify RabbitMQ connectivity
   - Check S3 trigger configuration

### Debug Commands

```powershell
# Check LocalStack status
docker-compose ps

# View LocalStack logs
docker-compose logs -f localstack

# Check RabbitMQ status
docker-compose logs -f rabbitmq

# Verify S3 bucket
aws --endpoint-url=http://localhost:4566 --region eu-west-1 s3 ls
```

## Best Practices

1. Always run cleanup before fresh deployments
2. Use init.ps1 when setting up new environments
3. Run full test suite after changes
4. Check logs for troubleshooting
5. Use region flag with AWS CLI commands
6. Verify RabbitMQ connectivity before testing

## Contributing

1. Fork the repository
2. Create your feature branch
3. Run full test suite
4. Commit your changes
5. Push to the branch
6. Create a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.