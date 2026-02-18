#!/usr/bin/env bash
set -euo pipefail

# 04-build-fa.sh
# Build Flash Attention wheel for ROCm with gfx1151 (Strix Halo) support

# Source environment if available
if [ -f "$(dirname "$0")/.toolbox.env" ]; then
  source "$(dirname "$0")/.toolbox.env"
fi

WORK_DIR="${WORK_DIR:-/workspace}"
VENV_DIR="${VENV_DIR:-/opt/venv}"
ROCM_HOME="${ROCM_HOME:-/opt/rocm}"
FA_DIR="${WORK_DIR}/flash-attention"
GPU_TARGET="${GPU_TARGET:-gfx1151}"
ROCM_INDEX_URL="${ROCM_INDEX_URL:-https://rocm.nightlies.amd.com/v2/gfx1151/}"
NOGPU="${NOGPU:-false}"

echo "[05] Building Flash Attention..."
echo "  GPU Target: ${GPU_TARGET}"
echo "  Flash Attention Dir: ${FA_DIR}"
echo "  NOGPU: ${NOGPU}"
echo ""

# Activate virtual environment
source "${VENV_DIR}/bin/activate"

# Explicitly set PATH and LD_LIBRARY_PATH - ROCm first, then venv
export PATH="${ROCM_HOME}/bin:${VENV_DIR}/bin:${PATH}"
export LD_LIBRARY_PATH="${ROCM_HOME}/lib:${LD_LIBRARY_PATH:-}"
echo "  ROCm Home: ${ROCM_HOME}"
echo "  PATH includes ${ROCM_HOME}/bin and ${VENV_DIR}/bin"
echo "  LD_LIBRARY_PATH includes ${ROCM_HOME}/lib"

# Clone Flash Attention repository
if [ -d "${FA_DIR}" ]; then
    echo "Flash Attention directory exists, pulling latest changes..."
    cd "${FA_DIR}"
    git pull origin main || true
else
    echo "Cloning Flash Attention repository..."
    git clone https://github.com/ROCm/flash-attention.git "${FA_DIR}"
    cd "${FA_DIR}"
fi

# Checkout main_perf branch
echo "Checking out main_perf branch..."
git checkout main_perf

# Set ROCm architecture for Flash Attention
echo "Setting ROCm architecture..."
export PYTORCH_ROCM_ARCH="${GPU_TARGET}"
export FLASH_ATTENTION_TRITON_AMD_ENABLE="TRUE"
echo "  PYTORCH_ROCM_ARCH=${PYTORCH_ROCM_ARCH}"
echo "  FLASH_ATTENTION_TRITON_AMD_ENABLE=${FLASH_ATTENTION_TRITON_AMD_ENABLE}"

# Set ROCm paths for Flash Attention
echo "Setting ROCm paths..."
export ROCM_PATH="${ROCM_HOME}"
export CMAKE_PREFIX_PATH="${ROCM_HOME}/lib/cmake:${CMAKE_PREFIX_PATH:-}"
export HIP_PATH="${ROCM_HOME}"
echo "  ROCM_HOME=${ROCM_HOME}"
echo "  CMAKE_PREFIX_PATH includes ${ROCM_HOME}/lib/cmake"
echo "  HIP_PATH=${HIP_PATH}"

# Build and install Flash Attention directly
echo "Building and installing Flash Attention (using no-build-isolation)..."
pip install . --no-deps --no-build-isolation

echo ""
echo "[05] Flash Attention build and installation complete!"
echo ""
echo "Verifying installation..."
if pip show flash-attn >/dev/null 2>&1; then
    echo "  ✅ Flash Attention: Successfully installed"
    pip show flash-attn | grep "^Name:" && pip show flash-attn | grep "^Version:"
else
    echo "  ❌ Flash Attention: Installation failed"
    exit 1
fi
