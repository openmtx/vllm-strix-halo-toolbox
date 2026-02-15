# syntax=docker/dockerfile:1

# =============================================================================
# Stage 1: Builder - Build AITER, Flash Attention, and vLLM wheels
# =============================================================================

FROM ubuntu:24.04 AS builder

LABEL maintainer="ken@epenguin.com" \
      description="CPU-only builder for ROCm gfx1151 wheels (AITER, Flash Attention, vLLM)"

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

# Run build scripts sequentially
RUN echo "==========================================" \
 && echo "Building ROCm gfx1151 Wheels" \
 && echo "==========================================" \
 && echo "" \
 && echo "[1/4] Installing build tools..." \
 && /workspace/01-install-tools.sh \
 && echo "" \
 && echo "[2/5] Installing ROCm and PyTorch..." \
 && /workspace/02-install-rocm.sh \
 && echo "" \
 && echo "[3/5] Building Flash Attention wheel..." \
 && /workspace/04-build-fa.sh || echo "WARNING: Flash Attention build failed" \
 && echo "" \
 && echo "[4/5] Building AITER wheel..." \
 && /workspace/03-build-aiter.sh || echo "WARNING: AITER build failed" \
 && echo "" \
 && echo "[5/5] Building vLLM wheel..." \
 && /workspace/05-build-vllm.sh || echo "WARNING: vLLM build failed" \
 && echo "" \
 && echo "==========================================" \
 && echo "Build Complete!" \
 && echo "==========================================" \
 && echo "" \
 && echo "Built wheels:" \
 && ls -lh ${WORK_DIR}/wheels/ || echo "No wheels built"

# =============================================================================
# Stage 2: Output - Copy only wheels to minimal image
# =============================================================================

FROM ubuntu:24.04 AS output

WORKDIR /output
COPY --from=builder /workspace/wheels /wheels

LABEL description="Contains built wheels for ROCm gfx1151"

# =============================================================================
# Usage
# =============================================================================
#
# Build:
#   docker build -f Dockerfile.builder -t vllm-gfx1151-wheels .
#
# Extract wheels:
#   docker run --rm -v $(pwd)/wheels:/output vllm-gfx1151-wheels
#
# Or run container and copy wheels:
#   docker run --rm -v $(pwd)/wheels:/output vllm-gfx1151-wheels \
#     bash -c "cp /wheels/*.whl /output/"
#
 # Built wheels (in ./wheels/):
 #   - amd_aiter-*.whl (29 MB)
 #   - flash_attn-*.whl (443 KB)
 #   - vllm-*.whl (52 MB)
#
# Install in ROCm environment:
#   pip install --index-url https://rocm.nightlies.amd.com/v2/gfx1151/ /path/to/wheels/*.whl
#
# Note: CPU-only builder
#   - NOGPU=true flag skips all GPU verification
#   - Wheels can be built without a GPU
#   - Wheels will work when installed on a system with gfx1151 GPU
# =============================================================================
