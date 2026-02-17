# vLLM for AMD Strix Halo (gfx1151)

Docker-based build system for running vLLM on AMD Strix Halo GPUs using nightly ROCm builds.

## Overview

This project enables vLLM inference on AMD Strix Halo APUs (gfx1151 architecture) using:
- AMD nightly ROCm builds with gfx1151 support
- PyTorch 2.11+ with ROCm backend
- vLLM compiled for gfx1151 target
- Flash Attention with AMD Triton backend
- CPU-only build support for CI/CD

## Quick Start

```bash
# Build the image
docker build -t vllm-gfx1151 .

# Run vLLM server
docker-compose up vllm

# Test the API
./test.sh
```

## Requirements

- Docker 24.0+
- Docker Compose 2.0+
- AMD Strix Halo GPU (Ryzen AI MAX+ PRO 395)
- 16GB+ RAM (32GB+ recommended)
- 50GB+ disk space

## Architecture

**gfx1151** is AMD's GPU architecture for Strix Halo APUs. It requires:
- ROCm 7.11+ nightly builds (stable releases don't support gfx1151 yet)
- PyTorch 2.11+ compiled for ROCm
- Target architecture: `gfx1151`
- GPU version: `11.5.1`

## Build Process

### Docker (Recommended)

Multi-stage build with 5 stages:

```
Stage 1: dev-base     → Install ROCm + PyTorch
Stage 2: build-aiter  → Build AITER kernels
Stage 3: build-fa     → Build Flash Attention
Stage 4: build-vllm   → Build vLLM
Stage 5: release      → Minimal runtime image (~18GB)
```

Build all stages:
```bash
docker build -t vllm-gfx1151 .
```

Build specific stage:
```bash
docker build --target build-vllm -t vllm-build .
```

### Manual (Distrobox)

For development and debugging:

```bash
# Create container
./00-provision-toolbox.sh

# Enter container
distrobox enter vllm-toolbox

# Run build scripts in order
./01-install-tools.sh    # Install build tools
./02-install-rocm.sh     # Install ROCm + PyTorch
./03-build-aiter.sh      # Build AITER
./04-build-fa.sh         # Build Flash Attention
./05-build-vllm.sh       # Build vLLM
```

## Usage

### Run Server

```bash
# Using docker-compose
docker-compose up vllm

# Or manually
docker run -it --rm \
  --device /dev/kfd \
  --device /dev/dri \
  -p 8080:8080 \
  -e HSA_OVERRIDE_GFX_VERSION=11.5.1 \
  vllm-gfx1151 \
  bash -c "vllm serve Qwen/Qwen2.5-0.5B-Instruct --host 0.0.0.0 --port 8080"
```

### API Test

```bash
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "Qwen/Qwen2.5-0.5B-Instruct",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

## Key Features

### CPU-Only Builds

Build GPU software without GPU hardware:

```bash
export NOGPU=true
docker build -t vllm-gfx1151 .
```

The build process:
- Compiles for `gfx1151` architecture
- Uses HIP compiler without GPU
- Generates GPU binaries ahead of time
- Works in CI/CD and cloud environments

### Pip-based ROCm

Uses pip to install ROCm instead of traditional system packages:

```bash
pip install --index-url https://rocm.nightlies.amd.com/v2/gfx1151/ \
    --pre torch torchvision torchaudio \
    rocm-sdk
```

Benefits:
- Automatic version matching with PyTorch
- No root privileges needed
- Per-environment isolation
- Creates `/opt/rocm` symlink for compatibility

### CMake Integration

```bash
export ROCM_HOME=/opt/rocm
export CMAKE_PREFIX_PATH="${ROCM_HOME}/lib/cmake"
export PYTORCH_ROCM_ARCH=gfx1151
```

CMake finds ROCm configs at `/opt/rocm/lib/cmake/` automatically.

## Configuration

### Environment Variables

```bash
# Required
ROCM_HOME=/opt/rocm
PYTORCH_ROCM_ARCH=gfx1151
HSA_OVERRIDE_GFX_VERSION=11.5.1
FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE

# Optional
MAX_JOBS=4                    # Build parallelism
NOGPU=true                    # CPU-only build mode
GPU_TARGET=gfx1151           # Target architecture
```

### Custom Models

Edit `docker-compose.yml`:

```yaml
command: >
  bash -c "vllm serve <MODEL_NAME> 
           --host 0.0.0.0 
           --port 8080
           --tensor-parallel-size 1"
```

## Project Structure

```
.
├── Dockerfile              # Multi-stage Docker build
├── docker-compose.yml      # Service configuration
├── 01-install-tools.sh     # Install build tools
├── 02-install-rocm.sh      # Install ROCm + PyTorch
├── 03-build-aiter.sh       # Build AITER
├── 04-build-fa.sh          # Build Flash Attention
├── 05-build-vllm.sh        # Build vLLM
├── test.sh                 # API test script
├── .toolbox.env            # Environment config
└── cache/                  # Model cache
```

## Troubleshooting

### Build Issues

**CMake can't find Torch:**
```bash
export Torch_DIR=/opt/venv/lib/python3.12/site-packages/torch/share/cmake/Torch
```

**GPU architecture detection fails:**
Ensure `NOGPU=true` is set for CPU-only builds. The build patches `CMakeLists.txt` to skip `enable_language(HIP)` when no GPU is present.

### Runtime Issues

**GPU not detected:**
```bash
# Check GPU access
rocminfo | grep gfx

# Verify environment
env | grep HSA_OVERRIDE
```

**Flash Attention errors:**
```bash
# Ensure AMD backend is enabled
export FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE

# Install build deps
apt-get install gcc make libc6-dev python3-dev
```

**Memory corruption:**
TCMalloc is pre-configured in `/etc/ld.so.preload` to prevent malloc issues with pip-installed ROCm.

## Technical Details

### Why This Approach?

**Traditional ROCm:**
- System-wide installation to `/opt/rocm`
- Large packages (10GB+)
- Root required
- Manual version management

**Our Pip-based Approach:**
```
/opt/venv/lib/python3.12/site-packages/
├── _rocm_sdk_devel/     → /opt/rocm (symlink)
└── torch/
```

- Automatic PyTorch version matching
- Per-environment isolation
- Symlink to `/opt/rocm` for compatibility
- Works with existing build tools

### CPU-Only Build Technique

The `05-build-vllm.sh` script patches vLLM's `CMakeLists.txt`:

```cmake
# Before patch:
enable_language(HIP)

# After patch (when NOGPU=true):
if(NOT DEFINED ENV{NOGPU} OR NOT "$ENV{NOGPU}" STREQUAL "true")
  enable_language(HIP)
endif()
```

This skips GPU detection while still compiling for `gfx1151` target.

## Acknowledgments

Based on pioneering work by **Donato Capitella** ([amd-strix-halo-vllm-toolboxes](https://github.com/kyuz0/amd-strix-halo-vllm-toolboxes)).

**Key improvements:**
- Ubuntu 24.04 base (vs Fedora)
- Pip-based ROCm with version matching
- No vLLM source patching required
- AITER and Flash Attention builds
- CPU-only build support
- Docker automation

## License

Apache 2.0 (same as vLLM)
