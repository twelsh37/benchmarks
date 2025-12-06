# pull_models_parallel.ps1 - Download models in parallel (use with caution)

$Models = @(
    "mistral:latest"
    "deepseek-coder:33b"
    "deepseek-r1:7b"
    "deepseek-r1:32b"
    "deepseek-r1:8b"
    "llama3.3:latest"
    "qwen3-coder:30b"
    "mistral-small3.2:latest"
    "phi4:14b"
    "codellama:34b"
)

Write-Host "Pulling $($Models.Count) models in parallel..." -ForegroundColor Cyan
Write-Host "Note: This will use significant bandwidth and disk I/O" -ForegroundColor Yellow
Write-Host ""

$Jobs = @()

foreach ($Model in $Models) {
    Write-Host "Starting: $Model" -ForegroundColor Gray
    $Jobs += Start-Job -ScriptBlock {
        param($ModelName)
        ollama pull $ModelName 2>&1
    } -ArgumentList $Model
}

Write-Host ""
Write-Host "Waiting for downloads to complete..." -ForegroundColor Cyan

$Jobs | Wait-Job | ForEach-Object {
    $Result = Receive-Job $_
    Write-Host $Result
    Remove-Job $_
}

Write-Host ""
Write-Host "Done! Installed models:" -ForegroundColor Green
ollama list
