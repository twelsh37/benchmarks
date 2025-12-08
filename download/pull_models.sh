# pull_models.ps1 - Download Ollama models for benchmarking

$Models = @(
    @{ Name = "mistral:latest";          Size = "~4.1GB" }
    @{ Name = "deepseek-coder:33b";      Size = "~19GB" }
    @{ Name = "deepseek-r1:7b";          Size = "~4.7GB" }
    @{ Name = "deepseek-r1:32b";         Size = "~20GB" }
    @{ Name = "deepseek-r1:8b";          Size = "~5.2GB" }
    @{ Name = "llama3.3:latest";         Size = "~43GB" }
    @{ Name = "qwen3-coder:30b";         Size = "~19GB" }
    @{ Name = "mistral-small3.2:latest"; Size = "~15GB" }
    @{ Name = "phi4:14b";                Size = "~9.1GB" }
    @{ Name = "codellama:34b";           Size = "~19GB" }
)

# Calculate total estimated size
Write-Host ""
Write-Host "╔═══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║              OLLAMA MODEL DOWNLOADER                          ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "Models to download:" -ForegroundColor Yellow
Write-Host ""

foreach ($Model in $Models) {
    Write-Host "  • $($Model.Name.PadRight(28)) $($Model.Size)" -ForegroundColor White
}

Write-Host ""
Write-Host "  Total estimated size: ~158GB" -ForegroundColor Magenta
Write-Host ""
Write-Host "Note: Models you already have will be skipped or updated." -ForegroundColor Gray
Write-Host ""

$Confirm = Read-Host "Proceed with download? (Y/n)"
if ($Confirm -eq "n" -or $Confirm -eq "N") {
    Write-Host "Cancelled." -ForegroundColor Yellow
    exit
}

Write-Host ""

$Successful = @()
$Failed = @()
$Skipped = @()

$Total = $Models.Count
$Current = 0

foreach ($Model in $Models) {
    $Current++
    $ModelName = $Model.Name
    
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host "[$Current/$Total] Pulling: $ModelName ($($Model.Size))" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
    
    try {
        $Process = Start-Process -FilePath "ollama" -ArgumentList "pull", $ModelName -NoNewWindow -Wait -PassThru
        
        if ($Process.ExitCode -eq 0) {
            Write-Host "✓ Successfully pulled $ModelName" -ForegroundColor Green
            $Successful += $ModelName
        } else {
            Write-Host "✗ Failed to pull $ModelName (Exit code: $($Process.ExitCode))" -ForegroundColor Red
            $Failed += $ModelName
        }
    }
    catch {
        Write-Host "✗ Error pulling $ModelName : $($_.Exception.Message)" -ForegroundColor Red
        $Failed += $ModelName
    }
    
    Write-Host ""
}

# Summary
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host "                         SUMMARY                               " -ForegroundColor Yellow
Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
Write-Host ""

if ($Successful.Count -gt 0) {
    Write-Host "Successful ($($Successful.Count)):" -ForegroundColor Green
    foreach ($Model in $Successful) {
        Write-Host "  ✓ $Model" -ForegroundColor Green
    }
    Write-Host ""
}

if ($Failed.Count -gt 0) {
    Write-Host "Failed ($($Failed.Count)):" -ForegroundColor Red
    foreach ($Model in $Failed) {
        Write-Host "  ✗ $Model" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "To retry failed models, run:" -ForegroundColor Yellow
    foreach ($Model in $Failed) {
        Write-Host "  ollama pull $Model" -ForegroundColor Gray
    }
    Write-Host ""
}

# List installed models
Write-Host "Currently installed models:" -ForegroundColor Cyan
ollama list

Write-Host ""
Write-Host "Done!" -ForegroundColor Green
