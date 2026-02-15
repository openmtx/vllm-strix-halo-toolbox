# Build Process Documentation: AITER, Flash Attention, and vLLM Wheels

This document explains how to build AITER, Flash Attention, and vLLM wheels for ROCm with gfx1151 (Strix Halo) GPU support.

---

## Prerequisites

Before building, ensure you have:
- Completed scripts 00-02 (toolbox setup, tools installation, ROCm installation)
- Active virtual environment: `source ${VENV_DIR}/bin/activate`
- ROCm SDK initialized: `rocm-sdk init`

**IMPORTANT: CMake Usage**

The build process uses **CMake from the Ubuntu repository** (`/usr/bin/cmake`), **NOT** from pip.

- **Do NOT** install cmake via pip
- **Do NOT** use pip-installed cmake
- The required cmake (3.28.3+) is installed by `01-install-tools.sh` from Ubuntu 24.04 apt repository
- Verify: `which cmake` should return `/usr/bin/cmake`
- Using pip-installed cmake may cause build failures with ROCm/HIP compilation

---

## Critical Environment Variables

These environment variables must be set correctly for successful builds:

### Global Build Variables (from `.toolbox.env`)

| Variable | Default | Purpose |
|----------|---------|---------|
| `WORK_DIR` | `/workspace` | Directory for cloning repos and building wheels |
| `VENV_DIR` | `/opt/venv` | Virtual environment path |
| `GPU_TARGET` | `gfx1151` | Target GPU architecture (Strix Halo) |
| `PYTORCH_ROCM_ARCH` | `gfx1151` | PyTorch ROCm architecture target |
| `HSA_OVERRIDE_GFX_VERSION` | `11.5.1` | Override GPU version for compatibility |

### AITER Build Variables

| Variable | Purpose | Notes |
|----------|---------|-------|
| `PYTORCH_ROCM_ARCH` | ROCm architecture for compilation | Must match GPU (gfx1151) |
| `ROCM_HOME` | ROCm SDK path | Set to venv's rocm_sdk location |
| `ROCM_PATH` | Alias for ROCM_HOME | Must match ROCM_HOME |
| `PATH` | Include venv bin | Priority for finding tools |

### vLLM Build Variables

| Variable | Purpose | Notes |
|----------|---------|-------|
| `PYTORCH_ROCM_ARCH` | ROCm architecture for compilation | Must match GPU (gfx1151) |
| `GPU_ARCHS` | GPU architectures for kernels | Must match GPU (gfx1151) |
| `MAX_JOBS` | Parallel compilation jobs | Defaults to `nproc` |
| `HIPFLAGS` | HIP compiler flags | Must include device lib path |
| `HIP_DEVICE_LIB_PATH` | Path to device bitcode libraries | Critical for kernel compilation |
| `ROCM_PATH` | ROCm SDK root path | Must match ROCm SDK installation |
| `ROCM_HOME` | Alias for ROCM_PATH | Must match ROCM_PATH |

---

## Step-by-Step Build Process

### Phase 1: Build AITER (Optional)

**Script:** `03-build-aiter.sh`

**WARNING:** AITER may NOT be compatible with gfx1151 (Strix Halo). vLLM works perfectly without it.

**Compatibility Note:**
- **Supported:** gfx942 (MI300X), gfx950 (MI350), gfx1250, gfx12*
- **Potentially Unsupported:** gfx1150, gfx1151 (Strix Halo)

AITER contains inline AMD GPU assembly instructions that may not be supported on gfx1151.

#### AITER Build Steps

1. **Activate virtual environment:**
   ```bash
   source ${VENV_DIR}/bin/activate
   ```

2. **Clone or update AITER repository:**
   ```bash
   git clone https://github.com/ROCm/aiter.git ${WORK_DIR}/aiter
   cd ${WORK_DIR}/aiter
   ```

3. **Set ROCm architecture:**
   ```bash
   export PYTORCH_ROCM_ARCH="${GPU_TARGET}"  # gfx1151
   ```

4. **Set ROCm paths (CRITICAL):**
   ```bash
   export ROCM_HOME="${VENV_DIR}/lib/python3.12/site-packages/_rocm_sdk_devel"
   export ROCM_PATH="${ROCM_HOME}"
   export PATH="${VENV_DIR}/bin:${PATH}"
   ```

5. **Build AITER wheel:**
   ```bash
   mkdir -p ${WORK_DIR}/wheels
   pip wheel . --no-deps --no-build-isolation -w ${WORK_DIR}/wheels
   ```

6. **Install AITER wheel (if build succeeded):**
   ```bash
   pip install ${WORK_DIR}/wheels/amd_aiter-*.whl
   ```

7. **Verify installation:**
   ```bash
   pip show amd-aiter
   ```

**Expected Output if AITER is installed:**
- `amd-aiter` package listed in pip
- Wheel file in `${WORK_DIR}/wheels/amd_aiter-*.whl`

**If AITER build fails:**
- vLLM will still work without AITER
- AITER is an optional performance optimization library
- All vLLM core functionality remains operational

---

### Phase 2: Build Flash Attention

**Script:** `04-build-fa.sh`

This phase builds Flash Attention wheel from source with ROCm support for gfx1151. Flash Attention provides optimized attention mechanisms for transformers.

**Note:** Flash Attention is recommended for improved performance with vLLM.

#### Flash Attention Build Variables

| Variable | Purpose | Notes |
|----------|---------|-------|
| `PYTORCH_ROCM_ARCH` | ROCm architecture for compilation | Must match GPU (gfx1151) |
| `FLASH_ATTENTION_TRITON_AMD_ENABLE` | Enable AMD Triton support | Set to "TRUE" |
| `ROCM_HOME` | ROCm SDK path | Set to venv's rocm_sdk location |
| `ROCM_PATH` | Alias for ROCM_HOME | Must match ROCM_HOME |
| `PATH` | Include venv bin | Priority for finding tools |

#### Flash Attention Build Steps

1. **Activate virtual environment:**
   ```bash
   source ${VENV_DIR}/bin/activate
   ```

2. **Clone or update Flash Attention repository:**
   ```bash
   git clone https://github.com/ROCm/flash-attention.git ${WORK_DIR}/flash-attention
   cd ${WORK_DIR}/flash-attention
   ```

3. **Checkout main_perf branch:**
   ```bash
   git checkout main_perf
   ```

4. **Set ROCm architecture and AMD Triton enable:**
   ```bash
   export PYTORCH_ROCM_ARCH="${GPU_TARGET}"  # gfx1151
   export FLASH_ATTENTION_TRITON_AMD_ENABLE="TRUE"
   ```

5. **Set ROCm paths (CRITICAL):**
   ```bash
   export ROCM_HOME="${VENV_DIR}/lib/python3.12/site-packages/_rocm_sdk_devel"
   export ROCM_PATH="${ROCM_HOME}"
   export PATH="${VENV_DIR}/bin:${PATH}"
   ```

6. **Build Flash Attention wheel:**
   ```bash
   mkdir -p ${WORK_DIR}/wheels
   pip wheel . --no-deps --no-build-isolation -w ${WORK_DIR}/wheels
   ```

7. **Install Flash Attention wheel:**
   ```bash
   pip install ${WORK_DIR}/wheels/flash_attn-*.whl
   ```

8. **Verify installation:**
   ```bash
   pip show flash-attn
   ```

**Expected Output:**
- `flash-attn` package listed in pip
- Wheel file in `${WORK_DIR}/wheels/flash_attn-*.whl`

---

### Phase 3: Build vLLM

**Script:** `05-build-vllm.sh`

This phase builds vLLM from source with ROCm support for gfx1151.

#### vLLM Build Steps

1. **Activate virtual environment:**
   ```bash
   source ${VENV_DIR}/bin/activate
   ```

2. **Initialize ROCm SDK (CRITICAL):**
   ```bash
   rocm-sdk init
   ```

3. **Get ROCm SDK paths:**
   ```bash
   ROCM_ROOT=$(python3 -m rocm_sdk path --root)
   ROCM_BIN=$(python3 -m rocm_sdk path --bin)
   ```

4. **Set ROCm environment variables (CRITICAL):**
   ```bash
   export HIP_DEVICE_LIB_PATH="${ROCM_ROOT}/lib/llvm/amdgcn/bitcode"
   export ROCM_PATH="${ROCM_ROOT}"
   export ROCM_HOME="${ROCM_ROOT}"
   ```

5. **Create /opt/rocm symlink for compatibility:**
   ```bash
   sudo mkdir -p /opt
   sudo ln -sf "${ROCM_ROOT}" /opt/rocm
   ```

6. **Clone vLLM repository:**
   ```bash
   git clone --depth=1 https://github.com/vllm-project/vllm.git ${WORK_DIR}/vllm
   cd ${WORK_DIR}/vllm
   ```

7. **Configure vLLM to use existing PyTorch (CRITICAL):**
   ```bash
   python3 use_existing_torch.py
   ```
   This tells vLLM's build system to use the pre-installed PyTorch with ROCm support instead of downloading a new one.

8. **Set build environment variables (CRITICAL):**
   ```bash
   export PYTORCH_ROCM_ARCH=gfx1151
   export GPU_ARCHS=gfx1151
   export MAX_JOBS=$(nproc)
   export HIPFLAGS="--rocm-device-lib-path=${HIP_DEVICE_LIB_PATH}"
   ```

9. **Install build dependencies:**
   ```bash
   pip install "setuptools-scm>=8"
   ```

10. **Build vLLM wheel:**
    ```bash
    mkdir -p ${WORK_DIR}/wheels
    pip wheel . --no-deps --no-build-isolation -w ${WORK_DIR}/wheels
    ```

11. **Install vLLM wheel:**
    ```bash
    pip install ${WORK_DIR}/wheels/vllm-*.whl
    ```

12. **Verify installation:**
    ```bash
    pip show vllm
    vllm --help
    ```

**Expected Output:**
- `vllm` package listed in pip
- Wheel file in `${WORK_DIR}/wheels/vllm-*.whl`
- `vllm --help` shows usage information

---

## Common Issues and Troubleshooting

### Issue: Wrong CMake being used (pip vs system)

**Symptoms:**
- Build uses pip-installed cmake instead of system cmake
- Compilation failures with ROCm/HIP
- CMake version mismatch warnings

**Solution:**
```bash
# Uninstall any pip-installed cmake
pip uninstall -y cmake

# Verify system cmake is being used
which cmake
# Should output: /usr/bin/cmake

# Check cmake version
cmake --version
# Should show version 3.28.3 or later from Ubuntu repository

# If system cmake is missing, reinstall from apt
sudo apt-get install -y cmake
```

**NOTE:** Always use `/usr/bin/cmake` from Ubuntu repository. Never install cmake via pip.

### Issue: ROCm SDK not found

**Symptoms:**
- `rocm-sdk init` fails
- ROCm paths are incorrect

**Solution:**
```bash
# Ensure ROCm packages are installed
pip list | grep rocm

# Reinitialize ROCm SDK
rocm-sdk init

# Verify ROCm paths
python3 -m rocm_sdk path --root
python3 -m rocm_sdk path --bin
```

### Issue: Device library path not found

**Symptoms:**
- Compilation errors about missing bitcode files
- `HIP_DEVICE_LIB_PATH` incorrect

**Solution:**
```bash
# Verify device library exists
ls ${ROCM_ROOT}/lib/llvm/amdgcn/bitcode

# Check HIPFLAGS includes device lib path
echo $HIPFLAGS
```

### Issue: AITER build fails on gfx1151

**Symptoms:**
- AITER wheel not built
- Compilation errors about unsupported instructions

**Solution:**
- This is expected for gfx1151 (Strix Halo)
- vLLM will work without AITER
- Do not use `export VLLM_ROCM_USE_AITER=1`

### Issue: vLLM build fails with PyTorch errors

**Symptoms:**
- Build tries to download new PyTorch
- PyTorch version conflicts

**Solution:**
```bash
# Ensure use_existing_torch.py was run
cd ${WORK_DIR}/vllm
python3 use_existing_torch.py

# Verify existing PyTorch
pip show torch
```

### Issue: Slow build performance

**Symptoms:**
- Build takes very long
- Only one CPU core used

**Solution:**
```bash
# Increase parallel jobs
export MAX_JOBS=8  # or more based on CPU cores
```

---

## Verification Checklist

After completing all builds, verify:

- [ ] System cmake used: `which cmake` (should be `/usr/bin/cmake`)
- [ ] No pip cmake: `pip list | grep -i cmake` (should return nothing)
- [ ] AITER installed (optional): `pip show amd-aiter`
- [ ] Flash Attention installed: `pip show flash-attn`
- [ ] vLLM installed: `pip show vllm`
- [ ] vLLM help works: `vllm --help`
- [ ] ROCm paths set: `echo $ROCM_PATH`
- [ ] Device lib path exists: `ls $HIP_DEVICE_LIB_PATH`
- [ ] Wheels in `${WORK_DIR}/wheels/`

---

## Next Steps

After building:

1. Test vLLM with a simple model:
   ```bash
   vllm serve meta-llama/Meta-Llama-3-8B-Instruct --gpu-memory-utilization 0.8
   ```

2. Monitor GPU usage:
   ```bash
   rocm-smi
   ```

3. Check for AITER usage (if installed):
   - AITER is automatically used if `VLLM_ROCM_USE_AITER=1` is set
   - vLLM logs will indicate if AITER kernels are loaded

---

## Environment Variables Summary

### Before Running Build Scripts

Set these in your shell or `.toolbox.env`:

```bash
# Build directories
WORK_DIR=/workspace
VENV_DIR=/opt/venv

# GPU target
GPU_TARGET=gfx1151
PYTORCH_ROCM_ARCH=gfx1151
GPU_ARCHS=gfx1151
HSA_OVERRIDE_GFX_VERSION=11.5.1

# Build performance
MAX_JOBS=$(nproc)
```

### Set Automatically by Scripts

These are set during the build process:

**For AITER:**
```bash
export ROCM_HOME="${VENV_DIR}/lib/python3.12/site-packages/_rocm_sdk_devel"
export ROCM_PATH="${ROCM_HOME}"
export PATH="${VENV_DIR}/bin:${PATH}"
```

**For vLLM:**
```bash
export HIP_DEVICE_LIB_PATH="${ROCM_ROOT}/lib/llvm/amdgcn/bitcode"
export ROCM_PATH="${ROCM_ROOT}"
export ROCM_HOME="${ROCM_ROOT}"
export HIPFLAGS="--rocm-device-lib-path=${HIP_DEVICE_LIB_PATH}"
```

---

## Quick Reference

### Build AITER
```bash
./03-build-aiter.sh
```

### Build Flash Attention
```bash
./04-build-fa.sh
```

### Build vLLM
```bash
./05-build-vllm.sh
```

### Enter toolbox (distrobox)
```bash
distrobox enter ${TOOLBOX_NAME:-restart}
source ${VENV_DIR}/bin/activate
```

### Verify builds
```bash
pip show amd-aiter  # optional
pip show flash-attn
pip show vllm
vllm --help
rocm-smi
```
