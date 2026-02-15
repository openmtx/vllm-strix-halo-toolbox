# vLLM for AMD Strix Halo (gfx1151) with Nightly ROCm

Complete toolkit for building and running vLLM with AMD nightly ROCm/PyTorch for Strix Halo GPUs (gfx1151).

## Overview

This repository provides a step-by-step workflow to build vLLM from source using AMD's nightly ROCm and PyTorch packages specifically for the gfx1151 architecture (AMD Strix Halo / Ryzen AI MAX+ PRO 395).

**Key Features:**
- Uses AMD nightly ROCm/PyTorch packages (gfx1151 support)
- Step-by-step modular build scripts
- TCMalloc to prevent memory corruption
- AITER support documented (optional, produces wheel but vLLM won't use on gfx1151)

## Requirements

- **OS:** Ubuntu 24.04 (via Distrobox)
- **GPU:** AMD Strix Halo (gfx1151) - Ryzen AI MAX+ PRO 395 with Radeon 8060S
- **RAM:** 16GB+ recommended
- **Disk:** 30GB+ for ROCm, PyTorch, and vLLM
- **Tools:** Distrobox, Docker, Docker.builder (CPU-only wheel builder)

## Quick Start

### Step 1: Create Toolbox Container

```bash
./00-provision-toolbox.sh -f
distrobox enter ${TOOLBOX_NAME:-restart}
```

### Step 2: Install System Tools

```bash
./01-install-tools.sh
```

This installs:
- Build essentials (cmake, ninja, gcc)
- Python 3.12 with venv
- TCMalloc (to prevent memory corruption)

### Step 3: Install ROCm and PyTorch

```bash
./02-install-rocm.sh
```

This installs:
- AMD nightly ROCm 7.11.0+ packages
- PyTorch 2.11.0a0+ with ROCm support
- Configures system-wide TCMalloc in `/etc/ld.so.preload`

### Step 4: Build AITER, Flash Attention, and vLLM

```bash
# Optional: Build AITER (produces wheel, but vLLM won't use on gfx1151)
./03-build-aiter.sh

# Build Flash Attention (recommended for performance)
./04-build-fa.sh

# Build vLLM
./05-build-vllm.sh
```

**Note:** AITER builds successfully and produces a wheel, but vLLM won't use it on gfx1151 since it only supports gfx9 architectures (MI300X, MI350). AITER warning at runtime is expected and harmless. Flash Attention provides optimized attention mechanisms for improved performance.

### Step 5: Complete Verification

```bash
distrobox enter restart
bash 10-verify-all.sh
```

This single script does everything:
- Fixes Triton (installs ROCm version)
- Installs all three wheels
- Tests all imports
- Shows GPU information
- Displays installed versions

### Step 6: Test vLLM

```bash
source /opt/venv/bin/activate
python -c "import vllm; print(f'vLLM {vllm.__version__}')"
vllm --version"
```

## Alternative: Docker Builder (Component-Based, CPU-Only)

For CI/CD or building wheels on a different machine, use the new component-based Docker builder:

### Build Specific Component

```bash
# Build AITER only
./build-components.sh aiter

# Build Flash Attention only
./build-components.sh flash-attn

# Build vLLM only
./build-components.sh vllm

# Build all three
./build-components.sh all
```

### Dockerfile.builder.components

The new `Dockerfile.builder.components` uses a multi-stage build approach:

- **Stage 1 (base):** Installs ROCm SDK and PyTorch (shared by all components)
- **Stage 2-4 (builders):** Each component built independently
- **Stage 5 (output):** Collects all wheels into one image

**Advantages:**
- Components don't interfere with each other
- Failed builds don't stop other components
- Easy to debug individual component issues
- Can build only what you need
- Shared base layer reduces build time when building multiple components

### Extract Wheels

```bash
# Extract all wheels
docker run --rm -v $(pwd)/wheels:/output vllm-gfx1151-components \
    bash -c "cp -r /output/aiter/* /output/flash-attn/* /output/vllm/* /output/"

# Extract specific component
docker run --rm -v $(pwd)/wheels:/output vllm-gfx1151-aiter \
    bash -c "cp /output/aiter/* /output/"
```

### Built Wheels (in ./wheels/)
- `amd_aiter-*.whl` (29 MB)
- `flash_attn-*.whl` (443 KB)
- `vllm-*.whl` (52 MB)

### Install in ROCm environment

```bash
pip install --index-url https://rocm.nightlies.amd.com/v2/gfx1151/ ./wheels/*.whl
```

## Alternative: Docker Builder (Legacy, CPU-Only)

```bash
# Build wheels (CPU-only, NOGPU=true)
docker build -f Dockerfile.builder -t vllm-gfx1151-wheels .

# Extract wheels from builder (copies to ./wheels/)
docker run --rm -v $(pwd)/wheels:/output vllm-gfx1151-wheels \
    bash -c "cp /wheels/*.whl /output/"

# You now have:
# - ./wheels/vllm-*.whl (52MB)
# - ./wheels/flash_attn-*.whl (varies)
# - ./wheels/amd_aiter-*.whl (29MB)
```

**What this does:**
- Creates Ubuntu 24.04 container
- Runs scripts 01-05 sequentially
- Produces vLLM, Flash Attention, and AITER wheels
- Uses `NOGPU=true` to skip all GPU verification
- No GPU access required (pure CPU build)

**Advantages:**
- No GPU required (builder is CPU-only)
- Reproducible builds
- Easy CI/CD integration
- Works on any machine with Docker

### Dockerfile.runtime (Minimal Runtime from Pre-built Wheels)

Alternative runtime Dockerfile that uses pre-built wheels instead of building from source:

```bash
# Build runtime image from pre-built wheels in ./wheels/
docker build -f Dockerfile.runtime -t vllm-rocm:runtime .

# Run vLLM server
docker run --gpus all -p 8080:8080 vllm-rocm:runtime \
    vllm serve Qwen/Qwen2.5-0.5B-Instruct \
    --host 0.0.0.0 \
    --port 8080
```

**Requirements:**
- Pre-built wheels in `./wheels/` directory (from `Dockerfile.builder.components` or distrobox build)
- Must include: `vllm-*.whl`, `flash_attn-*.whl`, `amd_aiter-*.whl`

**What this does:**
- Minimal Ubuntu 24.04 base image
- Installs ROCm SDK and PyTorch from nightly packages
- Copies and installs pre-built wheels
- Configures ROCm runtime library loading
- Sets environment variables for gfx1151 and Flash Attention AMD backend
- Includes gcc/make for Triton JIT compilation

**Runtime Environment Variables:**
- `HSA_OVERRIDE_GFX_VERSION="11.5.1"` - GPU version override for Strix Halo
- `VLLM_TARGET_DEVICE="rocm"` - Target device for vLLM
- `FLASH_ATTENTION_TRITON_AMD_ENABLE="TRUE"` - Enable AMD Triton backend for Flash Attention

**Advantages:**
- Faster builds (no compilation, just wheel installation)
- Smaller image (no build tools except gcc/make for Triton)
- Separates build and runtime concerns
- Can build wheels on one machine, deploy on another

### Main Dockerfile (Multi-stage Build & Runtime)

The main `Dockerfile` provides both builder and runtime stages in a single build:

```bash
# Build runtime image with vLLM and AITER pre-installed
docker build -t vllm-gfx1151-runtime .

# Run vLLM server
docker run --gpus all -p 8080:8080 vllm-gfx1151-runtime \
    vllm serve Qwen/Qwen2.5-0.5B-Instruct \
    --host 0.0.0.0 \
    --port 8080 \
    --enforce-eager
```

 **What this does:**
 - **Stage 1 (Builder):** Same as Dockerfile.builder - builds both wheels
 - **Stage 2 (Runtime):** Minimal Ubuntu 24.04 with:
   - Python 3.12 venv at `/opt/venv`
   - vLLM and AITER wheels installed
   - TCMalloc preloading configured
   - PATH set to `/opt/venv/bin`
   - ROCm environment variables set for gfx1151
   - Flash Attention AMD Triton backend enabled
   - gcc/make for Triton JIT compilation

 **Runtime Environment Variables:**
 - `HSA_OVERRIDE_GFX_VERSION="11.5.1"` - GPU version override for Strix Halo
 - `VLLM_TARGET_DEVICE="rocm"` - Target device for vLLM
 - `FLASH_ATTENTION_TRITON_AMD_ENABLE="TRUE"` - Enable AMD Triton backend for Flash Attention

 **Advantages:**
 - Single build command produces runnable image
 - Runtime image includes necessary build tools for Triton JIT
 - Ready-to-run with GPU access required
 - Properly configured for AMD ROCm and Flash Attention

## Scripts

### 00-provision-toolbox.sh

Creates a distrobox container for vLLM development.

**Usage:**
```bash
./00-provision-toolbox.sh [-f|--force]
```

**Options:**
- `-f, --force` - Destroy existing toolbox and recreate

**Base Image:** Ubuntu 24.04 (plain, for clean nightly installation)

### 01-install-tools.sh

Installs system-level build tools and TCMalloc.

**Installs:**
- build-essential, cmake, ninja-build
- python3.12, python3.12-venv
- google-perftools, libgoogle-perftools-dev
- Configures `/etc/ld.so.preload` for TCMalloc

### 02-install-rocm.sh

Creates Python virtual environment and installs AMD nightly ROCm/PyTorch.

**Installs:**
- ROCm 7.11.0a+ from nightly packages
- PyTorch 2.11.0a0+ with ROCm support
- amd_smi package from ROCm SDK for GPU monitoring and management
- Configures ROCm runtime library loading

**Runtime Library Loading:**
The script configures ROCm SDK .so files for runtime loading by:
- Adding ROCm library path to `/etc/ld.so.conf.d/rocm-sdk.conf`
- Running `ldconfig` to update the dynamic linker cache
- This ensures ROCm libraries can be found at runtime without manual LD_LIBRARY_PATH configuration

**Environment:**
- Virtual env: `/opt/venv`
- ROCm SDK: Automatically extracted from pip packages
- GPU: gfx1151 (Strix Halo)

### 03-build-aiter.sh

Builds AMD AITER (AI Tensor Engine for ROCm) from source.

**AITER Support Status:**
- Supported: gfx942 (MI300X), gfx950, gfx1250, gfx12
- **Not Supported by AITER: gfx1150, gfx1151 (Strix Halo)**

**Note:** AITER builds successfully on gfx1151 but vLLM won't use it since it only supports gfx9 architectures. Runtime warning is expected and harmless.

**Installs:**
- AITER wheel: `/workspace/wheels/amd_aiter-*.whl`
- AITER to virtual environment

**Usage:**
```bash
./03-build-aiter.sh
```

### 04-build-fa.sh

Builds Flash Attention wheel from source with ROCm support.

**Features:**
- Clones Flash Attention repository (main_perf branch)
- Uses existing PyTorch/ROCm installation
- Builds optimized attention kernels for gfx1151
- Creates installable wheel

**Output:**
- Wheel: `/workspace/wheels/flash_attn-*.whl`
- Installation: `/opt/venv`

**Usage:**
```bash
./04-build-fa.sh
```

### 05-build-vllm.sh

Builds vLLM from source with ROCm support.

**Features:**
- Clones vLLM repository (main branch)
- Uses existing PyTorch/ROCm installation
- Builds C++ extensions for gfx1151
- Creates installable wheel

**Output:**
- Wheel: `/workspace/wheels/vllm-*.whl`
- Installation: `/opt/venv`

Note: AITER and Flash Attention also produce wheels at `/workspace/wheels/`

## Configuration

### .toolbox.env

Environment configuration file:

```bash
# Base image for toolbox
BASE_IMAGE=docker.io/library/ubuntu:24.04

# ROCm nightly repository
ROCM_INDEX_URL=https://rocm.nightlies.amd.com/v2/gfx1151/

# Workspace settings
WORK_DIR=${HOME}/workspace
VENV_DIR=/opt/venv

# Python version
PYTHON_VERSION=3.12

# GPU architecture
PYTORCH_ROCM_ARCH=gfx1151
```

## Usage Examples

### Start vLLM Server

```bash
distrobox enter ${TOOLBOX_NAME:-restart}
source /opt/venv/bin/activate

# Serve a model
vllm serve Qwen/Qwen2.5-0.5B-Instruct \
    --host 0.0.0.0 \
    --port 8080 \
    --tensor-parallel-size 1
```

### Test API

```bash
./test.sh
```

Or manually:
```bash
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen2.5-0.5B-Instruct",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

### Download Models

```bash
./download-model.sh Qwen/Qwen2.5-0.5B-Instruct
```

Models are cached in `./cache/huggingface/`

## Key Technical Details

### Why TCMalloc?

The pip-installed ROCm SDK can cause "double free or corruption" memory errors. TCMalloc (Google's memory allocator) prevents this by replacing the standard malloc.

**Configured in:** `/etc/ld.so.preload`

### Device Libraries

ROCm device bitcode libraries are located at:
```
/opt/venv/lib/python3.12/site-packages/_rocm_sdk_devel/lib/llvm/amdgcn/bitcode/
```

These are required for compiling HIP kernels and are automatically configured.

### amd_smi Package

The `amd_smi` (AMD System Management Interface) package is installed from the ROCm SDK to provide GPU monitoring and management capabilities. This includes:
- GPU temperature and power monitoring
- Memory usage statistics
- Device information queries
- Performance metrics

The package is automatically installed from the ROCm SDK shared package location during the setup process.

### Flash Attention AMD Triton Backend

Flash Attention for ROCm uses a Triton-based backend instead of CUDA kernels. This requires:

1. **Environment Variable:** `FLASH_ATTENTION_TRITON_AMD_ENABLE="TRUE"`
   - Tells Flash Attention to import AMD Triton backend (`flash_attn_triton_amd`)
   - Without this, it tries to import CUDA backend (`flash_attn_2_cuda`) which fails on ROCm

2. **C Compiler and Headers:** gcc, make, libc6-dev, and python3-dev
   - Triton AMD backend JIT compiles HIP utilities at runtime
   - These utilities require a C compiler and standard C library headers
   - Error: `RuntimeError: Failed to find C compiler` if gcc/make missing
   - Error: `fatal error: stdint.h: No such file or directory` if libc6-dev missing
   - Error: `fatal error: Python.h: No such file or directory` if python3-dev missing

3. **ROCm Support:** The ROCm Flash Attention repository provides optimized attention kernels for AMD GPUs using Triton.

### ROCm Runtime Library Loading

ROCm SDK libraries (`.so` files) need to be available to the dynamic linker at runtime. The setup script automatically configures this by:
1. Adding the ROCm library directory to `/etc/ld.so.conf.d/rocm-sdk.conf`
2. Running `ldconfig` to update the linker cache

This eliminates the need to manually set `LD_LIBRARY_PATH` and ensures ROCm libraries are discoverable system-wide.

### ROCm Symlink

For compatibility with tools expecting ROCm at `/opt/rocm`:
```bash
/opt/rocm -> /workspace/venv/lib/python3.12/site-packages/_rocm_sdk_devel
```

## Recent Fixes (2026-02-15)

### Critical: Flash Attention AMD Triton Backend Support

**Problem:** Flash Attention AMD version requires specific environment variables and build tools to work correctly with ROCm.

**Solution:** Four issues were fixed in `Dockerfile.runtime`:

1. **Added `FLASH_ATTENTION_TRITON_AMD_ENABLE="TRUE"`** environment variable
   - This tells Flash Attention to use the AMD Triton backend instead of CUDA
   - Without this, Flash Attention tries to import `flash_attn_2_cuda` which doesn't exist on ROCm builds

2. **Added `gcc` and `make`** to runtime dependencies
   - Triton AMD backend JIT compiles HIP utilities at runtime
   - These C utilities require a C compiler to build
   - Without these, the error "Failed to find C compiler" occurs

3. **Added `libc6-dev`** to runtime dependencies
   - Provides standard C library headers like `stdint.h`
   - Required for Triton AMD backend to compile HIP utilities
   - Without this, the error "fatal error: stdint.h: No such file or directory" occurs

4. **Added `python3-dev`** to runtime dependencies
   - Provides Python development headers like `Python.h`
   - Required for Triton AMD backend to compile HIP utilities that embed Python
   - Without this, the error "fatal error: Python.h: No such file or directory" occurs

**Error messages fixed:**
- `ModuleNotFoundError: No module named 'flash_attn_2_cuda'`
- `RuntimeError: Failed to find C compiler. Please specify via CC environment variable`
- `fatal error: stdint.h: No such file or directory`
- `fatal error: Python.h: No such file or directory`

**Updated Environment Variables in Dockerfile.runtime:**
```dockerfile
ENV HSA_OVERRIDE_GFX_VERSION="11.5.1" \
    VLLM_TARGET_DEVICE="rocm" \
    FLASH_ATTENTION_TRITON_AMD_ENABLE="TRUE"
```

## Recent Fixes (2026-02-14)

### Critical: CUDA vs ROCm PyTorch Issue Fixed

**Problem:** When installing packages that depend on torch, pip would pull CUDA versions from PyPI instead of ROCm versions from AMD nightly repo.

**Solution:** All build scripts now use `--no-deps` when installing wheels to prevent pip from resolving torch as a dependency.

**Updated Scripts:**
- `04-build-fa.sh` - Added `--no-deps` when installing flash-attn wheel
- `05-build-vllm.sh` - Added `--no-deps` when installing vllm wheel

**Important:** When manually installing packages, always use:
```bash
pip install --index-url https://rocm.nightlies.amd.com/v2/gfx1151/ <package>
```

### AITER JIT Compilation Fixed

**Problem:** Standard `pip wheel` build doesn't include C++/HIP source files needed for runtime JIT compilation.

**Solution:** Two-stage build process in `03-build-aiter.sh`:
- `python setup.py develop --no-deps` - Build in development mode
- `python setup.py bdist_wheel` - Create complete wheel

**Environment Variables:**
- `GPU_ARCHS="gfx1151"` - Primary variable AITER's JIT system uses
- `AITER_REBUILD=1` - Force JIT modules to be rebuilt

### New Scripts

- `10-verify-all.sh` - Complete verification: fixes Triton, installs wheels, tests imports, shows GPU info
- `quick-start.sh` - Runs all build scripts in order
- `BUILD_SUMMARY.md` - Detailed build process documentation

## Troubleshooting

### GPU Not Detected

**Docker Builder:** This is expected - Docker builder uses `NOGPU=true` to build wheels without GPU access. This is correct and normal.

**Distrobox:** If GPU isn't detected:
```bash
# Check ROCm
rocminfo | grep gfx

# Check PyTorch
python -c "import torch; print(torch.cuda.is_available())"
```

**Skip verification:** To skip GPU checks (e.g., for CPU-only builds):
```bash
# Using NOGPU flag (recommended for CPU-only builds)
export NOGPU=true
./02-install-rocm.sh

# Or using SKIP_VERIFICATION flag
export SKIP_VERIFICATION=true
./02-install-rocm.sh
```

**Skip verification:** To skip GPU checks (e.g., for CPU-only builds):
```bash
# For individual script
SKIP_VERIFICATION=true ./02-install-rocm.sh
```

### Memory Corruption Errors

TCMalloc should prevent these. If they occur:
```bash
# Verify TCMalloc is loaded
cat /etc/ld.so.preload
# Should show: /usr/lib/x86_64-linux-gnu/libtcmalloc.so.4
```

### Build Failures

 1. Ensure ROCm SDK is initialized:
    ```bash
    rocm-sdk init
    ```

 2. Check device libraries exist:
    ```bash
    ls /opt/venv/lib/python3.12/site-packages/_rocm_sdk_devel/lib/llvm/amdgcn/bitcode/
    ```

 3. Reduce parallel jobs:
    ```bash
    export MAX_JOBS=4
    ```

### AITER Warning at Runtime

vLLM may show a warning about AITER at startup:
```
WARNING: AITER is not supported on this architecture (gfx1151)
```

This is **expected and harmless** - vLLM will automatically use standard ROCm/PyTorch kernels instead. AITER only supports gfx9 architectures (MI300X, MI350), not gfx1151 (Strix Halo).

### Flash Attention Import Errors

If you see errors like:
```
ModuleNotFoundError: No module named 'flash_attn_2_cuda'
RuntimeError: Failed to find C compiler
fatal error: stdint.h: No such file or directory
fatal error: Python.h: No such file or directory
```

These indicate:
1. Missing `FLASH_ATTENTION_TRITON_AMD_ENABLE="TRUE"` environment variable
2. Missing gcc/make for Triton JIT compilation
3. Missing libc6-dev for standard C library headers
4. Missing python3-dev for Python development headers

**Solution:** Ensure your `Dockerfile.runtime` or environment includes:
```bash
export FLASH_ATTENTION_TRITON_AMD_ENABLE="TRUE"
apt-get install gcc make libc6-dev python3-dev
```

## Directory Structure

```
.
├── 00-provision-toolbox.sh    # Create distrobox container
├── 01-install-tools.sh        # Install system build tools
├── 02-install-rocm.sh         # Install ROCm/PyTorch nightly
├── 03-build-aiter.sh          # AITER build (produces wheel)
├── 04-build-fa.sh             # Flash Attention build
├── 05-build-vllm.sh           # Build vLLM from source
├── 10-verify-all.sh          # Complete verification
├── build-components.sh         # Build individual components with Docker
├── download-model.sh          # Download Hugging Face models
├── test.sh                    # Test API endpoint
├── test_vllm.py               # Python test script
├── .toolbox.env               # Environment configuration
├── .dockerignore             # Docker build exclusions
 ├── docker-compose.yml         # Docker service (alternative)
 ├── Dockerfile                 # Docker build (alternative)
 ├── Dockerfile.runtime         # Docker runtime from pre-built wheels
 ├── Dockerfile.builder         # Docker wheel builder (legacy, CPU-only)
 ├── Dockerfile.builder.components  # Docker component builders (recommended)
├── cache/
│   └── huggingface/          # Model cache
├── wheels/                   # Built wheels (created by 03, 04 & 05 scripts)
├── BUILD_SUMMARY.md          # Detailed build process
└── README.md                  # This file
```
.
├── 00-provision-toolbox.sh    # Create distrobox container
├── 01-install-tools.sh        # Install system build tools
├── 02-install-rocm.sh         # Install ROCm/PyTorch nightly
├── 03-build-aiter.sh          # AITER build (produces wheel)
├── 04-build-fa.sh             # Flash Attention build
├── 05-build-vllm.sh           # Build vLLM from source
├── 10-verify-all.sh          # Complete verification
├── download-model.sh          # Download Hugging Face models
├── test.sh                    # Test API endpoint
├── test_vllm.py               # Python test script
├── quick-start.sh             # Run all build scripts in order
├── .toolbox.env               # Environment configuration
├── .dockerignore             # Docker build exclusions
├── docker-compose.yml         # Docker service (alternative)
├── Dockerfile                 # Docker build (alternative)
├── Dockerfile.builder         # Docker wheel builder (CPU-only, runs 01-05 scripts)
├── cache/
│   └── huggingface/          # Model cache
├── wheels/                   # Built wheels (created by 03, 04 & 05 scripts)
├── BUILD_SUMMARY.md          # Detailed build process
└── README.md                  # This file
```

## Build Status

| Component | Status | Notes |
|-----------|--------|-------|
| ROCm 7.11.0 | ✅ Working | Nightly packages for gfx1151 |
| PyTorch 2.11.0 | ✅ Working | ROCm backend functional |
| vLLM 0.16.0rc2 | ✅ Working | Built from source |
| TCMalloc | ✅ Configured | Prevents memory corruption |
| AITER | ✅ Builds | Produces wheel but vLLM won't use on gfx1151 (optional) |
| Flash Attention | ✅ Working | Optimized attention for improved performance |

## References

- [vLLM](https://github.com/vllm-project/vllm) - Open source LLM inference engine
- [ROCm](https://rocm.docs.amd.com/) - AMD's open-source GPU compute platform
- [ROCm TheRock](https://github.com/ROCm/TheRock) - AMD's nightly build system
- [PyTorch ROCm](https://pytorch.org/get-started/locally/) - PyTorch with AMD GPU support
- [Distrobox](https://distrobox.privatedns.org/) - Container tool for Linux distributions

## License

This project follows the same license as vLLM (Apache 2.0).
