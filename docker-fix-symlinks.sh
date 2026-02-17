#!/bin/bash
set -e

# Fix missing gfx1151 library symlinks
LIB_DIR="/opt/venv/lib/python3.12/site-packages/_rocm_sdk_libraries_gfx1151/lib"
TARGET_DIR="/opt/rocm/lib"

if [ -d "$LIB_DIR" ]; then
    mkdir -p "$TARGET_DIR"
    ln -sf "${LIB_DIR}/libhipfftw.so" "${TARGET_DIR}/libhipfftw.so.0"
    ln -sf "${LIB_DIR}/libhipfftw.so" "${TARGET_DIR}/libhipfftw.so.0.1"
    echo "Fixed missing ROCm library symlinks in /opt/rocm/lib"
else
    echo "Warning: _rocm_sdk_libraries_gfx1151 directory not found"
fi
