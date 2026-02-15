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
FA_DIR="${WORK_DIR}/flash-attention"
WHEEL_DIR="${WORK_DIR}/wheels"
GPU_TARGET="${GPU_TARGET:-gfx1151}"
ROCM_INDEX_URL="${ROCM_INDEX_URL:-https://rocm.nightlies.amd.com/v2/gfx1151/}"

echo "[04] Building Flash Attention..."
echo "  GPU Target: ${GPU_TARGET}"
echo "  Flash Attention Dir: ${FA_DIR}"
echo ""

# Activate virtual environment
source "${VENV_DIR}/bin/activate"

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
export ROCM_HOME="${VENV_DIR}/lib/python3.12/site-packages/_rocm_sdk_devel"
export ROCM_PATH="${ROCM_HOME}"
export PATH="${VENV_DIR}/bin:${PATH}"
echo "  ROCM_HOME=${ROCM_HOME}"
echo "  PATH includes ${VENV_DIR}/bin"

# Create wheels directory
mkdir -p "${WHEEL_DIR}"

# Build Flash Attention wheel
# Note: Using --no-build-isolation to use existing environment with rocm_sdk installed
echo "Building Flash Attention wheel (using no-build-isolation)..."
pip wheel . --no-deps --no-build-isolation -w "${WHEEL_DIR}"

# Find the built wheel
FA_WHEEL=$(ls -t "${WHEEL_DIR}"/flash_attn-*.whl 2>/dev/null | head -1)
if [ -z "${FA_WHEEL}" ]; then
    echo "ERROR: Failed to find built Flash Attention wheel"
    exit 1
fi

echo ""
echo "  ✓ Flash Attention wheel built: ${FA_WHEEL}"

# Install Flash Attention from wheel
echo ""
echo "Installing Flash Attention from wheel (with --no-deps to avoid CUDA torch)..."
pip install --no-deps "${FA_WHEEL}"

echo ""
echo "[04] Flash Attention build complete!"
echo ""
echo "Verifying installation..."
source "${VENV_DIR}/bin/activate"
if pip show flash-attn >/dev/null 2>&1; then
    echo "  ✅ Flash Attention: Successfully installed"
    pip show flash-attn | grep "^Name:" && pip show flash-attn | grep "^Version:"
    echo "  📦 Wheel: ${FA_WHEEL}"
else
    echo "  ❌ Flash Attention: Installation failed"
    exit 1
fi
echo ""
echo "To proceed with vLLM:"
echo "  distrobox enter ${TOOLBOX_NAME:-restart}"
echo "  source ${VENV_DIR}/bin/activate"
echo "  ./05-build-vllm.sh"
