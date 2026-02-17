# syntax=docker/dockerfile:1

# =============================================================================
# Stage 1: dev-base - Install build tools, ROCm SDK, build all packages
# =============================================================================

FROM ubuntu:24.04 AS dev-base

LABEL maintainer="ken@epenguin.com" \
      description="vLLM builder for AMD gfx1151 - builds AITER, Flash Attention, vLLM"

# Set consistent environment variables
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
COPY . /workspace/

# Make scripts executable
RUN chmod +x /workspace/*.sh

# Run build tools installation
RUN echo "==========================================" \
  && echo "[Stage 1/4] Installing build tools..." \
  && echo "==========================================" \
  && /workspace/01-install-tools.sh

# Run ROCm SDK installation
RUN echo "==========================================" \
  && echo "[Stage 1/4] Installing ROCm and PyTorch..." \
  && echo "==========================================" \
  && /workspace/02-install-rocm.sh

# =============================================================================
# Stage 2: build-aiter - Build AITER
# =============================================================================

FROM dev-base AS build-aiter

LABEL description="Build stage for AITER"

RUN echo "==========================================" \
  && echo "[Stage 2/4] Building AITER..." \
  && echo "==========================================" \
  && /workspace/03-build-aiter.sh || echo "WARNING: AITER build failed"

# =============================================================================
# Stage 3: build-fa - Build Flash Attention
# =============================================================================

FROM build-aiter AS build-fa

LABEL description="Build stage for Flash Attention"

RUN echo "==========================================" \
  && echo "[Stage 3/4] Building Flash Attention..." \
  && echo "==========================================" \
  && /workspace/04-build-fa.sh || echo "WARNING: Flash Attention build failed"

# =============================================================================
# Stage 4: build-vllm - Build vLLM
# =============================================================================

FROM build-fa AS build-vllm

LABEL description="Build stage for vLLM"

RUN echo "==========================================" \
  && echo "[Stage 4/4] Building vLLM..." \
  && echo "==========================================" \
  && /workspace/05-build-vllm.sh || echo "WARNING: vLLM build failed"

# =============================================================================
# Stage 5: release - Minimal runtime image
# =============================================================================

FROM ubuntu:24.04 AS release

LABEL maintainer="ken@epenguin.com" \
      description="vLLM runtime for AMD gfx1151"

# Install Python and runtime dependencies from Ubuntu repo
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.12 \
    python3.12-venv \
    python3.12-dev \
    curl \
    ca-certificates \
    google-perftools \
    libatomic1 \
    libgomp1 \
    gcc \
    make \
    libc6-dev \
 && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /workspace

# Set environment variables
ENV VENV_DIR=/opt/venv \
    ROCM_HOME=/opt/rocm \
    HSA_OVERRIDE_GFX_VERSION=11.5.1 \
    VLLM_TARGET_DEVICE=rocm \
    FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE \
    PATH="/opt/venv/bin:/opt/rocm/bin:${PATH}" \
    LD_LIBRARY_PATH="/opt/rocm/lib:${LD_LIBRARY_PATH:-}"

# Copy venv from build stage
COPY --from=build-vllm /opt/venv /opt/venv

# Create /opt/rocm symlink to _rocm_sdk_devel
RUN ln -sf /opt/venv/lib/python3.12/site-packages/_rocm_sdk_devel /opt/rocm

# Create ld.so.conf for ROCm libraries
RUN echo "/opt/rocm/lib" > /etc/ld.so.conf.d/rocm-sdk.conf \
  && ldconfig

# Default command
CMD ["/bin/bash"]
