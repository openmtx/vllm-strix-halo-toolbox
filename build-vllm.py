#!/usr/bin/env python3
import os
import sys
import subprocess

# Set environment
os.environ["PYTORCH_ROCM_ARCH"] = "gfx1151"
os.environ["HSA_OVERRIDE_GFX_VERSION"] = "11.5.1"
os.environ["GPU_ARCHS"] = "gfx1151"
os.environ["MAX_JOBS"] = "32"
os.environ["NOGPU"] = "true"

# Get torch directory and Torch_DIR
import torch

torch_dir = os.path.dirname(os.path.abspath(torch.__file__))
torch_share_dir = os.path.join(torch_dir, "share", "cmake", "Torch")

if os.path.isdir(torch_share_dir):
    torch_dir_env = torch_share_dir
    print(f"Torch_DIR={torch_dir_env}")
else:
    torch_dir_env = torch_dir
    print(f"Torch_DIR={torch_dir_env} (fallback)")

# Set CMAKE_ARGS with both Torch_DIR and CMAKE_PREFIX_PATH
# CMake needs ROCm paths too
rocm_path = "/opt/rocm"
cmake_prefix_path = f"{torch_dir}:{rocm_path}:{rocm_path}/lib/cmake:{rocm_path}/lib/cmake/hip:{rocm_path}/lib/cmake/hsa-runtime64:{rocm_path}/lib/cmake/amd_comgr:{rocm_path}/hip/share/cmake"
cmake_args = f"-DTorch_DIR={torch_dir_env} -DCMAKE_PREFIX_PATH={cmake_prefix_path}"
print(f"CMAKE_ARGS={cmake_args}")

# Export to environment
os.environ["Torch_DIR"] = torch_dir_env
os.environ["CMAKE_PREFIX_PATH"] = cmake_prefix_path
os.environ["CMAKE_ARGS"] = cmake_args
os.environ["ROCM_PATH"] = rocm_path
os.environ["HIP_PATH"] = rocm_path

# Install build deps
print("\nInstalling build dependencies...")
subprocess.run(
    [
        "pip",
        "install",
        "--no-cache-dir",
        "wheel",
        "build",
        "pybind11",
        "setuptools-scm>=8",
        "grpcio-tools",
        "einops",
        "pandas",
        "psutil",
    ],
    check=True,
)

# Run use_existing_torch.py
print("\nRunning use_existing_torch.py...")
subprocess.run(["python3", "use_existing_torch.py"], cwd="/workspace/vllm", check=False)

# Build vLLM wheel
print("\nBuilding vLLM wheel...")
env = os.environ.copy()
subprocess.run(
    ["python3", "setup.py", "bdist_wheel"], cwd="/workspace/vllm", env=env, check=True
)

# Install vLLM
print("\nInstalling vLLM...")
result = subprocess.run(
    ["bash", "-c", "pip install --no-deps ./dist/vllm-*.whl"],
    cwd="/workspace/vllm",
    check=True,
)

# Verify installation
print("\nVerifying vLLM installation...")
subprocess.run(
    ["python3", "-c", 'import vllm; print("vLLM version:", vllm.__version__)'],
    check=True,
)

print("\nvLLM build and installation complete!")
