#!/usr/bin/env python3
"""
Patching script to enable vLLM building without GPU access.
This patches vLLM platform detection and AMD-SMI handling.
"""

import re
from pathlib import Path
import sys


def patch_platforms_init():
    """Patch vllm/platforms/__init__.py to mock amdsmi"""
    p = Path("vllm/platforms/__init__.py")
    if not p.exists():
        print(f"Warning: {p} not found, skipping")
        return

    print(f"Patching {p}...")
    txt = p.read_text()

    # Comment out amdsmi import
    txt = txt.replace("import amdsmi", "# import amdsmi")

    # Force is_rocm = True
    txt = re.sub(r"is_rocm = .*", "is_rocm = True", txt)

    # Patch device handle check
    txt = txt.replace("if len(amdsmi.amdsmi_get_processor_handles()) > 0:", "if True:")

    # Replace amdsmi init/shutdown with pass
    txt = txt.replace("amdsmi.amdsmi_init()", "pass")
    txt = txt.replace("amdsmi.amdsmi_shut_down()", "pass")

    p.write_text(txt)
    print(f"  ✓ Patched {p}")


def patch_rocm_py():
    """Patch vllm/platforms/rocm.py to mock amdsmi module"""
    p = Path("vllm/platforms/rocm.py")
    if not p.exists():
        print(f"Warning: {p} not found, skipping")
        return

    print(f"Patching {p}...")
    txt = p.read_text()

    # Add mock amdsmi module at the top
    header = """import sys
from unittest.mock import MagicMock
sys.modules["amdsmi"] = MagicMock()
"""

    # Only add header if not already present
    if 'sys.modules["amdsmi"]' not in txt:
        txt = header + txt

    # Force device_type and device_name
    txt = re.sub(r"device_type = .*", 'device_type = "rocm"', txt)
    txt = re.sub(r"device_name = .*", 'device_name = "gfx1151"', txt)

    # Add get_device_name method if not present
    if "def get_device_name" not in txt:
        txt += """
    def get_device_name(self, device_id: int = 0) -> str:
        return "AMD-gfx1151"
"""

    p.write_text(txt)
    print(f"  ✓ Patched {p}")


def patch_cmake_targets():
    """Patch CMakeLists.txt to use gfx1151 target"""
    p = Path("CMakeLists.txt")
    if not p.exists():
        print(f"Warning: {p} not found, skipping")
        return

    print(f"Patching {p}...")
    txt = p.read_text()

    # Replace gfx1200 targets with gfx1151
    txt = txt.replace("gfx1200;gfx1201", "gfx1151")

    p.write_text(txt)
    print(f"  ✓ Patched {p}")


if __name__ == "__main__":
    print("Patching vLLM for GPU-less build...")
    print("=" * 60)

    patch_platforms_init()
    patch_rocm_py()
    patch_cmake_targets()

    print("=" * 60)
    print("Successfully patched vLLM for Strix Halo!")
