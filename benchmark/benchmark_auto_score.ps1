# benchmark_auto_score.ps1 - Ollama Benchmark with Automated LLM Scoring

# ═══════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════

# Model to use as the judge (should be one of your more capable models)
# Recommended: deepseek-r1:32b, llama3.3:latest, or qwen3-coder:30b
$JudgeModel = "llama3.3:latest"

# Models to benchmark
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

# Test prompts with expected answers and scoring criteria
$Prompts = @{
    "Reasoning" = @{
        Prompt = "Solve this step by step: A farmer has 17 sheep. All but 9 run away. How many sheep does the farmer have left? Then explain why this problem tricks most people."
        ExpectedAnswer = "The correct answer is 9 sheep. 'All but 9 run away' means 9 sheep REMAIN (not 9 leave). The trick is that people hear '17 sheep' and '9 run away' and instinctively subtract, getting 8. But the phrasing 'all but 9' means all except 9, so 9 stay."
        ScoringCriteria = @"
CORRECTNESS:
- 10: States answer is 9, explains 'all but 9' means 9 remain
- 7-9: Correct answer (9), explanation has minor gaps
- 4-6: Correct answer but wrong reasoning, OR wrong answer with some understanding
- 1-3: Wrong answer (e.g., 8), fundamentally misunderstands the problem

EFFICIENCY:
- 10: Concise, immediately identifies the linguistic trick
- 7-9: Clear explanation with minimal redundancy
- 4-6: Verbose or includes unnecessary steps
- 1-3: Rambling, circular, or confusing structure

OUTCOME:
- 10: Fully answers both parts (answer + why it tricks people)
- 7-9: Both parts addressed, minor incompleteness
- 4-6: Only one part addressed well
- 1-3: Fails to address the question properly
"@
    }
    "Coding" = @{
        Prompt = "Write a Python function called 'find_duplicates' that takes a list and returns a new list containing only the elements that appear more than once. Include type hints and a docstring. Then show an example of calling it."
        ExpectedAnswer = @"
A correct solution should:
1. Define function named 'find_duplicates'
2. Include type hints (e.g., def find_duplicates(items: list) -> list:)
3. Include a docstring explaining the function
4. Return elements that appear MORE THAN ONCE (not just duplicates of first occurrence)
5. Show a working example call
Efficient solutions use Counter, dict, or set-based O(n) approaches.
"@
        ScoringCriteria = @"
CORRECTNESS:
- 10: Code works perfectly, correct logic for finding duplicates (elements appearing >1 time)
- 7-9: Code mostly works, minor edge case issues
- 4-6: Logic errors but approach is reasonable
- 1-3: Fundamentally broken code

EFFICIENCY:
- 10: O(n) solution using Counter/dict/set, clean Pythonic code
- 7-9: O(n log n) or slightly suboptimal but readable
- 4-6: O(n²) nested loops but functional
- 1-3: Extremely inefficient or poorly structured

OUTCOME (Completeness):
- 10: All 5 requirements met: function name, type hints, docstring, example, working code
- 8-9: 4 of 5 requirements met
- 6-7: 3 of 5 requirements met
- 4-5: 2 of 5 requirements met
- 1-3: 1 or fewer requirements met
"@
    }
    "Logic" = @{
        Prompt = "Three boxes are labeled 'Apples', 'Oranges', and 'Mixed'. Each label is WRONG. You can pick one fruit from one box without looking inside. What's the minimum information needed to correctly label all boxes? Explain your reasoning."
        ExpectedAnswer = @"
Correct solution:
1. Pick ONE fruit from the box labeled 'Mixed'
2. Since ALL labels are wrong, the 'Mixed' box must contain ONLY apples OR ONLY oranges
3. If you pick an apple -> this box is actually 'Apples'
4. The box labeled 'Apples' cannot be Apples (wrong label) and isn't the one you identified -> must be 'Oranges'
5. The box labeled 'Oranges' must be 'Mixed'
MINIMUM INFORMATION: 1 fruit from the 'Mixed' labeled box
"@
        ScoringCriteria = @"
CORRECTNESS:
- 10: Correctly identifies: pick from 'Mixed' box, one fruit is sufficient, complete deduction chain
- 7-9: Correct answer and method, minor gaps in explanation
- 4-6: Wrong box choice OR correct choice but incomplete deduction
- 1-3: Fundamentally wrong approach

EFFICIENCY:
- 10: Clear step-by-step logic, no unnecessary cases explored
- 7-9: Good structure with slight redundancy
- 4-6: Confusing or includes irrelevant reasoning
- 1-3: Circular logic or very hard to follow

OUTCOME:
- 10: States minimum info (1 fruit from Mixed), explains full deduction chain
- 7-9: Correct conclusion with mostly complete reasoning
- 4-6: Partial solution or incomplete reasoning
- 1-3: Does not solve the puzzle
"@
    }
}

# ═══════════════════════════════════════════════════════════════
# FUNCTIONS
# ═══════════════════════════════════════════════════════════════

function Invoke-OllamaGenerate {
    param(
        [string]$Model,
        [string]$Prompt,
        [int]$TimeoutSec = 600
    )
    
    $Body = @{
        model  = $Model
        prompt = $Prompt
        stream = $false
    } | ConvertTo-Json -Depth 10
    
    $Response = Invoke-RestMethod -Uri "http://localhost:11434/api/generate" `
                                  -Method Post `
                                  -Body $Body `
                                  -ContentType "application/json" `
                                  -TimeoutSec $TimeoutSec
    return $Response
}

function Get-AutoScore {
    param(
        [string]$TestName,
        [string]$OriginalPrompt,
        [string]$ExpectedAnswer,
        [string]$ScoringCriteria,
        [string]$ModelResponse
    )
    
    $JudgePrompt = @"
You are an expert evaluator scoring an AI model's response. Be strict but fair.

TASK: $TestName

ORIGINAL PROMPT GIVEN TO THE MODEL:
$OriginalPrompt

EXPECTED ANSWER / KEY POINTS:
$ExpectedAnswer

SCORING CRITERIA:
$ScoringCriteria

MODEL'S RESPONSE TO EVALUATE:
---
$ModelResponse
---

Score the response on three dimensions. Be strict - only give 10 for truly excellent responses.

You MUST respond with ONLY a JSON object in this exact format, no other text:
{"correctness": <1-10>, "efficiency": <1-10>, "outcome": <1-10>, "reasoning": "<brief 1-2 sentence justification>"}
"@

    try {
        $JudgeResponse = Invoke-OllamaGenerate -Model $JudgeModel -Prompt $JudgePrompt -TimeoutSec 120
        $ResponseText = $JudgeResponse.response.Trim()
        
        # Try to extract JSON from the response
        if ($ResponseText -match '\{[^{}]*"correctness"[^{}]*\}') {
            $JsonMatch = $Matches[0]
            $Scores = $JsonMatch | ConvertFrom-Json
            return @{
                Correctness = [Math]::Max(1, [Math]::Min(10, [int]$Scores.correctness))
                Efficiency  = [Math]::Max(1, [Math]::Min(10, [int]$Scores.efficiency))
                Outcome     = [Math]::Max(1, [Math]::Min(10, [int]$Scores.outcome))
                Reasoning   = $Scores.reasoning
                RawResponse = $ResponseText
            }
        }
        
        # Fallback: try to parse numbers if JSON extraction fails
        $numbers = [regex]::Matches($ResponseText, '\b([1-9]|10)\b') | Select-Object -First 3
        if ($numbers.Count -ge 3) {
            return @{
                Correctness = [int]$numbers[0].Value
                Efficiency  = [int]$numbers[1].Value
                Outcome     = [int]$numbers[2].Value
                Reasoning   = "Extracted from non-JSON response"
                RawResponse = $ResponseText
            }
        }
        
        throw "Could not parse scores from judge response"
    }
    catch {
        return @{
            Correctness = 0
            Efficiency  = 0
            Outcome     = 0
            Reasoning   = "Scoring failed: $($_.Exception.Message)"
            RawResponse = ""
        }
    }
}

# ═══════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════════════════════

$Results = @()
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$OutputDir = "benchmark_auto_$Timestamp"
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

Clear-Host
Write-Host @"

╔═══════════════════════════════════════════════════════════════╗
║       OLLAMA BENCHMARK WITH AUTOMATED LLM SCORING             ║
╠═══════════════════════════════════════════════════════════════╣
║  Judge Model: $($JudgeModel.PadRight(43))║
║  Models to test: $($Models.Count.ToString().PadRight(40))║
║  Tests per model: 3 (Reasoning, Coding, Logic)                ║
╚═══════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

Write-Host "Output directory: $OutputDir`n" -ForegroundColor Gray

$TotalTests = $Models.Count * 3
$CurrentTest = 0

foreach ($Model in $Models) {
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    Write-Host " MODEL: $Model" -ForegroundColor Yellow
    Write-Host "═══════════════════════════════════════════════════════════════" -ForegroundColor Yellow
    
    foreach ($TestName in @("Reasoning", "Coding", "Logic")) {
        $CurrentTest++
        $PromptData = $Prompts[$TestName]
        
        Write-Host "`n  [$CurrentTest/$TotalTests] $TestName" -ForegroundColor White -NoNewline
        
        try {
            # Step 1: Get model response
            Write-Host " - Generating..." -ForegroundColor Gray -NoNewline
            $ModelResponse = Invoke-OllamaGenerate -Model $Model -Prompt $PromptData.Prompt
            
            $TokensPerSecond = if ($ModelResponse.eval_duration -gt 0) {
                [math]::Round($ModelResponse.eval_count / ($ModelResponse.eval_duration / 1e9), 2)
            } else { 0 }
            
            $TotalDuration = [math]::Round($ModelResponse.total_duration / 1e9, 2)
            
            # Save response
            $SafeModelName = $Model -replace ":", "_" -replace "/", "_"
            $ResponseFile = Join-Path $OutputDir "${SafeModelName}_${TestName}_response.txt"
            $ModelResponse.response | Out-File -FilePath $ResponseFile -Encoding UTF8
            
            # Step 2: Score with judge model
            Write-Host " Scoring..." -ForegroundColor Gray -NoNewline
            
            $Scores = Get-AutoScore -TestName $TestName `
                                    -OriginalPrompt $PromptData.Prompt `
                                    -ExpectedAnswer $PromptData.ExpectedAnswer `
                                    -ScoringCriteria $PromptData.ScoringCriteria `
                                    -ModelResponse $ModelResponse.response
            
            # Save judge reasoning
            $JudgeFile = Join-Path $OutputDir "${SafeModelName}_${TestName}_judge.txt"
            @"
Scores: Correctness=$($Scores.Correctness), Efficiency=$($Scores.Efficiency), Outcome=$($Scores.Outcome)
Reasoning: $($Scores.Reasoning)

Raw Judge Response:
$($Scores.RawResponse)
"@ | Out-File -FilePath $JudgeFile -Encoding UTF8
            
            $CompositeScore = [math]::Round(($Scores.Correctness + $Scores.Efficiency + $Scores.Outcome) / 3, 1)
            
            # Display result
            if ($Scores.Correctness -eq 0) {
                Write-Host " SCORING FAILED" -ForegroundColor Red
            } else {
                $ScoreColor = if ($CompositeScore -ge 8) { "Green" } 
                              elseif ($CompositeScore -ge 5) { "Yellow" } 
                              else { "Red" }
                Write-Host " Score: $CompositeScore/10 (C:$($Scores.Correctness) E:$($Scores.Efficiency) O:$($Scores.Outcome)) | $TokensPerSecond tok/s" -ForegroundColor $ScoreColor
            }
            
            $Results += [PSCustomObject]@{
                Model           = $Model
                Test            = $TestName
                Correctness     = $Scores.Correctness
                Efficiency      = $Scores.Efficiency
                Outcome         = $Scores.Outcome
                CompositeScore  = $CompositeScore
                TokensPerSecond = $TokensPerSecond
                OutputTokens    = $ModelResponse.eval_count
                Duration        = $TotalDuration
                JudgeReasoning  = $Scores.Reasoning
                Status          = if ($Scores.Correctness -eq 0) { "SCORE_FAILED" } else { "OK" }
            }
        }
        catch {
            Write-Host " ERROR: $($_.Exception.Message)" -ForegroundColor Red
            
            $Results += [PSCustomObject]@{
                Model           = $Model
                Test            = $TestName
                Correctness     = 0
                Efficiency      = 0
                Outcome         = 0
                CompositeScore  = 0
                TokensPerSecond = 0
                OutputTokens    = 0
                Duration        = 0
                JudgeReasoning  = "Model failed: $($_.Exception.Message)"
                Status          = "ERROR"
            }
        }
        
        # Brief pause between tests
        Start-Sleep -Seconds 2
    }
    
    # Longer pause between models
    Start-Sleep -Seconds 5
}

# ═══════════════════════════════════════════════════════════════
# RESULTS COMPILATION
# ═══════════════════════════════════════════════════════════════

Clear-Host
Write-Host @"

╔═══════════════════════════════════════════════════════════════╗
║                    BENCHMARK RESULTS                          ║
║               Judge Model: $($JudgeModel.PadRight(32))║
╚═══════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Green

# Build summary table
$SummaryData = foreach ($Model in $Models) {
    $ModelResults = $Results | Where-Object { $_.Model -eq $Model }
    
    $ReasoningScore = ($ModelResults | Where-Object { $_.Test -eq "Reasoning" }).CompositeScore
    $CodingScore = ($ModelResults | Where-Object { $_.Test -eq "Coding" }).CompositeScore
    $LogicScore = ($ModelResults | Where-Object { $_.Test -eq "Logic" }).CompositeScore
    
    $ValidScores = @($ReasoningScore, $CodingScore, $LogicScore) | Where-Object { $_ -gt 0 }
    $Average = if ($ValidScores.Count -gt 0) { 
        [math]::Round(($ValidScores | Measure-Object -Average).Average, 1) 
    } else { 0 }
    
    $AvgSpeed = ($ModelResults | Where-Object { $_.TokensPerSecond -gt 0 } | 
                 Measure-Object -Property TokensPerSecond -Average).Average
    $AvgSpeed = if ($AvgSpeed) { [math]::Round($AvgSpeed, 1) } else { 0 }
    
    [PSCustomObject]@{
        Model     = $Model
        Reasoning = if ($ReasoningScore) { $ReasoningScore } else { "-" }
        Coding    = if ($CodingScore) { $CodingScore } else { "-" }
        Logic     = if ($LogicScore) { $LogicScore } else { "-" }
        Average   = $Average
        "Tok/s"   = $AvgSpeed
    }
}

# Display main results table
Write-Host "QUALITY SCORES BY TEST (Composite: Correctness + Efficiency + Outcome / 3)" -ForegroundColor Yellow
Write-Host "═════════════════════════════════════════════════════════════════════════════" -ForegroundColor DarkGray

$SummaryData | Sort-Object -Property Average -Descending | Format-Table -AutoSize

# Detailed breakdown with judge reasoning
Write-Host "`nDETAILED SCORES WITH JUDGE REASONING:" -ForegroundColor Yellow
Write-Host "═════════════════════════════════════════════════════════════════════════════" -ForegroundColor DarkGray

$Results | Where-Object { $_.Status -eq "OK" } |
    Select-Object Model, Test, Correctness, Efficiency, Outcome, CompositeScore, JudgeReasoning |
    Format-Table -AutoSize -Wrap

# Rankings by category
Write-Host "`nRANKINGS BY CATEGORY:" -ForegroundColor Yellow
Write-Host "═════════════════════════════════════════════════════════════════════════════" -ForegroundColor DarkGray

Write-Host "`n  REASONING:" -ForegroundColor Cyan
$Results | Where-Object { $_.Test -eq "Reasoning" -and $_.Status -eq "OK" } |
    Sort-Object CompositeScore -Descending |
    Select-Object -First 5 |
    ForEach-Object { Write-Host "    $($_.CompositeScore.ToString().PadLeft(4))/10  $($_.Model)" }

Write-Host "`n  CODING:" -ForegroundColor Cyan
$Results | Where-Object { $_.Test -eq "Coding" -and $_.Status -eq "OK" } |
    Sort-Object CompositeScore -Descending |
    Select-Object -First 5 |
    ForEach-Object { Write-Host "    $($_.CompositeScore.ToString().PadLeft(4))/10  $($_.Model)" }

Write-Host "`n  LOGIC:" -ForegroundColor Cyan
$Results | Where-Object { $_.Test -eq "Logic" -and $_.Status -eq "OK" } |
    Sort-Object CompositeScore -Descending |
    Select-Object -First 5 |
    ForEach-Object { Write-Host "    $($_.CompositeScore.ToString().PadLeft(4))/10  $($_.Model)" }

Write-Host "`n  SPEED (Tokens/sec):" -ForegroundColor Cyan
$Results | Where-Object { $_.Status -eq "OK" } |
    Group-Object Model |
    ForEach-Object {
        $avg = [math]::Round(($_.Group | Measure-Object TokensPerSecond -Average).Average, 1)
        [PSCustomObject]@{ Model = $_.Name; AvgSpeed = $avg }
    } |
    Sort-Object AvgSpeed -Descending |
    Select-Object -First 5 |
    ForEach-Object { Write-Host "    $($_.AvgSpeed.ToString().PadLeft(6)) tok/s  $($_.Model)" }

# Best overall
Write-Host "`n═════════════════════════════════════════════════════════════════════════════" -ForegroundColor DarkGray
$BestOverall = $SummaryData | Sort-Object Average -Descending | Select-Object -First 1
$FastestModel = $SummaryData | Sort-Object "Tok/s" -Descending | Select-Object -First 1
Write-Host "  BEST OVERALL:  $($BestOverall.Model) (Avg: $($BestOverall.Average)/10)" -ForegroundColor Green
Write-Host "  FASTEST:       $($FastestModel.Model) ($($FastestModel.'Tok/s') tok/s)" -ForegroundColor Green
Write-Host "═════════════════════════════════════════════════════════════════════════════" -ForegroundColor DarkGray

# Export results
$CsvFile = Join-Path $OutputDir "benchmark_detailed.csv"
$Results | Export-Csv -Path $CsvFile -NoTypeInformation

$SummaryFile = Join-Path $OutputDir "benchmark_summary.csv"
$SummaryData | Export-Csv -Path $SummaryFile -NoTypeInformation

Write-Host "`nFiles saved:" -ForegroundColor Gray
Write-Host "  Detailed results: $CsvFile"
Write-Host "  Summary table:    $SummaryFile"
Write-Host "  Model responses:  $OutputDir\*_response.txt"
Write-Host "  Judge reasoning:  $OutputDir\*_judge.txt"
Write-Host ""
