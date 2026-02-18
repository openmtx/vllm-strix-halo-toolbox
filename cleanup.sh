#!/bin/bash
# Cleanup script for vLLM ROCm repository
# Removes build artifacts while preserving essential files

set -euo pipefail

echo "🧹 Cleaning up repository for GitHub workflow..."

# Remove Docker images (optional - uncomment if needed)
# echo "Removing Docker images..."
# docker images | grep vllm | awk '{print $3}' | xargs -r docker rmi -f 2>/dev/null || true

# Clean up any Python cache files
echo "Cleaning Python cache files..."
find . -type f -name "*.pyc" -delete 2>/dev/null || true
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find . -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true

# Clean up temporary files
echo "Cleaning temporary files..."
find . -name "*.tmp" -delete 2>/dev/null || true
find . -name "*.bak" -delete 2>/dev/null || true
find . -name "*~" -delete 2>/dev/null || true
find . -name ".DS_Store" -delete 2>/dev/null || true

# Clean up any build artifacts in workspace (but preserve cache)
echo "Cleaning workspace artifacts..."
rm -rf /tmp/build-* 2>/dev/null || true
rm -rf /tmp/pip-* 2>/dev/null || true

# Keep cache directory for model downloading
echo "✅ Preserving cache directory for model downloads"

# Show git status
echo "📊 Current git status:"
git status --short

echo "🎉 Cleanup completed! Repository ready for GitHub workflow."
echo "💡 Cache directory preserved for model downloading"