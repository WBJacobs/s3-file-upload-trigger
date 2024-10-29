# Build script for Lambda function

function Write-Status {
    param (
        [string]$Message,
        [string]$Status = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] $Status : $Message"
}

try {
    Write-Status "Verifying Go modules..."
    
    # Ensure go.mod exists
    if (-not (Test-Path "go.mod")) {
        Write-Status "Initializing Go module..."
        go mod init s3-lambda-processor
    }

    # Verify/download dependencies
    Write-Status "Downloading and verifying dependencies..."
    go mod tidy
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to download dependencies"
    }

    # Set Go build environment variables
    Write-Status "Setting build environment..."
    $env:GOOS = "linux"
    $env:GOARCH = "amd64"
    $env:CGO_ENABLED = "0"

    # Build the Go binary
    Write-Status "Building Go binary..."
    go build -o bootstrap main.go
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed"
    }

    if (-not (Test-Path "bootstrap")) {
        throw "Bootstrap binary was not created"
    }

    Write-Status "Build completed successfully" "SUCCESS"
}
catch {
    Write-Status "Build failed: $_" "ERROR"
    exit 1
}