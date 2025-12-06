#!/bin/zsh

# pull_models_parallel.sh - Download models in parallel (use with caution)

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

# Colors
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
GRAY='\033[0;90m'
NC='\033[0m'

# Maximum parallel downloads (adjust based on your bandwidth)
MAX_PARALLEL=3

echo ""
echo "${CYAN}Pulling ${#MODELS[@]} models (max $MAX_PARALLEL parallel)...${NC}"
echo "${YELLOW}Note: This will use significant bandwidth and disk I/O${NC}"
echo ""

# Create temp directory for status files
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Function to pull a model
pull_model() {
    local model=$1
    local status_file="$TEMP_DIR/$(echo $model | tr ':/' '__')"
    
    echo "${GRAY}Starting: $model${NC}"
    
    if ollama pull "$model" &> "$status_file.log"; then
        echo "success" > "$status_file"
        echo "${GREEN}✓ Completed: $model${NC}"
    else
        echo "failed" > "$status_file"
        echo "${RED}✗ Failed: $model${NC}"
    fi
}

# Run downloads with limited parallelism
RUNNING=0
for MODEL in "${MODELS[@]}"; do
    # Wait if we've hit the parallel limit
    while [[ $RUNNING -ge $MAX_PARALLEL ]]; do
        wait -n 2>/dev/null || true
        RUNNING=$(($(jobs -r | wc -l)))
    done
    
    pull_model "$MODEL" &
    ((RUNNING++))
done

# Wait for all remaining jobs
wait

echo ""
echo "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo "${CYAN}                         SUMMARY                               ${NC}"
echo "${CYAN}═══════════════════════════════════════════════════════════════${NC}"
echo ""

SUCCESSFUL=()
FAILED=()

for MODEL in "${MODELS[@]}"; do
    STATUS_FILE="$TEMP_DIR/$(echo $MODEL | tr ':/' '__')"
    if [[ -f "$STATUS_FILE" ]] && [[ "$(cat $STATUS_FILE)" == "success" ]]; then
        SUCCESSFUL+=("$MODEL")
    else
        FAILED+=("$MODEL")
    fi
done

if [[ ${#SUCCESSFUL[@]} -gt 0 ]]; then
    echo "${GREEN}Successful (${#SUCCESSFUL[@]}):${NC}"
    for MODEL in "${SUCCESSFUL[@]}"; do
        echo "  ${GREEN}✓ $MODEL${NC}"
    done
    echo ""
fi

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo "${RED}Failed (${#FAILED[@]}):${NC}"
    for MODEL in "${FAILED[@]}"; do
        echo "  ${RED}✗ $MODEL${NC}"
    done
    echo ""
    echo "${YELLOW}To retry failed models:${NC}"
    for MODEL in "${FAILED[@]}"; do
        echo "  ${GRAY}ollama pull $MODEL${NC}"
    done
    echo ""
    echo "${YELLOW}Check logs in: $TEMP_DIR${NC}"
fi

echo ""
echo "${CYAN}Currently installed models:${NC}"
ollama list

echo ""
echo "${GREEN}Done!${NC}"
