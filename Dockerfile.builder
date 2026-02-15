# syntax=docker/dockerfile:1

# =============================================================================
# Stage 1: dev-base - Install build tools and ROCm SDK
# =============================================================================

FROM ubuntu:24.04 AS dev-base

LABEL maintainer="ken@epenguin.com" \
      description="Base dev environment with ROCm SDK for gfx1151"

# Set consistent environment variables
ENV WORK_DIR=/workspace \
    VENV_DIR=/opt/venv \
    SUDO="" \
    SKIP_VERIFICATION=true \
    NOGPU=true \
    GPU_TARGET=gfx1151 \
    DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    ninja-build \
    git \
    python3.12 \
    python3.12-venv \
    wget \
    curl \
    ca-certificates \
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
 && echo "Installing build tools..." \
 && echo "==========================================" \
 && /workspace/01-install-tools.sh

# Run ROCm SDK installation
RUN echo "==========================================" \
 && echo "Installing ROCm and PyTorch..." \
 && echo "==========================================" \
 && /workspace/02-install-rocm.sh

# =============================================================================
# Stage 2: build-aiter - Build AITER
# =============================================================================

FROM dev-base AS build-aiter

LABEL description="Build stage for AITER"

RUN echo "==========================================" \
 && echo "Building AITER..." \
 && echo "==========================================" \
 && /workspace/03-build-aiter.sh || echo "WARNING: AITER build failed"

# =============================================================================
# Stage 3: build-fa - Build Flash Attention
# =============================================================================

FROM build-aiter AS build-fa

LABEL description="Build stage for Flash Attention"

RUN echo "==========================================" \
 && echo "Building Flash Attention..." \
 && echo "==========================================" \
 && /workspace/04-build-fa.sh || echo "WARNING: Flash Attention build failed"

# =============================================================================
# Stage 4: build-vllm - Build vLLM
# =============================================================================

FROM build-fa AS build-vllm

LABEL description="Build stage for vLLM"

RUN echo "==========================================" \
 && echo "Building vLLM..." \
 && echo "==========================================" \
 && /workspace/05-build-vllm.sh || echo "WARNING: vLLM build failed"

# =============================================================================
# Usage
# =============================================================================
#
# Build complete image:
#   docker build -f Dockerfile.builder --target build-vllm -t vllm-gfx1151-builder .
#
# Build intermediate stages:
#   docker build -f Dockerfile.builder --target dev-base -t dev-base .
#   docker build -f Dockerfile.builder --target build-aiter -t build-aiter .
#   docker build -f Dockerfile.builder --target build-fa -t build-fa .
#
# Extract venv from builder:
#   docker run --rm -v $(pwd)/venv:/output vllm-gfx1151-builder \
#     bash -c "cp -r /opt/venv /output/"
#
# Note: CPU-only builder
#   - NOGPU=true flag skips all GPU verification
#   - Packages can be built without a GPU
#   - Packages will work when used on a system with gfx1151 GPU
# =============================================================================
