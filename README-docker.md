# Docker Build and Run Instructions

## Build the image
```bash
docker build -f Dockerfile -t vllm-rocm-gfx1151 .
```

## Run with Docker Compose (with GPU)
```bash
docker compose up vllm
```

## Run directly with Docker (with GPU)
```bash
docker run --rm \
  --privileged \
  --cap-add SYS_PTRACE \
  --security-opt seccomp:unconfined \
  --device /dev/kfd:/dev/kfd \
  --device /dev/dri:/dev/dri \
  --group-add video \
  -p 8080:8080 \
  -e VLLM_TARGET_DEVICE=rocm \
  -e HSA_OVERRIDE_GFX_VERSION=11.5.1 \
  -e FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE \
  -v ./cache/huggingface:/root/.cache/huggingface \
  -v /dev/shm:/dev/shm \
  vllm-rocm-gfx1151:latest \
  vllm serve Qwen/Qwen2.5-0.5B-Instruct --host 0.0.0.0 --port 8080 --tensor-parallel-size 1
```

## Environment Variables
- `VLLM_TARGET_DEVICE=rocm` - Enable ROCm backend
- `HSA_OVERRIDE_GFX_VERSION=11.5.1` - Target gfx1151 architecture
- `FLASH_ATTENTION_TRITON_AMD_ENABLE=TRUE` - Enable ROCm Flash Attention
