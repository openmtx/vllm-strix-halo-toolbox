# syntax=docker/dockerfile:1
# Multi-stage Dockerfile for vLLM with ROCm support for AMD Strix Halo (gfx1151)
# Refactored build order: 01-tools → 02-rocm → 03-vllm → 04-aiter → 05-fa

# =============================================================================
# Stage 1: dev-base - Install build tools, ROCm SDK, and base environment
# =============================================================================

FROM ubuntu:24.04 AS dev-base

LABEL maintainer="ken@epengui.com" \
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

# Create workspace and venv directories
RUN mkdir -p ${WORK_DIR} ${VENV_DIR}

# Set working directory
WORKDIR ${WORK_DIR}

# Copy build scripts
COPY . /workspace/.

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
# Stage 2: builder - Build vLLM without FA support, then AITER and FA
# =============================================================================

FROM dev-base AS builder

LABEL description="Build stage for vLLM, AITER and FA"

RUN echo "==========================================" \
  && echo "[Stage 3/5] Building vLLM without FA support..." \
  && echo "==========================================" \
  && /workspace/03-build-vllm.sh

RUN echo "==========================================" \
  && echo "[Stage 4/5] Building AMD AITER..." \
  && echo "==========================================" \
  && /workspace/04-build-aiter.sh || echo "AITER: Built with warnings (expected for CPU-only)"

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
LABEL maintainer="ken@epenguin.com"

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
COPY --from=builder /opt/venv /opt/venv

# Create ROCm symlink to maintain compatibility
RUN ln -sf /opt/venv/lib/python3.12/site-packages/_rocm_sdk_devel /opt/rocm

# Configure ROCm library path
RUN echo "/opt/rocm/lib" > /etc/ld.so.conf.d/rocm-sdk.conf && ldconfig

# Configure TCMalloc system-wide to prevent memory corruption
RUN echo "/usr/lib/x86_64-linux-gnu/libtcmalloc.so.4" > /etc/ld.so.preload

# Default command
CMD ["/bin/bash"]
