#!/bin/zsh

# pull_models.sh - Download Ollama models for benchmarking (macOS/Linux)

# ═══════════════════════════════════════════════════════════════
# MODEL DEFINITIONS
# ═══════════════════════════════════════════════════════════════

declare -A MODEL_SIZES
MODEL_SIZES=(
    ["mistral:latest"]="~4.1GB"
    ["deepseek-coder:33b"]="~19GB"
    ["deepseek-r1:7b"]="~4.7GB"
    ["deepseek-r1:32b"]="~20GB"
    ["deepseek-r1:8b"]="~5.2GB"
    ["llama3.3:latest"]="~43GB"
    ["qwen3-coder:30b"]="~19GB"
    ["mistral-small3.2:latest"]="~15GB"
    ["phi4:14b"]="~9.1GB"
    ["codellama:34b"]="~19GB"
)

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

# ═══════════════════════════════════════════════════════════════
# COLORS
# ═══════════════════════════════════════════════════════════════

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# ═══════════════════════════════════════════════════════════════
# PREFLIGHT CHECKS
# ═══════════════════════════════════════════════════════════════

# Check if Ollama is installed
if ! command -v ollama &> /dev/null; then
    echo "${RED}Error: Ollama is not installed.${NC}"
    echo "Install from: https://ollama.com/download"
    exit 1
fi

# Check if Ollama is running
if ! curl -s http://localhost:11434/api/tags &> /dev/null; then
    echo "${YELLOW}Warning: Ollama doesn't appear to be running.${NC}"
    echo "Starting Ollama..."
    ollama serve &> /dev/null &
    sleep 3
    
    if ! curl -s http://localhost:11434/api/tags &> /dev/null; then
        echo "${RED}Error: Could not start Ollama. Please start it manually:${NC}"
        echo "  ollama serve"
        exit 1
    fi
    echo "${GREEN}Ollama started.${NC}"
    echo ""
fi

# ═══════════════════════════════════════════════════════════════
# DISPLAY MODEL LIST
# ═══════════════════════════════════════════════════════════════

clear
echo ""
echo "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo "${CYAN}║              OLLAMA MODEL DOWNLOADER                          ║${NC}"
echo "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "${YELLOW}Models to download:${NC}"
echo ""

for MODEL in "${MODELS[@]}"; do
    SIZE=${MODEL_SIZES[$MODEL]}
    printf "  ${WHITE}• %-30s %s${NC}\n" "$MODEL" "$SIZE"
done

echo ""
echo "  ${MAGENTA}Total estimated size: ~158GB${NC}"
echo ""
echo "${GRAY}Note: Models you already have will be skipped or updated.${NC}"
echo ""

# ═══════════════════════════════════════════════════════════════
# CONFIRMATION
# ═══════════════════════════════════════════════════════════════

echo -n "Proceed with download? (Y/n): "
read CONFIRM

if [[ "$CONFIRM" == "n" || "$CONFIRM" == "N" ]]; then
    echo "${YELLOW}Cancelled.${NC}"
    exit 0
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# DOWNLOAD MODELS
# ═══════════════════════════════════════════════════════════════

SUCCESSFUL=()
FAILED=()

TOTAL=${#MODELS[@]}
CURRENT=0

for MODEL in "${MODELS[@]}"; do
    ((CURRENT++))
    SIZE=${MODEL_SIZES[$MODEL]}
    
    echo "${GRAY}═══════════════════════════════════════════════════════════════${NC}"
    echo "${CYAN}[$CURRENT/$TOTAL] Pulling: $MODEL ($SIZE)${NC}"
    echo "${GRAY}═══════════════════════════════════════════════════════════════${NC}"
    
    if ollama pull "$MODEL"; then
        echo "${GREEN}✓ Successfully pulled $MODEL${NC}"
        SUCCESSFUL+=("$MODEL")
    else
        echo "${RED}✗ Failed to pull $MODEL${NC}"
        FAILED+=("$MODEL")
    fi
    
    echo ""
done

# ═══════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════

echo "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
echo "${YELLOW}                         SUMMARY                               ${NC}"
echo "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
echo ""

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
    echo "${YELLOW}To retry failed models, run:${NC}"
    for MODEL in "${FAILED[@]}"; do
        echo "  ${GRAY}ollama pull $MODEL${NC}"
    done
    echo ""
fi

# ═══════════════════════════════════════════════════════════════
# LIST INSTALLED MODELS
# ═══════════════════════════════════════════════════════════════

echo "${CYAN}Currently installed models:${NC}"
ollama list

echo ""
echo "${GREEN}Done!${NC}"
