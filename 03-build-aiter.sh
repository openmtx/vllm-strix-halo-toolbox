#!/usr/bin/env bash
set -euo pipefail

# Source environment if available
if [ -f "$(dirname "$0")/.toolbox.env" ]; then
  source "$(dirname "$0")/.toolbox.env"
fi

WORK_DIR="${WORK_DIR:-/workspace}"
VENV_DIR="${VENV_DIR:-/opt/venv}"
AITER_DIR="${WORK_DIR}/aiter"
NOGPU="${NOGPU:-false}"

# Set default GPU target
GPU_TARGET="${GPU_TARGET:-gfx1151}"

echo "[03] Building AMD AITER..."
echo "GPU Target: ${GPU_TARGET}"

# Source environment (includes PATH and LD_LIBRARY_PATH from /etc/profile.d/rocm-sdk.sh)
source "${VENV_DIR:-/opt/venv}/bin/activate"
source /etc/profile.d/rocm-sdk.sh

# Explicitly set PATH and LD_LIBRARY_PATH
ROCM_BIN_DIR=$(rocm-sdk path --bin)
ROCM_ROOT=$(rocm-sdk path --root)
export PATH="${VENV_DIR}/bin:${ROCM_BIN_DIR}:${PATH}"
export LD_LIBRARY_PATH="${ROCM_ROOT}/lib:${LD_LIBRARY_PATH:-}"

# Explicitly set GPU architecture for AITER JIT compilation
export GPU_ARCHS="${GPU_TARGET}"
echo "  Setting AITER GPU architecture..."
echo "  GPU_ARCHS=${GPU_ARCHS}"
export AITER_REBUILD=1

# Set ROCm paths
export ROCM_HOME="${VENV_DIR}/lib/python3.12/site-packages/_rocm_sdk_devel"
export ROCM_PATH="${ROCM_HOME}"

echo "  ROCM_HOME=${ROCM_HOME}"
echo "  PATH includes ${VENV_DIR}/bin and ${ROCM_BIN_DIR}"
echo "  LD_LIBRARY_PATH includes ${ROCM_ROOT}/lib"

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

echo "Building and installing AITER..."
echo ""
pip install . --no-deps --no-build-isolation || echo "AITER installation failed - vLLM will work without it"

echo ""
echo "[03] AITER build and installation complete!"