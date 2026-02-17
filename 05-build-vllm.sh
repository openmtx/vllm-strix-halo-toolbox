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
ROCM_HOME="${ROCM_HOME:-/opt/rocm}"
NOGPU="${NOGPU:-false}"

echo "[05] Building vLLM from source for ROCm gfx1151..."
echo "  NOGPU: ${NOGPU}"

# Activate virtual environment
source "${VENV_DIR}/bin/activate"

# Explicitly set PATH and LD_LIBRARY_PATH - ROCm first, then venv
export PATH="${ROCM_HOME}/bin:${VENV_DIR}/bin:${PATH}"
export LD_LIBRARY_PATH="${ROCM_HOME}/lib:${LD_LIBRARY_PATH:-}"

# Get ROCm SDK paths
export ROCM_PATH="${ROCM_HOME}"
export HIP_DEVICE_LIB_PATH="${ROCM_HOME}/lib/llvm/amdgcn/bitcode"

echo "  ROCm Root: ${ROCM_HOME}"
echo "  Device Lib Path: ${HIP_DEVICE_LIB_PATH}"
echo "  PATH includes ${ROCM_HOME}/bin and ${VENV_DIR}/bin"
echo "  LD_LIBRARY_PATH includes ${ROCM_HOME}/lib"

# Step 0: Create get-torch-dir.py helper script on the fly
echo "[05a] Creating get-torch-dir.py helper script..."
cat > "${WORK_DIR}/get-torch-dir.py" << 'GETTORCHEOF'
#!/usr/bin/env python3
import sys
import os

# Get torch directory from environment or use well-known path
# This avoids importing torch and triggering ROCm initialization messages
torch_dir = "/opt/venv/lib/python3.12/site-packages/torch"

if not os.path.isdir(torch_dir):
    # Fallback: try to find it
    import subprocess
    result = subprocess.run(
        [sys.executable, "-c", "import torch; print(torch.__file__, end='')"],
        capture_output=True,
        text=True
    )
    torch_file = result.stdout.strip()
    # Filter out any warning lines, keep only the path
    for line in torch_file.split('\n'):
        line = line.strip()
        if line and not line.startswith('[') and not line.startswith('Failed'):
            torch_file = line
            break
    torch_dir = os.path.dirname(os.path.abspath(torch_file))

print(torch_dir, end="")
GETTORCHEOF
chmod +x "${WORK_DIR}/get-torch-dir.py"
echo "  ✓ get-torch-dir.py created at ${WORK_DIR}/get-torch-dir.py"

# Step 1: Clone vLLM
echo "[05b] Checking vLLM repository..."
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

# Step 1b: Configure to use existing torch
echo "[05b] Configuring vLLM to use existing torch installation..."

# Run use_existing_torch.py - suppress all output
python3 use_existing_torch.py > /dev/null 2>&1 || echo "  WARNING: use_existing_torch.py had issues"

echo "  Torch configuration step complete"

# Step 1c: Patch CMakeLists.txt to skip enable_language(HIP) when NOGPU is set
# This avoids the "Failed to find a default HIP architecture" error in CPU-only builds
echo "[05c] Patching CMakeLists.txt for CPU-only build..."
if [ "${NOGPU}" = "true" ]; then
    echo "  NOGPU=true, patching CMakeLists.txt to skip enable_language(HIP)..."
    sed -i 's/enable_language(HIP)/if(NOT DEFINED ENV{NOGPU} OR NOT "\$ENV{NOGPU}" STREQUAL "true")\n  enable_language(HIP)\nendif()/' CMakeLists.txt
    echo "  ✓ CMakeLists.txt patched"
else
    echo "  NOGPU=${NOGPU}, skipping CMakeLists.txt patch"
fi

# Step 2: Set build environment
echo "[05d] Setting build environment for gfx1151..."
export PYTORCH_ROCM_ARCH=gfx1151
export HSA_OVERRIDE_GFX_VERSION=11.5.1
export GPU_ARCHS=gfx1151
export MAX_JOBS=$(nproc)
export PIP_EXTRA_INDEX_URL=""

# Set CMAKE_PREFIX_PATH and Torch_DIR to help CMake find torch
# Use Python script to get path without warnings
TORCH_DIR=$(python3 /workspace/get-torch-dir.py)

# Also set Torch_DIR explicitly for CMake to find TorchConfig.cmake
TORCH_SHARE_DIR="${TORCH_DIR}/share/cmake/Torch"

# Set CMAKE_PREFIX_PATH with ROCm paths
export CMAKE_PREFIX_PATH="${TORCH_DIR}:/opt/rocm:/opt/rocm/lib/cmake:/opt/rocm/lib/cmake/hip:/opt/rocm/lib/cmake/hsa-runtime64:/opt/rocm/lib/cmake/amd_comgr:/opt/rocm/hip/share/cmake"
export HIP_PATH="/opt/rocm"
if [ -d "${TORCH_SHARE_DIR}" ]; then
    export Torch_DIR="${TORCH_SHARE_DIR}"
    echo "  Torch_DIR=${Torch_DIR}"
    # Verify TorchConfig.cmake exists
    if [ -f "${TORCH_SHARE_DIR}/TorchConfig.cmake" ]; then
        echo "  ✓ TorchConfig.cmake found"
    else
        echo "  WARNING: TorchConfig.cmake not found at ${TORCH_SHARE_DIR}"
    fi
else
    # Fallback to parent directory
    export Torch_DIR="${TORCH_DIR}"
    echo "  Torch_DIR=${TORCH_DIR} (fallback)"
fi

# Set minimal CMAKE_ARGS - just Torch_DIR, avoid quoting issues
export CMAKE_ARGS="-DTorch_DIR=${Torch_DIR}"

echo "  PYTORCH_ROCM_ARCH=${PYTORCH_ROCM_ARCH}"
echo "  HSA_OVERRIDE_GFX_VERSION=${HSA_OVERRIDE_GFX_VERSION}"
echo "  MAX_JOBS=${MAX_JOBS}"

# Step 3: Install build dependencies
echo "[05e] Installing build dependencies and vLLM requirements..."
# cmake and ninja are already installed via pip in 02-install-rocm.sh
pip install --no-cache-dir wheel build pybind11 "setuptools-scm>=8" grpcio-tools einops pandas psutil

# Step 4: Build and install vLLM using setup.py directly
echo "[05f] Building and installing vLLM using setup.py..."
# CMAKE_ARGS should already be set by use_existing_torch.py
echo "  Using CMAKE_ARGS: ${CMAKE_ARGS:-not set}"
echo "  Torch_DIR: ${Torch_DIR:-not set}"

# Build vLLM wheel directly with explicit CMake args
CMAKE_ARGS="-DTorch_DIR=${Torch_DIR} -DCMAKE_PREFIX_PATH=${CMAKE_PREFIX_PATH}" python3 setup.py bdist_wheel

# Install the wheel
pip install --no-deps ./dist/vllm-*.whl || pip install ./dist/vllm-*.whl

echo ""
echo "[05] vLLM build and installation complete!"
echo "  Installation: $(pip show vllm | grep Location)"
echo ""
echo "To use vLLM:"
echo "  source ${VENV_DIR}/bin/activate"
echo "  vllm --help"
