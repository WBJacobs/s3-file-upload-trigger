# Test script for s3-to-rabbitmq-processor
$ErrorActionPreference = "Stop"

function Write-Status {
    param (
        [string]$Message,
        [string]$Status = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $color = switch ($Status) {
        "SUCCESS" { "Green" }
        "ERROR" { "Red" }
        "WARN" { "Yellow" }
        default { "White" }
    }
    Write-Host "[$timestamp] $Status : $Message" -ForegroundColor $color
}

function Test-LocalStackHealth {
    try {
        $response = Invoke-RestMethod -Uri "http://localhost:4566/_localstack/health" -Method Get
        
        # Debug output
        Write-Status "LocalStack services status:" "INFO"
        $response.services | ConvertTo-Json | Write-Status

        # Check if the required services are available
        $requiredServices = @("lambda", "s3", "cloudformation", "logs", "iam", "events", "ssm")
        $allServicesReady = $true
        
        foreach ($service in $requiredServices) {
            if ($response.services.$service -ne "available" -and $response.services.$service -ne "running") {
                Write-Status "Service $service is not ready (Status: $($response.services.$service))" "WARN"
                $allServicesReady = $false
            }
        }

        return $allServicesReady
    }
    catch {
        Write-Status "Error checking LocalStack health: $_" "WARN"
        return $false
    }
}

function Test-RabbitMQHealth {
    try {
        $auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("guest:guest"))
        $headers = @{
            Authorization = "Basic $auth"
        }
        
        # First try to access the management API
        $response = Invoke-RestMethod -Uri "http://localhost:15672/api/healthchecks/node" -Headers $headers -Method Get
        Write-Status "RabbitMQ Management API response received" "INFO"
        
        # Then verify AMQP port is accessible
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $portOpen = $tcpClient.ConnectAsync("localhost", 5672).Wait(1000)
        $tcpClient.Close()
        
        if (-not $portOpen) {
            Write-Status "RabbitMQ AMQP port is not accessible" "WARN"
            return $false
        }
        
        return $true
    }
    catch {
        Write-Status "Error checking RabbitMQ health: $_" "WARN"
        return $false
    }
}

function Wait-ForService {
    param (
        [string]$ServiceName,
        [scriptblock]$TestScript,
        [int]$TimeoutSeconds = 60,
        [int]$RetryIntervalSeconds = 5
    )
    
    Write-Status "Waiting for $ServiceName to be ready..."
    $startTime = Get-Date
    $ready = $false
    $attempt = 1
    
    while (-not $ready -and ((Get-Date) - $startTime).TotalSeconds -lt $TimeoutSeconds) {
        Write-Status "Attempt $attempt to check $ServiceName health..." "INFO"
        if (& $TestScript) {
            $ready = $true
            Write-Status "$ServiceName is ready" "SUCCESS"
        }
        else {
            Write-Status "$ServiceName not ready, waiting $RetryIntervalSeconds seconds..." "INFO"
            Start-Sleep -Seconds $RetryIntervalSeconds
            $attempt++
        }
    }
    
    if (-not $ready) {
        throw "$ServiceName did not become ready within $TimeoutSeconds seconds"
    }
}

function Test-QueueHasMessages {
    param (
        [int]$TimeoutSeconds = 30,
        [int]$RetryIntervalSeconds = 5
    )
    
    Write-Status "Checking RabbitMQ queue for messages (timeout: ${TimeoutSeconds}s)..."
    $startTime = Get-Date
    $attempt = 1
    
    while (((Get-Date) - $startTime).TotalSeconds -lt $TimeoutSeconds) {
        Write-Status "Queue check attempt $attempt..." "INFO"
        try {
            $auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("guest:guest"))
            $headers = @{
                Authorization = "Basic $auth"
            }
            $queueInfo = Invoke-RestMethod -Uri "http://localhost:15672/api/queues/%2F/s3_uploads" -Headers $headers -Method Get
            
            $totalMessages = $queueInfo.messages_ready + $queueInfo.messages_unacknowledged
            Write-Status "Found $totalMessages messages in queue" "INFO"
            
            if ($totalMessages -gt 0) {
                # Get message details for verification
                $messages = Invoke-RestMethod -Uri "http://localhost:15672/api/queues/%2F/s3_uploads/get" -Headers $headers -Method Post -Body '{"count":1,"ackmode":"ack_requeue_true","encoding":"auto","truncate":50000}' -ContentType "application/json"
                Write-Status "Message content: $($messages | ConvertTo-Json -Depth 10)" "INFO"
                return $true
            }
        }
        catch {
            Write-Status "Error checking queue: $_" "WARN"
        }
        
        Write-Status "No messages found yet, waiting $RetryIntervalSeconds seconds..." "INFO"
        Start-Sleep -Seconds $RetryIntervalSeconds
        $attempt++
    }
    
    return $false
}

function Get-LambdaLogs {
    param (
        [string]$LogGroupName,
        [int]$RetryAttempts = 12,
        [int]$RetryInterval = 5
    )

    Write-Status "Checking Lambda logs (with retries)..."
    
    for ($i = 1; $i -le $RetryAttempts; $i++) {
        try {
            Write-Status "Attempt $i to get Lambda logs..." "INFO"
            
            # Note the addition of --region parameter
            $logs = aws --endpoint-url=http://localhost:4566 --region eu-west-1 logs describe-log-streams `
                --log-group-name $LogGroupName `
                --no-cli-pager 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                $logsObj = $logs | ConvertFrom-Json
                if ($logsObj.logStreams.Count -gt 0) {
                    Write-Status "Lambda logs found" "SUCCESS"
                    
                    # Get the most recent log stream
                    $latestStream = $logsObj.logStreams | Sort-Object -Property lastEventTimestamp -Descending | Select-Object -First 1
                    
                    # Note the addition of --region parameter here too
                    $events = aws --endpoint-url=http://localhost:4566 --region eu-west-1 logs get-log-events `
                        --log-group-name $LogGroupName `
                        --log-stream-name $latestStream.logStreamName `
                        --no-cli-pager | ConvertFrom-Json

                    foreach ($event in $events.events) {
                        Write-Status "Log: $($event.message)" "INFO"
                    }
                    return $true
                }
            }
            else {
                Write-Status "Log group query failed with exit code $LASTEXITCODE" "WARN"
                Write-Status "Response: $logs" "INFO"
            }
            
            Write-Status "No logs available yet, waiting $RetryInterval seconds..." "INFO"
            Start-Sleep -Seconds $RetryInterval
            
        } catch {
            if ($i -eq $RetryAttempts) {
                Write-Status "Final attempt to get logs failed: $_" "WARN"
                return $false
            }
            Write-Status "Attempt $i failed: $_" "WARN"
            Start-Sleep -Seconds $RetryInterval
        }
    }
    
    Write-Status "No Lambda logs found after $RetryAttempts attempts" "WARN"
    return $false
}

try {
    # Clean up and rebuild
    Write-Status "Cleaning up previous deployment..."
    .\cleanup.ps1

    Write-Status "Initializing environment..."
    .\init.ps1

    Write-Status "Building Go binary..."
    .\build.ps1
    if (-not (Test-Path "bootstrap")) {
        throw "Bootstrap binary was not created"
    }

    # Start services
    Write-Status "Starting LocalStack and RabbitMQ..."
    docker-compose up -d

    # Wait for services to be healthy with increased timeout
    Wait-ForService -ServiceName "LocalStack" -TestScript ${function:Test-LocalStackHealth} -TimeoutSeconds 120 -RetryIntervalSeconds 10
    Wait-ForService -ServiceName "RabbitMQ" -TestScript ${function:Test-RabbitMQHealth} -TimeoutSeconds 60 -RetryIntervalSeconds 5

    # Deploy with Serverless
    Write-Status "Deploying with Serverless..."
    serverless deploy --stage local
    if ($LASTEXITCODE -ne 0) {
        throw "Serverless deployment failed"
    }

    # Create test bucket if it doesn't exist
    Write-Status "Creating test bucket..."
    aws --endpoint-url=http://localhost:4566 --region eu-west-1 s3 mb s3://test-bucket --no-cli-pager 2>&1 | Out-Null

    # Create and upload test file
    Write-Status "Creating and uploading test file..."
    $testContent = @{
        timestamp = Get-Date -Format "o"
        message = "Test message"
    } | ConvertTo-Json

    $testContent | Out-File -FilePath .\test.json -Encoding utf8
    aws --endpoint-url=http://localhost:4566 --region eu-west-1 s3 cp test.json s3://test-bucket/uploads/test.json --no-cli-pager

    # Wait for processing
    Write-Status "Waiting for message processing..."
    Start-Sleep -Seconds 5

    # Wait for Lambda cold start and message processing
    Write-Status "Waiting for Lambda execution and message processing..."
    Start-Sleep -Seconds 10  # Initial wait for Lambda to start

    # Check RabbitMQ queue with retries
    if (Test-QueueHasMessages -TimeoutSeconds 60 -RetryIntervalSeconds 5) {
        Write-Status "Successfully found messages in queue" "SUCCESS"
    }
    else {
        Write-Status "No messages found in queue after maximum wait time" "ERROR"
        throw "Queue check failed - no messages found"
    }

    # Check Lambda logs with retries
    $logGroupName = "/aws/lambda/s3-to-rabbitmq-processor-local-processUpload"
    if (Get-LambdaLogs -LogGroupName $logGroupName -RetryAttempts 12 -RetryInterval 5) {
        Write-Status "Successfully retrieved Lambda logs" "SUCCESS"
    } else {
        Write-Status "Failed to retrieve Lambda logs after maximum attempts" "WARN"
        # Don't fail the test just because we couldn't get logs
    }

    Write-Status "Test completed successfully" "SUCCESS"
}
catch {
    Write-Status "Test failed: $_" "ERROR"
    exit 1
}
finally {
    # Cleanup test files
    if (Test-Path "test.json") {
        Remove-Item "test.json"
    }
}