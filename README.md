# vLLM for AMD Strix Halo (gfx1151)

This repository provides a complete build system for running vLLM on AMD Strix Halo GPUs (gfx1151 architecture) using nightly ROCm builds.

## Acknowledgments

This project builds upon the pioneering work by **Donato Capitella** and his repository:
- **[amd-strix-halo-vllm-toolboxes](https://github.com/kyuz0/amd-strix-halo-vllm-toolboxes)**

Donato's original approach demonstrated that vLLM could run on AMD Strix Halo GPUs and provided the foundation for understanding the technical challenges involved.

**Our improvements on Donato's approach:**

1. **Ubuntu 24.04 Base**: Our image is based on Ubuntu 24.04, while Donato's uses Fedora. Ubuntu provides broader compatibility with most containerization tools and cloud environments.

2. **Pip-based ROCm Installation**: Instead of using nightly ROCm tarballs extracted to `/opt/rocm`, we use pip to install ROCm SDK with automatic PyTorch version matching. This ensures ROCm and PyTorch are always compatible and simplifies version management.

3. **No Source Code Patching**: Donato's method requires patching vLLM source code to work with gfx1151. We build vLLM as-is without any source modifications, relying on upstream ROCm/PyTorch packages and proper build configuration. This makes it easier to update vLLM to newer versions and maintain the build process.

4. **Additional Performance Optimizations**: We built AITER and Flash Attention for gfx1151, which vLLM can use to improve performance. AITER's main branch now supports gfx1151 (issue #1552 was fixed in December 2025), though its primary focus is on gfx9 architectures (MI300X, MI350, MI450) where it provides the most benefit. Flash Attention provides optimized attention mechanisms that can significantly boost inference speed.

5. **Docker Automation**: Created a multi-stage Dockerfile for reproducible, automated builds that can run anywhere, including CPU-only environments.

6. **CPU-Only Build Support**: Enabled building GPU software without requiring GPU hardware, making CI/CD and remote builds possible.

## The Challenge

Running vLLM on AMD Strix Halo (gfx1151) presents several challenges:

1. **No Official ROCm Release Yet**: ROCm 7.11 (the latest stable release) doesn't officially support gfx1151. We need nightly builds.

2. **ROCm/PyTorch Version Matching**: PyTorch ROCm builds are tightly coupled to specific ROCm versions. Using mismatched versions causes runtime failures.

3. **Pip-based ROCm Installation**: Modern ROCm is distributed via pip packages rather than traditional `/opt/rocm` system installations. This breaks tools that expect the traditional directory structure.

4. **Build Tool Expectations**: Many build tools (CMake, HIP compiler) expect ROCm libraries at `/opt/rocm/lib`, but pip installs them in Python's site-packages directory.

5. **Limited GPU Access**: Building GPU software typically requires GPU access, making CI/CD and remote builds difficult.

## Key Concepts

### gfx1151 Architecture

**gfx1151** is AMD's GPU architecture for Strix Halo APUs (e.g., Ryzen AI MAX+ PRO 395). It's a next-generation mobile APU that combines CPU and GPU on a single chip.

**Key facts:**
- Not yet supported in stable ROCm releases (as of ROCm 7.11)
- Requires nightly ROCm builds for development
- Uses HSA (Heterogeneous System Architecture) for CPU-GPU communication
- Supports ROCm HIP programming model

### ROCm Version Coupling

ROCm and PyTorch ROCm builds are tightly coupled:

```
ROCm 7.11.0  → PyTorch 2.5.x (stable)
ROCm 7.11+    → PyTorch 2.11.0a0+ (nightly, gfx1151 support)
```

**Why this matters:**
- Using mismatched versions causes runtime failures
- PyTorch ROCm builds link against specific ROCm libraries
- GPU kernels are compiled for specific ROCm versions

**Our solution:** Use pip to install both from AMD nightly repo, ensuring automatic version matching.

### Pip-based vs Traditional ROCm

**Traditional ROCm installation:**
- System-wide installation to `/opt/rocm`
- Large installer packages (10GB+)
- Root privileges required
- Manual version management

**Pip-based ROCm installation:**
- Per-environment installation in Python venv
- Downloads only needed packages
- No root privileges needed
- Automatic version matching with PyTorch

**Key insight:** We can "morph" pip structure to traditional `/opt/rocm` layout using symlinks, getting benefits of both approaches.

### CPU-Only GPU Builds

**How it works:**
- HIP compiler generates GPU code without needing physical GPU
- Architecture targeting (`gfx1151`) is a compile-time flag
- GPU binaries are generated ahead of time
- Runtime only needs to load and execute pre-compiled kernels

**Why this is important:**
- Enables CI/CD without GPU hardware
- Builds can run anywhere
- Reproducible builds across environments
- Pre-packaging for deployment

## Development Process

This project evolved through a systematic development process:

### Phase 1: Distrobox-based Iteration

We started by using Distrobox to create an isolated Ubuntu 24.04 environment for manual experimentation. This allowed us to:

1. **Iterate on build scripts** (00-05*.sh) by running them step-by-step
2. **Debug issues interactively** with full shell access
3. **Verify GPU functionality** on actual hardware
4. **Test different approaches** to ROCm installation and configuration

The distrobox approach provided a reproducible environment for:
- Installing ROCm SDK and PyTorch from AMD nightly builds
- Building AITER, Flash Attention, and vLLM for gfx1151
- Fixing missing ROCm library symlinks
- Standardizing paths to `/opt/rocm`
- Verifying CPU-only builds work correctly

**Scripts used in this phase:**
- `00-provision-toolbox.sh` - Create distrobox container
- `01-install-tools.sh` - Install build tools
- `02-install-rocm.sh` - Install ROCm + PyTorch + create symlinks
- `03-build-aiter.sh` - Build AITER for gfx1151
- `04-build-fa.sh` - Build Flash Attention for gfx1151
- `05-build-vllm.sh` - Build vLLM for gfx1151

### Phase 2: Docker Image Creation

Once the manual procedure was validated, we automated it using Docker:

1. **Multi-stage build** - Each component built in separate stage for caching and isolation
2. **CPU-only builds** - `NOGPU=true` flag enables building anywhere
3. **Production-ready image** - Final release stage contains only runtime dependencies
4. **Docker Compose integration** - Easy deployment and configuration

**Docker stages:**
1. **dev-base** - Installs build tools, ROCm SDK, PyTorch
2. **build-aiter** - Builds AITER for gfx1151
3. **build-fa** - Builds Flash Attention for gfx1151
4. **build-vllm** - Builds vLLM for gfx1151
5. **release** - Minimal runtime image (18GB)

The Dockerfile directly uses the same build scripts (01-05*.sh) validated during the distrobox phase, ensuring consistency between manual and automated builds.

## Our Approach

### 1. Pip-based ROCm + PyTorch Installation

We install ROCm and PyTorch together using a single pip command from AMD's nightly repository:

```bash
pip install --index-url https://rocm.nightlies.amd.com/v2/gfx1151/ \
    --pre torch torchvision torchaudio \
    --index-url https://rocm.nightlies.amd.com/v2/gfx1151/ \
    rocm-sdk
```

**Why this works:**
- Automatically matches ROCm release with the latest pre-release PyTorch 2.11 for ROCm
- Ensures version compatibility between ROCm and PyTorch
- Gets gfx1151-specific pre-built binaries

### 2. "Morphing" Pip Structure to `/opt/rocm` Layout

The pip-installed ROCm SDK places everything in Python's site-packages:

```
/opt/venv/lib/python3.12/site-packages/
├── _rocm_sdk_devel/          # ROCm development files
│   ├── bin/
│   ├── include/
│   └── lib/
└── _rocm_sdk_libraries_gfx1151/  # gfx1151-specific libraries
    └── lib/
```

Traditional tools expect:

```
/opt/rocm/
├── bin/
├── include/
└── lib/
```

**Our Solution:** Create symlinks to "morph" the pip structure:

```bash
ln -sf /opt/venv/lib/python3.12/site-packages/_rocm_sdk_devel /opt/rocm
```

This gives us:
- Traditional `/opt/rocm` path for build tools
- Pip-based version management
- Best of both worlds

### 3. CMake Integration

We configure CMake to find ROCm configs:

```bash
export ROCM_HOME=/opt/rocm
export CMAKE_PREFIX_PATH="${ROCM_HOME}/lib/cmake:${CMAKE_PREFIX_PATH:-}"
```

This ensures CMake finds all ROCm CMake config files at `/opt/rocm/lib/cmake/`.

### 4. Fixing Missing Library Symlinks

ROCm SDK's CMake config files reference versioned libraries (e.g., `libhipfftw.so.0.1`) that the SDK installation doesn't create symlinks for. We create these manually:

```bash
ln -sf ${LIB_SOURCE_DIR}/libhipfftw.so /opt/rocm/lib/libhipfftw.so.0
ln -sf ${LIB_SOURCE_DIR}/libhipfftw.so /opt/rocm/lib/libhipfftw.so.0.1
```

### 5. CPU-Only Builds

Our build process works entirely on CPU:

- All builds specify `GPU_ARCHS=gfx1151` and `PYTORCH_ROCM_ARCH=gfx1151`
- HIP compiler generates GPU code without needing physical GPU
- `NOGPU=true` flag skips runtime GPU verification only
- Result: GPU-ready binaries that work on actual AMD gfx1151 hardware

**This enables:**
- CI/CD without GPU access
- Building wheels on different machines than deployment
- Reproducible builds
- Pre-packaging for deployment

## What We Built

We successfully built three ROCm-based packages for gfx1151:

### vLLM
The main LLM inference engine, built from source with ROCm support.

```bash
./05-build-vllm.sh  # or docker build --target build-vllm
```

**Build result:** vllm 0.1.dev1+g3b30e6150.rocm711 (53.6MB wheel)

### Flash Attention
Optimized attention mechanisms for improved performance.

```bash
./04-build-fa.sh  # or docker build --target build-fa
```

**Build result:** flash_attn 2.8.3 (ROCm/AMD backend)

**Key configuration:**
```bash
export FLASH_ATTENTION_TRITON_AMD_ENABLE="TRUE"
```

This tells Flash Attention to use the AMD Triton backend instead of CUDA.

### AITER
AI Tensor Engine for ROCm (optional).

```bash
./03-build-aiter.sh  # or docker build --target build-aiter
```

**Build result:** amd-aiter 0.0.0 (30MB wheel)

**Note:** AITER builds successfully on gfx1151 but vLLM won't use it since AITER only supports gfx9 architectures (MI300X, MI350). The runtime warning is expected and harmless.

## Quick Start with Docker

### Build the Complete Image

```bash
docker build -f Dockerfile -t vllm-gfx1151-dev .
```

This builds all five stages:
1. **dev-base** - Installs build tools, ROCm SDK, PyTorch
2. **build-aiter** - Builds AITER for gfx1151
3. **build-fa** - Builds Flash Attention for gfx1151
4. **build-vllm** - Builds vLLM for gfx1151
5. **release** - Minimal runtime image (18GB)

### Run vLLM Server

```bash
docker-compose up vllm-gfx1151-runtime
```

The server will:
- Start on port 8080
- Serve Qwen/Qwen2.5-0.5B-Instruct model
- Use gfx1151 GPU with proper ROCm configuration

### Test the API

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

### Development with Distrobox

For development and iteration, you can still use the manual distrobox approach:

```bash
# Create distrobox container
./00-provision-toolbox.sh

# Enter container
distrobox enter restart

# Run build scripts step-by-step
./01-install-tools.sh
./02-install-rocm.sh
./03-build-aiter.sh
./04-build-fa.sh
./05-build-vllm.sh

# Test locally
source /opt/venv/bin/activate
vllm serve Qwen/Qwen2.5-0.5B-Instruct --host 0.0.0.0 --port 8080
```

**When to use distrobox:**
- Debugging build issues interactively
- Experimenting with new ROCm versions
- Testing on actual GPU hardware
- Developing new build scripts

**When to use Docker:**
- Production deployments
- CI/CD pipelines
- Reproducible builds
- Sharing with others

## Directory Structure

```
.
├── 00-provision-toolbox.sh    # Create distrobox container (for manual builds)
├── 01-install-tools.sh        # Install system build tools
├── 02-install-rocm.sh         # Install ROCm/PyTorch and create /opt/rocm symlinks
├── 03-build-aiter.sh          # Build AITER for gfx1151
├── 04-build-fa.sh             # Build Flash Attention for gfx1151
├── 05-build-vllm.sh           # Build vLLM for gfx1151
├── Dockerfile                 # Multi-stage Docker build
├── docker-compose.yml         # Docker service configuration
├── download-model.sh          # Download Hugging Face models
├── test.sh                    # Test API endpoint
├── test_vllm.py               # Python test script
├── .toolbox.env               # Environment configuration
├── .toolbox.env.sample        # Sample configuration
├── .dockerignore              # Docker build exclusions
├── .gitignore                 # Git ignore patterns
├── cache/
│   └── huggingface/          # Model cache (mounted into container)
└── README.md                  # This file
```

## Environment Variables

### Core ROCm Variables
```bash
ROCM_HOME=/opt/rocm                    # Standardized ROCm installation path
ROCM_PATH=/opt/rocm                    # Alternative path variable
CMAKE_PREFIX_PATH="${ROCM_HOME}/lib/cmake:${CMAKE_PREFIX_PATH:-}"  # CMake configs
```

### GPU-Specific Variables (gfx1151/Strix Halo)
```bash
PYTORCH_ROCM_ARCH=gfx1151               # PyTorch ROCm architecture target
GPU_ARCHS=gfx1151                        # vLLM/AITER GPU architecture
HSA_OVERRIDE_GFX_VERSION=11.5.1           # GPU version override for Strix Halo
HIP_DEVICE_LIB_PATH="${ROCM_HOME}/lib/llvm/amdgcn/bitcode"  # Device libraries
```

### Path Configuration
```bash
PATH="/opt/venv/bin:/opt/rocm/bin:${PATH}"
LD_LIBRARY_PATH="/opt/rocm/lib:${LD_LIBRARY_PATH:-}"
```

### Flash Attention AMD Backend
```bash
FLASH_ATTENTION_TRITON_AMD_ENABLE="TRUE"  # Enable AMD Triton backend
```

### CPU-Only Build Mode
```bash
NOGPU=true                                 # Skip GPU runtime tests only
                                           # Still builds for gfx1151 target
```

## Technical Details

### Why Pip-based ROCm Installation?

Traditional ROCm installation involves:
- Downloading large installer packages
- System-wide installation to `/opt/rocm`
- Root privileges required
- Difficult version management

Pip-based installation:
- Automatic version matching with PyTorch
- Per-environment isolation
- No root privileges needed
- Easy version switching

### Symlink Strategy

We create a single symlink to morph the pip structure:

```bash
/opt/rocm -> /opt/venv/lib/python3.12/site-packages/_rocm_sdk_devel
```

This works because:
- `_rocm_sdk_devel` contains all traditional ROCm directories (bin, include, lib)
- Build tools look for files at `/opt/rocm/...`
- Symlinks are resolved at file system level
- Transparent to applications

### CMake Integration

All ROCm CMake configs are at `/opt/rocm/lib/cmake/`:

```
/opt/rocm/lib/cmake/
├── hip/
├── hipblas/
├── hipsolver/
├── rocthrust/
└── ... (40+ config directories)
```

Setting `CMAKE_PREFIX_PATH` ensures CMake finds all these configs.

### JIT Compilation Requirements

Flash Attention's AMD Triton backend JIT compiles HIP utilities at runtime. This requires:

1. **C Compiler and Headers:** gcc, make, libc6-dev
2. **Python Headers:** python3-dev
3. **ROCm Libraries:** Available at `/opt/rocm/lib/`

Without these, you'll see errors like:
- `RuntimeError: Failed to find C compiler`
- `fatal error: stdint.h: No such file or directory`
- `fatal error: Python.h: No such file or directory`

### Memory Corruption Protection

Pip-installed ROCm can cause "double free or corruption" errors. We use TCMalloc:

```bash
# Configured in /etc/ld.so.preload
/usr/lib/x86_64-linux-gnu/libtcmalloc.so.4
```

This replaces the standard malloc with Google's memory allocator, preventing these errors.

## Customization

### Using Different Models

To serve a different model, modify the `docker-compose.yml` command:

```yaml
command: >
  bash -c "source /opt/venv/bin/activate &&
           vllm serve <MODEL_NAME> --host 0.0.0.0 --port 8080
           --tensor-parallel-size 1"
```

Replace `<MODEL_NAME>` with your desired model from Hugging Face:
- `meta-llama/Llama-3.2-1B`
- `mistralai/Mistral-7B-v0.1`
- `google/gemma-2-2b`

**Note:** Larger models may require more GPU memory or multiple GPUs.

### Targeting Different GPU Architectures

To build for a different AMD GPU architecture:

1. **Update the ROCm repository URL:**
   ```bash
   # For gfx1100 (RDNA 3)
   export ROCM_INDEX_URL=https://rocm.nightlies.amd.com/v2/gfx1100/

   # For gfx942 (MI300X)
   export ROCM_INDEX_URL=https://rocm.nightlies.amd.com/v2/gfx942/
   ```

2. **Update GPU architecture variables in scripts:**
   ```bash
   # In 02-install-rocm.sh
   export GPU_TARGET=gfx1100
   export PYTORCH_ROCM_ARCH=gfx1100

   # In build scripts (03, 04, 05)
   export GPU_ARCHS=gfx1100
   ```

3. **Update HSA override (if needed):**
   ```bash
   # gfx1100 = 11.0.0
   # gfx1102 = 11.0.2
   # gfx1151 = 11.5.1 (Strix Halo)
   export HSA_OVERRIDE_GFX_VERSION=11.0.0
   ```

**Common AMD GPU architectures:**
- `gfx900-gfx908` - Vega (Radeon VII, Instinct MI50)
- `gfx940-gfx942` - CDNA 3 (MI300X, MI350)
- `gfx1030-gfx1035` - RDNA 2 (RX 6000 series)
- `gfx1100-gfx1102` - RDNA 3 (RX 7000 series)
- `gfx1151` - RDNA 3.5 (Strix Halo APUs)

### Adjusting Build Parallelism

To speed up builds on machines with more CPU cores:

```bash
# In build scripts (03, 04, 05)
export MAX_JOBS=8  # Default is 4

# Or use nproc to use all available cores
export MAX_JOBS=$(nproc)
```

To reduce memory usage during builds:

```bash
export MAX_JOBS=2
```

### Custom PyTorch/vLLM Versions

To use specific versions instead of latest nightly builds:

```bash
# In 02-install-rocm.sh
pip install --index-url https://rocm.nightlies.amd.com/v2/gfx1151/ \
    torch==2.11.0a0+git<COMMIT> torchvision torchaudio \
    --index-url https://rocm.nightlies.amd.com/v2/gfx1151/ \
    rocm-sdk

# In 05-build-vllm.sh
git clone https://github.com/vllm-project/vllm.git
cd vllm
git checkout <TAG_OR_COMMIT>  # e.g., v0.6.3
pip install -e .
```

**Warning:** Different versions may have compatibility issues. Test thoroughly.

### Adding Additional Python Packages

To add extra Python packages to the build:

```bash
# In Dockerfile, after building vLLM
RUN source ${VENV_DIR}/bin/activate && \
    pip install <package1> <package2>

# Example: Add monitoring and logging
RUN source ${VENV_DIR}/bin/activate && \
    pip install prometheus-client structlog
```

Or for distrobox builds:

```bash
distrobox enter restart
source /opt/venv/bin/activate
pip install <package1> <package2>
```

## Troubleshooting

### Build Failures

1. **Check ROCm initialization:**
   ```bash
   rocm-sdk init
   ```

2. **Verify device libraries exist:**
   ```bash
   ls /opt/rocm/lib/llvm/amdgcn/bitcode/
   ```

3. **Reduce parallel jobs:**
   ```bash
   export MAX_JOBS=4
   ```

4. **Check library symlinks:**
   ```bash
   ls -la /opt/rocm/lib/libhipfftw.so*
   ```

### Runtime Issues

1. **Flash Attention import errors:**
   - Ensure `FLASH_ATTENTION_TRITON_AMD_ENABLE="TRUE"` is set
   - Install gcc, make, libc6-dev, python3-dev

2. **GPU not detected:**
   - Check GPU access: `rocminfo | grep gfx`
   - Verify `HSA_OVERRIDE_GFX_VERSION=11.5.1`
   - Check device access permissions

3. **Memory corruption errors:**
   - Verify TCMalloc is loaded: `cat /etc/ld.so.preload`

### CPU-Only Builds

If building without GPU access (e.g., CI/CD):
```bash
export NOGPU=true
```

This skips runtime GPU verification only. Builds still produce gfx1151-targeted binaries.

## Build Status

| Component | Status | Notes |
|-----------|--------|-------|
| ROCm 7.11.0+ | ✅ Working | Nightly packages for gfx1151 |
| PyTorch 2.11.0+ | ✅ Working | ROCm backend functional |
| vLLM 0.1.dev+ | ✅ Working | Built from source (gfx1151 target) |
| AITER 0.0.0 | ✅ Working | Builds for gfx1151 (not used by vLLM) |
| Flash Attention 2.8.3 | ✅ Working | ROCm/AMD backend |
| TCMalloc | ✅ Configured | Prevents memory corruption |

**CPU-Only Build:** All packages successfully build for gfx1151 GPU target in CPU-only environment. Binaries are GPU-ready for actual AMD gfx1151 hardware.

## FAQ

### Q: Why do I need nightly ROCm builds for gfx1151?

A: Stable ROCm releases (e.g., ROCm 7.11) don't officially support gfx1151 (Strix Halo) yet. Nightly builds from AMD's TheRock repository include experimental support for newer architectures.

### Q: Can I use this on other AMD GPUs?

A: Yes, but you'll need to modify the GPU architecture variables and ROCm repository URL. See the "Customization" section above for details. This approach should work for any AMD GPU with nightly ROCm support.

### Q: Why not just use the official vLLM Docker image?

A: Official vLLM images don't include ROCm support for gfx1151. They typically only support CUDA (NVIDIA) or older ROCm architectures. Building from source with nightly ROCm enables support for the latest AMD GPUs.

### Q: What's the difference between distrobox and Docker approaches?

A: **Distrobox** is for development and iteration - interactive shell, step-by-step execution, easy debugging. **Docker** is for production - automated builds, reproducible images, CI/CD friendly. Both use the same underlying build scripts.

### Q: Do I need a GPU to build the Docker image?

A: No! The build uses `NOGPU=true`, which skips runtime GPU verification but still compiles GPU kernels for gfx1151. The resulting binaries work on actual AMD gfx1151 hardware.

### Q: Why is the Docker image 18GB?

A: This includes:
- ROCm SDK development files (~10GB)
- PyTorch with ROCm support (~3GB)
- vLLM, Flash Attention, AITER compiled binaries (~5GB)
- Python dependencies and build tools

The final runtime could be smaller if we stripped build tools, but we keep them for JIT compilation at runtime.

### Q: Can I reduce the image size?

A: Yes, but you'll lose runtime JIT capabilities. Options:
1. Remove build tools (gcc, make) - breaks Triton JIT
2. Use a smaller base image - may break ROCm compatibility
3. Use multi-stage builds more aggressively - complex but possible

We recommend the 18GB image for full functionality.

### Q: What happens if I get "AITER not supported on this architecture" warning?

A: This is expected and harmless. AITER only supports gfx9 architectures (MI300X, MI350), not gfx1151 (Strix Halo). vLLM will automatically fall back to standard ROCm/PyTorch kernels.

### Q: Can I use this for inference on multiple GPUs?

A: Yes! vLLM supports tensor parallelism across multiple GPUs. Modify the `--tensor-parallel-size` parameter:

```bash
vllm serve <model> --tensor-parallel-size 2
```

For docker-compose, ensure multiple GPUs are exposed to the container.

### Q: How do I update to newer ROCm/PyTorch versions?

A: Wait for AMD to release new nightly builds for gfx1151, then:
1. Update ROCm repository URL if the version changed
2. Rebuild the Docker image: `docker build --no-cache -f Dockerfile -t vllm-gfx1151-dev .`

The `--no-cache` flag ensures you get the latest packages.

### Q: What if nightly ROCm builds have bugs?

A: Nightly builds are experimental and may have bugs. Solutions:
1. Try an earlier nightly build (pin specific commit hash in requirements)
2. File bug reports with AMD: https://github.com/ROCm/TheRock/issues
3. Wait for a new nightly build
4. Use stable ROCm with supported architecture if available

### Q: How does this differ from Donato Capitella's approach?

A: We built upon Donato's pioneering work and made several improvements:

**Donato's original approach:**
- Uses nightly ROCm tarballs extracted to `/opt/rocm`
- Patches vLLM source code to work with gfx1151
- Fedora-based
- Manual setup process
- Provides deep control over vLLM internals

**Our improvements:**
- Uses pip to install ROCm SDK with automatic PyTorch version matching (ensures compatibility)
- Builds vLLM without any source modifications (easier to update to newer versions)
- Ubuntu-based
- Builds AITER and Flash Attention for gfx1151 (Flash Attention can improve performance)
- Automated Docker builds with multi-stage caching
- CPU-only build support for CI/CD and remote builds

These improvements make the build process more automated, easier to maintain, and more accessible to users who want to experiment with vLLM on Strix Halo GPUs.

### Q: Can I contribute back improvements?

A: Absolutely! This is an open reference project. Improvements could include:
- Support for other AMD GPU architectures
- Smaller image optimizations
- Additional pre-built models
- Performance benchmarks
- Documentation improvements

Feel free to fork, experiment, and submit issues or PRs.

## References

- [vLLM](https://github.com/vllm-project/vllm) - Open source LLM inference engine
- [ROCm](https://rocm.docs.amd.com/) - AMD's open-source GPU compute platform
- [ROCm TheRock](https://github.com/ROCm/TheRock) - AMD's nightly build system
- [PyTorch ROCm](https://pytorch.org/get-started/locally/) - PyTorch with AMD GPU support
- [Distrobox](https://distrobox.privatedns.org/) - Container tool for Linux distributions
- [amd-strix-halo-vllm-toolboxes](https://github.com/kyuz0/amd-strix-halo-vllm-toolboxes) - Original Strix Halo vLLM project by Donato Capitella

## License

This project follows the same license as vLLM (Apache 2.0).
# vLLM for AMD Strix Halo (gfx1151)

This repository provides a complete build system for running vLLM on AMD Strix Halo GPUs (gfx1151 architecture) using nightly ROCm builds.

## Acknowledgments

This project builds upon the pioneering work by **Donato Capitella** and his repository:
- **[amd-strix-halo-vllm-toolboxes](https://github.com/kyuz0/amd-strix-halo-vllm-toolboxes)**

Donato's original approach demonstrated that vLLM could run on AMD Strix Halo GPUs and provided the foundation for understanding the technical challenges involved.

**Our improvements on Donato's approach:**

1. **Ubuntu 24.04 Base**: Our image is based on Ubuntu 24.04, while Donato's uses Fedora. Ubuntu provides broader compatibility with most containerization tools and cloud environments.

2. **Pip-based ROCm Installation**: Instead of using nightly ROCm tarballs extracted to `/opt/rocm`, we use pip to install ROCm SDK with automatic PyTorch version matching. This ensures ROCm and PyTorch are always compatible and simplifies version management.

3. **No Source Code Patching**: Donato's method requires patching vLLM source code to work with gfx1151. We build vLLM as-is without any source modifications, relying on upstream ROCm/PyTorch packages and proper build configuration. This makes it easier to update vLLM to newer versions and maintain the build process.

4. **Additional Performance Optimizations**: We built AITER and Flash Attention for gfx1151, which vLLM can use to improve performance. AITER's main branch now supports gfx1151 (issue #1552 was fixed in December 2025), though its primary focus is on gfx9 architectures (MI300X, MI350, MI450) where it provides the most benefit. Flash Attention provides optimized attention mechanisms that can significantly boost inference speed.

5. **Docker Automation**: Created a multi-stage Dockerfile for reproducible, automated builds that can run anywhere, including CPU-only environments.

6. **CPU-Only Build Support**: Enabled building GPU software without requiring GPU hardware, making CI/CD and remote builds possible.

## The Challenge

Running vLLM on AMD Strix Halo (gfx1151) presents several challenges:

1. **No Official ROCm Release Yet**: ROCm 7.11 (the latest stable release) doesn't officially support gfx1151. We need nightly builds.

2. **ROCm/PyTorch Version Matching**: PyTorch ROCm builds are tightly coupled to specific ROCm versions. Using mismatched versions causes runtime failures.

3. **Pip-based ROCm Installation**: Modern ROCm is distributed via pip packages rather than traditional `/opt/rocm` system installations. This breaks tools that expect the traditional directory structure.

4. **Build Tool Expectations**: Many build tools (CMake, HIP compiler) expect ROCm libraries at `/opt/rocm/lib`, but pip installs them in Python's site-packages directory.

5. **Limited GPU Access**: Building GPU software typically requires GPU access, making CI/CD and remote builds difficult.

## Key Concepts

### gfx1151 Architecture

**gfx1151** is AMD's GPU architecture for Strix Halo APUs (e.g., Ryzen AI MAX+ PRO 395). It's a next-generation mobile APU that combines CPU and GPU on a single chip.

**Key facts:**
- Not yet supported in stable ROCm releases (as of ROCm 7.11)
- Requires nightly ROCm builds for development
- Uses HSA (Heterogeneous System Architecture) for CPU-GPU communication
- Supports ROCm HIP programming model

### ROCm Version Coupling

ROCm and PyTorch ROCm builds are tightly coupled:

```
ROCm 7.11.0  → PyTorch 2.5.x (stable)
ROCm 7.11+    → PyTorch 2.11.0a0+ (nightly, gfx1151 support)
```

**Why this matters:**
- Using mismatched versions causes runtime failures
- PyTorch ROCm builds link against specific ROCm libraries
- GPU kernels are compiled for specific ROCm versions

**Our solution:** Use pip to install both from AMD nightly repo, ensuring automatic version matching.

### Pip-based vs Traditional ROCm

**Traditional ROCm installation:**
- System-wide installation to `/opt/rocm`
- Large installer packages (10GB+)
- Root privileges required
- Manual version management

**Pip-based ROCm installation:**
- Per-environment installation in Python venv
- Downloads only needed packages
- No root privileges needed
- Automatic version matching with PyTorch

**Key insight:** We can "morph" pip structure to traditional `/opt/rocm` layout using symlinks, getting benefits of both approaches.

### CPU-Only GPU Builds

**How it works:**
- HIP compiler generates GPU code without needing physical GPU
- Architecture targeting (`gfx1151`) is a compile-time flag
- GPU binaries are generated ahead of time
- Runtime only needs to load and execute pre-compiled kernels

**Why this is important:**
- Enables CI/CD without GPU hardware
- Builds can run anywhere
- Reproducible builds across environments
- Pre-packaging for deployment

## Development Process

This project evolved through a systematic development process:

### Phase 1: Distrobox-based Iteration

We started by using Distrobox to create an isolated Ubuntu 24.04 environment for manual experimentation. This allowed us to:

1. **Iterate on build scripts** (00-05*.sh) by running them step-by-step
2. **Debug issues interactively** with full shell access
3. **Verify GPU functionality** on actual hardware
4. **Test different approaches** to ROCm installation and configuration

The distrobox approach provided a reproducible environment for:
- Installing ROCm SDK and PyTorch from AMD nightly builds
- Building AITER, Flash Attention, and vLLM for gfx1151
- Fixing missing ROCm library symlinks
- Standardizing paths to `/opt/rocm`
- Verifying CPU-only builds work correctly

**Scripts used in this phase:**
- `00-provision-toolbox.sh` - Create distrobox container
- `01-install-tools.sh` - Install build tools
- `02-install-rocm.sh` - Install ROCm + PyTorch + create symlinks
- `03-build-aiter.sh` - Build AITER for gfx1151
- `04-build-fa.sh` - Build Flash Attention for gfx1151
- `05-build-vllm.sh` - Build vLLM for gfx1151

### Phase 2: Docker Image Creation

Once the manual procedure was validated, we automated it using Docker:

1. **Multi-stage build** - Each component built in separate stage for caching and isolation
2. **CPU-only builds** - `NOGPU=true` flag enables building anywhere
3. **Production-ready image** - Final release stage contains only runtime dependencies
4. **Docker Compose integration** - Easy deployment and configuration

**Docker stages:**
1. **dev-base** - Installs build tools, ROCm SDK, PyTorch
2. **build-aiter** - Builds AITER for gfx1151
3. **build-fa** - Builds Flash Attention for gfx1151
4. **build-vllm** - Builds vLLM for gfx1151
5. **release** - Minimal runtime image (18GB)

The Dockerfile directly uses the same build scripts (01-05*.sh) validated during the distrobox phase, ensuring consistency between manual and automated builds.

## Our Approach

### 1. Pip-based ROCm + PyTorch Installation

We install ROCm and PyTorch together using a single pip command from AMD's nightly repository:

```bash
pip install --index-url https://rocm.nightlies.amd.com/v2/gfx1151/ \
    --pre torch torchvision torchaudio \
    --index-url https://rocm.nightlies.amd.com/v2/gfx1151/ \
    rocm-sdk
```

**Why this works:**
- Automatically matches ROCm release with the latest pre-release PyTorch 2.11 for ROCm
- Ensures version compatibility between ROCm and PyTorch
- Gets gfx1151-specific pre-built binaries

### 2. "Morphing" Pip Structure to `/opt/rocm` Layout

The pip-installed ROCm SDK places everything in Python's site-packages:

```
/opt/venv/lib/python3.12/site-packages/
├── _rocm_sdk_devel/          # ROCm development files
│   ├── bin/
│   ├── include/
│   └── lib/
└── _rocm_sdk_libraries_gfx1151/  # gfx1151-specific libraries
    └── lib/
```

Traditional tools expect:

```
/opt/rocm/
├── bin/
├── include/
└── lib/
```

**Our Solution:** Create symlinks to "morph" the pip structure:

```bash
ln -sf /opt/venv/lib/python3.12/site-packages/_rocm_sdk_devel /opt/rocm
```

This gives us:
- Traditional `/opt/rocm` path for build tools
- Pip-based version management
- Best of both worlds

### 3. CMake Integration

We configure CMake to find ROCm configs:

```bash
export ROCM_HOME=/opt/rocm
export CMAKE_PREFIX_PATH="${ROCM_HOME}/lib/cmake:${CMAKE_PREFIX_PATH:-}"
```

This ensures CMake finds all ROCm CMake config files at `/opt/rocm/lib/cmake/`.

### 4. Fixing Missing Library Symlinks

ROCm SDK's CMake config files reference versioned libraries (e.g., `libhipfftw.so.0.1`) that the SDK installation doesn't create symlinks for. We create these manually:

```bash
ln -sf ${LIB_SOURCE_DIR}/libhipfftw.so /opt/rocm/lib/libhipfftw.so.0
ln -sf ${LIB_SOURCE_DIR}/libhipfftw.so /opt/rocm/lib/libhipfftw.so.0.1
```

### 5. CPU-Only Builds

Our build process works entirely on CPU:

- All builds specify `GPU_ARCHS=gfx1151` and `PYTORCH_ROCM_ARCH=gfx1151`
- HIP compiler generates GPU code without needing physical GPU
- `NOGPU=true` flag skips runtime GPU verification only
- Result: GPU-ready binaries that work on actual AMD gfx1151 hardware

**This enables:**
- CI/CD without GPU access
- Building wheels on different machines than deployment
- Reproducible builds
- Pre-packaging for deployment

## What We Built

We successfully built three ROCm-based packages for gfx1151:

### vLLM
The main LLM inference engine, built from source with ROCm support.

```bash
./05-build-vllm.sh  # or docker build --target build-vllm
```

**Build result:** vllm 0.1.dev1+g3b30e6150.rocm711 (53.6MB wheel)

### Flash Attention
Optimized attention mechanisms for improved performance.

```bash
./04-build-fa.sh  # or docker build --target build-fa
```

**Build result:** flash_attn 2.8.3 (ROCm/AMD backend)

**Key configuration:**
```bash
export FLASH_ATTENTION_TRITON_AMD_ENABLE="TRUE"
```

This tells Flash Attention to use the AMD Triton backend instead of CUDA.

### AITER
AI Tensor Engine for ROCm (optional).

```bash
./03-build-aiter.sh  # or docker build --target build-aiter
```

**Build result:** amd-aiter 0.0.0 (30MB wheel)

**Note:** AITER builds successfully on gfx1151 but vLLM won't use it since AITER only supports gfx9 architectures (MI300X, MI350). The runtime warning is expected and harmless.

## Quick Start with Docker

### Build the Complete Image

```bash
docker build -f Dockerfile -t vllm-gfx1151-dev .
```

This builds all five stages:
1. **dev-base** - Installs build tools, ROCm SDK, PyTorch
2. **build-aiter** - Builds AITER for gfx1151
3. **build-fa** - Builds Flash Attention for gfx1151
4. **build-vllm** - Builds vLLM for gfx1151
5. **release** - Minimal runtime image (18GB)

### Run vLLM Server

```bash
docker-compose up vllm-gfx1151-runtime
```

The server will:
- Start on port 8080
- Serve Qwen/Qwen2.5-0.5B-Instruct model
- Use gfx1151 GPU with proper ROCm configuration

### Test the API

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

### Development with Distrobox

For development and iteration, you can still use the manual distrobox approach:

```bash
# Create distrobox container
./00-provision-toolbox.sh

# Enter container
distrobox enter restart

# Run build scripts step-by-step
./01-install-tools.sh
./02-install-rocm.sh
./03-build-aiter.sh
./04-build-fa.sh
./05-build-vllm.sh

# Test locally
source /opt/venv/bin/activate
vllm serve Qwen/Qwen2.5-0.5B-Instruct --host 0.0.0.0 --port 8080
```

**When to use distrobox:**
- Debugging build issues interactively
- Experimenting with new ROCm versions
- Testing on actual GPU hardware
- Developing new build scripts

**When to use Docker:**
- Production deployments
- CI/CD pipelines
- Reproducible builds
- Sharing with others

## Directory Structure

```
.
├── 00-provision-toolbox.sh    # Create distrobox container (for manual builds)
├── 01-install-tools.sh        # Install system build tools
├── 02-install-rocm.sh         # Install ROCm/PyTorch and create /opt/rocm symlinks
├── 03-build-aiter.sh          # Build AITER for gfx1151
├── 04-build-fa.sh             # Build Flash Attention for gfx1151
├── 05-build-vllm.sh           # Build vLLM for gfx1151
├── Dockerfile                 # Multi-stage Docker build
├── docker-compose.yml         # Docker service configuration
├── download-model.sh          # Download Hugging Face models
├── test.sh                    # Test API endpoint
├── test_vllm.py               # Python test script
├── .toolbox.env               # Environment configuration
├── .toolbox.env.sample        # Sample configuration
├── .dockerignore              # Docker build exclusions
├── .gitignore                 # Git ignore patterns
├── cache/
│   └── huggingface/          # Model cache (mounted into container)
└── README.md                  # This file
```

## Environment Variables

### Core ROCm Variables
```bash
ROCM_HOME=/opt/rocm                    # Standardized ROCm installation path
ROCM_PATH=/opt/rocm                    # Alternative path variable
CMAKE_PREFIX_PATH="${ROCM_HOME}/lib/cmake:${CMAKE_PREFIX_PATH:-}"  # CMake configs
```

### GPU-Specific Variables (gfx1151/Strix Halo)
```bash
PYTORCH_ROCM_ARCH=gfx1151               # PyTorch ROCm architecture target
GPU_ARCHS=gfx1151                        # vLLM/AITER GPU architecture
HSA_OVERRIDE_GFX_VERSION=11.5.1           # GPU version override for Strix Halo
HIP_DEVICE_LIB_PATH="${ROCM_HOME}/lib/llvm/amdgcn/bitcode"  # Device libraries
```

### Path Configuration
```bash
PATH="/opt/venv/bin:/opt/rocm/bin:${PATH}"
LD_LIBRARY_PATH="/opt/rocm/lib:${LD_LIBRARY_PATH:-}"
```

### Flash Attention AMD Backend
```bash
FLASH_ATTENTION_TRITON_AMD_ENABLE="TRUE"  # Enable AMD Triton backend
```

### CPU-Only Build Mode
```bash
NOGPU=true                                 # Skip GPU runtime tests only
                                           # Still builds for gfx1151 target
```

## Technical Details

### Why Pip-based ROCm Installation?

Traditional ROCm installation involves:
- Downloading large installer packages
- System-wide installation to `/opt/rocm`
- Root privileges required
- Difficult version management

Pip-based installation:
- Automatic version matching with PyTorch
- Per-environment isolation
- No root privileges needed
- Easy version switching

### Symlink Strategy

We create a single symlink to morph the pip structure:

```bash
/opt/rocm -> /opt/venv/lib/python3.12/site-packages/_rocm_sdk_devel
```

This works because:
- `_rocm_sdk_devel` contains all traditional ROCm directories (bin, include, lib)
- Build tools look for files at `/opt/rocm/...`
- Symlinks are resolved at file system level
- Transparent to applications

### CMake Integration

All ROCm CMake configs are at `/opt/rocm/lib/cmake/`:

```
/opt/rocm/lib/cmake/
├── hip/
├── hipblas/
├── hipsolver/
├── rocthrust/
└── ... (40+ config directories)
```

Setting `CMAKE_PREFIX_PATH` ensures CMake finds all these configs.

### JIT Compilation Requirements

Flash Attention's AMD Triton backend JIT compiles HIP utilities at runtime. This requires:

1. **C Compiler and Headers:** gcc, make, libc6-dev
2. **Python Headers:** python3-dev
3. **ROCm Libraries:** Available at `/opt/rocm/lib/`

Without these, you'll see errors like:
- `RuntimeError: Failed to find C compiler`
- `fatal error: stdint.h: No such file or directory`
- `fatal error: Python.h: No such file or directory`

### Memory Corruption Protection

Pip-installed ROCm can cause "double free or corruption" errors. We use TCMalloc:

```bash
# Configured in /etc/ld.so.preload
/usr/lib/x86_64-linux-gnu/libtcmalloc.so.4
```

This replaces the standard malloc with Google's memory allocator, preventing these errors.

## Customization

### Using Different Models

To serve a different model, modify the `docker-compose.yml` command:

```yaml
command: >
  bash -c "source /opt/venv/bin/activate &&
           vllm serve <MODEL_NAME> --host 0.0.0.0 --port 8080
           --tensor-parallel-size 1"
```

Replace `<MODEL_NAME>` with your desired model from Hugging Face:
- `meta-llama/Llama-3.2-1B`
- `mistralai/Mistral-7B-v0.1`
- `google/gemma-2-2b`

**Note:** Larger models may require more GPU memory or multiple GPUs.

### Targeting Different GPU Architectures

To build for a different AMD GPU architecture:

1. **Update the ROCm repository URL:**
   ```bash
   # For gfx1100 (RDNA 3)
   export ROCM_INDEX_URL=https://rocm.nightlies.amd.com/v2/gfx1100/

   # For gfx942 (MI300X)
   export ROCM_INDEX_URL=https://rocm.nightlies.amd.com/v2/gfx942/
   ```

2. **Update GPU architecture variables in scripts:**
   ```bash
   # In 02-install-rocm.sh
   export GPU_TARGET=gfx1100
   export PYTORCH_ROCM_ARCH=gfx1100

   # In build scripts (03, 04, 05)
   export GPU_ARCHS=gfx1100
   ```

3. **Update HSA override (if needed):**
   ```bash
   # gfx1100 = 11.0.0
   # gfx1102 = 11.0.2
   # gfx1151 = 11.5.1 (Strix Halo)
   export HSA_OVERRIDE_GFX_VERSION=11.0.0
   ```

**Common AMD GPU architectures:**
- `gfx900-gfx908` - Vega (Radeon VII, Instinct MI50)
- `gfx940-gfx942` - CDNA 3 (MI300X, MI350)
- `gfx1030-gfx1035` - RDNA 2 (RX 6000 series)
- `gfx1100-gfx1102` - RDNA 3 (RX 7000 series)
- `gfx1151` - RDNA 3.5 (Strix Halo APUs)

### Adjusting Build Parallelism

To speed up builds on machines with more CPU cores:

```bash
# In build scripts (03, 04, 05)
export MAX_JOBS=8  # Default is 4

# Or use nproc to use all available cores
export MAX_JOBS=$(nproc)
```

To reduce memory usage during builds:

```bash
export MAX_JOBS=2
```

### Custom PyTorch/vLLM Versions

To use specific versions instead of latest nightly builds:

```bash
# In 02-install-rocm.sh
pip install --index-url https://rocm.nightlies.amd.com/v2/gfx1151/ \
    torch==2.11.0a0+git<COMMIT> torchvision torchaudio \
    --index-url https://rocm.nightlies.amd.com/v2/gfx1151/ \
    rocm-sdk

# In 05-build-vllm.sh
git clone https://github.com/vllm-project/vllm.git
cd vllm
git checkout <TAG_OR_COMMIT>  # e.g., v0.6.3
pip install -e .
```

**Warning:** Different versions may have compatibility issues. Test thoroughly.

### Adding Additional Python Packages

To add extra Python packages to the build:

```bash
# In Dockerfile, after building vLLM
RUN source ${VENV_DIR}/bin/activate && \
    pip install <package1> <package2>

# Example: Add monitoring and logging
RUN source ${VENV_DIR}/bin/activate && \
    pip install prometheus-client structlog
```

Or for distrobox builds:

```bash
distrobox enter restart
source /opt/venv/bin/activate
pip install <package1> <package2>
```

## Troubleshooting

### Build Failures

1. **Check ROCm initialization:**
   ```bash
   rocm-sdk init
   ```

2. **Verify device libraries exist:**
   ```bash
   ls /opt/rocm/lib/llvm/amdgcn/bitcode/
   ```

3. **Reduce parallel jobs:**
   ```bash
   export MAX_JOBS=4
   ```

4. **Check library symlinks:**
   ```bash
   ls -la /opt/rocm/lib/libhipfftw.so*
   ```

### Runtime Issues

1. **Flash Attention import errors:**
   - Ensure `FLASH_ATTENTION_TRITON_AMD_ENABLE="TRUE"` is set
   - Install gcc, make, libc6-dev, python3-dev

2. **GPU not detected:**
   - Check GPU access: `rocminfo | grep gfx`
   - Verify `HSA_OVERRIDE_GFX_VERSION=11.5.1`
   - Check device access permissions

3. **Memory corruption errors:**
   - Verify TCMalloc is loaded: `cat /etc/ld.so.preload`

### CPU-Only Builds

If building without GPU access (e.g., CI/CD):
```bash
export NOGPU=true
```

This skips runtime GPU verification only. Builds still produce gfx1151-targeted binaries.

## Build Status

| Component | Status | Notes |
|-----------|--------|-------|
| ROCm 7.11.0+ | ✅ Working | Nightly packages for gfx1151 |
| PyTorch 2.11.0+ | ✅ Working | ROCm backend functional |
| vLLM 0.1.dev+ | ✅ Working | Built from source (gfx1151 target) |
| AITER 0.0.0 | ✅ Working | Builds for gfx1151 (not used by vLLM) |
| Flash Attention 2.8.3 | ✅ Working | ROCm/AMD backend |
| TCMalloc | ✅ Configured | Prevents memory corruption |

**CPU-Only Build:** All packages successfully build for gfx1151 GPU target in CPU-only environment. Binaries are GPU-ready for actual AMD gfx1151 hardware.

## FAQ

### Q: Why do I need nightly ROCm builds for gfx1151?

A: Stable ROCm releases (e.g., ROCm 7.11) don't officially support gfx1151 (Strix Halo) yet. Nightly builds from AMD's TheRock repository include experimental support for newer architectures.

### Q: Can I use this on other AMD GPUs?

A: Yes, but you'll need to modify the GPU architecture variables and ROCm repository URL. See the "Customization" section above for details. This approach should work for any AMD GPU with nightly ROCm support.

### Q: Why not just use the official vLLM Docker image?

A: Official vLLM images don't include ROCm support for gfx1151. They typically only support CUDA (NVIDIA) or older ROCm architectures. Building from source with nightly ROCm enables support for the latest AMD GPUs.

### Q: What's the difference between distrobox and Docker approaches?

A: **Distrobox** is for development and iteration - interactive shell, step-by-step execution, easy debugging. **Docker** is for production - automated builds, reproducible images, CI/CD friendly. Both use the same underlying build scripts.

### Q: Do I need a GPU to build the Docker image?

A: No! The build uses `NOGPU=true`, which skips runtime GPU verification but still compiles GPU kernels for gfx1151. The resulting binaries work on actual AMD gfx1151 hardware.

### Q: Why is the Docker image 18GB?

A: This includes:
- ROCm SDK development files (~10GB)
- PyTorch with ROCm support (~3GB)
- vLLM, Flash Attention, AITER compiled binaries (~5GB)
- Python dependencies and build tools

The final runtime could be smaller if we stripped build tools, but we keep them for JIT compilation at runtime.

### Q: Can I reduce the image size?

A: Yes, but you'll lose runtime JIT capabilities. Options:
1. Remove build tools (gcc, make) - breaks Triton JIT
2. Use a smaller base image - may break ROCm compatibility
3. Use multi-stage builds more aggressively - complex but possible

We recommend the 18GB image for full functionality.

### Q: What happens if I get "AITER not supported on this architecture" warning?

A: This is expected and harmless. AITER only supports gfx9 architectures (MI300X, MI350), not gfx1151 (Strix Halo). vLLM will automatically fall back to standard ROCm/PyTorch kernels.

### Q: Can I use this for inference on multiple GPUs?

A: Yes! vLLM supports tensor parallelism across multiple GPUs. Modify the `--tensor-parallel-size` parameter:

```bash
vllm serve <model> --tensor-parallel-size 2
```

For docker-compose, ensure multiple GPUs are exposed to the container.

### Q: How do I update to newer ROCm/PyTorch versions?

A: Wait for AMD to release new nightly builds for gfx1151, then:
1. Update ROCm repository URL if the version changed
2. Rebuild the Docker image: `docker build --no-cache -f Dockerfile -t vllm-gfx1151-dev .`

The `--no-cache` flag ensures you get the latest packages.

### Q: What if nightly ROCm builds have bugs?

A: Nightly builds are experimental and may have bugs. Solutions:
1. Try an earlier nightly build (pin specific commit hash in requirements)
2. File bug reports with AMD: https://github.com/ROCm/TheRock/issues
3. Wait for a new nightly build
4. Use stable ROCm with supported architecture if available

### Q: How does this differ from Donato Capitella's approach?

A: We built upon Donato's pioneering work and made several improvements:

**Donato's original approach:**
- Uses nightly ROCm tarballs extracted to `/opt/rocm`
- Patches vLLM source code to work with gfx1151
- Fedora-based
- Manual setup process
- Provides deep control over vLLM internals

**Our improvements:**
- Uses pip to install ROCm SDK with automatic PyTorch version matching (ensures compatibility)
- Builds vLLM without any source modifications (easier to update to newer versions)
- Ubuntu-based
- Builds AITER and Flash Attention for gfx1151 (Flash Attention can improve performance)
- Automated Docker builds with multi-stage caching
- CPU-only build support for CI/CD and remote builds

These improvements make the build process more automated, easier to maintain, and more accessible to users who want to experiment with vLLM on Strix Halo GPUs.

### Q: Can I contribute back improvements?

A: Absolutely! This is an open reference project. Improvements could include:
- Support for other AMD GPU architectures
- Smaller image optimizations
- Additional pre-built models
- Performance benchmarks
- Documentation improvements

Feel free to fork, experiment, and submit issues or PRs.

## References

- [vLLM](https://github.com/vllm-project/vllm) - Open source LLM inference engine
- [ROCm](https://rocm.docs.amd.com/) - AMD's open-source GPU compute platform
- [ROCm TheRock](https://github.com/ROCm/TheRock) - AMD's nightly build system
- [PyTorch ROCm](https://pytorch.org/get-started/locally/) - PyTorch with AMD GPU support
- [Distrobox](https://distrobox.privatedns.org/) - Container tool for Linux distributions
- [amd-strix-halo-vllm-toolboxes](https://github.com/kyuz0/amd-strix-halo-vllm-toolboxes) - Original Strix Halo vLLM project by Donato Capitella

## License

This project follows the same license as vLLM (Apache 2.0).
