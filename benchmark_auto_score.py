#!/usr/bin/env python3
"""
Ollama Benchmark with Automated LLM Scoring

This script benchmarks multiple Ollama models on reasoning, coding, and logic tasks,
using another LLM as an automated judge to score the responses.
"""

import json
import os
import re
import sys
import time
from datetime import datetime
from pathlib import Path
from typing import Optional

import requests

# ═══════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════

# Model to use as the judge (should be one of your more capable models)
JUDGE_MODEL = "phi4:14b"

# Models to benchmark
MODELS = [
    "mistral:latest",
    "deepseek-coder:33b",
    "deepseek-r1:7b",
    "deepseek-r1:32b",
    "deepseek-r1:8b",
    "llama3.3:latest",
    "qwen3-coder:30b",
    "mistral-small3.2:latest",
    "phi4:14b",
    "codellama:34b",
]

# Ollama API endpoint
OLLAMA_URL = "http://localhost:11434/api/generate"

# Timeouts (in seconds)
GENERATE_TIMEOUT = 600
JUDGE_TIMEOUT = 120

# ═══════════════════════════════════════════════════════════════
# TEST PROMPTS AND CRITERIA
# ═══════════════════════════════════════════════════════════════

TESTS = {
    "Reasoning": {
        "prompt": "Solve this step by step: A farmer has 17 sheep. All but 9 run away. How many sheep does the farmer have left? Then explain why this problem tricks most people.",
        "expected": """The correct answer is 9 sheep. 'All but 9 run away' means 9 sheep REMAIN (not 9 leave). The trick is that people hear '17 sheep' and '9 run away' and instinctively subtract, getting 8. But the phrasing 'all but 9' means all except 9, so 9 stay.""",
        "criteria": """CORRECTNESS:
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
- 1-3: Fails to address the question properly"""
    },
    "Coding": {
        "prompt": "Write a Python function called 'find_duplicates' that takes a list and returns a new list containing only the elements that appear more than once. Include type hints and a docstring. Then show an example of calling it.",
        "expected": """A correct solution should:
1. Define function named 'find_duplicates'
2. Include type hints (e.g., def find_duplicates(items: list) -> list:)
3. Include a docstring explaining the function
4. Return elements that appear MORE THAN ONCE (not just duplicates of first occurrence)
5. Show a working example call
Efficient solutions use Counter, dict, or set-based O(n) approaches.""",
        "criteria": """CORRECTNESS:
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
- 1-3: 1 or fewer requirements met"""
    },
    "Logic": {
        "prompt": "Three boxes are labeled 'Apples', 'Oranges', and 'Mixed'. Each label is WRONG. You can pick one fruit from one box without looking inside. What's the minimum information needed to correctly label all boxes? Explain your reasoning.",
        "expected": """Correct solution:
1. Pick ONE fruit from the box labeled 'Mixed'
2. Since ALL labels are wrong, the 'Mixed' box must contain ONLY apples OR ONLY oranges
3. If you pick an apple -> this box is actually 'Apples'
4. The box labeled 'Apples' cannot be Apples (wrong label) and isn't the one you identified -> must be 'Oranges'
5. The box labeled 'Oranges' must be 'Mixed'
MINIMUM INFORMATION: 1 fruit from the 'Mixed' labeled box""",
        "criteria": """CORRECTNESS:
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
- 1-3: Does not solve the puzzle"""
    }
}

# ═══════════════════════════════════════════════════════════════
# COLORS FOR OUTPUT
# ═══════════════════════════════════════════════════════════════

class Colors:
    RED = '\033[0;31m'
    GREEN = '\033[0;32m'
    YELLOW = '\033[1;33m'
    CYAN = '\033[0;36m'
    WHITE = '\033[1;37m'
    GRAY = '\033[0;90m'
    NC = '\033[0m'  # No Color


# ═══════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════

def ollama_generate(model: str, prompt: str, timeout: int = GENERATE_TIMEOUT) -> dict:
    """
    Call the Ollama API to generate a response.

    Returns a dict with 'response', 'eval_count', 'eval_duration', 'total_duration'
    or 'error' if something went wrong.
    """
    try:
        response = requests.post(
            OLLAMA_URL,
            json={"model": model, "prompt": prompt, "stream": False},
            timeout=timeout
        )
        response.raise_for_status()
        return response.json()
    except requests.exceptions.Timeout:
        return {"error": f"Request timed out after {timeout}s"}
    except requests.exceptions.ConnectionError:
        return {"error": "Could not connect to Ollama. Is 'ollama serve' running?"}
    except requests.exceptions.RequestException as e:
        return {"error": str(e)}
    except json.JSONDecodeError as e:
        return {"error": f"Invalid JSON response: {e}"}


def get_auto_score(test_name: str, original_prompt: str, expected: str,
                   criteria: str, model_response: str) -> dict:
    """
    Use the judge model to score a response.

    Returns a dict with 'correctness', 'efficiency', 'outcome', 'reasoning', 'raw_response'
    """
    judge_prompt = f"""You are an expert evaluator scoring an AI model's response. Be strict but fair.

TASK: {test_name}

ORIGINAL PROMPT GIVEN TO THE MODEL:
{original_prompt}

EXPECTED ANSWER / KEY POINTS:
{expected}

SCORING CRITERIA:
{criteria}

MODEL'S RESPONSE TO EVALUATE:
---
{model_response}
---

Score the response on three dimensions. Be strict - only give 10 for truly excellent responses.

You MUST respond with ONLY a JSON object in this exact format, no other text:
{{"correctness": <1-10>, "efficiency": <1-10>, "outcome": <1-10>, "reasoning": "<brief 1-2 sentence justification>"}}"""

    result = ollama_generate(JUDGE_MODEL, judge_prompt, JUDGE_TIMEOUT)

    if "error" in result:
        return {
            "correctness": 0,
            "efficiency": 0,
            "outcome": 0,
            "reasoning": f"Judge error: {result['error']}",
            "raw_response": result.get("error", "")
        }

    judge_text = result.get("response", "")

    if not judge_text:
        return {
            "correctness": 0,
            "efficiency": 0,
            "outcome": 0,
            "reasoning": "Judge returned empty response",
            "raw_response": ""
        }

    # Try to extract JSON from the response
    # Look for a JSON object containing "correctness"
    json_match = re.search(r'\{[^{}]*"correctness"[^{}]*\}', judge_text)

    if json_match:
        try:
            scores = json.loads(json_match.group())
            correctness = int(scores.get("correctness", 0))
            efficiency = int(scores.get("efficiency", 0))
            outcome = int(scores.get("outcome", 0))
            reasoning = scores.get("reasoning", "No reasoning provided")

            # Clamp values between 1 and 10
            correctness = max(1, min(10, correctness)) if correctness > 0 else 0
            efficiency = max(1, min(10, efficiency)) if efficiency > 0 else 0
            outcome = max(1, min(10, outcome)) if outcome > 0 else 0

            return {
                "correctness": correctness,
                "efficiency": efficiency,
                "outcome": outcome,
                "reasoning": reasoning,
                "raw_response": judge_text
            }
        except (json.JSONDecodeError, ValueError, TypeError):
            pass

    # Fallback: try to extract any numbers
    numbers = re.findall(r'\b([1-9]|10)\b', judge_text)
    if len(numbers) >= 3:
        return {
            "correctness": int(numbers[0]),
            "efficiency": int(numbers[1]),
            "outcome": int(numbers[2]),
            "reasoning": "Extracted from non-JSON response",
            "raw_response": judge_text
        }

    return {
        "correctness": 0,
        "efficiency": 0,
        "outcome": 0,
        "reasoning": "Could not parse judge response",
        "raw_response": judge_text
    }


def calculate_tokens_per_sec(eval_count: int, eval_duration: int) -> float:
    """Calculate tokens per second from Ollama metrics."""
    if eval_duration and eval_duration > 0:
        return round(eval_count / (eval_duration / 1_000_000_000), 2)
    return 0.0


def print_score(composite: float, correctness: int, efficiency: int,
                outcome: int, tokens_per_sec: float):
    """Print a formatted score line with color coding."""
    if composite >= 8:
        color = Colors.GREEN
    elif composite >= 5:
        color = Colors.YELLOW
    else:
        color = Colors.RED

    print(f" {color}Score: {composite:.1f}/10 (C:{correctness} E:{efficiency} O:{outcome}) | {tokens_per_sec} tok/s{Colors.NC}")


# ═══════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════════════════════

def main():
    # Create output directory
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_dir = Path(f"benchmark_auto_{timestamp}")
    output_dir.mkdir(exist_ok=True)

    # Initialize results
    results = []
    model_scores = {model: {"Reasoning": 0, "Coding": 0, "Logic": 0, "speeds": []}
                    for model in MODELS}

    # Print header
    print()
    print(f"{Colors.CYAN}╔═══════════════════════════════════════════════════════════════╗{Colors.NC}")
    print(f"{Colors.CYAN}║       OLLAMA BENCHMARK WITH AUTOMATED LLM SCORING             ║{Colors.NC}")
    print(f"{Colors.CYAN}╠═══════════════════════════════════════════════════════════════╣{Colors.NC}")
    print(f"{Colors.CYAN}║  Judge Model: {JUDGE_MODEL:<45}║{Colors.NC}")
    print(f"{Colors.CYAN}║  Models to test: {len(MODELS):<42}║{Colors.NC}")
    print(f"{Colors.CYAN}║  Tests per model: 3 (Reasoning, Coding, Logic)                ║{Colors.NC}")
    print(f"{Colors.CYAN}╚═══════════════════════════════════════════════════════════════╝{Colors.NC}")
    print()
    print(f"{Colors.GRAY}Output directory: {output_dir}{Colors.NC}")
    print()

    # Pre-flight check: verify judge model
    print(f"{Colors.GRAY}Verifying judge model ({JUDGE_MODEL})...{Colors.NC}", end="", flush=True)
    judge_check = ollama_generate(JUDGE_MODEL, "Say OK", 30)

    if "error" in judge_check:
        print(f" {Colors.RED}FAILED{Colors.NC}")
        print()
        print(f"{Colors.RED}ERROR: Judge model '{JUDGE_MODEL}' failed to respond.{Colors.NC}")
        print(f"{Colors.RED}Reason: {judge_check['error']}{Colors.NC}")
        print()
        print("Possible solutions:")
        print("  1. Restart Ollama: pkill ollama && ollama serve")
        print(f"  2. Pull the model: ollama pull {JUDGE_MODEL}")
        print("  3. Use a smaller judge model by editing JUDGE_MODEL in the script")
        print()
        sys.exit(1)

    if not judge_check.get("response"):
        print(f" {Colors.RED}FAILED{Colors.NC}")
        print()
        print(f"{Colors.RED}ERROR: Judge model returned empty response.{Colors.NC}")
        sys.exit(1)

    print(f" {Colors.GREEN}OK{Colors.NC}")
    print()

    total_tests = len(MODELS) * len(TESTS)
    current_test = 0

    # Run benchmarks
    for model in MODELS:
        print(f"{Colors.YELLOW}═══════════════════════════════════════════════════════════════{Colors.NC}")
        print(f"{Colors.YELLOW} MODEL: {model}{Colors.NC}")
        print(f"{Colors.YELLOW}═══════════════════════════════════════════════════════════════{Colors.NC}")

        safe_model_name = model.replace(":", "_").replace("/", "_")

        for test_name, test_data in TESTS.items():
            current_test += 1
            print(f"  {Colors.WHITE}[{current_test}/{total_tests}] {test_name}{Colors.NC}", end="")
            print(f"{Colors.GRAY} - Generating...{Colors.NC}", end="", flush=True)

            # Generate response
            response = ollama_generate(model, test_data["prompt"])

            if "error" in response:
                print(f" {Colors.RED}ERROR: {response['error']}{Colors.NC}")
                results.append({
                    "model": model,
                    "test": test_name,
                    "correctness": 0,
                    "efficiency": 0,
                    "outcome": 0,
                    "composite": 0,
                    "tokens_per_sec": 0,
                    "output_tokens": 0,
                    "duration": 0,
                    "status": "ERROR",
                    "reasoning": response["error"]
                })
                continue

            response_text = response.get("response", "")
            eval_count = response.get("eval_count", 0)
            eval_duration = response.get("eval_duration", 0)
            total_duration = response.get("total_duration", 0)

            tokens_per_sec = calculate_tokens_per_sec(eval_count, eval_duration)
            duration_sec = round(total_duration / 1_000_000_000, 2) if total_duration else 0

            model_scores[model]["speeds"].append(tokens_per_sec)

            # Save response
            response_file = output_dir / f"{safe_model_name}_{test_name}_response.txt"
            response_file.write_text(response_text)

            # Score the response
            print(" Scoring...", end="", flush=True)
            scores = get_auto_score(
                test_name,
                test_data["prompt"],
                test_data["expected"],
                test_data["criteria"],
                response_text
            )

            # Save judge output
            judge_file = output_dir / f"{safe_model_name}_{test_name}_judge.txt"
            judge_content = f"""Scores: Correctness={scores['correctness']}, Efficiency={scores['efficiency']}, Outcome={scores['outcome']}
Reasoning: {scores['reasoning']}

Raw Judge Response:
{scores['raw_response']}
"""
            judge_file.write_text(judge_content)

            if scores["correctness"] > 0:
                composite = round((scores["correctness"] + scores["efficiency"] + scores["outcome"]) / 3, 1)
                model_scores[model][test_name] = composite
                print_score(composite, scores["correctness"], scores["efficiency"],
                           scores["outcome"], tokens_per_sec)
                status = "OK"
            else:
                print(f" {Colors.RED}SCORING FAILED{Colors.NC}")
                composite = 0
                status = "SCORE_FAILED"

            results.append({
                "model": model,
                "test": test_name,
                "correctness": scores["correctness"],
                "efficiency": scores["efficiency"],
                "outcome": scores["outcome"],
                "composite": composite,
                "tokens_per_sec": tokens_per_sec,
                "output_tokens": eval_count,
                "duration": duration_sec,
                "status": status,
                "reasoning": scores["reasoning"]
            })

            time.sleep(2)  # Brief pause between tests

        print()
        time.sleep(5)  # Pause between models

    # ═══════════════════════════════════════════════════════════════
    # RESULTS COMPILATION
    # ═══════════════════════════════════════════════════════════════

    # Write detailed CSV
    csv_file = output_dir / "benchmark_detailed.csv"
    with open(csv_file, "w") as f:
        f.write("Model,Test,Correctness,Efficiency,Outcome,CompositeScore,TokensPerSecond,OutputTokens,Duration,Status,JudgeReasoning\n")
        for r in results:
            # Escape quotes in reasoning
            reasoning = r["reasoning"].replace('"', '""')
            f.write(f'"{r["model"]}","{r["test"]}",{r["correctness"]},{r["efficiency"]},{r["outcome"]},{r["composite"]},{r["tokens_per_sec"]},{r["output_tokens"]},{r["duration"]},"{r["status"]}","{reasoning}"\n')

    # Calculate summaries
    summaries = []
    for model in MODELS:
        scores = model_scores[model]
        r_score = scores["Reasoning"]
        c_score = scores["Coding"]
        l_score = scores["Logic"]

        valid_scores = [s for s in [r_score, c_score, l_score] if s > 0]
        avg_score = round(sum(valid_scores) / len(valid_scores), 1) if valid_scores else 0

        speeds = scores["speeds"]
        avg_speed = round(sum(speeds) / len(speeds), 2) if speeds else 0

        summaries.append({
            "model": model,
            "reasoning": r_score,
            "coding": c_score,
            "logic": l_score,
            "average": avg_score,
            "speed": avg_speed
        })

    # Sort by average score
    summaries.sort(key=lambda x: x["average"], reverse=True)

    # Write summary CSV
    summary_file = output_dir / "benchmark_summary.csv"
    with open(summary_file, "w") as f:
        f.write("Model,Reasoning,Coding,Logic,Average,Tok/s\n")
        for s in summaries:
            f.write(f'"{s["model"]}",{s["reasoning"]},{s["coding"]},{s["logic"]},{s["average"]},{s["speed"]}\n')

    # Print results
    print()
    print(f"{Colors.GREEN}╔═══════════════════════════════════════════════════════════════╗{Colors.NC}")
    print(f"{Colors.GREEN}║                    BENCHMARK RESULTS                          ║{Colors.NC}")
    print(f"{Colors.GREEN}║               Judge Model: {JUDGE_MODEL:<32}║{Colors.NC}")
    print(f"{Colors.GREEN}╚═══════════════════════════════════════════════════════════════╝{Colors.NC}")
    print()

    print(f"{Colors.YELLOW}QUALITY SCORES BY TEST (Composite: Correctness + Efficiency + Outcome / 3){Colors.NC}")
    print(f"{Colors.GRAY}═════════════════════════════════════════════════════════════════════════════{Colors.NC}")
    print()

    # Print table header
    print(f"{'Model':<28} {'Reasoning':>10} {'Coding':>10} {'Logic':>10} {'Average':>10} {'Tok/s':>10}")
    print(f"{'-'*28} {'-'*10} {'-'*10} {'-'*10} {'-'*10} {'-'*10}")

    for s in summaries:
        r_disp = "-" if s["reasoning"] == 0 else str(s["reasoning"])
        c_disp = "-" if s["coding"] == 0 else str(s["coding"])
        l_disp = "-" if s["logic"] == 0 else str(s["logic"])
        print(f"{s['model']:<28} {r_disp:>10} {c_disp:>10} {l_disp:>10} {s['average']:>10} {s['speed']:>10}")

    # Print rankings
    print()
    print(f"{Colors.YELLOW}RANKINGS BY CATEGORY:{Colors.NC}")
    print(f"{Colors.GRAY}═════════════════════════════════════════════════════════════════════════════{Colors.NC}")

    for category in ["Reasoning", "Coding", "Logic"]:
        print()
        print(f"  {Colors.CYAN}{category.upper()}:{Colors.NC}")
        ranked = sorted(
            [(s["model"], s[category.lower()]) for s in summaries if s[category.lower()] > 0],
            key=lambda x: x[1],
            reverse=True
        )[:5]
        for model, score in ranked:
            print(f"    {score:>5}/10  {model}")

    # Speed ranking
    print()
    print(f"  {Colors.CYAN}SPEED (Tokens/sec):{Colors.NC}")
    speed_ranked = sorted(
        [(s["model"], s["speed"]) for s in summaries if s["speed"] > 0],
        key=lambda x: x[1],
        reverse=True
    )[:5]
    for model, speed in speed_ranked:
        print(f"    {speed:>8} tok/s  {model}")

    # Best overall
    print()
    print(f"{Colors.GRAY}═════════════════════════════════════════════════════════════════════════════{Colors.NC}")

    if summaries:
        best = summaries[0]
        fastest = max(summaries, key=lambda x: x["speed"])
        print(f"  {Colors.GREEN}BEST OVERALL:  {best['model']} (Avg: {best['average']}/10){Colors.NC}")
        print(f"  {Colors.GREEN}FASTEST:       {fastest['model']} ({fastest['speed']} tok/s){Colors.NC}")

    print(f"{Colors.GRAY}═════════════════════════════════════════════════════════════════════════════{Colors.NC}")
    print()
    print(f"{Colors.GRAY}Files saved:{Colors.NC}")
    print(f"  Detailed results: {csv_file}")
    print(f"  Summary table:    {summary_file}")
    print(f"  Model responses:  {output_dir}/*_response.txt")
    print(f"  Judge reasoning:  {output_dir}/*_judge.txt")
    print()


if __name__ == "__main__":
    main()

