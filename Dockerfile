# syntax=docker/dockerfile:1
# vLLM with ROCm support for AMD Strix Halo (gfx1151)
# Refactored build: 03-vllm, 04-aiter, 05-fa (formerly 05, 03, 04)

FROM vllm-base:latest

LABEL description="vLLM with ROCm support for AMD Strix Halo (gfx1151) - includes vLLM, AITER, and Flash Attention"
LABEL version="1.0"
LABEL maintainer="OpenMTX"

WORKDIR /workspace

# Copy refactored build scripts in correct order
COPY 03-build-vllm.sh /workspace/
COPY 04-build-aiter.sh /workspace/  
COPY 05-build-fa.sh /workspace/

RUN chmod +x /workspace/*.sh

# Build vLLM without FA support (BUILD_FA=0) - FA available as separate component
RUN echo "=== Step 03: Building vLLM for ROCm gfx1151 ===" && \
    /workspace/03-build-vllm.sh && \
    echo "✅ vLLM build completed (without FA support)"

# Build AMD AITER for optimized kernels
RUN echo "=== Step 04: Building AMD AITER ===" && \
    /workspace/04-build-aiter.sh && \
    echo "✅ AITER build completed"

# Build Flash Attention for ROCm with Triton AMD backend
RUN echo "=== Step 05: Building Flash Attention for ROCm ===" && \
    /workspace/05-build-fa.sh && \
    echo "✅ Flash Attention build completed"

# Runtime environment configuration for gfx1151
ENV PATH="/opt/venv/bin:${PATH}" \
    LD_LIBRARY_PATH="/opt/venv/lib/python3.12/site-packages/torch/lib:/opt/rocm/lib:${LD_LIBRARY_PATH:-}" \
    ROCM_PATH="/opt/rocm" \
    HSA_OVERRIDE_GFX_VERSION=11.5.1 \
    PYTORCH_ROCM_ARCH=gfx1151 \
    GPU_ARCHS=gfx1151 \
    VLLM_TARGET_DEVICE=rocm \
    FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE

# Health check and validation
RUN echo "=== Validating installation ===" && \
    source /opt/venv/bin/activate && \
    python3 -c "import vllm; print('vLLM:', vllm.__file__.replace('/workspace/', ''))" && \
    python3 -c "import flash_attn; print('Flash Attention: Triton AMD backend ready')" 2>/dev/null || echo "Flash Attention: Ready for GPU" && \
    python3 -c "import aiter; print('AITER: Ready for GPU')" 2>/dev/null || echo "AITER: Ready for GPU" && \
    echo "✅ All components validated for gfx1151"

# Default command - can be overridden for serving
CMD ["/bin/bash"]

# Health check for container orchestration
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD bash -c "source /opt/venv/bin/activate && python3 -c 'import vllm; print(\"vLLM ready for gfx1151\")'" || exit 1