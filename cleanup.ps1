# Stop and remove containers
Write-Host "Stopping and removing containers..."
docker-compose down -v

# Remove build artifacts
Write-Host "Cleaning build artifacts..."
if (Test-Path bootstrap) {
    Remove-Item bootstrap
}
if (Test-Path function.zip) {
    Remove-Item function.zip
}
if (Test-Path main) {
    Remove-Item main
}

# Clean LocalStack artifacts
Write-Host "Cleaning LocalStack artifacts..."
if (Test-Path volume) {
    Remove-Item -Recurse -Force volume
}
if (Test-Path .localstack) {
    Remove-Item -Recurse -Force .localstack
}
if (Test-Path localstack_endpoints.json) {
    Remove-Item localstack_endpoints.json
}

# Clean serverless artifacts
Write-Host "Cleaning Serverless artifacts..."
if (Test-Path .serverless) {
    Remove-Item -Recurse -Force .serverless
}

# Clean node artifacts
Write-Host "Cleaning node artifacts..."
if (Test-Path node_modules) {
    Remove-Item -Recurse -Force node_modules
}
if (Test-Path package-lock.json) {
    Remove-Item package-lock.json
}
if (Test-Path .npm) {
    Remove-Item -Recurse -Force .npm
}
if (Test-Path .npmrc) {
    Remove-Item .npmrc
}

# Clean test artifacts
Write-Host "Cleaning test artifacts..."
if (Test-Path test.json) {
    Remove-Item test.json
}
if (Test-Path test.txt) {
    Remove-Item test.txt
}

# Clean log files
Write-Host "Cleaning log files..."
Remove-Item *.log -ErrorAction SilentlyContinue

Write-Host "Cleanup completed successfully!"