#!/usr/bin/env bash
set -euo pipefail

# Source environment if available
if [ -f "$(dirname "$0")/.toolbox.env" ]; then
  source "$(dirname "$0")/.toolbox.env"
fi

WORK_DIR="${WORK_DIR:-/workspace}"
VENV_DIR="${VENV_DIR:-/opt/venv}"
AITER_DIR="${WORK_DIR}/aiter"

# Set default GPU target
GPU_TARGET="${GPU_TARGET:-gfx1151}"

echo "[03] Building AMD AITER..."
echo "GPU Target: ${GPU_TARGET}"

# Source environment
source "${VENV_DIR:-/opt/venv}/bin/activate"

# Explicitly set GPU architecture for AITER JIT compilation
export GPU_ARCHS="${GPU_TARGET}"
echo "  Setting AITER GPU architecture..."
echo "  GPU_ARCHS=${GPU_ARCHS}"
export AITER_REBUILD=1

# Set ROCm paths
export ROCM_HOME="${VENV_DIR}/lib/python3.12/site-packages/_rocm_sdk_devel"
export ROCM_PATH="${ROCM_HOME}"
export PATH="${VENV_DIR}/bin:${PATH}"

echo "  ROCM_HOME=${ROCM_HOME}"
echo "  PATH includes ${VENV_DIR}/bin"

# Clone AITER repository
if [ -d "${AITER_DIR}" ]; then
    echo "AITER directory exists, pulling latest changes..."
    cd "${AITER_DIR}"
    git pull origin main || true
else
    echo "Cloning AITER repository..."
    git clone https://github.com/ROCm/aiter.git "${AITER_DIR}"
    cd "${AITER_DIR}"
fi

echo "Building AITER (includes JIT source files for gfx1151)..."
echo ""
echo "Step 1: Build in develop mode (includes source files)..."
python setup.py develop --no-deps || echo "AITER develop mode build failed - vLLM will work without it"

echo ""
echo "Step 2: Create wheel from development build..."
python setup.py bdist_wheel || echo "AITER wheel creation failed - vLLM will work without it"

# Copy wheel to wheels directory
echo ""
echo "Copying wheel to workspace wheels directory..."
WHEEL_DIR="${WORK_DIR}/wheels"
mkdir -p "${WHEEL_DIR}"
cp -v dist/amd_aiter-*.whl "${WHEEL_DIR}/" 2>/dev/null || echo "Failed to copy AITER wheel"

echo ""
echo "[03] AITER build complete!"