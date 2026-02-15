#!/bin/bash
set -euo pipefail

# 10-verify-all.sh
# Complete verification: Fix Triton, install wheels, test imports, show GPU info

VENV_DIR="${VENV_DIR:-/opt/venv}"
ROCM_INDEX_URL="${ROCM_INDEX_URL:-https://rocm.nightlies.amd.com/v2/gfx1151/}"
NOGPU="${NOGPU:-false}"

echo "=========================================="
echo "Complete Verification"
echo "=========================================="
echo ""

source "${VENV_DIR}/bin/activate"

# Step 1: Fix Triton (install ROCm version)
echo "Step 1: Fixing Triton (ROCm version)..."
pip uninstall -y triton 2>/dev/null || true
pip install --index-url "${ROCM_INDEX_URL}" --force-reinstall --no-deps triton==3.6.0
echo ""

# Step 2: Install all wheels
echo "Step 2: Installing wheels (with --no-deps to avoid CUDA torch)..."
pip install --no-deps /workspace/wheels/amd_aiter-*.whl 2>/dev/null || echo "  AITER already installed"
pip install --no-deps /workspace/wheels/flash_attn-*.whl 2>/dev/null || echo "  Flash Attention already installed"
pip install --no-deps /workspace/wheels/vllm-*.whl 2>/dev/null || echo "  vLLM already installed"
echo ""

# Step 3: Show GPU info
echo "Step 3: GPU Information..."
if [ "${NOGPU}" = "true" ]; then
    echo "  SKIPPED: GPU info check (--nogpu flag set, CPU-only build)"
else
    if command -v rocminfo &> /dev/null; then
        rocminfo 2>&1 | grep -A 8 "Agent 2" | grep -E "Name:|Marketing Name:|Device Type:" | sed 's/^/  /'
    else
        echo "  ⚠️  rocminfo not available (GPU may not be accessible)"
    fi
fi
echo ""

# Step 4: PyTorch GPU check
echo "Step 4: PyTorch GPU Check..."
python3 << 'EOF'
import os
skip_gpu = os.environ.get('NOGPU', 'false') == 'true'

import torch
print(f"  Version: {torch.__version__}")
print(f"  GPU available: {torch.cuda.is_available()}")
if skip_gpu:
    print("  GPU check SKIPPED (--nogpu flag set)")
elif torch.cuda.is_available():
    print(f"  Device: {torch.cuda.get_device_name(0)}")
    print(f"  Device count: {torch.cuda.device_count()}")
else:
    print("  ⚠️  No GPU detected")
EOF
echo ""

# Step 5: Test imports
echo "Step 5: Testing Imports..."
echo ""

echo "Testing AITER..."
python3 << 'EOF'
import os
os.environ['GPU_ARCHS'] = 'gfx1151'
try:
    import aiter
    print("  ✅ AITER imported successfully")
except Exception as e:
    print(f"  ❌ AITER failed: {type(e).__name__}")
EOF

echo "Testing Flash Attention..."
python3 << 'EOF'
import os
os.environ['FLASH_ATTENTION_TRITON_AMD_ENABLE'] = 'TRUE'
try:
    import flash_attn
    print("  ✅ Flash Attention imported successfully")
except Exception as e:
    print(f"  ❌ Flash Attention failed: {type(e).__name__}")
EOF

echo "Testing vLLM..."
python3 << 'EOF'
try:
    import vllm
    print("  ✅ vLLM imported successfully")
except Exception as e:
    print(f"  ❌ vLLM failed: {type(e).__name__}")
EOF
echo ""

# Step 6: Show installed versions
echo "Step 6: Installed Versions..."
echo ""
for pkg in amd-aiter flash-attn vllm triton torch; do
    version=$(pip show "$pkg" 2>/dev/null | grep Version | cut -d' ' -f2)
    if [ -n "$version" ]; then
        printf "  %-20s %s\n" "$pkg:" "$version"
    fi
done
echo ""

# Step 7: Show built wheels
echo "Step 7: Built Wheels (in /workspace/wheels/)..."
ls -lh /workspace/wheels/*.whl 2>/dev/null | awk '{printf "  %-50s %10s\n", $9, $5}' || echo "  No wheels found"
echo ""

# Summary
echo "=========================================="
echo "Verification Complete!"
echo "=========================================="
