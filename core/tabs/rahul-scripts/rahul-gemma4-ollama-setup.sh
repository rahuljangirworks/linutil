#!/bin/sh -e
. ../common-script.sh

checkEnv

clear
printf "%b\n" "${CYAN}=================================================================${RC}"
printf "%b\n" "${YELLOW}   Rahul's Gemma 4 + Ollama AI Setup (Universal Linux)           ${RC}"
printf "%b\n" "${CYAN}=================================================================${RC}"
echo ""

# ── 1. System Detection ──────────────────────────────────────────
printf "%b\n" "${CYAN}━━━ System Detection ━━━${RC}"
echo ""

# RAM (in GB)
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_RAM_GB=$(( TOTAL_RAM_KB / 1024 / 1024 ))
printf "%b\n" "${CYAN}[ℹ]${RC} RAM detected: ${TOTAL_RAM_GB} GB"

# CPU cores
CPU_CORES=$(nproc)
printf "%b\n" "${CYAN}[ℹ]${RC} CPU cores: ${CPU_CORES}"

# GPU detection
GPU_INFO=""
HAS_NVIDIA=false
HAS_AMD=false
VRAM_GB=0

if command_exists nvidia-smi; then
    HAS_NVIDIA=true
    VRAM_MB=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits 2>/dev/null | head -1 || echo "0")
    VRAM_GB=$(( VRAM_MB / 1024 ))
    GPU_INFO="NVIDIA GPU — ${VRAM_GB}GB VRAM"
    printf "%b\n" "${CYAN}[ℹ]${RC} GPU: $GPU_INFO"
elif lspci 2>/dev/null | grep -qi "amd\|radeon"; then
    HAS_AMD=true
    GPU_INFO="AMD GPU"
    printf "%b\n" "${CYAN}[ℹ]${RC} GPU: $GPU_INFO (ROCm support depends on your card)"
else
    printf "%b\n" "${YELLOW}[⚠]${RC} No dedicated GPU detected — will run on CPU"
fi

echo ""

# ── 2. Model Selection ───────────────────────────────────────────
printf "%b\n" "${CYAN}━━━ Selecting Gemma 4 Model ━━━${RC}"
echo ""

# Gemma 4 variants with corrected Ollama tag names
# Decision logic based on RAM / VRAM

if $HAS_NVIDIA && [ "$VRAM_GB" -ge 6 ]; then
    # GPU acceleration available
    if [ "$VRAM_GB" -ge 24 ]; then
        MODEL="gemma4:26b"
    elif [ "$VRAM_GB" -ge 10 ]; then
        MODEL="gemma4:e4b"
    else
        MODEL="gemma4:e2b"
    fi
    printf "%b\n" "${CYAN}[ℹ]${RC} Using GPU acceleration"
else
    # CPU / RAM based selection
    if [ "$TOTAL_RAM_GB" -ge 32 ]; then
        MODEL="gemma4:26b"
    elif [ "$TOTAL_RAM_GB" -ge 12 ]; then
        MODEL="gemma4:e4b"
    else
        MODEL="gemma4:e2b"
    fi
    printf "%b\n" "${CYAN}[ℹ]${RC} Using CPU inference"
fi

printf "%b\n" "${CYAN}[ℹ]${RC} Selected model: ${GREEN}${MODEL}${RC}"

# Warn if RAM might be tight
if [ "$MODEL" = "gemma4:26b" ] && [ "$TOTAL_RAM_GB" -lt 32 ]; then
    printf "%b\n" "${YELLOW}[⚠]${RC} 26B model needs ~32GB RAM — you have ${TOTAL_RAM_GB}GB. Consider closing other apps."
fi
if [ "$MODEL" = "gemma4:e4b" ] && [ "$TOTAL_RAM_GB" -lt 12 ]; then
    printf "%b\n" "${YELLOW}[⚠]${RC} e4b model needs ~12GB RAM — you have ${TOTAL_RAM_GB}GB. Performance may be limited."
fi

echo ""

# ── 3. Install Ollama ────────────────────────────────────────────
printf "%b\n" "${CYAN}━━━ Installing Ollama ━━━${RC}"
echo ""

if command_exists ollama; then
    printf "%b\n" "${GREEN}[✔]${RC} Ollama already installed: $(ollama --version 2>/dev/null || echo 'unknown version')"
else
    printf "%b\n" "${CYAN}[ℹ]${RC} Installing ollama..."

    # Arch Linux (pacman/AUR)
    case "$PACKAGER" in
        pacman)
            checkAURHelper
            if command_exists yay; then
                printf "%b\n" "${CYAN}[ℹ]${RC} Using yay to install ollama..."
                yay -S --noconfirm ollama
            elif command_exists paru; then
                printf "%b\n" "${CYAN}[ℹ]${RC} Using paru to install ollama..."
                paru -S --noconfirm ollama
            else
                printf "%b\n" "${YELLOW}[⚠]${RC} No AUR helper found — using official Ollama install script"
                curl -fsSL https://ollama.com/install.sh | sh
            fi
            ;;
        *)
            # Debian/Ubuntu/Fedora/openSUSE/Alpine/Void/Solus — use official script
            printf "%b\n" "${CYAN}[ℹ]${RC} Using official Ollama install script..."
            curl -fsSL https://ollama.com/install.sh | sh
            ;;
    esac

    printf "%b\n" "${GREEN}[✔]${RC} Ollama installed successfully"
fi

echo ""

# ── 4. NVIDIA Driver Check ───────────────────────────────────────
if $HAS_NVIDIA; then
    printf "%b\n" "${CYAN}━━━ NVIDIA Setup Check ━━━${RC}"
    echo ""
    
    case "$PACKAGER" in
        pacman)
            if ! pacman -Qq nvidia-utils &>/dev/null && ! pacman -Qq cuda &>/dev/null; then
                printf "%b\n" "${YELLOW}[⚠]${RC} NVIDIA drivers may not be installed. For GPU support run:"
                printf "%b\n" "  ${YELLOW}sudo pacman -S nvidia nvidia-utils${RC}"
            else
                printf "%b\n" "${GREEN}[✔]${RC} NVIDIA drivers found"
            fi
            ;;
        apt-get|nala|apt)
            if ! dpkg -l | grep -q nvidia-driver; then
                printf "%b\n" "${YELLOW}[⚠]${RC} NVIDIA drivers may not be installed. For GPU support run:"
                printf "%b\n" "  ${YELLOW}sudo apt install nvidia-driver-535${RC} (or latest)"
            else
                printf "%b\n" "${GREEN}[✔]${RC} NVIDIA drivers found"
            fi
            ;;
        dnf)
            if ! rpm -q nvidia-driver &>/dev/null; then
                printf "%b\n" "${YELLOW}[⚠]${RC} NVIDIA drivers may not be installed. For GPU support run:"
                printf "%b\n" "  ${YELLOW}sudo dnf install akmod-nvidia${RC}"
            else
                printf "%b\n" "${GREEN}[✔]${RC} NVIDIA drivers found"
            fi
            ;;
        *)
            printf "%b\n" "${CYAN}[ℹ]${RC} Verify NVIDIA drivers are installed for your distro"
            ;;
    esac
    echo ""
fi

# ── 5. Enable & Start Ollama Service ─────────────────────────────
printf "%b\n" "${CYAN}━━━ Starting Ollama Service ━━━${RC}"
echo ""

# Check if systemd is available
if command_exists systemctl; then
    if systemctl is-enabled --quiet ollama 2>/dev/null; then
        printf "%b\n" "${GREEN}[✔]${RC} ollama.service already enabled"
    else
        printf "%b\n" "${CYAN}[ℹ]${RC} Enabling ollama.service..."
        "$ESCALATION_TOOL" systemctl enable ollama
    fi

    if systemctl is-active --quiet ollama 2>/dev/null; then
        printf "%b\n" "${GREEN}[✔]${RC} ollama.service already running"
    else
        printf "%b\n" "${CYAN}[ℹ]${RC} Starting ollama.service..."
        "$ESCALATION_TOOL" systemctl start ollama
        sleep 2  # give it a moment to initialize
    fi
else
    printf "%b\n" "${CYAN}[ℹ]${RC} systemd not found — starting ollama manually..."
    # Start ollama in background if not running
    if ! pgrep -x ollama >/dev/null; then
        ollama serve &
        sleep 3
        printf "%b\n" "${GREEN}[✔]${RC} Ollama started in background"
    else
        printf "%b\n" "${GREEN}[✔]${RC} Ollama already running"
    fi
fi

printf "%b\n" "${GREEN}[✔]${RC} Ollama service is running"
echo ""

# ── 6. Pull Gemma 4 Model ────────────────────────────────────────
printf "%b\n" "${CYAN}━━━ Pulling ${MODEL} ━━━${RC}"
echo ""

printf "%b\n" "${CYAN}[ℹ]${RC} This may take a while depending on your internet speed..."
printf "%b\n" "${CYAN}[ℹ]${RC} Model will be saved to ~/.ollama/models/"
echo ""

ollama pull "$MODEL"

printf "%b\n" "${GREEN}[✔]${RC} Model ${MODEL} pulled successfully!"
echo ""

# ── 7. Quick Test ────────────────────────────────────────────────
printf "%b\n" "${CYAN}━━━ Quick Sanity Test ━━━${RC}"
echo ""

printf "%b\n" "${CYAN}[ℹ]${RC} Running a quick test prompt..."
RESPONSE=$(ollama run "$MODEL" "Say hello in one sentence." 2>/dev/null || echo "")

if [ -n "$RESPONSE" ]; then
    printf "%b\n" "${GREEN}[✔]${RC} Model responded: $RESPONSE"
else
    printf "%b\n" "${YELLOW}[⚠]${RC} Model did not respond — try manually: ollama run $MODEL"
fi

echo ""

# ── 8. Summary ───────────────────────────────────────────────────
printf "%b\n" "${GREEN}=================================================================${RC}"
printf "%b\n" "${GREEN}  Setup Complete 🎉                                                ${RC}"
printf "%b\n" "${GREEN}=================================================================${RC}"
echo ""
printf "%b\n" "${CYAN}Your setup:${RC}"
printf "%b\n" "  Model     : ${GREEN}${MODEL}${RC}"
printf "%b\n" "  RAM       : ${TOTAL_RAM_GB} GB"
printf "%b\n" "  GPU       : ${GPU_INFO:-None (CPU mode)}"
echo ""
printf "%b\n" "${CYAN}Useful commands:${RC}"
printf "%b\n" "  ${CYAN}ollama run ${MODEL}${RC}          — start interactive chat"
printf "%b\n" "  ${CYAN}ollama list${RC}                  — list downloaded models"
printf "%b\n" "  ${CYAN}ollama rm ${MODEL}${RC}            — remove the model"

if command_exists systemctl; then
    printf "%b\n" "  ${CYAN}systemctl status ollama${RC}       — check service status"
    printf "%b\n" "  ${CYAN}journalctl -u ollama -f${RC}       — live logs"
else
    printf "%b\n" "  ${CYAN}pgrep -x ollama${RC}               — check if running"
    printf "%b\n" "  ${CYAN}pkill -x ollama${RC}               — stop ollama"
fi

echo ""
printf "%b\n" "  Open WebUI (optional browser UI):"
printf "%b\n" "  ${CYAN}docker run -d -p 3000:8080 --add-host=host.docker.internal:host-gateway ghcr.io/open-webui/open-webui:main${RC}"
echo ""
printf "%b\n" "${GREEN}[✔]${RC} Done! Run: ${CYAN}ollama run ${MODEL}${RC}"
echo ""
