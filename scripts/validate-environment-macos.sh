#!/usr/bin/env bash
# validate-environment-macos.sh - Pre-flight environment validation for quick-cleanup on macOS

set -e

echo "=== Validating environment for quick-cleanup (macOS) ==="

# Check OS compatibility
echo "Checking OS compatibility..."
if [ "$(uname -s)" != "Darwin" ]; then
  echo "❌ ERROR: This script requires macOS (Darwin)."
  exit 1
fi

OS_VERSION=$(sw_vers -productVersion)
echo "✅ OS: macOS $OS_VERSION"

# Check required tools
echo ""
echo "Checking required tools..."

if ! command -v sudo &> /dev/null; then
  echo "❌ ERROR: Missing required tool: sudo"
  echo "   Please install sudo before running quick-cleanup."
  exit 1
fi
echo "✅ Required tools found (sudo)"

# Check optional tools
echo ""
echo "Checking optional tools..."
if command -v docker &> /dev/null; then
  echo "✅ Docker is available"
else
  echo "ℹ️  Docker not found (optional on macOS)"
fi

if command -v brew &> /dev/null; then
  echo "✅ Homebrew is available"
else
  echo "ℹ️  Homebrew not found"
fi

if command -v xcrun &> /dev/null; then
  echo "✅ Xcode command-line tools available"
else
  echo "ℹ️  Xcode command-line tools not found"
fi

# Check sudo access
echo ""
echo "Checking sudo access..."
if ! sudo -n true 2>/dev/null; then
  echo "⚠️  WARNING: sudo requires password. This may cause issues in GitHub Actions."
else
  echo "✅ sudo access available"
fi

# Analyze disk layout
echo ""
echo "Analyzing disk layout..."

if ! df / &> /dev/null; then
  echo "❌ ERROR: Cannot access root partition"
  exit 1
fi

ROOT_AVAILABLE_KB=$(df -k / | tail -1 | awk '{print $4}')
ROOT_AVAILABLE_GB=$((ROOT_AVAILABLE_KB / 1024 / 1024))
echo "  Root partition (/): ${ROOT_AVAILABLE_GB}GB available"

# Detect GitHub Actions environment
echo ""
if [ -n "$GITHUB_ACTIONS" ]; then
  echo "✅ GitHub Actions environment detected"
  echo "  Runner OS: ${RUNNER_OS:-unknown}"
  echo "  Runner Arch: ${RUNNER_ARCH:-unknown}"
else
  echo "⚠️  Not running in GitHub Actions environment"
  echo "   This action is designed for GitHub Actions runners"
fi

# System information
echo ""
echo "=== System Information ==="
echo "OS: macOS $OS_VERSION"
echo "Architecture: $(uname -m)"
echo "Kernel: $(uname -r)"
MEMORY_BYTES=$(sysctl -n hw.memsize)
MEMORY_GB=$((MEMORY_BYTES / 1024 / 1024 / 1024))
echo "Memory: ${MEMORY_GB}GB total"
echo "CPU cores: $(sysctl -n hw.ncpu)"
echo "Disk layout:"
df -h | grep -E '^(Filesystem|/dev/)' || df -h

echo ""
echo "✅ Environment validation complete"
