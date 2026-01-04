#!/usr/bin/env bash
# validate-environment.sh - Pre-flight environment validation for quick-cleanup

set -e

echo "=== Validating environment for quick-cleanup ==="

# Check OS compatibility
echo "Checking OS compatibility..."
if ! command -v lsb_release &> /dev/null; then
  echo "❌ ERROR: lsb_release not found. This action requires Ubuntu."
  exit 1
fi

OS_DESCRIPTION=$(lsb_release -d | cut -f2)
if ! echo "$OS_DESCRIPTION" | grep -q "Ubuntu"; then
  echo "❌ ERROR: Unsupported OS: $OS_DESCRIPTION"
  echo "   This action currently supports Ubuntu only."
  exit 1
fi
echo "✅ OS: $OS_DESCRIPTION"

# Check required tools
echo ""
echo "Checking required tools..."
MISSING_TOOLS=()

if ! command -v jq &> /dev/null; then
  MISSING_TOOLS+=("jq")
fi

if ! command -v docker &> /dev/null; then
  MISSING_TOOLS+=("docker")
fi

if ! command -v sudo &> /dev/null; then
  MISSING_TOOLS+=("sudo")
fi

if [ ${#MISSING_TOOLS[@]} -gt 0 ]; then
  echo "❌ ERROR: Missing required tools: ${MISSING_TOOLS[*]}"
  echo "   Please install the missing tools before running quick-cleanup."
  exit 1
fi
echo "✅ All required tools found (jq, docker, sudo)"

# Check sudo access
echo ""
echo "Checking sudo access..."
if ! sudo -n true 2>/dev/null; then
  echo "⚠️  WARNING: sudo requires password. This may cause issues in GitHub Actions."
else
  echo "✅ sudo access available"
fi

# Check partition layout
echo ""
echo "Analyzing partition layout..."

# Check root partition
if ! df / &> /dev/null; then
  echo "❌ ERROR: Cannot access root partition"
  exit 1
fi

ROOT_AVAILABLE_KB=$(df / | tail -1 | awk '{print $4}')
ROOT_AVAILABLE_GB=$((ROOT_AVAILABLE_KB / 1024 / 1024))
echo "  Root partition (/):    ${ROOT_AVAILABLE_GB}GB available"

# Check /mnt partition
if df /mnt &> /dev/null; then
  MNT_AVAILABLE_KB=$(df /mnt | tail -1 | awk '{print $4}')
  MNT_AVAILABLE_GB=$((MNT_AVAILABLE_KB / 1024 / 1024))
  echo "  Mount partition (/mnt): ${MNT_AVAILABLE_GB}GB available"

  if [ "$MNT_AVAILABLE_GB" -lt 5 ]; then
    echo "  ⚠️  WARNING: /mnt partition has limited space (${MNT_AVAILABLE_GB}GB)"
  fi
else
  echo "  ⚠️  WARNING: /mnt partition not found or not accessible"
  echo "     Docker relocation may not work as expected"
fi

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
echo "OS: $OS_DESCRIPTION"
echo "Architecture: $(uname -m)"
echo "Kernel: $(uname -r)"
echo "Memory: $(free -h | grep '^Mem:' | awk '{print $2}' | tr -d '\n') total, $(free -h | grep '^Mem:' | awk '{print $7}' | tr -d '\n') available"
echo "CPU cores: $(nproc)"
echo "Disk layout:"
df -h | grep -E '^(Filesystem|/dev/)' || df -h

echo ""
echo "✅ Environment validation complete"
