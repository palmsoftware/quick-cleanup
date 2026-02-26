#!/usr/bin/env bash
# cleanup-disk-macos.sh - Intelligent disk space cleanup for macOS GitHub Actions runners
#
# Parameters:
#   $1 - CLEANUP_MODE: auto, light, aggressive, or skip
#   $2 - THRESHOLD_GB: threshold in GB for auto mode (default: 20)
#   $3 - MINIMUM_FREE_GB: minimum required space in GB (default: 0 = no validation)
#   $4 - REMOVE_ANDROID: true or false
#   $5 - REMOVE_DOCKER_IMAGES: true or false
#   $6 - REMOVE_XCODE_SIMULATORS: true or false
#   $7 - REMOVE_HOMEBREW_CACHE: true or false

# Note: Using best-effort approach - don't exit on cleanup failures
# set -e

CLEANUP_MODE="${1:-auto}"
THRESHOLD_GB="${2:-20}"
MINIMUM_FREE_GB="${3:-0}"
REMOVE_ANDROID="${4:-true}"
REMOVE_DOCKER_IMAGES="${5:-true}"
REMOVE_XCODE_SIMULATORS="${6:-true}"
REMOVE_HOMEBREW_CACHE="${7:-true}"

# Start timing
START_TIME=$(date +%s)

echo "=============================================="
echo "  DISK SPACE CLEANUP (macOS)"
echo "=============================================="
echo "Configuration:"
echo "  Mode: $CLEANUP_MODE"
echo "  Threshold: ${THRESHOLD_GB}GB"
echo "  Minimum required: ${MINIMUM_FREE_GB}GB"
echo "  Remove Android: $REMOVE_ANDROID"
echo "  Remove Docker images: $REMOVE_DOCKER_IMAGES"
echo "  Remove Xcode simulators: $REMOVE_XCODE_SIMULATORS"
echo "  Remove Homebrew cache: $REMOVE_HOMEBREW_CACHE"
echo ""

# Skip if mode is 'skip'
if [ "$CLEANUP_MODE" = "skip" ]; then
  echo "Cleanup disabled (mode: skip). Skipping."
  exit 0
fi

echo "=== Initial disk usage ==="
df -h
echo ""
echo "=== Initial system info ==="
echo "OS: macOS $(sw_vers -productVersion)"
echo "Architecture: $(uname -m)"
MEMORY_BYTES=$(sysctl -n hw.memsize)
MEMORY_GB=$((MEMORY_BYTES / 1024 / 1024 / 1024))
echo "Memory: ${MEMORY_GB}GB"
echo "CPU: $(sysctl -n hw.ncpu) cores"

# Check available space (use -k for consistent KB output on macOS)
INITIAL_AVAILABLE_KB=$(df -k / | tail -1 | awk '{print $4}')
INITIAL_AVAILABLE_GB=$((INITIAL_AVAILABLE_KB / 1024 / 1024))
echo ""
echo "Initial available space: ${INITIAL_AVAILABLE_GB}GB"

# Determine cleanup intensity
LIGHT_CLEANUP=0
if [ "$CLEANUP_MODE" = "auto" ]; then
  if [ "$INITIAL_AVAILABLE_GB" -gt "$THRESHOLD_GB" ]; then
    echo "✅ Plenty of space available (>${THRESHOLD_GB}GB). Performing light cleanup."
    LIGHT_CLEANUP=1
  else
    echo "⚠️  Limited space detected (<=${THRESHOLD_GB}GB). Performing aggressive cleanup."
    LIGHT_CLEANUP=0
  fi
elif [ "$CLEANUP_MODE" = "light" ]; then
  echo "Light cleanup mode selected."
  LIGHT_CLEANUP=1
elif [ "$CLEANUP_MODE" = "aggressive" ]; then
  echo "Aggressive cleanup mode selected."
  LIGHT_CLEANUP=0
else
  echo "❌ ERROR: Invalid cleanup mode: $CLEANUP_MODE"
  echo "   Valid modes: auto, light, aggressive, skip"
  exit 2
fi

# Homebrew cache cleanup
if [ "$REMOVE_HOMEBREW_CACHE" = "true" ]; then
  echo "=== Cleaning Homebrew cache ==="
  if command -v brew >/dev/null 2>&1; then
    brew cleanup -s 2>&1 || echo "⚠️  brew cleanup had some errors (non-critical)"
    BREW_CACHE=$(brew --cache 2>/dev/null || echo "")
    if [ -n "$BREW_CACHE" ] && [ -d "$BREW_CACHE" ]; then
      echo "Removing Homebrew cache directory: $BREW_CACHE"
      rm -rf "$BREW_CACHE" 2>&1 || echo "⚠️  Could not fully remove Homebrew cache"
    fi
    echo "✅ Homebrew cache cleaned"
  else
    echo "✅ Homebrew not available, skipping"
  fi
else
  echo "=== Skipping Homebrew cache cleanup (disabled) ==="
fi

# Remove Android SDK if enabled
if [ "$REMOVE_ANDROID" = "true" ]; then
  echo "=== Checking for Android SDK ==="
  ANDROID_DIRS="/usr/local/lib/android /opt/android ${ANDROID_HOME:-} ${ANDROID_SDK_ROOT:-}"
  ANDROID_FOUND=0
  for dir in $ANDROID_DIRS; do
    if [ -d "$dir" ] && [ "$dir" != "" ]; then
      echo "📱 Removing Android SDK: $dir"
      sudo rm -rf "$dir" 2>&1 || echo "⚠️  Could not fully remove $dir"
      ANDROID_FOUND=1
    fi
  done
  if [ "$ANDROID_FOUND" -eq 0 ]; then
    echo "✅ No Android SDK found to remove"
  fi
else
  echo "=== Skipping Android SDK removal (disabled) ==="
fi

# Docker cleanup if enabled
if [ "$REMOVE_DOCKER_IMAGES" = "true" ]; then
  echo "=== Docker cleanup ==="
  if command -v docker >/dev/null 2>&1; then
    docker system prune -af --volumes 2>&1 || echo "⚠️  Docker cleanup had some errors (non-critical)"
  else
    echo "✅ Docker not available, skipping"
  fi
else
  echo "=== Skipping Docker cleanup (disabled) ==="
fi

echo "=== Cleaning temporary files ==="
sudo rm -rf /tmp/* 2>/dev/null || true
sudo rm -rf /var/tmp/* 2>/dev/null || true

echo "=== Cleaning log files ==="
sudo rm -rf /var/log/*.log 2>/dev/null || true

# Aggressive cleanup: remove large directories and Xcode simulators
if [ "$LIGHT_CLEANUP" -eq 0 ]; then
  # Xcode simulator cleanup
  if [ "$REMOVE_XCODE_SIMULATORS" = "true" ]; then
    echo "=== Removing Xcode simulator runtimes ==="
    if command -v xcrun >/dev/null 2>&1; then
      echo "Deleting all simulator devices..."
      xcrun simctl delete all 2>&1 || echo "⚠️  Could not delete all simulator devices"
      echo "Deleting all simulator runtimes..."
      xcrun simctl runtime delete all 2>&1 || echo "⚠️  Could not delete all simulator runtimes"
    fi
    # Remove simulator runtime files directly
    SIMULATOR_DIRS="/Library/Developer/CoreSimulator/Volumes /Library/Developer/CoreSimulator/Profiles/Runtimes"
    for dir in $SIMULATOR_DIRS; do
      if [ -d "$dir" ]; then
        echo "🗂️  Removing: $dir"
        sudo rm -rf "$dir" 2>&1 || echo "⚠️  Could not fully remove $dir"
      fi
    done
    echo "✅ Xcode simulator cleanup complete"
  else
    echo "=== Skipping Xcode simulator removal (disabled) ==="
  fi

  echo "=== Removing other large directories ==="
  LARGE_DIRS="/usr/local/share/dotnet /usr/local/share/powershell /usr/local/share/chromium /usr/local/lib/node_modules /opt/ghc /usr/local/.ghcup"
  for dir in $LARGE_DIRS; do
    if [ -d "$dir" ]; then
      echo "🗂️  Removing: $dir"
      sudo rm -rf "$dir" 2>&1 || echo "⚠️  Could not fully remove $dir"
    fi
  done

  echo "=== Cleaning system caches ==="
  if [ -d "$HOME/Library/Caches" ]; then
    echo "Cleaning user library caches..."
    rm -rf "${HOME:?}/Library/Caches/"* 2>/dev/null || true
  fi
  if [ -d "/Library/Caches" ]; then
    echo "Cleaning system library caches..."
    sudo rm -rf /Library/Caches/* 2>/dev/null || true
  fi
else
  echo "=== Skipping large directory cleanup (light mode) ==="
  # Still clean Xcode simulators in light mode if explicitly requested
  if [ "$REMOVE_XCODE_SIMULATORS" = "true" ]; then
    echo "=== Removing Xcode simulator runtimes (explicitly enabled) ==="
    if command -v xcrun >/dev/null 2>&1; then
      echo "Deleting all simulator devices..."
      xcrun simctl delete all 2>&1 || echo "⚠️  Could not delete all simulator devices"
      echo "Deleting all simulator runtimes..."
      xcrun simctl runtime delete all 2>&1 || echo "⚠️  Could not delete all simulator runtimes"
    fi
    SIMULATOR_DIRS="/Library/Developer/CoreSimulator/Volumes /Library/Developer/CoreSimulator/Profiles/Runtimes"
    for dir in $SIMULATOR_DIRS; do
      if [ -d "$dir" ]; then
        echo "🗂️  Removing: $dir"
        sudo rm -rf "$dir" 2>&1 || echo "⚠️  Could not fully remove $dir"
      fi
    done
    echo "✅ Xcode simulator cleanup complete"
  fi
fi

echo "=== Cleanup Summary ==="
df -h

# Calculate space freed (use -k for consistent KB output)
FINAL_AVAILABLE_KB=$(df -k / | tail -1 | awk '{print $4}')
FINAL_AVAILABLE_GB=$((FINAL_AVAILABLE_KB / 1024 / 1024))
SPACE_FREED_GB=$((FINAL_AVAILABLE_GB - INITIAL_AVAILABLE_GB))

# Calculate cleanup duration
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo "📊 DISK SPACE ANALYSIS"
echo "├─ Initial space: ${INITIAL_AVAILABLE_GB}GB"
echo "├─ Final space: ${FINAL_AVAILABLE_GB}GB"
echo "├─ Space freed: ${SPACE_FREED_GB}GB"
echo "├─ Cleanup duration: ${DURATION}s"
echo "└─ Root partition: $(df -h / | tail -1 | awk '{print $4}') free"

# Validate minimum space requirement
echo ""
if [ "$MINIMUM_FREE_GB" -gt 0 ]; then
  echo "=== Validating minimum space requirement ==="
  # Re-enable strict error handling for final validation
  set -e
  if [ "$FINAL_AVAILABLE_GB" -lt "$MINIMUM_FREE_GB" ]; then
    echo "❌ ERROR: Insufficient disk space (${FINAL_AVAILABLE_GB}GB)."
    echo "   Required: ${MINIMUM_FREE_GB}GB"
    echo "   Suggestion: Try cleanup-mode: aggressive or reduce minimum-free-space requirement"
    echo ""
    echo "Available space breakdown:"
    df -h
    exit 1
  fi
  echo "✅ Sufficient disk space available (${FINAL_AVAILABLE_GB}GB >= ${MINIMUM_FREE_GB}GB required)"
else
  echo "=== Skipping space validation (minimum-free-space: 0) ==="
fi

echo ""
echo "=============================================="
echo "✅ DISK CLEANUP COMPLETED SUCCESSFULLY"
echo "=============================================="
exit 0
