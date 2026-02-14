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
distrobox enter vllm-toolbox
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

### Step 4: Build vLLM (AITER is Optional)

```bash
# Optional: Build AITER (produces wheel, but vLLM won't use on gfx1151)
./03-build-aiter.sh

# Build vLLM
./04-build-vllm.sh
```

**Note:** AITER builds successfully and produces a wheel, but vLLM won't use it on gfx1151 since it only supports gfx9 architectures (MI300X, MI350). AITER warning at runtime is expected and harmless.

### Step 5: Test vLLM

```bash
source /opt/venv/bin/activate
python -c "import vllm; print(f'vLLM {vllm.__version__}')"
vllm --version
```

## Alternative: Docker Builder

For CI/CD or building wheels on a different machine, use the Docker builder:

```bash
# Build the builder image and run all build scripts
docker build -f Dockerfile.builder -t vllm-gfx1151-builder .

# Extract wheels from builder (copies to ./wheels/)
docker run --rm -v $(pwd)/wheels:/output vllm-gfx1151-builder \
    bash -c "cp /workspace/wheels/*.whl /output/"

# You now have:
# - ./wheels/vllm-*.whl (52MB)
# - ./wheels/amd_aiter-*.whl (29MB)
```

**What this does:**
- Creates Ubuntu 24.04 container
- Runs scripts 01-04 sequentially
- Produces both vLLM and AITER wheels
- All scripts execute with correct paths (`/workspace`, `/opt/venv`)
- Skips GPU verification (CPU-only builder, no GPU needed for wheel building)

**Advantages:**
- No GPU required (builder is CPU-only)
- Reproducible builds
- Easy CI/CD integration

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
- Configures device library paths
- Creates `/opt/rocm` symlink

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

### 04-build-vllm.sh

Builds vLLM from source with ROCm support.

**Features:**
- Clones vLLM repository (main branch)
- Uses existing PyTorch/ROCm installation
- Builds C++ extensions for gfx1151
- Creates installable wheel

**Output:**
- Wheel: `/workspace/wheels/vllm-*.whl`
- Installation: `/opt/venv`

Note: AITER also produces a wheel at `/workspace/wheels/amd_aiter-*.whl`

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
distrobox enter vllm-toolbox
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

### ROCm Symlink

For compatibility with tools expecting ROCm at `/opt/rocm`:
```bash
/opt/rocm -> /workspace/venv/lib/python3.12/site-packages/_rocm_sdk_devel
```

## Troubleshooting

### GPU Not Detected

**Docker Builder:** This is expected and harmless - the Docker builder is CPU-only and doesn't need GPU access to build wheels.

**Distrobox:** If GPU isn't detected:
```bash
# Check ROCm
rocminfo | grep gfx

# Check PyTorch
python -c "import torch; print(torch.cuda.is_available())"
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

## Directory Structure

```
.
├── 00-provision-toolbox.sh    # Create distrobox container
├── 01-install-tools.sh        # Install system build tools
├── 02-install-rocm.sh         # Install ROCm/PyTorch nightly
├── 03-build-aiter.sh          # AITER build (produces wheel)
├── 04-build-vllm.sh           # Build vLLM from source
├── download-model.sh          # Download Hugging Face models
├── test.sh                    # Test API endpoint
├── test_vllm.py               # Python test script
├── .toolbox.env               # Environment configuration
├── .dockerignore             # Docker build exclusions
├── docker-compose.yml         # Docker service (alternative)
├── Dockerfile                 # Docker build (alternative)
├── Dockerfile.builder         # Docker wheel builder (CPU-only, runs 01-04 scripts)
├── cache/
│   └── huggingface/          # Model cache
├── wheels/                   # Built wheels (created by 03 & 04 scripts)
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

## References

- [vLLM](https://github.com/vllm-project/vllm) - Open source LLM inference engine
- [ROCm](https://rocm.docs.amd.com/) - AMD's open-source GPU compute platform
- [ROCm TheRock](https://github.com/ROCm/TheRock) - AMD's nightly build system
- [PyTorch ROCm](https://pytorch.org/get-started/locally/) - PyTorch with AMD GPU support
- [Distrobox](https://distrobox.privatedns.org/) - Container tool for Linux distributions

## License

This project follows the same license as vLLM (Apache 2.0).
