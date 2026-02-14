# syntax=docker/dockerfile:1

# =============================================================================
# Stage 1: Builder - Build vLLM and AITER wheels
# =============================================================================

# Use Ubuntu 24.04 as base (same as toolbox)
FROM ubuntu:24.04 AS builder

LABEL maintainer="ken@epenguin.com" \
      description="vLLM and AITER wheels builder for AMD gfx1151"

# Install basic dependencies
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

# Create workspace directory
WORKDIR /workspace

# Copy entire project to workspace
COPY . /workspace/

# Make scripts executable
RUN chmod +x /workspace/*.sh

# Run build scripts sequentially
# Note: Running as root, so SUDO="" (no sudo needed)
ENV SUDO="" SKIP_VERIFICATION=true

# 01: Install system tools and create venv
RUN /workspace/01-install-tools.sh

# 02: Install ROCm and PyTorch (nightly packages)
RUN /workspace/02-install-rocm.sh

# 03: Build AITER wheel (optional, but vLLM won't use on gfx1151)
RUN /workspace/03-build-aiter.sh

# 04: Build vLLM wheel
RUN /workspace/04-build-vllm.sh

# Set output path for easy access
ENV WHEELS_DIR=/workspace/wheels

# Show what was built
RUN echo "=== Build Complete ===" \
 && echo "" \
 && echo "Built wheels:" \
 && ls -lh ${WHEELS_DIR}/

# =============================================================================
# Note: This is a BUILDER image only
# To use the wheels:
#   1. Run: docker run --rm -v $(pwd)/wheels:/output <image> bash -c "cp /workspace/wheels/*.whl /output/"
#   2. Then install in your ROCm environment: pip install /output/*.whl
# =============================================================================
