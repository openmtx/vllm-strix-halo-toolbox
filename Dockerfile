# syntax=docker/dockerfile:1

# ROCm-enabled PyTorch base image with Ubuntu 24.04
ARG BASE_IMAGE=docker.io/rocm/pytorch:rocm7.2_ubuntu24.04_py3.12_pytorch_release_2.9.1

# =============================================================================
# Stage 1: Base - ROCm/PyTorch environment
# =============================================================================
FROM ${BASE_IMAGE} AS base

LABEL maintainer="ken@epenguin.com" \
      description="vLLM built with ROCm support for AMD GPUs" \
      base.image="${BASE_IMAGE}"

# Configure ROCm paths and hardware-specific environment variables
ENV ROCM_PATH=/opt/rocm \
    PATH=/opt/venv/bin:/opt/rocm/bin:$PATH \
    LD_LIBRARY_PATH=/opt/rocm/lib:$LD_LIBRARY_PATH \
    # gfx1151 = Strix Halo (AMD Ryzen AI 300 series)
    PYTORCH_ROCM_ARCH=gfx1151 \
    HSA_OVERRIDE_GFX_VERSION=11.5.1 \
    VLLM_TARGET_DEVICE=rocm

# =============================================================================
# Stage 2: Builder - Compile vLLM wheel
# =============================================================================
FROM base AS builder

ARG VLLM_BRANCH=main
ARG MAX_JOBS
ENV MAX_JOBS=${MAX_JOBS:-$(nproc)}

WORKDIR /workspace

RUN git clone --depth 1 --branch ${VLLM_BRANCH} https://github.com/vllm-project/vllm.git .

# Build dependencies
RUN pip install --no-cache-dir \
    build wheel ninja cmake pybind11 amd_aiter \
    "setuptools-scm>=8" grpcio-tools==1.78.0

# Force pip to use base image's PyTorch (ROCm 7.2 compatible)
ENV PIP_EXTRA_INDEX_URL=""

RUN if [ -f "use_existing_torch.py" ]; then python3 use_existing_torch.py; fi

# Build vLLM wheel
RUN python3 -m build --wheel --no-isolation

# =============================================================================
# Stage 3: Runtime - Production Image
# =============================================================================
FROM base AS runtime

LABEL stage="runtime" \
      description="vLLM runtime with ROCm support"

WORKDIR /workspace

# Install vLLM wheel 
COPY --from=builder /workspace/dist/*.whl /tmp/
RUN python3 -m pip install /tmp/*.whl --no-build-isolation \
    --extra-index-url https://download.pytorch.org \
 && rm -f /tmp/*.whl

# Install amdsmi from ROCm distribution
# Required for vLLM to detect AMD GPUs - without it, device detection fails
RUN python3 -m pip install /opt/rocm/share/amd_smi \
 && python3 -m pip install amd_aiter

EXPOSE 8080

# Start vLLM OpenAI API server
# Model: Qwen2.5-0.5B-Instruct (replace as needed)
# --enforce-eager: disable CUDA graphs (ROCm compatibility)
CMD ["vllm", "serve", "Qwen/Qwen2.5-0.5B-Instruct", "--host", "0.0.0.0", "--port", "8080", "--enforce-eager"]

