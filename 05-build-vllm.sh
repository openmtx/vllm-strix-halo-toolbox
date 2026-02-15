#!/usr/bin/env bash
set -euo pipefail

# 05-build-vllm.sh
# Build vLLM from source for ROCm with gfx1151 support
# Based on 99-build-vllm.sh from main branch

# Source environment if available
if [ -f "$(dirname "$0")/.toolbox.env" ]; then
  # shellcheck disable=SC1090
  source "$(dirname "$0")/.toolbox.env"
fi

WORK_DIR="${WORK_DIR:-/workspace}"
VLLM_DIR="${WORK_DIR}/vllm"
VENV_DIR="${VENV_DIR:-/opt/venv}"
NOGPU="${NOGPU:-false}"

echo "[05] Building vLLM from source for ROCm gfx1151..."

# Activate virtual environment
source "${VENV_DIR}/bin/activate"

# Explicitly set PATH and LD_LIBRARY_PATH
ROCM_BIN_DIR=$(rocm-sdk path --bin)
ROCM_ROOT=$(rocm-sdk path --root)
export PATH="${VENV_DIR}/bin:${ROCM_BIN_DIR}:${PATH}"
export LD_LIBRARY_PATH="${ROCM_ROOT}/lib:${LD_LIBRARY_PATH:-}"

# Get ROCm SDK paths
export HIP_DEVICE_LIB_PATH="${ROCM_ROOT}/lib/llvm/amdgcn/bitcode"
export ROCM_PATH="${ROCM_ROOT}"
export ROCM_HOME="${ROCM_ROOT}"

echo "  ROCm Root: ${ROCM_ROOT}"
echo "  Device Lib Path: ${HIP_DEVICE_LIB_PATH}"
echo "  PATH includes ${VENV_DIR}/bin and ${ROCM_BIN_DIR}"
echo "  LD_LIBRARY_PATH includes ${ROCM_ROOT}/lib"

# Step 1: Clone vLLM
echo "[05a] Checking vLLM repository..."
cd "${WORK_DIR}"
if [ ! -d "${VLLM_DIR}" ]; then
    echo "  Cloning vLLM..."
    git clone --depth=1 https://github.com/vllm-project/vllm.git
    cd "${VLLM_DIR}"
else
    echo "  Using existing vLLM directory"
    cd "${VLLM_DIR}"
    git fetch origin || true
    git reset --hard origin/main || true
fi

# Step 2: Configure to use existing PyTorch
echo "[05b] Configuring vLLM to use existing PyTorch..."
if [ -f "use_existing_torch.py" ]; then
    python use_existing_torch.py
else
    echo "  Warning: use_existing_torch.py not found"
fi

# Step 3: Set build environment
echo "[05c] Setting build environment for gfx1151..."
export PYTORCH_ROCM_ARCH=gfx1151
export HSA_OVERRIDE_GFX_VERSION=11.5.1
export GPU_ARCHS=gfx1151
export MAX_JOBS=$(nproc)
export PIP_EXTRA_INDEX_URL=""

# Set CMAKE_PREFIX_PATH and Torch_DIR to help CMake find torch
TORCH_DIR=$(python3 -c "import torch; import os; print(os.path.dirname(torch.__file__))")
export CMAKE_PREFIX_PATH="${TORCH_DIR}"

# Also set Torch_DIR explicitly for CMake to find TorchConfig.cmake
TORCH_SHARE_DIR=$(python3 -c "import torch, os; print(os.path.join(os.path.dirname(torch.__file__), 'share', 'cmake', 'Torch'))")
if [ -d "${TORCH_SHARE_DIR}" ]; then
    export Torch_DIR="${TORCH_SHARE_DIR}"
    echo "  Torch_DIR=${Torch_DIR}"
else
    # Fallback to parent directory
    export Torch_DIR="${TORCH_DIR}"
    echo "  Torch_DIR=${TORCH_DIR} (fallback)"
fi

echo "  PYTORCH_ROCM_ARCH=${PYTORCH_ROCM_ARCH}"
echo "  HSA_OVERRIDE_GFX_VERSION=${HSA_OVERRIDE_GFX_VERSION}"
echo "  MAX_JOBS=${MAX_JOBS}"

# Step 4: Install build dependencies
echo "[05d] Installing build dependencies..."
pip install --no-cache-dir ninja cmake wheel build pybind11 "setuptools-scm>=8" grpcio-tools

# Step 5: Build and install vLLM
echo "[05e] Building and installing vLLM..."
pip install -e . --no-build-isolation --no-deps

echo ""
echo "[05] vLLM build and installation complete!"
echo "  Installation: $(pip show vllm | grep Location)"
echo ""
echo "To use vLLM:"
echo "  source ${VENV_DIR}/bin/activate"
echo "  vllm --help"
