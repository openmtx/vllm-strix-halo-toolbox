#!/usr/bin/env bash
set -euo pipefail

# 01-install-tools.sh
# Install system-level build tools and dependencies
# Run inside the distrobox: ./01-install-tools.sh

# Source environment if available
if [ -f "$(dirname "$0")/.toolbox.env" ]; then
  # shellcheck disable=SC1090
  source "$(dirname "$0")/.toolbox.env"
fi

WORK_DIR="${WORK_DIR:-/workspace}"
VENV_DIR="${VENV_DIR:-/opt/venv}"

# Set SUDO based on whether running as root (Docker) or non-root (distrobox)
if [ "$(id -u)" = "0" ]; then
    SUDO=""
else
    SUDO="sudo"
fi

# Create workspace and venv directories with correct ownership
echo "[01] Creating directories..."
${SUDO} mkdir -p "${WORK_DIR}" "${VENV_DIR}"
# Skip chown in Docker (running as root), but use in distrobox (needs sudo)
if [ -n "${SUDO}" ]; then
    ${SUDO} chown -R "$(id -u):$(id -g)" "${WORK_DIR}" "${VENV_DIR}"
    echo "  ✓ Created ${WORK_DIR} (ownership set)"
else
    echo "  ✓ Created ${WORK_DIR} (Docker, no ownership needed)"
fi
echo "  ✓ Created ${VENV_DIR}"

echo "[01] Installing system build tools..."

# Update package lists
echo "Updating package lists..."
${SUDO} apt-get update

# Install build essentials and development tools
echo "Installing build essentials..."
${SUDO} apt-get install --no-install-recommends -y \
    build-essential \
    git \
    curl \
    ca-certificates \
    wget \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    python3-pip \
    pkg-config \
    libssl-dev \
    libffi-dev \
    google-perftools \
    libgoogle-perftools-dev \
    libgfortran5 \
    libatomic1 \
    libgomp1

# Verify installations
echo "Verifying installations..."
echo "  Python3: $(python3 --version)"
echo "  Git: $(git --version)"
echo "  TCMalloc: $(dpkg -l | grep google-perftools | head -1 | awk '{print $2 ":" $3}')"

# Configure tcmalloc system-wide to prevent memory corruption with pip-installed ROCm
echo ""
echo "Configuring TCMalloc system-wide..."
TCMALLOC_PATH="/usr/lib/x86_64-linux-gnu/libtcmalloc.so.4"
if [ -f "$TCMALLOC_PATH" ]; then
    if [ -f "/etc/ld.so.preload" ] && grep -q "^$TCMALLOC_PATH$" /etc/ld.so.preload; then
        echo "  ✓ TCMalloc already configured in /etc/ld.so.preload"
    else
        echo "$TCMALLOC_PATH" | ${SUDO} tee /etc/ld.so.preload > /dev/null
        echo "  ✓ TCMalloc configured in /etc/ld.so.preload"
    fi
else
    echo "  Warning: TCMalloc library not found at expected location"
fi

echo ""
echo "[01] System tools installation complete!"
echo "Note: TCMalloc is configured system-wide to prevent memory corruption issues."
