#!/usr/bin/env bash
# relocate-docker.sh - Relocate Docker storage to larger partition
#
# Parameters:
#   $1 - MODE: always, auto, or never
#   $2 - TARGET_PATH: target directory for Docker storage (default: /mnt/docker-storage)

set -e

MODE="${1:-always}"
TARGET_PATH="${2:-/mnt/docker-storage}"

echo "=== Docker Storage Relocation ==="
echo "Mode: $MODE"
echo "Target path: $TARGET_PATH"

# Skip if mode is 'never'
if [ "$MODE" = "never" ]; then
  echo "Relocation disabled (mode: never). Skipping."
  exit 0
fi

# Check dependencies
for cmd in jq docker; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ ERROR: $cmd is not installed."
    exit 1
  fi
done

# Check if Docker is already relocated
echo ""
echo "Checking if Docker is already relocated..."
CURRENT_DATA_ROOT=$(docker info 2>/dev/null | grep "Docker Root Dir:" | awk '{print $4}' || echo "")
if [ -n "$CURRENT_DATA_ROOT" ] && [ "$CURRENT_DATA_ROOT" = "$TARGET_PATH" ]; then
  echo "✅ Docker already relocated to $TARGET_PATH. Skipping."
  exit 0
fi

# Analyze partition space
echo ""
echo "Analyzing partition space..."
df -h
lsblk

ROOT_AVAILABLE_KB=$(df / | tail -1 | awk '{print $4}')
ROOT_AVAILABLE_GB=$((ROOT_AVAILABLE_KB / 1024 / 1024))
echo "Root partition (/): ${ROOT_AVAILABLE_GB}GB available"

# Check if /mnt is on a different partition than /
ROOT_DEVICE=$(df / | tail -1 | awk '{print $1}')
MNT_DEVICE=$(df /mnt 2>/dev/null | tail -1 | awk '{print $1}' || echo "$ROOT_DEVICE")

echo "Root device: $ROOT_DEVICE"
echo "Mount device: $MNT_DEVICE"

if [ "$ROOT_DEVICE" = "$MNT_DEVICE" ]; then
  echo "⚠️  /mnt is on the same partition as / - relocation would not free space"
  if [ "$MODE" = "always" ]; then
    echo "❌ ERROR: mode=always but /mnt is not a separate partition"
    echo "   Suggestion: Use relocate-docker: auto or relocate-docker: never"
    exit 1
  fi
  echo "Skipping Docker relocation (same partition)."
  exit 0
fi

# Get /mnt partition info
if df /mnt &> /dev/null; then
  MNT_AVAILABLE_KB=$(df /mnt | tail -1 | awk '{print $4}')
  MNT_AVAILABLE_GB=$((MNT_AVAILABLE_KB / 1024 / 1024))
  echo "Mount partition (/mnt): ${MNT_AVAILABLE_GB}GB available"
else
  echo "⚠️  WARNING: /mnt partition not found. Skipping relocation."
  if [ "$MODE" = "always" ]; then
    echo "❌ ERROR: mode=always but /mnt partition unavailable"
    exit 1
  fi
  exit 0
fi

TARGET_AVAILABLE_GB=$MNT_AVAILABLE_GB

# Validate target partition has sufficient space
if [ "${TARGET_AVAILABLE_GB:-0}" -lt 10 ]; then
  echo "⚠️  WARNING: Target partition has insufficient space (${TARGET_AVAILABLE_GB}GB < 10GB)"
  if [ "$MODE" = "always" ]; then
    echo "❌ ERROR: mode=always but target partition has insufficient space"
    exit 1
  fi
  echo "Skipping relocation."
  exit 0
fi

# Auto mode: only relocate if target has significantly more space
if [ "$MODE" = "auto" ]; then
  SPACE_DIFF=$((TARGET_AVAILABLE_GB - ROOT_AVAILABLE_GB))
  if [ "$SPACE_DIFF" -lt 10 ]; then
    echo "Auto mode: Target partition does not have significantly more space (${SPACE_DIFF}GB difference)"
    echo "Skipping relocation."
    exit 0
  fi
  echo "Auto mode: Target partition has ${SPACE_DIFF}GB more space. Proceeding with relocation."
fi

# Create daemon.json if it doesn't exist
if [ ! -f /etc/docker/daemon.json ]; then
  echo "Creating /etc/docker/daemon.json..."
  echo '{}' | sudo tee /etc/docker/daemon.json > /dev/null
fi

# Backup original daemon.json
echo ""
echo "Backing up original Docker configuration..."
sudo cp /etc/docker/daemon.json /etc/docker/daemon.json.backup

# Stop Docker to relocate safely
echo ""
echo "Stopping Docker service..."
if ! sudo systemctl stop docker; then
  echo "⚠️  Failed to stop Docker gracefully, forcing..."
  sudo systemctl kill docker || true
  sleep 2
fi

# Create target directory
echo ""
echo "Creating Docker storage directory: $TARGET_PATH"
if [ ! -d "$TARGET_PATH" ]; then
  sudo mkdir -p "$TARGET_PATH"
  echo "✅ Created $TARGET_PATH"
else
  echo "✅ $TARGET_PATH already exists"
fi

# Move existing Docker data if present
if [ -d "/var/lib/docker" ] && [ "$(ls -A /var/lib/docker 2>/dev/null)" ]; then
  echo "Moving existing Docker data to $TARGET_PATH..."
  sudo mv /var/lib/docker/* "$TARGET_PATH/" 2>/dev/null || true
  echo "✅ Existing data moved"
fi

# Update Docker daemon.json
echo ""
echo "Updating Docker configuration..."
if ! sudo jq ". += {\"data-root\": \"$TARGET_PATH\"}" /etc/docker/daemon.json | sudo tee /tmp/docker-daemon.json > /dev/null; then
  echo "❌ ERROR: Failed to update daemon.json"
  echo "Restoring backup..."
  sudo cp /etc/docker/daemon.json.backup /etc/docker/daemon.json
  exit 1
fi
sudo cp /tmp/docker-daemon.json /etc/docker/daemon.json
sudo rm /tmp/docker-daemon.json

echo "Docker daemon.json:"
cat /etc/docker/daemon.json

# Configure containerd
echo ""
echo "Configuring containerd..."
if [ -f /etc/containerd/config.toml ]; then
  sudo cp /etc/containerd/config.toml /etc/containerd/config.toml.backup
fi

sudo mkdir -p /etc/containerd
sudo tee /etc/containerd/config.toml > /dev/null <<EOF
version = 2
root = "$TARGET_PATH/containerd"
state = "$TARGET_PATH/containerd-state"

[grpc]
  address = "/run/containerd/containerd.sock"

[plugins."io.containerd.grpc.v1.cri"]
  sandbox_image = "registry.k8s.io/pause:3.9"

[plugins."io.containerd.grpc.v1.cri".containerd]
  snapshotter = "overlayfs"

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc]
  runtime_type = "io.containerd.runc.v2"

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]
  SystemdCgroup = true
EOF

# Create containerd directories
sudo mkdir -p "$TARGET_PATH/containerd"
sudo mkdir -p "$TARGET_PATH/containerd-state"
echo "✅ Containerd configured"

# Restart services
echo ""
echo "Restarting container services..."
sudo systemctl restart containerd
sudo systemctl restart docker

# Validate services are running
echo ""
echo "Validating service status..."
if ! sudo systemctl is-active docker > /dev/null; then
  echo "❌ ERROR: Docker service failed to start"
  echo "Attempting to restore backup configuration..."
  sudo cp /etc/docker/daemon.json.backup /etc/docker/daemon.json
  if [ -f /etc/containerd/config.toml.backup ]; then
    sudo cp /etc/containerd/config.toml.backup /etc/containerd/config.toml
  fi
  sudo systemctl restart containerd
  sudo systemctl restart docker
  exit 1
fi
echo "✅ Docker service is active"

if ! sudo systemctl is-active containerd > /dev/null; then
  echo "⚠️  WARNING: Containerd service is not active"
else
  echo "✅ Containerd service is active"
fi

# Validate Docker functionality
echo ""
echo "Testing Docker functionality..."
if ! docker info > /dev/null 2>&1; then
  echo "❌ ERROR: Docker is not responding"
  exit 1
fi
echo "✅ Docker is responding"

# Verify new data root
NEW_DATA_ROOT=$(docker info 2>/dev/null | grep "Docker Root Dir:" | awk '{print $4}' || echo "")
if [ "$NEW_DATA_ROOT" = "$TARGET_PATH" ]; then
  echo "✅ Docker successfully relocated to $TARGET_PATH"
else
  echo "❌ ERROR: Docker data root is $NEW_DATA_ROOT, expected $TARGET_PATH"
  exit 1
fi

# Validate storage directory
echo ""
echo "Validating storage directory..."
if [ -d "$TARGET_PATH" ]; then
  STORAGE_SIZE=$(sudo du -sh "$TARGET_PATH" 2>/dev/null | cut -f1 || echo "unknown")
  echo "✅ Docker storage directory: ${STORAGE_SIZE}"
  sudo ls -la "$TARGET_PATH"
else
  echo "❌ ERROR: Storage directory not found!"
  exit 1
fi

echo ""
echo "=== Docker Relocation Complete ==="
df -h
