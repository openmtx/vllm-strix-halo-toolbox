#!/usr/bin/env bash
set -euo pipefail

# 05-build-vllm.sh
# Build vLLM from source for ROCm with gfx1151 support

# Source environment if available
if [ -f "$(dirname "$0")/.toolbox.env" ]; then
  # shellcheck disable=SC1090
  source "$(dirname "$0")/.toolbox.env"
fi

WORK_DIR="${WORK_DIR:-/workspace}"
VENV_DIR="${VENV_DIR:-${WORK_DIR}/venv}"
VLLM_DIR="${WORK_DIR}/vllm"
ROCM_INDEX_URL="${ROCM_INDEX_URL:-https://rocm.nightlies.amd.com/v2/gfx1151/}"
NOGPU="${NOGPU:-false}"

# Set SUDO based on whether running as root (Docker) or non-root (distrobox)
if [ "$(id -u)" = "0" ]; then
    SUDO=""
else
    SUDO="sudo"
fi

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

# Ensure /opt/rocm symlink exists for compatibility
if [ ! -L "/opt/rocm" ]; then
    echo "  Creating /opt/rocm symlink..."
    ${SUDO} mkdir -p /opt
    ${SUDO} ln -sf "${ROCM_ROOT}" /opt/rocm
fi

# Step 1: Clone vLLM
echo "[05a] Checking vLLM repository..."
if [ ! -d "${VLLM_DIR}" ]; then
    echo "  Cloning vLLM..."
    git clone --depth=1 https://github.com/vllm-project/vllm.git "${VLLM_DIR}"
fi
cd "${VLLM_DIR}"

# Step 2: Apply AMD-SMI patches for NOGPU mode
echo "[05b] Applying AMD-SMI patches for NOGPU mode..."
cd "${VLLM_DIR}"
if [ -f "${WORK_DIR}/patch_vllm.py" ]; then
    python3 "${WORK_DIR}/patch_vllm.py"
else
    echo "Warning: patch_vllm.py not found, skipping patch"
fi

# Step 3: Configure to use existing PyTorch
echo "[05c] Configuring vLLM..."
python3 use_existing_torch.py

# Step 4: Set build environment
echo "[05d] Setting build environment..."
export PYTORCH_ROCM_ARCH=gfx1151
export GPU_ARCHS=gfx1151
export MAX_JOBS=$(nproc)

# Set CMAKE_PREFIX_PATH to help CMake find torch
TORCH_DIR=$(python3 -c "import torch; import os; print(os.path.dirname(torch.__file__))")
export CMAKE_PREFIX_PATH="${TORCH_DIR}"
echo "  CMAKE_PREFIX_PATH=${CMAKE_PREFIX_PATH}"

# Important: Set compiler flags to find device libraries
export HIPFLAGS="--rocm-device-lib-path=${HIP_DEVICE_LIB_PATH}"

echo "  PYTORCH_ROCM_ARCH=${PYTORCH_ROCM_ARCH}"
echo "  HIPFLAGS=${HIPFLAGS}"

# Step 5: Install setuptools-scm for vLLM build (needed for --no-deps)
echo "[05e] Installing build dependencies..."
pip install "setuptools-scm>=8"

# Step 6: Build and install vLLM directly (tcmalloc is preloaded system-wide via /etc/ld.so.preload)
echo "[05f] Building and installing vLLM..."
pip install . --no-deps --no-build-isolation

echo ""
echo "[05] vLLM build and installation complete!"
echo "  Installation: $(pip show vllm | grep Location)"
echo ""
echo "To use vLLM:"
echo "  distrobox enter ${TOOLBOX_NAME:-restart}"
echo "  source ${VENV_DIR}/bin/activate"
echo "  vllm --help"
