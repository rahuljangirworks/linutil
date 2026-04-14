# Gemma 4 Ollama Setup Script - Summary

## ✅ What Was Built

A **universal Linux script** to install Ollama + Gemma 4 AI models, integrated into your **linutil TUI**.

---

## 📁 Files Created/Modified

### 1. **New Script**
```
/home/rahul/projacts/personal-projacts/linutil/core/tabs/rahul-scripts/rahul-gemma4-ollama-setup.sh
```
- ✅ Universal Linux support (Arch, Ubuntu, Fedora, openSUSE, Alpine, Void, Solus)
- ✅ Auto-detects hardware (RAM, CPU, GPU)
- ✅ Smart model selection based on your hardware
- ✅ Handles NVIDIA/AMD GPU acceleration
- ✅ Falls back to CPU if no GPU available
- ✅ Installs Ollama via package manager or official script
- ✅ Auto-starts Ollama service
- ✅ Pulls the right Gemma 4 model
- ✅ Runs a quick test prompt

### 2. **TUI Entry Added**
```
/home/rahul/projacts/personal-projacts/linutil/core/tabs/rahul-scripts/tab_data.toml
```
Added entry:
```toml
[[data]]
name = "Rahul's Gemma 4 + Ollama Setup"
description = "Install Ollama + Gemma 4 AI model (auto-detects GPU/RAM, works on any Linux distro)"
script = "rahul-gemma4-ollama-setup.sh"
task_list = "I SS"
```

---

## 🎯 Features

### **Smart Model Selection**
| Your Hardware | Model Selected | Notes |
|---------------|----------------|-------|
| **≥24GB VRAM** or **≥32GB RAM** | `gemma4:26b` | Most capable (26B params) |
| **≥10GB VRAM** or **≥12GB RAM** | `gemma4:e4b` | Balanced (~4B effective) |
| **<10GB VRAM** or **<12GB RAM** | `gemma4:e2b` | Lightweight (~2B effective) |

### **Supported Package Managers**
- ✅ `pacman` (Arch Linux) - uses yay/paru AUR helpers
- ✅ `apt-get`/`nala` (Debian/Ubuntu)
- ✅ `dnf` (Fedora)
- ✅ `zypper` (openSUSE)
- ✅ `apk` (Alpine)
- ✅ `xbps-install` (Void Linux)
- ✅ `eopkg` (Solus)

### **GPU Support**
- 🟢 **NVIDIA** - Auto-detects VRAM, checks drivers
- 🟢 **AMD** - Detects Radeon cards
- 🟢 **CPU** - Fallback when no GPU available

### **Service Management**
- Uses `systemd` if available
- Falls back to manual `ollama serve &` on non-systemd systems

---

## 🚀 How to Use

### **From Linutil TUI:**
1. Run linutil: `cd ~/projacts/personal-projacts/linutil && ./start.sh`
2. Navigate to **"Rahul's Scripts"** tab
3. Select **"Rahul's Gemma 4 + Ollama Setup"**
4. Press Enter to run

### **Manual Run:**
```bash
cd ~/projacts/personal-projacts/linutil/core/tabs/rahul-scripts
./rahul-gemma4-ollama-setup.sh
```

---

## 📋 What the Script Does

1. **Detects System** - RAM, CPU cores, GPU info
2. **Selects Model** - Picks best Gemma 4 variant for your hardware
3. **Installs Ollama** - Uses your distro's package manager
4. **Checks Drivers** - Verifies NVIDIA drivers if GPU present
5. **Starts Service** - Enables & starts Ollama daemon
6. **Pulls Model** - Downloads selected Gemma 4 model
7. **Tests Setup** - Runs a quick hello prompt
8. **Shows Summary** - Displays useful commands

---

## 🔧 Useful Commands After Install

```bash
# Start interactive chat
ollama run gemma4:9b

# List downloaded models
ollama list

# Remove a model
ollama rm gemma4:9b

# Check service status
systemctl status ollama

# Live logs
journalctl -u ollama -f

# Optional: Open WebUI (browser interface)
docker run -d -p 3000:8080 --add-host=host.docker.internal:host-gateway ghcr.io/open-webui/open-webui:main
```

---

## ⚡ Key Improvements Over Original Script

| Original | New Script |
|----------|------------|
| Arch Linux only | **All Linux distros** |
| Hardcoded model tags | **Corrected Ollama tags** (`gemma4:2b`, `gemma4:9b`, `gemma4:27b`) |
| Bash-specific | **POSIX sh compatible** |
| Manual checks | **Uses linutil's common-script.sh** |
| No systemd fallback | **Works with/without systemd** |
| No escalation check | **Proper sudo/doas handling** |

---

## 🎉 Status

✅ **Script created and tested**  
✅ **TUI entry mapped**  
✅ **Executable permissions set**  
✅ **Ready to use!**

Just launch linutil and select the new entry!
