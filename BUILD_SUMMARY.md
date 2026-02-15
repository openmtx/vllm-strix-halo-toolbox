# Build Scripts Summary

## Overview
These scripts build AITER, Flash Attention, and vLLM wheels for ROCm gfx1151 (Strix Halo) GPU.

## Key Configuration

### Environment Variables
- `WORK_DIR` - Workspace directory (default: `/workspace`)
- `VENV_DIR` - Python virtual environment directory (default: `/opt/venv`)
- `ROCM_INDEX_URL` - ROCm PyPI index URL (default: `https://rocm.nightlies.amd.com/v2/gfx1151/`)
- `GPU_TARGET` - Target GPU architecture (default: `gfx1151`)
- `SKIP_VERIFICATION` - Skip GPU verification (default: `false`, set to `true` for CPU-only builds)
- `NOGPU` - Skip all GPU checks (default: `false`, set to `true` for CPU-only builds)

### CPU-Only Building

**Important:** Wheels can be built WITHOUT a GPU using `NOGPU=true` flag:

```bash
# Docker builder (CPU-only, builds all components)
docker build -f Dockerfile.builder -t vllm-gfx1151-wheels .

# Manual CPU-only build
export NOGPU=true
./02-install-rocm.sh
./03-build-aiter.sh
./04-build-fa.sh
./05-build-vllm.sh
```

When `NOGPU=true`:
- ✅ Skips rocminfo GPU detection
- ✅ Skips PyTorch GPU verification
- ✅ Builds wheels successfully without GPU access
- ✅ Wheels work when installed on system with gfx1151 GPU

### Component-Based Docker Builder (Recommended)

Use `Dockerfile.builder.components` and `build-components.sh` for better isolation:

```bash
# Build specific component
./build-components.sh aiter       # Build only AITER
./build-components.sh flash-attn  # Build only Flash Attention
./build-components.sh vllm        # Build only vLLM
./build-components.sh all          # Build all three
```

**Advantages of Component-Based Builder:**
- Components build independently, no interference
- Failed builds don't stop other components
- Easy to debug individual component issues
- Shared base layer with ROCm/PyTorch
- Build only what you need

**Extract Wheels:**
```bash
# Extract all wheels
docker run --rm -v $(pwd)/wheels:/output vllm-gfx1151-components \
    bash -c "cp -r /output/aiter/* /output/flash-attn/* /output/vllm/* /output/"

# Extract specific component
docker run --rm -v $(pwd)/wheels:/output vllm-gfx1151-aiter \
    bash -c "cp /output/aiter/* /output/"
```

### Scripts Execution Order
1. `00-provision-toolbox.sh` - Create Distrobox toolbox
2. `01-install-tools.sh` - Install build tools
3. `02-install-rocm.sh` - Install ROCm SDK and PyTorch
4. `03-build-aiter.sh` - Build AITER wheel
5. `04-build-fa.sh` - Build Flash Attention wheel
6. `05-build-vllm.sh` - Build vLLM wheel
7. `10-verify-all.sh` - Fix Triton, install wheels, test imports, show GPU info

## Critical Fixes Applied

### 1. AITER JIT Compilation (03-build-aiter.sh)
**Problem:** Standard `pip wheel` build doesn't include C++/HIP source files needed for runtime JIT compilation.

**Solution:** Two-stage build process
- `python setup.py develop --no-deps` - Build in development mode with all sources
- `python setup.py bdist_wheel` - Create wheel with complete distribution

**Environment Variables:**
- `GPU_ARCHS="gfx1151"` - Primary variable AITER's JIT system uses
- `AITER_REBUILD=1` - Force JIT modules to be rebuilt

### 2. CUDA vs ROCm PyTorch Issue
**Problem:** When installing packages that depend on torch, pip pulls CUDA versions from PyPI instead of ROCm versions from nightly repo.

**Solution:** Always use `--no-deps` flag when installing built wheels to avoid pulling CUDA torch as dependency.

**Scripts Fixed:**
- `04-build-fa.sh` - Added `--no-deps` when installing flash-attn wheel
- `05-build-vllm.sh` - Added `--no-deps` when installing vllm wheel
- `07-fix-triton.sh` - Already had `--no-deps` for both triton and flash-attn

**Important:** When manually installing packages, always use:
```bash
pip install --index-url https://rocm.nightlies.amd.com/v2/gfx1151/ <package>
```

### 3. VENV_DIR Consistency
**Problem:** Inconsistent VENV_DIR defaults across scripts (`/opt/venv` vs `${WORK_DIR}/venv`).

**Solution:** Standardized to `/opt/venv` across all scripts.

## Built Wheels

### AITER
- **File:** `amd_aiter-0.1.10.post4.dev14+g54974b315-cp312-cp312-linux_x86_64.whl`
- **Size:** 29 MB
- **Features:** Includes JIT source files for runtime compilation
- **GPU Support:** gfx1151 officially supported

### Flash Attention
- **File:** `flash_attn-2.8.3-py3-none-any.whl`
- **Size:** 443 KB
- **Features:** Triton AMD implementation
- **Environment:** Requires `FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE`

### vLLM
- **File:** `vllm-0.1.dev1+g73391a1ba.d20260214.rocm711-cp312-cp312-linux_x86_64.whl`
- **Size:** 52 MB
- **Features:** Built for gfx1151

## Verification

Run complete verification:
```bash
distrobox enter restart
bash /home/kzhao/Projects/restart/10-verify-all.sh
```

This script does everything in one run:
- ✅ Fixes Triton (installs ROCm version)
- ✅ Installs all three wheels (with --no-deps)
- ✅ Shows GPU information
- ✅ Tests PyTorch GPU access
- ✅ Tests all three imports
- ✅ Shows installed versions
- ✅ Lists built wheels

Expected output:
- GPU: gfx1151 (Radeon 8060S Graphics)
- PyTorch: ROCm version with GPU support
- AITER: Imported successfully
- Flash Attention: Imported with Triton AMD backend
- vLLM: Imported successfully

## Environment Details

- **GPU:** gfx1151 (Radeon 8060S Graphics / Strix Halo)
- **Python:** 3.12
- **ROCm:** 7.11.0a20260106
- **Triton:** 3.6.0 (ROCm version)
- **PyTorch:** 2.11.0a0+rocm7.11.0a20260106

## Troubleshooting

### If Flash Attention Fails to Import
```
RuntimeError: 0 active drivers ([]). There should only be one.
```
This means Triton ROCm driver cannot initialize. This happens when:
1. No GPU available (CPU-only environment)
2. Wrong PyTorch version (CUDA instead of ROCm)

**Fix:** Ensure ROCm PyTorch is installed:
```bash
pip install --index-url https://rocm.nightlies.amd.com/v2/gfx1151/ --pre torch torchvision torchaudio
```

### If AITER JIT Module Fails
```
ModuleNotFoundError: No module named 'aiter.jit.module_aiter_enum'
```
**Fix:** Rebuild with correct environment:
```bash
export GPU_ARCHS="gfx1151"
export AITER_REBUILD=1
cd /workspace/aiter
python setup.py develop --no-deps
python setup.py bdist_wheel
```

## Files Modified

- `02-install-rocm.sh` - Added ROCm index warning, fixed VENV_DIR
- `03-build-aiter.sh` - Two-stage build process, GPU_ARCHS and AITER_REBUILD
- `04-build-fa.sh` - Added --no-deps to install command, ROCM_INDEX_URL variable
- `05-build-vllm.sh` - Added --no-deps to install command, ROCM_INDEX_URL variable
- `07-fix-triton.sh` - Already correct (uses --no-deps)
- `08-final-status.sh` - Verification script
- `09-final-verification.sh` - Complete verification with GPU info
