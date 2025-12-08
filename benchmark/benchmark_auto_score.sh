#!/bin/zsh

# benchmark_auto_score.sh - Ollama Benchmark with Automated LLM Scoring for macOS

# ═══════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════

# Model to use as the judge (should be one of your more capable models)
# Note: Using a smaller model to avoid memory issues when switching between test models
JUDGE_MODEL="phi4:14b"

# Models to benchmark
MODELS=(
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

# Ollama API endpoint
OLLAMA_URL="http://localhost:11434/api/generate"

# Output directory
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_DIR="benchmark_auto_${TIMESTAMP}"
mkdir -p "$OUTPUT_DIR"

# ═══════════════════════════════════════════════════════════════
# TEST PROMPTS
# ═══════════════════════════════════════════════════════════════

REASONING_PROMPT="Solve this step by step: A farmer has 17 sheep. All but 9 run away. How many sheep does the farmer have left? Then explain why this problem tricks most people."

REASONING_EXPECTED="The correct answer is 9 sheep. 'All but 9 run away' means 9 sheep REMAIN (not 9 leave). The trick is that people hear '17 sheep' and '9 run away' and instinctively subtract, getting 8. But the phrasing 'all but 9' means all except 9, so 9 stay."

REASONING_CRITERIA="CORRECTNESS:
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
- 1-3: Fails to address the question properly"

CODING_PROMPT="Write a Python function called 'find_duplicates' that takes a list and returns a new list containing only the elements that appear more than once. Include type hints and a docstring. Then show an example of calling it."

CODING_EXPECTED="A correct solution should:
1. Define function named 'find_duplicates'
2. Include type hints (e.g., def find_duplicates(items: list) -> list:)
3. Include a docstring explaining the function
4. Return elements that appear MORE THAN ONCE (not just duplicates of first occurrence)
5. Show a working example call
Efficient solutions use Counter, dict, or set-based O(n) approaches."

CODING_CRITERIA="CORRECTNESS:
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
- 1-3: 1 or fewer requirements met"

LOGIC_PROMPT="Three boxes are labeled 'Apples', 'Oranges', and 'Mixed'. Each label is WRONG. You can pick one fruit from one box without looking inside. What's the minimum information needed to correctly label all boxes? Explain your reasoning."

LOGIC_EXPECTED="Correct solution:
1. Pick ONE fruit from the box labeled 'Mixed'
2. Since ALL labels are wrong, the 'Mixed' box must contain ONLY apples OR ONLY oranges
3. If you pick an apple -> this box is actually 'Apples'
4. The box labeled 'Apples' cannot be Apples (wrong label) and isn't the one you identified -> must be 'Oranges'
5. The box labeled 'Oranges' must be 'Mixed'
MINIMUM INFORMATION: 1 fruit from the 'Mixed' labeled box"

LOGIC_CRITERIA="CORRECTNESS:
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
- 1-3: Does not solve the puzzle"

# ═══════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ═══════════════════════════════════════════════════════════════

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo "${RED}Error: jq is required but not installed.${NC}"
    echo "Install with: brew install jq"
    exit 1
fi

# Function to sanitize text by removing problematic control characters
# Keeps newlines (\n = 0x0A) and carriage returns (\r = 0x0D) but removes others
sanitize_for_json() {
    local text="$1"
    # Remove control characters except newline (0x0A) and carriage return (0x0D)
    # Then let jq handle the proper JSON escaping
    printf '%s' "$text" | tr -d '\000-\011\013\014\016-\037'
}

# Function to call Ollama API
ollama_generate() {
    local model="$1"
    local prompt="$2"
    local timeout="${3:-600}"

    # Escape the prompt for JSON using printf to preserve characters
    # Use a temp file to avoid shell escaping issues with large prompts
    local tmpfile=$(mktemp)
    printf '%s' "$prompt" > "$tmpfile"
    local escaped_prompt=$(jq -Rs '.' < "$tmpfile")
    rm -f "$tmpfile"

    curl -s --max-time "$timeout" "$OLLAMA_URL" \
        -H "Content-Type: application/json" \
        -d "{\"model\": \"$model\", \"prompt\": $escaped_prompt, \"stream\": false}"
}

# Function to extract JSON value (with error suppression)
json_get() {
    local json="$1"
    local query="$2"

    # Return empty if input is empty
    if [[ -z "$json" ]]; then
        echo ""
        return
    fi

    # Use a temp file to avoid issues with control characters in the JSON
    local tmpfile=$(mktemp)
    printf '%s' "$json" > "$tmpfile"
    local result=$(jq -r "$query // empty" < "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"

    # Return the result (echo adds the newline needed for command substitution)
    echo "$result"
}

# Function to check if Ollama response contains an error
ollama_has_error() {
    local response="$1"
    if [[ -z "$response" ]]; then
        return 0  # Empty response is an error
    fi
    # Check if the response contains an error field
    local tmpfile=$(mktemp)
    printf '%s' "$response" > "$tmpfile"
    local error=$(jq -r '.error // empty' < "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    [[ -n "$error" ]]
}

# Function to get Ollama error message
ollama_get_error() {
    local response="$1"
    local tmpfile=$(mktemp)
    printf '%s' "$response" > "$tmpfile"
    local error=$(jq -r '.error // "Unknown error"' < "$tmpfile" 2>/dev/null)
    rm -f "$tmpfile"
    echo "$error"
}

# Function to score with judge model
get_auto_score() {
    local test_name="$1"
    local original_prompt="$2"
    local expected_answer="$3"
    local scoring_criteria="$4"
    local model_response="$5"

    # Sanitize the model response to remove problematic control characters
    local clean_response=$(sanitize_for_json "$model_response")

    local judge_prompt="You are an expert evaluator scoring an AI model's response. Be strict but fair.

TASK: $test_name

ORIGINAL PROMPT GIVEN TO THE MODEL:
$original_prompt

EXPECTED ANSWER / KEY POINTS:
$expected_answer

SCORING CRITERIA:
$scoring_criteria

MODEL'S RESPONSE TO EVALUATE:
---
$clean_response
---

Score the response on three dimensions. Be strict - only give 10 for truly excellent responses.

You MUST respond with ONLY a JSON object in this exact format, no other text:
{\"correctness\": <1-10>, \"efficiency\": <1-10>, \"outcome\": <1-10>, \"reasoning\": \"<brief 1-2 sentence justification>\"}"

    local judge_response=$(ollama_generate "$JUDGE_MODEL" "$judge_prompt" 120)

    # Check if Ollama returned an error
    if ollama_has_error "$judge_response"; then
        local error_msg=$(ollama_get_error "$judge_response")
        printf '%s|%s|%s|%s|%s\n' "0" "0" "0" "Judge model error: $error_msg" "ERROR: $error_msg"
        return
    fi

    local judge_text=$(json_get "$judge_response" '.response')

    # Check if judge response is empty
    if [[ -z "$judge_text" ]]; then
        printf '%s|%s|%s|%s|%s\n' "0" "0" "0" "Judge returned empty response" "Empty response from judge"
        return
    fi

    # Try to extract JSON from response using a temp file to avoid control character issues
    local tmpfile=$(mktemp)
    printf '%s' "$judge_text" > "$tmpfile"
    local json_match=$(grep -o '{[^{}]*"correctness"[^{}]*}' "$tmpfile" 2>/dev/null | head -1)
    rm -f "$tmpfile"

    if [[ -n "$json_match" ]]; then
        # Parse the JSON match using temp file to avoid issues
        local tmpjson=$(mktemp)
        printf '%s' "$json_match" > "$tmpjson"
        local correctness=$(jq -r '.correctness // 0' < "$tmpjson" 2>/dev/null || echo "0")
        local efficiency=$(jq -r '.efficiency // 0' < "$tmpjson" 2>/dev/null || echo "0")
        local outcome=$(jq -r '.outcome // 0' < "$tmpjson" 2>/dev/null || echo "0")
        local reasoning=$(jq -r '.reasoning // "No reasoning provided"' < "$tmpjson" 2>/dev/null || echo "No reasoning provided")
        rm -f "$tmpjson"

        # Ensure we have numeric values
        [[ "$correctness" =~ ^[0-9]+$ ]] || correctness=0
        [[ "$efficiency" =~ ^[0-9]+$ ]] || efficiency=0
        [[ "$outcome" =~ ^[0-9]+$ ]] || outcome=0

        # Clamp values between 1 and 10 (only if > 0)
        if ((correctness > 0)); then
            correctness=$((correctness < 1 ? 1 : (correctness > 10 ? 10 : correctness)))
        fi
        if ((efficiency > 0)); then
            efficiency=$((efficiency < 1 ? 1 : (efficiency > 10 ? 10 : efficiency)))
        fi
        if ((outcome > 0)); then
            outcome=$((outcome < 1 ? 1 : (outcome > 10 ? 10 : outcome)))
        fi

        # Sanitize reasoning for output (remove pipes and newlines)
        reasoning=$(printf '%s' "$reasoning" | tr '|\n\r' '   ')
        # Sanitize judge_text for output (remove pipes and newlines to work with IFS read)
        local clean_judge=$(printf '%s' "$judge_text" | tr '|\n\r' '   ')

        printf '%s|%s|%s|%s|%s\n' "$correctness" "$efficiency" "$outcome" "$reasoning" "$clean_judge"
    else
        # Fallback: try to extract any numbers
        local tmpnum=$(mktemp)
        printf '%s' "$judge_text" > "$tmpnum"
        local numbers=($(grep -oE '\b([1-9]|10)\b' "$tmpnum" 2>/dev/null | head -3))
        rm -f "$tmpnum"

        # Sanitize judge_text for output (remove pipes and newlines to work with IFS read)
        local clean_judge=$(printf '%s' "$judge_text" | tr '|\n\r' '   ')

        if [[ ${#numbers[@]} -ge 3 ]]; then
            printf '%s|%s|%s|%s|%s\n' "${numbers[0]}" "${numbers[1]}" "${numbers[2]}" "Extracted from non-JSON response" "$clean_judge"
        else
            printf '%s|%s|%s|%s|%s\n' "0" "0" "0" "Scoring failed - could not parse response" "$clean_judge"
        fi
    fi
}

# Function to calculate average (zsh compatible)
calc_average() {
    local sum=0
    local count=0
    for val in "$@"; do
        if [[ "$val" =~ ^[0-9]+\.?[0-9]*$ ]] && (( $(echo "$val > 0" | bc -l) )); then
            sum=$(echo "$sum + $val" | bc -l)
            ((count++))
        fi
    done
    if ((count > 0)); then
        echo "scale=1; $sum / $count" | bc -l
    else
        echo "0"
    fi
}

# ═══════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ═══════════════════════════════════════════════════════════════

# Initialize results file
RESULTS_FILE="$OUTPUT_DIR/benchmark_detailed.csv"
echo "Model,Test,Correctness,Efficiency,Outcome,CompositeScore,TokensPerSecond,OutputTokens,Duration,Status,JudgeReasoning" > "$RESULTS_FILE"

# Arrays to store results for summary
declare -A REASONING_SCORES
declare -A CODING_SCORES
declare -A LOGIC_SCORES
declare -A AVG_SPEEDS

clear
echo ""
echo "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo "${CYAN}║       OLLAMA BENCHMARK WITH AUTOMATED LLM SCORING             ║${NC}"
echo "${CYAN}╠═══════════════════════════════════════════════════════════════╣${NC}"
printf "${CYAN}║  Judge Model: %-45s║${NC}\n" "$JUDGE_MODEL"
printf "${CYAN}║  Models to test: %-42s║${NC}\n" "${#MODELS[@]}"
echo "${CYAN}║  Tests per model: 3 (Reasoning, Coding, Logic)                ║${NC}"
echo "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "${GRAY}Output directory: $OUTPUT_DIR${NC}"
echo ""

# Pre-flight check: verify judge model is available
echo -n "${GRAY}Verifying judge model ($JUDGE_MODEL)...${NC}"
JUDGE_CHECK=$(ollama_generate "$JUDGE_MODEL" "Say OK" 30)
if ollama_has_error "$JUDGE_CHECK"; then
    echo " ${RED}FAILED${NC}"
    echo ""
    JUDGE_ERROR=$(ollama_get_error "$JUDGE_CHECK")
    echo "${RED}ERROR: Judge model '$JUDGE_MODEL' failed to respond.${NC}"
    if [[ -n "$JUDGE_ERROR" ]]; then
        echo "${RED}Reason: $JUDGE_ERROR${NC}"
    else
        echo "${RED}Reason: No response from Ollama (server may not be running)${NC}"
    fi
    echo ""
    echo "Possible solutions:"
    echo "  1. Restart Ollama: pkill ollama && ollama serve"
    echo "  2. Pull the model: ollama pull $JUDGE_MODEL"
    echo "  3. Use a smaller judge model by editing JUDGE_MODEL in the script"
    echo "     (Current judge model may be too large for available memory)"
    echo ""
    exit 1
fi
JUDGE_CHECK_RESPONSE=$(json_get "$JUDGE_CHECK" '.response')
if [[ -z "$JUDGE_CHECK_RESPONSE" ]]; then
    echo " ${RED}FAILED${NC}"
    echo ""
    echo "${RED}ERROR: Judge model '$JUDGE_MODEL' returned empty response.${NC}"
    echo "Try restarting Ollama: ollama serve"
    echo ""
    exit 1
fi
echo " ${GREEN}OK${NC}"
echo ""

TOTAL_TESTS=$((${#MODELS[@]} * 3))
CURRENT_TEST=0

for MODEL in "${MODELS[@]}"; do
    echo "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
    echo "${YELLOW} MODEL: $MODEL${NC}"
    echo "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"

    SAFE_MODEL_NAME=$(echo "$MODEL" | tr ':/' '__')
    MODEL_SPEEDS=()

    # Test 1: Reasoning
    ((CURRENT_TEST++))
    echo -n "  ${WHITE}[$CURRENT_TEST/$TOTAL_TESTS] Reasoning${NC}"
    echo -n "${GRAY} - Generating...${NC}"

    RESPONSE=$(ollama_generate "$MODEL" "$REASONING_PROMPT")

    if [[ -n "$RESPONSE" ]]; then
        RESPONSE_TEXT=$(json_get "$RESPONSE" '.response')
        EVAL_COUNT=$(json_get "$RESPONSE" '.eval_count')
        EVAL_DURATION=$(json_get "$RESPONSE" '.eval_duration')
        TOTAL_DURATION=$(json_get "$RESPONSE" '.total_duration')

        # Calculate metrics
        if [[ -n "$EVAL_DURATION" ]] && ((EVAL_DURATION > 0)); then
            TOKENS_PER_SEC=$(echo "scale=2; $EVAL_COUNT / ($EVAL_DURATION / 1000000000)" | bc -l)
        else
            TOKENS_PER_SEC=0
        fi
        DURATION_SEC=$(echo "scale=2; $TOTAL_DURATION / 1000000000" | bc -l)

        MODEL_SPEEDS+=("$TOKENS_PER_SEC")

        # Save response
        echo "$RESPONSE_TEXT" > "$OUTPUT_DIR/${SAFE_MODEL_NAME}_Reasoning_response.txt"

        # Score
        echo -n " Scoring..."
        SCORE_RESULT=$(get_auto_score "Reasoning" "$REASONING_PROMPT" "$REASONING_EXPECTED" "$REASONING_CRITERIA" "$RESPONSE_TEXT")

        IFS='|' read -r CORRECTNESS EFFICIENCY OUTCOME REASONING JUDGE_RAW <<< "$SCORE_RESULT"

        # Save judge output
        echo "Scores: Correctness=$CORRECTNESS, Efficiency=$EFFICIENCY, Outcome=$OUTCOME" > "$OUTPUT_DIR/${SAFE_MODEL_NAME}_Reasoning_judge.txt"
        echo "Reasoning: $REASONING" >> "$OUTPUT_DIR/${SAFE_MODEL_NAME}_Reasoning_judge.txt"
        echo "" >> "$OUTPUT_DIR/${SAFE_MODEL_NAME}_Reasoning_judge.txt"
        echo "Raw Judge Response:" >> "$OUTPUT_DIR/${SAFE_MODEL_NAME}_Reasoning_judge.txt"
        echo "$JUDGE_RAW" >> "$OUTPUT_DIR/${SAFE_MODEL_NAME}_Reasoning_judge.txt"

        if ((CORRECTNESS > 0)); then
            COMPOSITE=$(echo "scale=1; ($CORRECTNESS + $EFFICIENCY + $OUTCOME) / 3" | bc -l)
            REASONING_SCORES[$MODEL]=$COMPOSITE

            if (( $(echo "$COMPOSITE >= 8" | bc -l) )); then
                echo " ${GREEN}Score: $COMPOSITE/10 (C:$CORRECTNESS E:$EFFICIENCY O:$OUTCOME) | $TOKENS_PER_SEC tok/s${NC}"
            elif (( $(echo "$COMPOSITE >= 5" | bc -l) )); then
                echo " ${YELLOW}Score: $COMPOSITE/10 (C:$CORRECTNESS E:$EFFICIENCY O:$OUTCOME) | $TOKENS_PER_SEC tok/s${NC}"
            else
                echo " ${RED}Score: $COMPOSITE/10 (C:$CORRECTNESS E:$EFFICIENCY O:$OUTCOME) | $TOKENS_PER_SEC tok/s${NC}"
            fi

            echo "\"$MODEL\",\"Reasoning\",$CORRECTNESS,$EFFICIENCY,$OUTCOME,$COMPOSITE,$TOKENS_PER_SEC,$EVAL_COUNT,$DURATION_SEC,\"OK\",\"$REASONING\"" >> "$RESULTS_FILE"
        else
            echo " ${RED}SCORING FAILED${NC}"
            REASONING_SCORES[$MODEL]=0
            echo "\"$MODEL\",\"Reasoning\",0,0,0,0,$TOKENS_PER_SEC,$EVAL_COUNT,$DURATION_SEC,\"SCORE_FAILED\",\"$REASONING\"" >> "$RESULTS_FILE"
        fi
    else
        echo " ${RED}ERROR: No response${NC}"
        REASONING_SCORES[$MODEL]=0
        echo "\"$MODEL\",\"Reasoning\",0,0,0,0,0,0,0,\"ERROR\",\"No response from model\"" >> "$RESULTS_FILE"
    fi

    sleep 2

    # Test 2: Coding
    ((CURRENT_TEST++))
    echo -n "  ${WHITE}[$CURRENT_TEST/$TOTAL_TESTS] Coding${NC}"
    echo -n "${GRAY} - Generating...${NC}"

    RESPONSE=$(ollama_generate "$MODEL" "$CODING_PROMPT")

    if [[ -n "$RESPONSE" ]]; then
        RESPONSE_TEXT=$(json_get "$RESPONSE" '.response')
        EVAL_COUNT=$(json_get "$RESPONSE" '.eval_count')
        EVAL_DURATION=$(json_get "$RESPONSE" '.eval_duration')
        TOTAL_DURATION=$(json_get "$RESPONSE" '.total_duration')

        if [[ -n "$EVAL_DURATION" ]] && ((EVAL_DURATION > 0)); then
            TOKENS_PER_SEC=$(echo "scale=2; $EVAL_COUNT / ($EVAL_DURATION / 1000000000)" | bc -l)
        else
            TOKENS_PER_SEC=0
        fi
        DURATION_SEC=$(echo "scale=2; $TOTAL_DURATION / 1000000000" | bc -l)

        MODEL_SPEEDS+=("$TOKENS_PER_SEC")

        echo "$RESPONSE_TEXT" > "$OUTPUT_DIR/${SAFE_MODEL_NAME}_Coding_response.txt"

        echo -n " Scoring..."
        SCORE_RESULT=$(get_auto_score "Coding" "$CODING_PROMPT" "$CODING_EXPECTED" "$CODING_CRITERIA" "$RESPONSE_TEXT")

        IFS='|' read -r CORRECTNESS EFFICIENCY OUTCOME REASONING JUDGE_RAW <<< "$SCORE_RESULT"

        echo "Scores: Correctness=$CORRECTNESS, Efficiency=$EFFICIENCY, Outcome=$OUTCOME" > "$OUTPUT_DIR/${SAFE_MODEL_NAME}_Coding_judge.txt"
        echo "Reasoning: $REASONING" >> "$OUTPUT_DIR/${SAFE_MODEL_NAME}_Coding_judge.txt"
        echo "" >> "$OUTPUT_DIR/${SAFE_MODEL_NAME}_Coding_judge.txt"
        echo "Raw Judge Response:" >> "$OUTPUT_DIR/${SAFE_MODEL_NAME}_Coding_judge.txt"
        echo "$JUDGE_RAW" >> "$OUTPUT_DIR/${SAFE_MODEL_NAME}_Coding_judge.txt"

        if ((CORRECTNESS > 0)); then
            COMPOSITE=$(echo "scale=1; ($CORRECTNESS + $EFFICIENCY + $OUTCOME) / 3" | bc -l)
            CODING_SCORES[$MODEL]=$COMPOSITE

            if (( $(echo "$COMPOSITE >= 8" | bc -l) )); then
                echo " ${GREEN}Score: $COMPOSITE/10 (C:$CORRECTNESS E:$EFFICIENCY O:$OUTCOME) | $TOKENS_PER_SEC tok/s${NC}"
            elif (( $(echo "$COMPOSITE >= 5" | bc -l) )); then
                echo " ${YELLOW}Score: $COMPOSITE/10 (C:$CORRECTNESS E:$EFFICIENCY O:$OUTCOME) | $TOKENS_PER_SEC tok/s${NC}"
            else
                echo " ${RED}Score: $COMPOSITE/10 (C:$CORRECTNESS E:$EFFICIENCY O:$OUTCOME) | $TOKENS_PER_SEC tok/s${NC}"
            fi

            echo "\"$MODEL\",\"Coding\",$CORRECTNESS,$EFFICIENCY,$OUTCOME,$COMPOSITE,$TOKENS_PER_SEC,$EVAL_COUNT,$DURATION_SEC,\"OK\",\"$REASONING\"" >> "$RESULTS_FILE"
        else
            echo " ${RED}SCORING FAILED${NC}"
            CODING_SCORES[$MODEL]=0
            echo "\"$MODEL\",\"Coding\",0,0,0,0,$TOKENS_PER_SEC,$EVAL_COUNT,$DURATION_SEC,\"SCORE_FAILED\",\"$REASONING\"" >> "$RESULTS_FILE"
        fi
    else
        echo " ${RED}ERROR: No response${NC}"
        CODING_SCORES[$MODEL]=0
        echo "\"$MODEL\",\"Coding\",0,0,0,0,0,0,0,\"ERROR\",\"No response from model\"" >> "$RESULTS_FILE"
    fi

    sleep 2

    # Test 3: Logic
    ((CURRENT_TEST++))
    echo -n "  ${WHITE}[$CURRENT_TEST/$TOTAL_TESTS] Logic${NC}"
    echo -n "${GRAY} - Generating...${NC}"

    RESPONSE=$(ollama_generate "$MODEL" "$LOGIC_PROMPT")

    if [[ -n "$RESPONSE" ]]; then
        RESPONSE_TEXT=$(json_get "$RESPONSE" '.response')
        EVAL_COUNT=$(json_get "$RESPONSE" '.eval_count')
        EVAL_DURATION=$(json_get "$RESPONSE" '.eval_duration')
        TOTAL_DURATION=$(json_get "$RESPONSE" '.total_duration')

        if [[ -n "$EVAL_DURATION" ]] && ((EVAL_DURATION > 0)); then
            TOKENS_PER_SEC=$(echo "scale=2; $EVAL_COUNT / ($EVAL_DURATION / 1000000000)" | bc -l)
        else
            TOKENS_PER_SEC=0
        fi
        DURATION_SEC=$(echo "scale=2; $TOTAL_DURATION / 1000000000" | bc -l)

        MODEL_SPEEDS+=("$TOKENS_PER_SEC")

        echo "$RESPONSE_TEXT" > "$OUTPUT_DIR/${SAFE_MODEL_NAME}_Logic_response.txt"

        echo -n " Scoring..."
        SCORE_RESULT=$(get_auto_score "Logic" "$LOGIC_PROMPT" "$LOGIC_EXPECTED" "$LOGIC_CRITERIA" "$RESPONSE_TEXT")

        IFS='|' read -r CORRECTNESS EFFICIENCY OUTCOME REASONING JUDGE_RAW <<< "$SCORE_RESULT"

        echo "Scores: Correctness=$CORRECTNESS, Efficiency=$EFFICIENCY, Outcome=$OUTCOME" > "$OUTPUT_DIR/${SAFE_MODEL_NAME}_Logic_judge.txt"
        echo "Reasoning: $REASONING" >> "$OUTPUT_DIR/${SAFE_MODEL_NAME}_Logic_judge.txt"
        echo "" >> "$OUTPUT_DIR/${SAFE_MODEL_NAME}_Logic_judge.txt"
        echo "Raw Judge Response:" >> "$OUTPUT_DIR/${SAFE_MODEL_NAME}_Logic_judge.txt"
        echo "$JUDGE_RAW" >> "$OUTPUT_DIR/${SAFE_MODEL_NAME}_Logic_judge.txt"

        if ((CORRECTNESS > 0)); then
            COMPOSITE=$(echo "scale=1; ($CORRECTNESS + $EFFICIENCY + $OUTCOME) / 3" | bc -l)
            LOGIC_SCORES[$MODEL]=$COMPOSITE

            if (( $(echo "$COMPOSITE >= 8" | bc -l) )); then
                echo " ${GREEN}Score: $COMPOSITE/10 (C:$CORRECTNESS E:$EFFICIENCY O:$OUTCOME) | $TOKENS_PER_SEC tok/s${NC}"
            elif (( $(echo "$COMPOSITE >= 5" | bc -l) )); then
                echo " ${YELLOW}Score: $COMPOSITE/10 (C:$CORRECTNESS E:$EFFICIENCY O:$OUTCOME) | $TOKENS_PER_SEC tok/s${NC}"
            else
                echo " ${RED}Score: $COMPOSITE/10 (C:$CORRECTNESS E:$EFFICIENCY O:$OUTCOME) | $TOKENS_PER_SEC tok/s${NC}"
            fi

            echo "\"$MODEL\",\"Logic\",$CORRECTNESS,$EFFICIENCY,$OUTCOME,$COMPOSITE,$TOKENS_PER_SEC,$EVAL_COUNT,$DURATION_SEC,\"OK\",\"$REASONING\"" >> "$RESULTS_FILE"
        else
            echo " ${RED}SCORING FAILED${NC}"
            LOGIC_SCORES[$MODEL]=0
            echo "\"$MODEL\",\"Logic\",0,0,0,0,$TOKENS_PER_SEC,$EVAL_COUNT,$DURATION_SEC,\"SCORE_FAILED\",\"$REASONING\"" >> "$RESULTS_FILE"
        fi
    else
        echo " ${RED}ERROR: No response${NC}"
        LOGIC_SCORES[$MODEL]=0
        echo "\"$MODEL\",\"Logic\",0,0,0,0,0,0,0,\"ERROR\",\"No response from model\"" >> "$RESULTS_FILE"
    fi

    # Calculate average speed for this model
    AVG_SPEEDS[$MODEL]=$(calc_average "${MODEL_SPEEDS[@]}")

    echo ""
    sleep 5
done

# ═══════════════════════════════════════════════════════════════
# RESULTS COMPILATION
# ═══════════════════════════════════════════════════════════════

clear
echo ""
echo "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo "${GREEN}║                    BENCHMARK RESULTS                          ║${NC}"
printf "${GREEN}║               Judge Model: %-32s║${NC}\n" "$JUDGE_MODEL"
echo "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Create summary CSV
SUMMARY_FILE="$OUTPUT_DIR/benchmark_summary.csv"
echo "Model,Reasoning,Coding,Logic,Average,Tok/s" > "$SUMMARY_FILE"

echo "${YELLOW}QUALITY SCORES BY TEST (Composite: Correctness + Efficiency + Outcome / 3)${NC}"
echo "${GRAY}═════════════════════════════════════════════════════════════════════════════${NC}"
echo ""

# Print header
printf "%-28s %10s %10s %10s %10s %10s\n" "Model" "Reasoning" "Coding" "Logic" "Average" "Tok/s"
printf "%-28s %10s %10s %10s %10s %10s\n" "----------------------------" "----------" "----------" "----------" "----------" "----------"

# Collect data for sorting
declare -a SUMMARY_LINES

for MODEL in "${MODELS[@]}"; do
    R_SCORE=${REASONING_SCORES[$MODEL]:-0}
    C_SCORE=${CODING_SCORES[$MODEL]:-0}
    L_SCORE=${LOGIC_SCORES[$MODEL]:-0}
    SPEED=${AVG_SPEEDS[$MODEL]:-0}

    # Calculate average
    AVG=$(calc_average "$R_SCORE" "$C_SCORE" "$L_SCORE")

    # Format scores for display
    R_DISP=$([ "$R_SCORE" = "0" ] && echo "-" || echo "$R_SCORE")
    C_DISP=$([ "$C_SCORE" = "0" ] && echo "-" || echo "$C_SCORE")
    L_DISP=$([ "$L_SCORE" = "0" ] && echo "-" || echo "$L_SCORE")

    # Store for sorting (prepend average for sort, will strip later)
    SUMMARY_LINES+=("$AVG|$MODEL|$R_DISP|$C_DISP|$L_DISP|$AVG|$SPEED")

    # Write to CSV
    echo "\"$MODEL\",$R_SCORE,$C_SCORE,$L_SCORE,$AVG,$SPEED" >> "$SUMMARY_FILE"
done

# Sort by average (descending) and print
echo "${SUMMARY_LINES[@]}" | tr ' ' '\n' | sort -t'|' -k1 -rn | while IFS='|' read -r SORT_KEY MODEL R C L AVG SPEED; do
    printf "%-28s %10s %10s %10s %10s %10s\n" "$MODEL" "$R" "$C" "$L" "$AVG" "$SPEED"
done

echo ""
echo "${YELLOW}RANKINGS BY CATEGORY:${NC}"
echo "${GRAY}═════════════════════════════════════════════════════════════════════════════${NC}"

# Best Reasoning
echo ""
echo "  ${CYAN}REASONING:${NC}"
for MODEL in "${MODELS[@]}"; do
    SCORE=${REASONING_SCORES[$MODEL]:-0}
    if (( $(echo "$SCORE > 0" | bc -l) )); then
        echo "$SCORE|$MODEL"
    fi
done | sort -t'|' -k1 -rn | head -5 | while IFS='|' read -r SCORE MODEL; do
    printf "    %5s/10  %s\n" "$SCORE" "$MODEL"
done

# Best Coding
echo ""
echo "  ${CYAN}CODING:${NC}"
for MODEL in "${MODELS[@]}"; do
    SCORE=${CODING_SCORES[$MODEL]:-0}
    if (( $(echo "$SCORE > 0" | bc -l) )); then
        echo "$SCORE|$MODEL"
    fi
done | sort -t'|' -k1 -rn | head -5 | while IFS='|' read -r SCORE MODEL; do
    printf "    %5s/10  %s\n" "$SCORE" "$MODEL"
done

# Best Logic
echo ""
echo "  ${CYAN}LOGIC:${NC}"
for MODEL in "${MODELS[@]}"; do
    SCORE=${LOGIC_SCORES[$MODEL]:-0}
    if (( $(echo "$SCORE > 0" | bc -l) )); then
        echo "$SCORE|$MODEL"
    fi
done | sort -t'|' -k1 -rn | head -5 | while IFS='|' read -r SCORE MODEL; do
    printf "    %5s/10  %s\n" "$SCORE" "$MODEL"
done

# Fastest
echo ""
echo "  ${CYAN}SPEED (Tokens/sec):${NC}"
for MODEL in "${MODELS[@]}"; do
    SPEED=${AVG_SPEEDS[$MODEL]:-0}
    if (( $(echo "$SPEED > 0" | bc -l) )); then
        echo "$SPEED|$MODEL"
    fi
done | sort -t'|' -k1 -rn | head -5 | while IFS='|' read -r SPEED MODEL; do
    printf "    %8s tok/s  %s\n" "$SPEED" "$MODEL"
done

# Best overall
echo ""
echo "${GRAY}═════════════════════════════════════════════════════════════════════════════${NC}"

BEST_OVERALL=""
BEST_AVG=0
FASTEST_MODEL=""
FASTEST_SPEED=0

for MODEL in "${MODELS[@]}"; do
    R=${REASONING_SCORES[$MODEL]:-0}
    C=${CODING_SCORES[$MODEL]:-0}
    L=${LOGIC_SCORES[$MODEL]:-0}
    AVG=$(calc_average "$R" "$C" "$L")
    SPEED=${AVG_SPEEDS[$MODEL]:-0}

    if (( $(echo "$AVG > $BEST_AVG" | bc -l) )); then
        BEST_AVG=$AVG
        BEST_OVERALL=$MODEL
    fi
    if (( $(echo "$SPEED > $FASTEST_SPEED" | bc -l) )); then
        FASTEST_SPEED=$SPEED
        FASTEST_MODEL=$MODEL
    fi
done

echo "  ${GREEN}BEST OVERALL:  $BEST_OVERALL (Avg: $BEST_AVG/10)${NC}"
echo "  ${GREEN}FASTEST:       $FASTEST_MODEL ($FASTEST_SPEED tok/s)${NC}"
echo "${GRAY}═════════════════════════════════════════════════════════════════════════════${NC}"

echo ""
echo "${GRAY}Files saved:${NC}"
echo "  Detailed results: $RESULTS_FILE"
echo "  Summary table:    $SUMMARY_FILE"
echo "  Model responses:  $OUTPUT_DIR/*_response.txt"
echo "  Judge reasoning:  $OUTPUT_DIR/*_judge.txt"
echo ""
