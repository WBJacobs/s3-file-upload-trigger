# Initialize environment for local development

function Write-Status {
    param (
        [string]$Message,
        [string]$Status = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Status : $Message"
}

# Check prerequisites
$prerequisites = @{
    "docker" = "Docker Desktop"
    "docker-compose" = "Docker Compose"
    "go" = "Go"
    "node" = "Node.js"
    "serverless" = "Serverless Framework"
    "aws" = "AWS CLI"
}

Write-Status "Checking prerequisites..."
foreach ($cmd in $prerequisites.Keys) {
    if (!(Get-Command $cmd -ErrorAction SilentlyContinue)) {
        Write-Status "$($prerequisites[$cmd]) is not installed or not in PATH" "ERROR"
        exit 1
    }
}

# Initialize Go module if needed
if (-not (Test-Path "go.mod")) {
    Write-Status "Initializing Go module..."
    go mod init s3-lambda-processor
    if ($LASTEXITCODE -ne 0) {
        Write-Status "Failed to initialize Go module" "ERROR"
        exit 1
    }
}

# Add required Go dependencies
Write-Status "Adding required Go dependencies..."
go get github.com/aws/aws-lambda-go/events
go get github.com/aws/aws-lambda-go/lambda
go get github.com/streadway/amqp

# Verify and tidy Go modules
Write-Status "Verifying Go modules..."
go mod tidy
if ($LASTEXITCODE -ne 0) {
    Write-Status "Failed to verify Go modules" "ERROR"
    exit 1
}

# Create endpoints configuration file for serverless-localstack
Write-Status "Creating LocalStack endpoints configuration..."
$endpointsConfig = @{
    "CloudFormation" = "http://localhost:4566"
    "CloudWatch" = "http://localhost:4566"
    "Lambda" = "http://localhost:4566"
    "S3" = "http://localhost:4566"
    "IAM" = "http://localhost:4566"
    "Logs" = "http://localhost:4566"
    "Events" = "http://localhost:4566"
    "SSM" = "http://localhost:4566"
} | ConvertTo-Json

$endpointsConfig | Out-File -FilePath "localstack_endpoints.json" -Encoding UTF8

# Set AWS CLI default region
$env:AWS_DEFAULT_REGION = "eu-west-1"

# Ensure AWS credentials are set for LocalStack
$env:AWS_ACCESS_KEY_ID = "test"
$env:AWS_SECRET_ACCESS_KEY = "test"

# Create necessary directories
Write-Status "Creating required directories..."
New-Item -ItemType Directory -Force -Path "volume" | Out-Null

# Install node dependencies if package.json exists
if (Test-Path "package.json") {
    Write-Status "Installing npm dependencies..."
    npm install
    if ($LASTEXITCODE -ne 0) {
        Write-Status "Failed to install npm dependencies" "ERROR"
        exit 1
    }
}

Write-Status "Environment initialized successfully!" "SUCCESS"