#!/usr/bin/env bash
set -euo pipefail

# 00-provision-toolbox.sh
# Create and provision a distrobox/toolbox container using ROCm/PyTorch image.
# The image includes ROCm SDK, PyTorch, and all dependencies for building vLLM.
# Usage: ./00-provision-toolbox.sh [-f|--force] [container-name]

# Source environment overrides if present
if [ -f "$(dirname "$0")/.toolbox.env" ]; then
  # shellcheck disable=SC1090
  source "$(dirname "$0")/.toolbox.env"
fi

# Default BASE_IMAGE if not set in .toolbox.env
BASE_IMAGE="${BASE_IMAGE:-docker.io/rocm/pytorch:rocm7.2_ubuntu24.04_py3.12_pytorch_release_2.9.1}"

WORK_DIR="${WORK_DIR:-/workspace}"
CONTAINER_NAME_DEFAULT="${TOOLBOX_NAME:-vllm-toolbox}"
FORCE=0

usage() {
  cat <<'USAGE'
Usage: 00-provision-toolbox.sh [-f|--force] [container-name]

Options:
  -f, --force    Destroy existing toolbox with the same name and recreate
  -h, --help     Show this help and exit

If no container-name is provided, the script uses TOOLBOX_NAME from .toolbox.env or 'vllm-toolbox'.
USAGE
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f|--force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -* )
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
    *)
      CONTAINER_NAME="$1"
      shift
      ;;
  esac
done

CONTAINER_NAME="${CONTAINER_NAME:-$CONTAINER_NAME_DEFAULT}"

echo "[00] Provisioning vLLM toolbox container: ${CONTAINER_NAME} (image: ${BASE_IMAGE})"

# Ensure distrobox is available
if ! command -v distrobox >/dev/null 2>&1; then
  echo "Error: 'distrobox' is required but not found in PATH. Install distrobox and retry." >&2
  exit 1
fi

# Check if toolbox exists
if distrobox list 2>/dev/null | grep -qw "${CONTAINER_NAME}"; then
  if [ "$FORCE" -eq 1 ]; then
    echo "Force removing existing toolbox '${CONTAINER_NAME}'..."
    DBX_NON_INTERACTIVE=1 distrobox stop "$CONTAINER_NAME" 2>/dev/null || true
    DBX_NON_INTERACTIVE=1 distrobox rm --force "$CONTAINER_NAME" 2>/dev/null || true
  else
    echo "Toolbox '${CONTAINER_NAME}' already exists. Use -f to force recreate." >&2
    exit 1
  fi
fi

SCRIPT_DIR="$(dirname "$0")"

echo "Creating distrobox toolbox '${CONTAINER_NAME}' using docker..."
distrobox create --pull --engine docker --image "${BASE_IMAGE}" --name "${CONTAINER_NAME}" \
  --additional-flags "--privileged --cap-add=SYS_PTRACE \
                      --security-opt seccomp=unconfined \
                      --device=/dev/kfd --device=/dev/dri \
                      --group-add video --ipc=host"

echo "Creating ${WORK_DIR} directory inside toolbox..."
distrobox enter "${CONTAINER_NAME}" -- bash -c "mkdir -p ${WORK_DIR} && chown $(id -u):$(id -g) ${WORK_DIR}"

echo "[00] Provisioning complete. Use 'distrobox enter ${CONTAINER_NAME}' to access the toolbox."
