#!/usr/bin/env bash
set -euo pipefail

# 02-install-rocm.sh
# Create virtual environment and install AMD nightly ROCm and PyTorch
# Run inside the distrobox: ./02-install-rocm.sh
#
# Environment Variables:
#   SKIP_VERIFICATION=true  - Skip GPU verification tests (useful for CPU-only builds)

# Source environment if available
if [ -f "$(dirname "$0")/.toolbox.env" ]; then
  # shellcheck disable=SC1090
  source "$(dirname "$0")/.toolbox.env"
fi

WORK_DIR="${WORK_DIR:-/workspace}"
VENV_DIR="${VENV_DIR:-/opt/venv}"
ROCM_INDEX_URL="${ROCM_INDEX_URL:-https://rocm.nightlies.amd.com/v2/gfx1151/}"
ROCM_HOME="${ROCM_HOME:-/opt/rocm}"
PYTHON_VERSION="${PYTHON_VERSION:-3.12}"
SKIP_VERIFICATION="${SKIP_VERIFICATION:-false}"
NOGPU="${NOGPU:-false}"

# Set SUDO based on whether running as root (Docker) or non-root (distrobox)
if [ "$(id -u)" = "0" ]; then
    SUDO=""
else
    SUDO="sudo"
fi

# Check if we should skip GPU verification (CPU-only build)
if [ "${NOGPU}" = "true" ] || [ "${SKIP_VERIFICATION}" = "true" ]; then
    SKIP_GPU_CHECK="true"
else
    SKIP_GPU_CHECK="false"
fi

echo "[02] Setting up Python virtual environment and installing AMD nightly packages..."
echo "  ROCm Index: ${ROCM_INDEX_URL}"
echo "  VENV: ${VENV_DIR}"

# Create workspace directory
mkdir -p "${WORK_DIR}"

# Create virtual environment
echo "Creating Python ${PYTHON_VERSION} virtual environment..."
python${PYTHON_VERSION} -m venv "${VENV_DIR}"

# Activate virtual environment
source "${VENV_DIR}/bin/activate"

# Upgrade pip and basic tools
echo "Upgrading pip, wheel, and setuptools..."
pip install --upgrade pip wheel setuptools

echo "[02a-0] Installing CMake 3.26.4 and Ninja via pip..."
pip install cmake==3.26.4 ninja
echo "  ✓ Installed CMake 3.26.4 (avoids HIP detection bug in 3.28)"
echo "  ✓ Installed Ninja"

echo "[02a] Installing AMD nightly ROCm base package..."
pip install --index-url "${ROCM_INDEX_URL}" "rocm"

echo "[02b] Installing AMD nightly PyTorch packages (prerelease)..."
# This will install a specific rocm[libraries] version as a dependency
pip install --pre --index-url "${ROCM_INDEX_URL}" torch torchaudio torchvision

echo "[02c-1] Synchronizing ROCm SDK component versions..."

# Extract the canonical version string from rocm package
VERSION=$(pip show rocm | grep -i "Version:" | awk '{print $2}')

if [ -z "$VERSION" ]; then
    echo "  ❌ ERROR: Failed to extract version from 'pip show rocm'"
    echo "  This indicates a critical installation problem. Exiting."
    exit 1
fi

echo "  ✅ Found Version: $VERSION"
echo "  🚀 Installing SDK components to match..."

# Install all three SDK components with exact same version
# Using --no-deps prevents pip from changing Torch dependencies
pip install --no-deps --index-url "${ROCM_INDEX_URL}" \
    "rocm-sdk-core==$VERSION" \
    "rocm-sdk-devel==$VERSION" \
    "rocm-sdk-libraries-gfx1151==$VERSION"

if [ $? -ne 0 ]; then
    echo "  ❌ ERROR: Failed to install SDK components with matching version"
    exit 1
fi

echo "  ✅ SDK component versions synchronized"

echo "[02c] Initializing ROCm SDK..."
rocm-sdk init
echo "  ✓ ROCm SDK initialized"

echo "[02c-2] Creating /opt/rocm symlink..."
${SUDO} ln -sf "${VENV_DIR}/lib/python${PYTHON_VERSION}/site-packages/_rocm_sdk_devel" "${ROCM_HOME}"
echo "  ✓ Created symlink: ${ROCM_HOME} → _rocm_sdk_devel"

echo "[02d] Installing amd_smi package from SDK..."
cd "${VENV_DIR}/lib/python${PYTHON_VERSION}/site-packages/_rocm_sdk_core/share/amd_smi" && pip install .

echo "[02e] Adding ROCm SDK to system PATH and creating symlinks..."
echo "[02e-1] Making ROCm SDK .so files runtime loadable..."
echo "${ROCM_HOME}/lib" | ${SUDO} tee /etc/ld.so.conf.d/rocm-sdk.conf > /dev/null
${SUDO} ldconfig
echo "  ✓ ROCm SDK library path configured: ${ROCM_HOME}/lib"

echo "[02e-2] Adding ROCm SDK to system PATH..."
cat <<EOF | ${SUDO} tee /etc/profile.d/rocm-sdk.sh > /dev/null
export PATH="\${PATH}:${ROCM_HOME}/bin"
export LD_LIBRARY_PATH="${ROCM_HOME}/lib:\${LD_LIBRARY_PATH:-}"
EOF
echo "  ✓ ROCm SDK bin directory added to PATH: ${ROCM_HOME}/bin"
echo "  ✓ ROCm SDK library path added to LD_LIBRARY_PATH"

echo "[02g-1] Adding virtual environment to system PATH..."
cat <<EOF | ${SUDO} tee /etc/profile.d/opt-venv.sh > /dev/null
export PATH="${VENV_DIR}/bin:\${PATH}"
EOF
echo "  ✓ Virtual environment bin directory added to PATH: ${VENV_DIR}/bin"

echo "[02g] Setting up current shell environment..."
export PATH="${ROCM_HOME}/bin:${VENV_DIR}/bin:${PATH}"
export LD_LIBRARY_PATH="${ROCM_HOME}/lib:${LD_LIBRARY_PATH:-}"
echo "  ✓ Current shell PATH updated to include ${ROCM_HOME}/bin and ${VENV_DIR}/bin"
echo "  ✓ Current shell LD_LIBRARY_PATH updated to ${ROCM_HOME}/lib"

if [ "${SKIP_GPU_CHECK}" = "true" ]; then
    echo "  SKIPPED: amdsmi tests (--no-verification or --nogpu flag set)"
else
    echo "[02h] Running amdsmi tests..."
    python3 -c "import amdsmi; amdsmi.amdsmi_init(); print('  ✓ amdsmi initialization successful')" || echo "  WARNING: amdsmi test had issues, but continuing..."
fi

echo "[02i] Checking version consistency..."
echo "  ROCm version: $(pip show rocm | grep Version | cut -d' ' -f2)"
echo "  PyTorch ROCm build: $(pip show torch | grep Version | cut -d' ' -f2)"
echo ""
echo "  ⚠️  IMPORTANT: When installing any packages that depend on PyTorch,"
echo "     always use: pip install --index-url ${ROCM_INDEX_URL}"
echo "     Otherwise, pip will pull CUDA versions from PyPI."

# Extract ROCm version from torch package
TORCH_ROCM_VER=$(pip show torch | grep Version | grep -oP 'rocm\K[0-9.]+' | head -1)
ROCM_VER=$(pip show rocm | grep Version | grep -oP '\d+\.\d+' | head -1)

if [ -n "$TORCH_ROCM_VER" ] && [ -n "$ROCM_VER" ]; then
    echo "  PyTorch built against ROCm: ${TORCH_ROCM_VER}"
    echo "  Installed ROCm: ${ROCM_VER}"
    if [[ "$TORCH_ROCM_VER" == "$ROCM_VER"* ]]; then
        echo "  ✓ Versions match!"
    else
        echo "  ⚠ Warning: Version mismatch detected. PyTorch may not work correctly."
        echo "    Consider reinstalling with: pip install --pre --force-reinstall ..."
    fi
fi

echo "[02j] Verifying ROCm installation..."
echo "  ROCm packages:"
pip freeze | grep -i rocm || echo "    (No rocm packages found in pip list)"

echo "  Testing ROCm SDK..."
rocm-sdk test || echo "  WARNING: rocm-sdk test had issues, but continuing..."

echo "  Checking GPU with rocminfo..."
if [ "${SKIP_GPU_CHECK}" = "true" ]; then
    echo "  SKIPPED: GPU verification (--no-verification or --nogpu flag set)"
else
    rocminfo | grep -E "(Name:|gfx)" | head -20 || echo "  WARNING: rocminfo not available"
fi

echo "[02k] Verifying PyTorch installation..."
echo "  Installed versions:"
echo "    $(pip freeze | grep -E '^(rocm|torch)')"

if [ "${SKIP_GPU_CHECK}" = "true" ]; then
    echo "  SKIPPED: PyTorch GPU verification (--no-verification or --nogpu flag set)"
else
    python3 << 'ENDPYTHON'
import torch
import sys

print("  PyTorch version: " + str(torch.__version__))
print("  CUDA available: " + str(torch.cuda.is_available()))

# Check for ROCm backend (may not be available in all PyTorch builds)
try:
    rocm_available = torch.backends.rocm.is_available()
    print("  ROCm backend available: " + str(rocm_available))
except AttributeError:
    print("  ROCm backend: Not exposed via torch.backends (this is normal for some builds)")
    rocm_available = torch.cuda.is_available()  # ROCm uses CUDA interface

if torch.cuda.is_available():
    print("  CUDA/ROCm version: " + torch.version.cuda)
    print("  Device count: " + str(torch.cuda.device_count()))
    for i in range(torch.cuda.device_count()):
        print("  Device " + str(i) + ": " + torch.cuda.get_device_name(i))
    print("  Current device: " + str(torch.cuda.current_device()))
else:
    print("  WARNING: No GPU detected!")
    sys.exit(1)

print("\n  PyTorch GPU test: Creating a tensor on GPU...")
x = torch.randn(3, 3).cuda()
print("  Tensor device: " + str(x.device))
print("  Tensor shape: " + str(x.shape))
print("  Tensor sum: " + str(x.sum().item()))
print("  SUCCESS: PyTorch can use to GPU!")
ENDPYTHON
fi

echo ""
echo "[02l] Initializing ROCm SDK devel contents..."
echo "  This extracts development tools like hipconfig, hipcc, etc."
rocm-sdk init
echo "  ✓ ROCm SDK initialized"

echo ""
echo "[02] Installation complete!"
echo "  Virtual environment: ${VENV_DIR}"
echo "  To activate: source ${VENV_DIR}/bin/activate"
