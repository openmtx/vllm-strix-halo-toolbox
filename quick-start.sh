#!/bin/bash
# Quick Start Guide
# ==================
#
# This script runs all build scripts in order to build AITER, Flash Attention, and vLLM wheels
# for ROCm gfx1151 (Strix Halo) GPU.
#
# Prerequisites:
#   - Distrobox installed (for local builds)
#   - Docker installed (for CPU-only builds)
#   - Internet connection for downloading packages and repositories
#
# Options:
#   --nogpu, -n  - Build without GPU verification (CPU-only)

set -euo pipefail

NOGPU=false
for arg in "$@"; do
    case $arg in
        --nogpu|-n)
            NOGPU=true
            shift
            ;;
    esac
done

if [ "$NOGPU" = "true" ]; then
    echo "=========================================="
    echo "Building ROCm gfx1151 Wheels (CPU-Only)"
    echo "=========================================="
else
    echo "=========================================="
    echo "Building ROCm gfx1151 Wheels"
    echo "=========================================="
fi
echo ""

echo "=========================================="
echo "Building ROCm gfx1151 Wheels"
echo "=========================================="
echo ""

# Create toolbox
echo "[1/7] Creating Distrobox toolbox..."
./00-provision-toolbox.sh
echo ""

# Install tools
echo "[2/7] Installing build tools..."
distrobox enter restart -- bash /home/kzhao/Projects/restart/01-install-tools.sh
echo ""

# Install ROCm and PyTorch
echo "[3/7] Installing ROCm SDK and PyTorch..."
distrobox enter restart -- bash /home/kzhao/Projects/restart/02-install-rocm.sh
echo ""

# Build AITER
echo "[4/7] Building AITER wheel..."
distrobox enter restart -- bash /home/kzhao/Projects/restart/03-build-aiter.sh
echo ""

# Build Flash Attention
echo "[5/7] Building Flash Attention wheel..."
distrobox enter restart -- bash /home/kzhao/Projects/restart/04-build-fa.sh
echo ""

# Build vLLM
echo "[6/7] Building vLLM wheel..."
distrobox enter restart -- bash /home/kzhao/Projects/restart/05-build-vllm.sh
echo ""

# Final verification
echo "[7/7] Running complete verification..."
distrobox enter restart -- bash /home/kzhao/Projects/restart/10-verify-all.sh
echo ""

echo "=========================================="
echo "Build Complete!"
echo "=========================================="
echo ""
echo "Wheels are available in: /workspace/wheels/"
echo ""
echo "To verify installation:"
echo "  distrobox enter restart"
echo "  bash /home/kzhao/Projects/restart/10-verify-all.sh"
echo ""
if [ "$NOGPU" = "true" ]; then
    echo "Note: Built with --nogpu flag (CPU-only)"
    echo "Wheels will work when installed on system with gfx1151 GPU"
fi
echo ""

# Create toolbox
echo "[1/9] Creating Distrobox toolbox..."
./00-provision-toolbox.sh
echo ""

# Install tools
echo "[2/9] Installing build tools..."
distrobox enter restart -- bash /home/kzhao/Projects/restart/01-install-tools.sh
echo ""

# Install ROCm and PyTorch
echo "[3/9] Installing ROCm SDK and PyTorch..."
distrobox enter restart -- bash /home/kzhao/Projects/restart/02-install-rocm.sh
echo ""

# Build AITER
echo "[4/9] Building AITER wheel..."
distrobox enter restart -- bash /home/kzhao/Projects/restart/03-build-aiter.sh
echo ""

# Build Flash Attention
echo "[5/9] Building Flash Attention wheel..."
distrobox enter restart -- bash /home/kzhao/Projects/restart/04-build-fa.sh
echo ""

# Build vLLM
echo "[6/9] Building vLLM wheel..."
distrobox enter restart -- bash /home/kzhao/Projects/restart/05-build-vllm.sh
echo ""

# Final verification
echo "[7/7] Running complete verification..."
distrobox enter restart -- bash /home/kzhao/Projects/restart/10-verify-all.sh
echo ""

echo "=========================================="
echo "Build Complete!"
echo "=========================================="
echo ""
echo "Wheels are available in: /workspace/wheels/"
echo ""
echo "To verify installation:"
echo "  distrobox enter restart"
echo "  bash /home/kzhao/Projects/restart/09-final-verification.sh"
echo ""
