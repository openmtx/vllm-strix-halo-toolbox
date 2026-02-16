#!/usr/bin/env bash
set -euo pipefail

# Source environment if available
if [ -f "$(dirname "$0")/.toolbox.env" ]; then
  source "$(dirname "$0")/.toolbox.env"
fi

WORK_DIR="${WORK_DIR:-/workspace}"
VENV_DIR="${VENV_DIR:-/opt/venv}"
ROCM_HOME="${ROCM_HOME:-/opt/rocm}"
AITER_DIR="${WORK_DIR}/aiter"
NOGPU="${NOGPU:-false}"

# Set default GPU target
GPU_TARGET="${GPU_TARGET:-gfx1151}"

echo "[03] Building AMD AITER..."
echo "GPU Target: ${GPU_TARGET}"
echo "NOGPU: ${NOGPU}"

# Activate virtual environment
source "${VENV_DIR}/bin/activate"

# Explicitly set PATH and LD_LIBRARY_PATH
export PATH="${VENV_DIR}/bin:${ROCM_HOME}/bin:${PATH}"
export LD_LIBRARY_PATH="${ROCM_HOME}/lib:${LD_LIBRARY_PATH:-}"

# Explicitly set GPU architecture for AITER JIT compilation
export GPU_ARCHS="${GPU_TARGET}"
echo "  Setting AITER GPU architecture..."
echo "  GPU_ARCHS=${GPU_ARCHS}"
export AITER_REBUILD=1

# Set ROCm paths
export ROCM_PATH="${ROCM_HOME}"
export CMAKE_PREFIX_PATH="${ROCM_HOME}/lib/cmake:${CMAKE_PREFIX_PATH:-}"

echo "  ROCM_HOME=${ROCM_HOME}"
echo "  PATH includes ${VENV_DIR}/bin and ${ROCM_HOME}/bin"
echo "  LD_LIBRARY_PATH includes ${ROCM_HOME}/lib"
echo "  CMAKE_PREFIX_PATH includes ${ROCM_HOME}/lib/cmake"

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