# Ollama Model Benchmark Suite

A cross-platform benchmarking toolkit for evaluating locally-run LLMs via [Ollama](https://ollama.com). Automatically scores model responses on **Reasoning**, **Coding**, and **Logic** tasks using an LLM-as-judge approach.

![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux-blue)
![Shell](https://img.shields.io/badge/shell-PowerShell%20%7C%20zsh-green)
![License](https://img.shields.io/badge/license-MIT-lightgrey)

## Overview

Comparing LLM performance across different hardware setups is challenging. This toolkit provides standardised benchmarks that can be run on any machine with Ollama installed, producing consistent, comparable metrics.

**Key Features:**
- 🔄 Cross-platform scripts (PowerShell for Windows, zsh for macOS/Linux)
- 🤖 Automated scoring using a local "judge" model
- 📊 Structured CSV output for easy comparison
- 🎯 Three benchmark categories testing different capabilities
- ⚡ Captures both quality scores and performance metrics (tokens/sec)

## Benchmarks

| Test | Description | What It Measures |
|------|-------------|------------------|
| **Reasoning** | "All but 9 sheep" problem | Basic reasoning, linguistic comprehension, explanation ability |
| **Coding** | Python `find_duplicates` function | Code correctness, efficiency (Big-O), completeness (type hints, docstrings) |
| **Logic** | Three mislabelled boxes puzzle | Deductive reasoning, step-by-step problem solving |

Each response is scored on three dimensions:
- **Correctness** (1-10): Is the answer right?
- **Efficiency** (1-10): Is the approach optimal/concise?
- **Outcome** (1-10): Does it fully address the question?

## Prerequisites

### All Platforms
- [Ollama](https://ollama.com/download) installed and running
- At least one model pulled (e.g., `ollama pull llama3.3:latest`)

### Windows
- PowerShell 5.1+ (pre-installed on Windows 10/11)

### macOS / Linux
- zsh shell (default on macOS, install via package manager on Linux)
- `jq` for JSON parsing:
```bash
  # macOS
  brew install jq
  
  # Ubuntu/Debian
  sudo apt install jq
  
  # Fedora
  sudo dnf install jq
```

## Installation
```bash
# Clone the repository
git clone https://github.com/yourusername/ollama-benchmark.git
cd ollama-benchmark

# Make the zsh script executable (macOS/Linux)
chmod +x benchmark_auto_score.sh
```

## Configuration

Edit the configuration section at the top of either script:

### Models to Benchmark
```powershell
# PowerShell (benchmark_auto_score.ps1)
$Models = @(
    "mistral:latest"
    "llama3.3:latest"
    "deepseek-r1:7b"
    # Add or remove models as needed
)
```
```bash
# zsh (benchmark_auto_score.sh)
MODELS=(
    "mistral:latest"
    "llama3.3:latest"
    "deepseek-r1:7b"
    # Add or remove models as needed
)
```

### Judge Model

The judge model evaluates responses from other models. Use your most capable available model:
```powershell
# PowerShell
$JudgeModel = "llama3.3:latest"
```
```bash
# zsh
JUDGE_MODEL="llama3.3:latest"
```

> ⚠️ **Note:** Avoid having a model judge itself, as this may inflate scores. If benchmarking `llama3.3`, consider using `deepseek-r1:32b` as the judge, or vice versa.

## Usage

### Windows (PowerShell)
```powershell
# Open PowerShell and navigate to the repository
cd path\to\ollama-benchmark

# If you encounter execution policy errors, run:
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Run the benchmark
.\benchmark_auto_score.ps1
```

### macOS / Linux (zsh)
```bash
# Navigate to the repository
cd path/to/ollama-benchmark

# Run the benchmark
./benchmark_auto_score.sh
```

### Runtime Expectations

| Models | Approximate Time |
|--------|------------------|
| 5 models | 15-30 minutes |
| 10 models | 30-60 minutes |
| 10 models + large judge | 1-2 hours |

Times vary significantly based on hardware and model sizes.

## Output

Each run creates a timestamped directory containing:
```
benchmark_auto_YYYYMMDD_HHMMSS/
├── benchmark_detailed.csv      # All scores with judge reasoning
├── benchmark_summary.csv       # Summary table for quick comparison
├── modelname_Reasoning_response.txt
├── modelname_Reasoning_judge.txt
├── modelname_Coding_response.txt
├── modelname_Coding_judge.txt
├── modelname_Logic_response.txt
└── modelname_Logic_judge.txt
```

### Sample Summary Output
```
Model                    Reasoning  Coding  Logic  Average  Tok/s
----------------------------  ----------  ----------  ----------  ----------  ----------
deepseek-r1:32b               9.3        8.7        9.7        9.2        12.4
qwen3-coder:30b               8.0        9.3        8.3        8.5        28.6
llama3.3:latest               8.7        7.7        8.7        8.4        18.2
phi4:14b                      7.3        8.0        7.0        7.4        35.1
mistral:latest                6.7        6.3        6.0        6.3        42.8
```

## Scoring Methodology

### Reasoning Task (Farmer/Sheep Problem)

**Prompt:** *"A farmer has 17 sheep. All but 9 run away. How many sheep does the farmer have left?"*

| Score | Criteria |
|-------|----------|
| 10 | Correct answer (9), clearly explains the linguistic trick |
| 7-9 | Correct answer, explanation has minor gaps |
| 4-6 | Correct answer but wrong reasoning, OR wrong answer with partial understanding |
| 1-3 | Wrong answer, fundamentally misunderstands the problem |

### Coding Task (find_duplicates Function)

**Checklist:**
- [ ] Function named `find_duplicates`
- [ ] Type hints present
- [ ] Docstring included
- [ ] Working example provided
- [ ] Code executes correctly

| Score | Criteria |
|-------|----------|
| 10 | All 5 requirements, O(n) solution, clean code |
| 7-9 | 4/5 requirements, minor issues |
| 4-6 | 2-3/5 requirements, logic errors |
| 1-3 | Fundamentally broken |

### Logic Task (Three Boxes Puzzle)

**Correct Solution:** Pick from the "Mixed" labelled box. Since all labels are wrong, this box contains only one fruit type, revealing its true contents and allowing deduction of the other two.

| Score | Criteria |
|-------|----------|
| 10 | Correct box choice, complete deduction chain |
| 7-9 | Correct answer, minor gaps in explanation |
| 4-6 | Wrong box or incomplete deduction |
| 1-3 | Fundamentally wrong approach |

## Comparing Across Machines

To compare results between different hardware setups:

1. Run the benchmark on each machine with identical configuration
2. Copy the `benchmark_summary.csv` files to a single location
3. Use the comparison script or manually compare in a spreadsheet

### Quick Comparison (Manual)
```bash
# Rename output files by machine
mv machine1/benchmark_summary.csv results/summary_windows_rtx4090.csv
mv machine2/benchmark_summary.csv results/summary_mac_m3max.csv
```

### Key Metrics to Compare

| Metric | Indicates |
|--------|-----------|
| **Average Score** | Overall model quality on your hardware |
| **Tok/s** | Raw inference speed |
| **Score / Tok/s ratio** | Quality-adjusted performance |

## Troubleshooting

### "Connection refused" error
Ensure Ollama is running:
```bash
ollama serve
```

### Judge returns unparseable scores
The script includes fallback parsing, but if scores consistently fail:
- Try a more capable judge model
- Check the `*_judge.txt` files for raw output
- Ensure the judge model follows instructions well

### Out of memory errors
- Reduce the number of concurrent models
- Use quantised model versions (e.g., `model:7b-q4_0`)
- Increase swap space

### zsh: permission denied
```bash
chmod +x benchmark_auto_score.sh
```

### PowerShell execution policy error
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## Customisation

### Adding Custom Benchmarks

To add a new benchmark category, add entries to the prompts configuration:

**PowerShell:**
```powershell
$Prompts["NewCategory"] = @{
    Prompt = "Your test prompt here"
    ExpectedAnswer = "What constitutes a correct answer"
    ScoringCriteria = "Detailed rubric for the judge"
}
```

**zsh:**
```bash
NEWCATEGORY_PROMPT="Your test prompt here"
NEWCATEGORY_EXPECTED="What constitutes a correct answer"
NEWCATEGORY_CRITERIA="Detailed rubric for the judge"
```

### Using an External Judge (API)

For more objective scoring, you can modify the scripts to use an external API (OpenAI, Anthropic) as the judge. Replace the `ollama_generate` / `Invoke-OllamaGenerate` calls in the scoring function with your preferred API client.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request. For major changes, please open an issue first to discuss what you would like to change.

### Development Guidelines
- Maintain feature parity between PowerShell and zsh versions
- Test on both Windows and macOS before submitting
- Update this README if adding new features

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgements

- [Ollama](https://ollama.com) for making local LLM deployment accessible
- The open-source LLM community for the models

---

**Found this useful?** Give it a ⭐ on GitHub!

