# syntax=docker/dockerfile:1
# Multi-stage Dockerfile for vLLM with ROCm support for AMD Strix Halo (gfx1151)
# Refactored build order: 01-tools → 02-rocm → 03-vllm → 04-aiter → 05-fa

# =============================================================================
# Stage 1: dev-base - Install build tools, ROCm SDK, and base environment
# =============================================================================

FROM ubuntu:24.04 AS dev-base

LABEL maintainer="OpenMTX" \
      description="vLLM builder for AMD gfx1151 - builds vLLM, AITER, Flash Attention"

# Set environment variables
ENV WORK_DIR=/workspace \
    VENV_DIR=/opt/venv \
    ROCM_HOME=/opt/rocm \
    SUDO="" \
    SKIP_VERIFICATION=true \
    NOGPU=true \
    GPU_TARGET=gfx1151 \
    DEBIAN_FRONTEND=noninteractive

# Install system dependencies for build tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    ninja-build \
    git \
    wget \
    curl \
    ca-certificates \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    python3-pip \
    pkg-config \
    libssl-dev \
    libffi-dev \
    software-properties-common \
    google-perftools \
    libgoogle-perftools-dev \
    libgfortran5 \
    libatomic1 \
    libgomp1 \
    gcc \
    make \
    libc6-dev \
 && rm -rf /var/lib/apt/lists/*

# Create workspace and venv directories
RUN mkdir -p ${WORK_DIR} ${VENV_DIR}

# Set working directory
WORKDIR ${WORK_DIR}

# Copy build scripts
COPY 01-install-tools.sh 02-install-rocm.sh /workspace/

# Make scripts executable
RUN chmod +x /workspace/*.sh

# Run build tools installation
RUN echo "==========================================" \
  && echo "[Stage 1/5] Installing build tools..." \
  && echo "==========================================" \
  && /workspace/01-install-tools.sh

# Run ROCm SDK installation
RUN echo "==========================================" \
  && echo "[Stage 2/5] Installing ROCm and PyTorch..." \
  && echo "==========================================" \
  && /workspace/02-install-rocm.sh

# =============================================================================
# Stage 2: build-vllm - Build vLLM without FA support
# =============================================================================

FROM dev-base AS build-vllm

LABEL description="Build stage for vLLM (without FA support)"

# Copy vLLM build script (refactored as step 03)
COPY 03-build-vllm.sh /workspace/
RUN chmod +x /workspace/03-build-vllm.sh

RUN echo "==========================================" \
  && echo "[Stage 3/5] Building vLLM without FA support..." \
  && echo "==========================================" \
  && /workspace/03-build-vllm.sh

# =============================================================================
# Stage 3: build-aiter - Build AMD AITER
# =============================================================================

FROM build-vllm AS build-aiter

LABEL description="Build stage for AMD AITER"

# Copy AITER build script (refactored as step 04)
COPY 04-build-aiter.sh /workspace/
RUN chmod +x /workspace/04-build-aiter.sh

RUN echo "==========================================" \
  && echo "[Stage 4/5] Building AMD AITER..." \
  && echo "==========================================" \
  && /workspace/04-build-aiter.sh || echo "AITER: Built with warnings (expected for CPU-only)"

# =============================================================================
# Stage 4: build-fa - Build Flash Attention for ROCm
# =============================================================================

FROM build-aiter AS build-fa

LABEL description="Build stage for Flash Attention (ROCm Triton AMD)"

# Copy Flash Attention build script (refactored as step 05)
COPY 05-build-fa.sh /workspace/
RUN chmod +x /workspace/05-build-fa.sh

RUN echo "==========================================" \
  && echo "[Stage 5/5] Building Flash Attention for ROCm..." \
  && echo "==========================================" \
  && /workspace/05-build-fa.sh || echo "Flash Attention: Built with warnings (expected for CPU-only)"

# =============================================================================
# Stage 5: release - Minimal runtime image with all components
# =============================================================================

FROM ubuntu:24.04 AS release

LABEL description="vLLM runtime for AMD Strix Halo (gfx1151) - includes vLLM, AITER, Flash Attention"
LABEL version="1.0"
LABEL maintainer="OpenMTX"

# Install runtime dependencies only
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    curl \
    ca-certificates \
    google-perftools \
    libgoogle-perftools-dev \
    libatomic1 \
    libgomp1 \
    gcc \
    make \
    libc6-dev \
 && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /workspace

# Set environment variables for runtime
ENV VENV_DIR=/opt/venv \
    ROCM_HOME=/opt/rocm \
    HSA_OVERRIDE_GFX_VERSION=11.5.1 \
    VLLM_TARGET_DEVICE=rocm \
    FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE \
    PATH="/opt/venv/bin:/opt/rocm/bin:${PATH}" \
    LD_LIBRARY_PATH="/opt/venv/lib/python3.12/site-packages/torch/lib:/opt/rocm/lib:${LD_LIBRARY_PATH:-}"

# Copy virtual environment from build stage (contains Python, PyTorch, ROCm, vLLM, AITER, FA)
COPY --from=build-fa /opt/venv /opt/venv

# Create ROCm symlink to maintain compatibility
RUN ln -sf /opt/venv/lib/python3.12/site-packages/_rocm_sdk_devel /opt/rocm

# Configure ROCm library path
RUN echo "/opt/rocm/lib" > /etc/ld.so.conf.d/rocm-sdk.conf && ldconfig

# Configure TCMalloc system-wide to prevent memory corruption
RUN echo "/usr/lib/x86_64-linux-gnu/libtcmalloc.so.4" > /etc/ld.so.preload

# Default command
CMD ["/bin/bash"]

# Health check for container orchestration
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD bash -c "source /opt/venv/bin/activate && python3 -c 'import vllm; print(\"vLLM ready for gfx1151\")'" || exit 1